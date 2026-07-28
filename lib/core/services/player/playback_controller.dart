import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_waveforms/audio_waveforms.dart' hide PlayerState;
import 'package:u_player/core/services/access_to_files/access_service.dart';
import 'package:u_player/core/services/play_count/play_count_service.dart';

/// App-wide playback state. There used to be a separate AudioPlayer living
/// inside PlayerScreen's State — that meant it was destroyed every time you
/// navigated away from the player, and nothing outside PlayerScreen could
/// tell it to play a song. This is the same logic, pulled out into a
/// singleton `ChangeNotifier` so the library/artist/album screens can call
/// `PlaybackController.instance.playSong(song)` directly, and the player
/// screen just displays whatever this controller is doing.
class PlaybackController extends ChangeNotifier {
  PlaybackController._internal();
  static final PlaybackController instance = PlaybackController._internal();

  final LocalAudioRepository _audioRepository = LocalAudioRepository();
  final PlayCountService _playCountService = PlayCountService();
  final AudioPlayer audioPlayer = AudioPlayer();

  List<SongModel> songs = [];
  bool isLoading = true;
  int currentIndex = 0;

  final Map<int, List<double>> waveformCache = {};
  int? waveformLoadingId;

  // In-memory cache of play counts so widgets don't re-hit SharedPreferences
  // on every rebuild. Populated lazily via getPlayCount() and kept current
  // by _registerPlay().
  final Map<int, int> playCounts = {};

  bool isShuffleEnabled = false;
  LoopMode loopMode = LoopMode.off;
  Timer? _sleepTimer;
  Duration? sleepTimerDuration;

  Future<void>? _initFuture;
  bool _listenersAttached = false;

  /// Toggled by PlayerScreen's own initState/dispose. The floating
  /// mini-player watches this so it hides itself while the full player
  /// screen is already open, instead of stacking on top of it.
  final ValueNotifier<bool> isPlayerScreenVisible = ValueNotifier<bool>(false);

  SongModel? get currentSong => songs.isEmpty ? null : songs[currentIndex];
  bool get hasSleepTimer => _sleepTimer != null;

  /// Cheap to call from every screen that touches playback — the real
  /// work (scanning the device + building the playlist) only runs once,
  /// no matter how many screens call this.
  Future<void> ensureInitialized() {
    _initFuture ??= _init();
    return _initFuture!;
  }

  Future<void> _init() async {
    final loaded = await _audioRepository.fetchLocalSongs();
    songs = loaded;

    if (loaded.isNotEmpty) {
      await audioPlayer.setAudioSource(_createPlaylist(loaded));
      _loadWaveformFor(loaded[currentIndex]);
    }

    isLoading = false;
    notifyListeners();

    if (!_listenersAttached) {
      _listenersAttached = true;
      audioPlayer.currentIndexStream.listen((index) {
        if (index != null && index != currentIndex && index < songs.length) {
          currentIndex = index;
          _loadWaveformFor(songs[index]);
          _registerPlay(songs[index].id);
          notifyListeners();
        }
      });
    }
  }

