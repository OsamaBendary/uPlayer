import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_waveforms/audio_waveforms.dart' hide PlayerState;
import 'package:u_player/core/services/access_to_files/access_service.dart';
import 'package:u_player/core/services/play_count/play_count_service.dart';
import 'package:u_player/core/services/playback_state/playback_state_service.dart';

/// App-wide playback state.
class PlaybackController extends ChangeNotifier with WidgetsBindingObserver {
  PlaybackController._internal();
  static final PlaybackController instance = PlaybackController._internal();

  final LocalAudioRepository _audioRepository = LocalAudioRepository();
  final PlayCountService _playCountService = PlayCountService();
  final PlaybackStateService _playbackStateService = PlaybackStateService();
  final AudioPlayer audioPlayer = AudioPlayer();
  final OnAudioQuery _audioQuery = OnAudioQuery();

  // Cached per album (falling back to per-song for tracks with no album),
  // so a library of thousands of songs only decodes artwork once per
  // unique album instead of once per track. Null value = "checked, no art".
  final Map<int, String?> _artworkUriCache = {};

  Timer? _stateSaveTimer;
  static const Duration _stateSaveInterval = Duration(seconds: 5);

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
  bool isPlayOnce = false;
  Timer? _sleepTimer;
  Duration? sleepTimerDuration;
  int? _trackedSongId;
  bool _hasCountedCurrentPlayback = false;

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
    try {
      final loaded = await _audioRepository.fetchLocalSongs();
      songs = loaded;
      queue = List.from(loaded);
      queueIsWholeLibrary = true;

      if (loaded.isNotEmpty) {
        var initialIndex = 0;
        var initialPosition = Duration.zero;

        final lastSongId = await _playbackStateService.getLastSongId();
        if (lastSongId != null) {
          final restoredIndex = queue.indexWhere((s) => s.id == lastSongId);
          if (restoredIndex != -1) {
            initialIndex = restoredIndex;
            initialPosition = await _playbackStateService.getLastPosition();
          }
        }

        currentIndex = initialIndex;
        await audioPlayer.setAudioSource(
          await _createPlaylist(queue, initialIndex: initialIndex),
          initialIndex: initialIndex,
          initialPosition: initialPosition,
        );
        _loadWaveformFor(queue[currentIndex]);
      }

      if (!_listenersAttached) {
        _listenersAttached = true;
        audioPlayer.currentIndexStream.listen((index) {
          if (index != null && index != currentIndex && index < queue.length) {
            if (isPlayOnce) {
              audioPlayer.pause();
              isPlayOnce = false;
            }
            currentIndex = index;
            _trackedSongId = null;
            _hasCountedCurrentPlayback = false;
            _loadWaveformFor(queue[index]);
            _persistPlaybackState();
            _resolveArtworkUri(queue[index]);
            notifyListeners();
          }
        });

        audioPlayer.playerStateStream.listen((state) {
          if (isPlayOnce && state.processingState == ProcessingState.completed) {
            audioPlayer.pause();
            isPlayOnce = false;
            notifyListeners();
          } else if (!state.playing) {
            _persistPlaybackState();
          }
        });

        audioPlayer.positionStream.listen((position) {
          final song = currentSong;
          if (song == null) return;

          if (_trackedSongId != song.id) {
            _trackedSongId = song.id;
            _hasCountedCurrentPlayback = false;
          }

          if (_hasCountedCurrentPlayback && position.inSeconds < 2) {
            _hasCountedCurrentPlayback = false;
          }

          if (_hasCountedCurrentPlayback) return;

          final totalMs = audioPlayer.duration?.inMilliseconds ?? song.duration ?? 0;
          if (totalMs <= 0) return;

          if (position.inMilliseconds >= (totalMs ~/ 2)) {
            _hasCountedCurrentPlayback = true;
            _registerPlay(song.id);
          }
        });
      }

      _startStateSaveTimer();
      WidgetsBinding.instance.addObserver(this);
    } catch (e) {
      debugPrint('[PlaybackController] Initialization error: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _persistPlaybackState();
    }
  }

