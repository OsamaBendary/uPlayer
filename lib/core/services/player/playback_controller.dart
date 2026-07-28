import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_waveforms/audio_waveforms.dart' hide PlayerState;
import 'package:u_player/core/services/access_to_files/access_service.dart';
import 'package:u_player/core/services/play_count/play_count_service.dart';

/// App-wide playback state.
class PlaybackController extends ChangeNotifier {
  PlaybackController._internal();
  static final PlaybackController instance = PlaybackController._internal();

  final LocalAudioRepository _audioRepository = LocalAudioRepository();
  final PlayCountService _playCountService = PlayCountService();
  final AudioPlayer audioPlayer = AudioPlayer();

  List<SongModel> songs = [];
  List<SongModel> queue = [];
  bool queueIsWholeLibrary = true;

  bool isLoading = true;
  int currentIndex = 0;

  final Map<int, List<double>> waveformCache = {};
  int? waveformLoadingId;

  final Map<int, int> playCounts = {};

  bool isShuffleEnabled = false;
  LoopMode loopMode = LoopMode.off;
  Timer? _sleepTimer;
  Duration? sleepTimerDuration;

  Future<void>? _initFuture;
  bool _listenersAttached = false;

  final ValueNotifier<bool> isPlayerScreenVisible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isMiniPlayerDismissed = ValueNotifier<bool>(false);

  SongModel? get currentSong => queue.isEmpty ? null : queue[currentIndex];
  bool get hasSleepTimer => _sleepTimer != null;

  Future<void> ensureInitialized() {
    _initFuture ??= _init();
    return _initFuture!;
  }

  Future<void> _init() async {
    final loaded = await _audioRepository.fetchLocalSongs();
    songs = loaded;
    queue = List.from(loaded);
    queueIsWholeLibrary = true;

    if (loaded.isNotEmpty) {
      await audioPlayer.setAudioSource(_createPlaylist(queue));
      _loadWaveformFor(queue[currentIndex]);
    }

    isLoading = false;
    notifyListeners();

    if (!_listenersAttached) {
      _listenersAttached = true;
      audioPlayer.currentIndexStream.listen((index) {
        if (index != null && index != currentIndex && index < queue.length) {
          currentIndex = index;
          _loadWaveformFor(queue[index]);
          _registerPlay(queue[index].id);
          notifyListeners();
        }
      });
    }
  }

  Future<void> refreshLibrary() async {
    final loaded = await _audioRepository.fetchLocalSongs();
    songs = loaded;

    if (queueIsWholeLibrary) {
      final playing = currentSong;
      final position = audioPlayer.position;

      queue = List.from(loaded);

      if (loaded.isEmpty) {
        currentIndex = 0;
      } else {
        final newIndex = playing != null ? queue.indexWhere((s) => s.id == playing.id) : 0;
        currentIndex = newIndex == -1 ? 0 : newIndex;
        await audioPlayer.setAudioSource(
          _createPlaylist(queue),
          initialIndex: currentIndex,
          initialPosition: position,
        );
      }
    }

    notifyListeners();
  }