  ConcatenatingAudioSource _createPlaylist(List<SongModel> list) {
    return ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: list.map((song) {
        return AudioSource.uri(
          Uri.file(song.data),
          tag: MediaItem(
            id: song.id.toString(),
            title: song.title,
            artist: song.artist == '<unknown>' ? 'Unknown Artist' : (song.artist ?? 'Unknown Artist'),
            album: song.album == '<unknown>' ? 'Unknown Album' : (song.album ?? 'Unknown Album'),
          ),
        );
      }).toList(),
    );
  }

  /// Jumps playback straight to `song` — this is what the library, album,
  /// and artist screens call when the user taps a track.
  Future<void> playSong(SongModel song) async {
    await ensureInitialized();
    final idx = songs.indexWhere((s) => s.id == song.id);
    if (idx == -1) return;

    currentIndex = idx;
    notifyListeners();

    await audioPlayer.seek(Duration.zero, index: idx);
    await audioPlayer.play();
    _registerPlay(song.id);
  }

  // --- Play counts ---

  Future<void> _registerPlay(int songId) async {
    final count = await _playCountService.incrementPlayCount(songId);
    playCounts[songId] = count;
    notifyListeners();
  }

  /// Returns the play count for a song, using the in-memory cache when
  /// available and only reading from disk once per song otherwise.
  Future<int> getPlayCount(int songId) async {
    if (playCounts.containsKey(songId)) return playCounts[songId]!;
    final count = await _playCountService.getPlayCount(songId);
    playCounts[songId] = count;
    return count;
  }

  // --- Shuffle ---

  Future<void> toggleShuffle() async {
    final next = !isShuffleEnabled;
    // just_audio's shuffle() only (re)computes the shuffle order — it has
    // to be called before enabling shuffle mode for the new order to apply.
    if (next) {
      await audioPlayer.shuffle();
    }
    await audioPlayer.setShuffleModeEnabled(next);
    isShuffleEnabled = next;
    notifyListeners();
  }

  // --- Repeat ---

  Future<void> cycleRepeatMode() async {
    final next = switch (loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await audioPlayer.setLoopMode(next);
    loopMode = next;
    notifyListeners();
  }

  // --- Sleep timer ---

  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    sleepTimerDuration = duration;
    _sleepTimer = Timer(duration, () {
      audioPlayer.pause();
      _sleepTimer = null;
      sleepTimerDuration = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerDuration = null;
    notifyListeners();
  }

  // --- Waveform extraction (unchanged logic, just lives here now so the
  // cache survives leaving and returning to the player screen) ---

  Future<void> _loadWaveformFor(SongModel song) async {
    if (waveformCache.containsKey(song.id)) return;

    final file = File(song.data);
    final exists = await file.exists();
    debugPrint('WAVEFORM CHECK: "${song.title}" path=${song.data} exists=$exists');

    if (!exists) {
      debugPrint('WAVEFORM ABORT: file not directly readable, skipping extraction for "${song.title}"');
      return;
    }

    int durationMs = song.duration ?? 0;
    if (durationMs <= 0) {
      durationMs = audioPlayer.duration?.inMilliseconds ?? 0;
    }
    debugPrint('WAVEFORM DURATION: "${song.title}" durationMs=$durationMs');

    if (durationMs <= 0) {
      debugPrint('WAVEFORM ABORT: no usable duration for "${song.title}"');
      return;
    }

    waveformLoadingId = song.id;
    notifyListeners();

    final waveformController = PlayerController();
    try {
      const samplesPerSecond = 4;
      final sampleCount = ((durationMs / 1000) * samplesPerSecond).round().clamp(50, 4000);

      debugPrint('WAVEFORM START: "${song.title}" samples=$sampleCount');

      final data = await waveformController.extractWaveformData(
        path: song.data,
        noOfSamples: sampleCount,
      );

      debugPrint('WAVEFORM DONE: "${song.title}" got ${data.length} samples, '
          'sample values e.g. ${data.take(5).toList()}');

      waveformCache[song.id] = data;
      if (waveformLoadingId == song.id) waveformLoadingId = null;
      notifyListeners();
    } catch (e, st) {
      debugPrint('WAVEFORM FAILED: "${song.title}" — $e');
      debugPrint('$st');
      if (waveformLoadingId == song.id) {
        waveformLoadingId = null;
        notifyListeners();
      }
    } finally {
      waveformController.dispose();
    }
  }

  @override
  void dispose() {
    // In practice this singleton lives for the app's whole lifetime, but
    // keep it clean in case that ever changes.
    _sleepTimer?.cancel();
    audioPlayer.dispose();
    isPlayerScreenVisible.dispose();
    super.dispose();
  }
}