  Future<void> refreshLibrary() async {
    try {
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
            await _createPlaylist(queue, initialIndex: currentIndex),
            initialIndex: currentIndex,
            initialPosition: position,
          );
        }
      }
    } catch (e) {
      debugPrint('[PlaybackController] refreshLibrary error: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Resolves a stable local file:// URI for a song's album art, decoding
  /// and caching it on first use. Cached by album id so every track on the
  /// same album reuses one decode + one file. Returns null if the track
  /// has no art (not an error — plenty of tracks genuinely don't).
  Future<String?> _resolveArtworkUri(SongModel song) async {
    final cacheKey = song.albumId ?? song.id;
    if (_artworkUriCache.containsKey(cacheKey)) {
      return _artworkUriCache[cacheKey];
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/u_player_art_$cacheKey.jpg');

      if (await file.exists() && await file.length() > 0) {
        final uri = file.uri.toString();
        _artworkUriCache[cacheKey] = uri;
        return uri;
      }

      final bytes = await _audioQuery.queryArtwork(
        song.id,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 400,
      );

      if (bytes == null || bytes.isEmpty) {
        _artworkUriCache[cacheKey] = null;
        return null;
      }

      await file.writeAsBytes(bytes, flush: true);
      final uri = file.uri.toString();
      _artworkUriCache[cacheKey] = uri;
      return uri;
    } catch (e) {
      debugPrint('ARTWORK FAILED for "${song.title}": $e');
      _artworkUriCache[cacheKey] = null;
      return null;
    }
  }

  Future<ConcatenatingAudioSource> _createPlaylist(List<SongModel> list, {int? initialIndex}) async {
    // Only pre-resolve artwork for the initial track so startup is instant (< 50ms).
    // Other tracks use cached artwork if available, or resolve lazily on playback.
    String? initialArtUri;
    if (initialIndex != null && initialIndex >= 0 && initialIndex < list.length) {
      initialArtUri = await _resolveArtworkUri(list[initialIndex]);
    }

    return ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: List.generate(list.length, (i) {
        final song = list[i];
        final artUriString = (i == initialIndex)
            ? initialArtUri
            : _artworkUriCache[song.albumId ?? song.id];
        return AudioSource.uri(
          Uri.file(song.data),
          tag: MediaItem(
            id: song.id.toString(),
            title: song.title,
            artist: song.artist == '<unknown>' ? 'Unknown Artist' : (song.artist ?? 'Unknown Artist'),
            album: song.album == '<unknown>' ? 'Unknown Album' : (song.album ?? 'Unknown Album'),
            artUri: artUriString != null ? Uri.parse(artUriString) : null,
          ),
        );
      }),
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

    await audioPlayer.setAudioSource(await _createPlaylist(queue), initialIndex: clampedStart);

    if (wasShuffled) {
      await audioPlayer.shuffle();
      await audioPlayer.setShuffleModeEnabled(true);
    }

    await audioPlayer.play();
    notifyListeners();
    _trackedSongId = null;
    _hasCountedCurrentPlayback = false;
    isPlayOnce = false;
    _persistPlaybackState();
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

  Future<void> clearPlayCounts() async {
    await _playCountService.clearAll();
    playCounts.clear();
    notifyListeners();
  }

  // --- Shuffle ---

  Future<void> toggleShuffle() async {
    if (isShuffleEnabled) {
      await turnOffShuffle();
    } else {
      await shuffleThisList();
    }
  }

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

  Future<void> cycleRepeatMode() async {
    switch (loopMode) {
      case LoopMode.off:
        await repeatThisList();
        break;
      case LoopMode.all:
        await repeatOneSong();
        break;
      case LoopMode.one:
      default:
        await repeatOff();
        break;
    }
  }

  Future<void> repeatOff() async {
    await audioPlayer.setLoopMode(LoopMode.off);
    loopMode = LoopMode.off;
    isPlayOnce = false;
    notifyListeners();
  }

  Future<void> playOnce() async {
    await audioPlayer.setLoopMode(LoopMode.off);
    loopMode = LoopMode.off;
    isPlayOnce = true;
    notifyListeners();
  }

  Future<void> repeatOneSong() async {
    await audioPlayer.setLoopMode(LoopMode.one);
    loopMode = LoopMode.one;
    isPlayOnce = false;
    notifyListeners();
  }

  Future<void> repeatThisList() async {
    await audioPlayer.setLoopMode(LoopMode.all);
    loopMode = LoopMode.all;
    isPlayOnce = false;
    notifyListeners();
  }

  Future<void> repeatAllSongs() async {
    await _rebuildQueueToWholeLibraryPreservingPlayback();
    await audioPlayer.setLoopMode(LoopMode.all);
    loopMode = LoopMode.all;
    isPlayOnce = false;
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
      await _createPlaylist(queue),
      initialIndex: currentIndex,
      initialPosition: position,
    );
    await audioPlayer.play();
  }

  // --- Playback state persistence ---

  void _startStateSaveTimer() {
    _stateSaveTimer?.cancel();
    _stateSaveTimer = Timer.periodic(_stateSaveInterval, (_) {
      _persistPlaybackState();
    });
  }

  Future<void> _persistPlaybackState() async {
    final song = currentSong;
    if (song == null) return;
    await _playbackStateService.saveState(
      songId: song.id,
      position: audioPlayer.position,
    );
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
      const samplesPerSecond = 64;
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
    WidgetsBinding.instance.removeObserver(this);
    _sleepTimer?.cancel();
    _stateSaveTimer?.cancel();
    unawaited(_persistPlaybackState());
    audioPlayer.dispose();
    isPlayerScreenVisible.dispose();
    isMiniPlayerDismissed.dispose();
    super.dispose();
  }
}