  ConcatenatingAudioSource _createPlaylist(List<SongModel> list) {
    return ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: list.map((song) {
        // Construct the Android MediaStore content URI for track artwork
        final artUri = Uri.parse('content://media/external/audio/media/${song.id}/albumart');

        return AudioSource.uri(
          Uri.file(song.data),
          tag: MediaItem(
            id: song.id.toString(),
            title: song.title,
            artist: song.artist == '<unknown>' ? 'Unknown Artist' : (song.artist ?? 'Unknown Artist'),
            album: song.album == '<unknown>' ? 'Unknown Album' : (song.album ?? 'Unknown Album'),
            artUri: artUri, // <--- Emits artwork to system notification & lock screen
          ),
        );
      }).toList(),
    );
  }

  Future<void> playSong(SongModel song) async {
    await ensureInitialized();
    final idx = songs.indexWhere((s) => s.id == song.id);
    if (idx == -1) return;
    await playQueue(songs, startIndex: idx);
  }

  Future<void> playQueue(List<SongModel> list, {required int startIndex}) async {
    await ensureInitialized();
    if (list.isEmpty) return;
    final clampedStart = startIndex.clamp(0, list.length - 1);

    final wasShuffled = isShuffleEnabled;
    if (wasShuffled) {
      await audioPlayer.setShuffleModeEnabled(false);
    }

    queue = List.from(list);
    queueIsWholeLibrary = _isSameSongs(queue, songs);
    currentIndex = clampedStart;

    await audioPlayer.setAudioSource(_createPlaylist(queue), initialIndex: clampedStart);

    if (wasShuffled) {
      await audioPlayer.shuffle();
      await audioPlayer.setShuffleModeEnabled(true);
    }

    await audioPlayer.play();
    notifyListeners();
    _registerPlay(queue[clampedStart].id);
  }

  bool _isSameSongs(List<SongModel> a, List<SongModel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  // --- Play counts ---

  Future<void> _registerPlay(int songId) async {
    final count = await _playCountService.incrementPlayCount(songId);
    playCounts[songId] = count;
    notifyListeners();
  }

  Future<int> getPlayCount(int songId) async {
    if (playCounts.containsKey(songId)) return playCounts[songId]!;
    final count = await _playCountService.getPlayCount(songId);
    playCounts[songId] = count;
    return count;
  }

  // --- Shuffle ---

  Future<void> turnOffShuffle() async {
    await audioPlayer.setShuffleModeEnabled(false);
    isShuffleEnabled = false;
    notifyListeners();
  }

  Future<void> shuffleThisList() async {
    await audioPlayer.shuffle();
    await audioPlayer.setShuffleModeEnabled(true);
    isShuffleEnabled = true;
    notifyListeners();
  }

  Future<void> shuffleAllSongs() async {
    await _rebuildQueueToWholeLibraryPreservingPlayback();
    await audioPlayer.shuffle();
    await audioPlayer.setShuffleModeEnabled(true);
    isShuffleEnabled = true;
    notifyListeners();
  }

  // --- Repeat ---

  Future<void> repeatOff() async {
    await audioPlayer.setLoopMode(LoopMode.off);
    loopMode = LoopMode.off;
    notifyListeners();
  }

  Future<void> repeatOneSong() async {
    await audioPlayer.setLoopMode(LoopMode.one);
    loopMode = LoopMode.one;
    notifyListeners();
  }

  Future<void> repeatThisList() async {
    await audioPlayer.setLoopMode(LoopMode.all);
    loopMode = LoopMode.all;
    notifyListeners();
  }

  Future<void> repeatAllSongs() async {
    await _rebuildQueueToWholeLibraryPreservingPlayback();
    await audioPlayer.setLoopMode(LoopMode.all);
    loopMode = LoopMode.all;
    notifyListeners();
  }

  Future<void> _rebuildQueueToWholeLibraryPreservingPlayback() async {
    if (queueIsWholeLibrary) return;

    final playing = currentSong;
    final position = audioPlayer.position;

    queue = List.from(songs);
    queueIsWholeLibrary = true;

    final newIndex = playing != null ? queue.indexWhere((s) => s.id == playing.id) : 0;
    currentIndex = newIndex == -1 ? 0 : newIndex;

    await audioPlayer.setAudioSource(
      _createPlaylist(queue),
      initialIndex: currentIndex,
      initialPosition: position,
    );
    await audioPlayer.play();
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

  // --- Waveform extraction ---

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

      debugPrint('WAVEFORM DONE: "${song.title}" got ${data.length} samples');

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
    _sleepTimer?.cancel();
    audioPlayer.dispose();
    isPlayerScreenVisible.dispose();
    isMiniPlayerDismissed.dispose();
    super.dispose();
  }
}