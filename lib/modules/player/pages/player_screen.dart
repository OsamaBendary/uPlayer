import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:marquee/marquee.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/access_to_files/access_service.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';
import 'package:u_player/modules/library/pages/library_screen.dart';
import 'package:u_player/modules/player/pages/widgets/fav_button.dart';
import 'package:u_player/modules/player/pages/widgets/seek_bar.dart';
import 'package:audio_waveforms/audio_waveforms.dart' hide PlayerState;

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final LocalAudioRepository _audioRepository = LocalAudioRepository();
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<SongModel> _songs = [];
  bool _isLoading = true;
  int _currentIndex = 0;

  final Map<int, List<double>> _waveformCache = {};
  int? _waveformLoadingId;

  // --- Shuffle / repeat / sleep timer state ---
  bool _isShuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  Timer? _sleepTimer;
  Duration? _sleepTimerDuration; // total duration of the active timer, for display
  DateTime? _sleepTimerEndsAt;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    final songs = await _audioRepository.fetchLocalSongs();

    if (songs.isNotEmpty) {
      final playlist = _createPlaylist(songs);
      await _audioPlayer.setAudioSource(playlist);

      setState(() {
        _songs = songs;
        _isLoading = false;
      });

      _loadWaveformFor(songs[_currentIndex]);
    } else {
      setState(() {
        _isLoading = false;
      });
    }

    _audioPlayer.currentIndexStream.listen((index) {
      if (index != null && mounted && index != _currentIndex) {
        setState(() {
          _currentIndex = index;
        });
        if (index < _songs.length) {
          _loadWaveformFor(_songs[index]);
        }
      }
    });
  }

  ConcatenatingAudioSource _createPlaylist(List<SongModel> songs) {
    return ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: songs.map((song) {
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

  Future<void> _loadWaveformFor(SongModel song) async {
    if (_waveformCache.containsKey(song.id)) return;

    // 1. Verify the file is actually reachable BEFORE handing it to the
    // native decoder. on_audio_query paths can be MediaStore-style URIs
    // that aren't directly openable on scoped-storage Android versions —
    // if this fails silently, extraction falls back to fake/short data
    // with no error, which is exactly what you were seeing.
    final file = File(song.data);
    final exists = await file.exists();
    debugPrint('WAVEFORM CHECK: "${song.title}" path=${song.data} exists=$exists');

    if (!exists) {
      debugPrint('WAVEFORM ABORT: file not directly readable, skipping extraction for "${song.title}"');
      return;
    }

    // 2. Get real duration. song.duration from on_audio_query is
    // sometimes 0/null before the media store has fully indexed a file —
    // fall back to the player's own duration if needed, since that's
    // read directly from the audio stream.
    int durationMs = song.duration ?? 0;
    if (durationMs <= 0) {
      final playerDuration = _audioPlayer.duration;
      durationMs = playerDuration?.inMilliseconds ?? 0;
    }
    debugPrint('WAVEFORM DURATION: "${song.title}" durationMs=$durationMs');

    if (durationMs <= 0) {
      debugPrint('WAVEFORM ABORT: no usable duration for "${song.title}"');
      return;
    }

    setState(() => _waveformLoadingId = song.id);

    final controller = PlayerController();
    try {
      const samplesPerSecond = 4;
      final sampleCount = ((durationMs / 1000) * samplesPerSecond).round().clamp(50, 4000);

      debugPrint('WAVEFORM START: "${song.title}" samples=$sampleCount');

      final data = await controller.extractWaveformData(
        path: song.data,
        noOfSamples: sampleCount,
      );

      debugPrint('WAVEFORM DONE: "${song.title}" got ${data.length} samples, '
          'sample values e.g. ${data.take(5).toList()}');

      if (!mounted) return;
      setState(() {
        _waveformCache[song.id] = data;
        if (_waveformLoadingId == song.id) _waveformLoadingId = null;
      });
    } catch (e, st) {
      debugPrint('WAVEFORM FAILED: "${song.title}" — $e');
      debugPrint('$st');
      if (mounted && _waveformLoadingId == song.id) {
        setState(() => _waveformLoadingId = null);
      }
    } finally {
      controller.dispose();
    }
  }

  // --- Shuffle ---

  Future<void> _toggleShuffle() async {
    final next = !_isShuffleEnabled;
    // just_audio's shuffle() only (re)computes the shuffle order — it has
    // to be called before enabling shuffle mode for the new order to apply.
    if (next) {
      await _audioPlayer.shuffle();
    }
    await _audioPlayer.setShuffleModeEnabled(next);
    if (!mounted) return;
    setState(() => _isShuffleEnabled = next);
  }

  // --- Repeat ---

  Future<void> _cycleRepeatMode() async {
    final next = switch (_loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _audioPlayer.setLoopMode(next);
    if (!mounted) return;
    setState(() => _loopMode = next);
  }

  // --- Sleep timer ---

  void _startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    final endsAt = DateTime.now().add(duration);
    setState(() {
      _sleepTimerDuration = duration;
      _sleepTimerEndsAt = endsAt;
      _sleepTimer = Timer(duration, () {
        _audioPlayer.pause();
        if (!mounted) return;
        setState(() {
          _sleepTimer = null;
          _sleepTimerDuration = null;
          _sleepTimerEndsAt = null;
        });
      });
    });
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    setState(() {
      _sleepTimer = null;
      _sleepTimerDuration = null;
      _sleepTimerEndsAt = null;
    });
  }

  Future<void> _showSleepTimerSheet() async {
    const presets = [
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(minutes: 45),
      Duration(minutes: 60),
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sleep timer',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              for (final preset in presets)
                ListTile(
                  title: Text(
                    '${preset.inMinutes} minutes',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _startSleepTimer(preset);
                  },
                ),
              if (_sleepTimer != null)
                ListTile(
                  title: const Text(
                    'Turn off timer',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _cancelSleepTimer();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // --- Swipe-down navigation ---

  void _handleArtworkSwipe(DragEndDetails details) {
    // Positive primaryVelocity means the drag ended moving downward.
    if ((details.primaryVelocity ?? 0) > 250) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LibraryScreen()),
      );
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D0D),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_songs.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            "No songs found on device",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final currentSong = _songs[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: DynamicGradientBackground(
          songId: currentSong.id,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double maxContentWidth = constraints.maxWidth;
                final double artworkSize = (maxContentWidth - 48).clamp(240.0, 420.0);
                final double horizontalPadding = (maxContentWidth - artworkSize) / 2;

                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const SizedBox(height: 30),
                          GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onVerticalDragEnd: _handleArtworkSwipe,
                            child: SizedBox(
                              width: artworkSize,
                              height: artworkSize,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: QueryArtworkWidget(
                                        id: currentSong.id,
                                        type: ArtworkType.AUDIO,
                                        artworkWidth: artworkSize,
                                        artworkHeight: artworkSize,
                                        artworkBorder: BorderRadius.circular(20),
                                        artworkFit: BoxFit.cover,
                                        nullArtworkWidget: Container(
                                          width: artworkSize,
                                          height: artworkSize,
                                          color: const Color(0xFF1A1A1A),
                                          child: const Icon(
                                            Icons.music_note_rounded,
                                            color: Colors.white38,
                                            size: 100,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    height: 80,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: const BorderRadius.only(
                                          bottomLeft: Radius.circular(20),
                                          bottomRight: Radius.circular(20),
                                        ),
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.7),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 12,
                                    right: 12,
                                    bottom: 8,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        FavoriteButton(songId: currentSong.id, songTitle: currentSong.title),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: SizedBox(
                                        width: artworkSize - 14,
                                        height: 28,
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            const style = TextStyle(
                                              color: Colors.white,
                                              fontSize: 21,
                                              fontWeight: FontWeight.bold,
                                            );

                                            // Measure the title's natural (unbounded) width so we can
                                            // tell whether it actually overflows this box, rather than
                                            // always scrolling regardless of length.
                                            final textPainter = TextPainter(
                                              text: TextSpan(text: currentSong.title, style: style),
                                              maxLines: 1,
                                              textDirection: TextDirection.ltr,
                                            )..layout();

                                            final bool overflows = textPainter.width > constraints.maxWidth;

                                            if (!overflows) {
                                              // Short title: normal static text, left-aligned, no motion.
                                              return Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  currentSong.title,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: style,
                                                ),
                                              );
                                            }

                                            // Long title: scrolls, pausing ~2s at the start of each pass.
                                            return Marquee(
                                              text: currentSong.title,
                                              style: style,
                                              scrollAxis: Axis.horizontal,
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              blankSpace: 40.0,
                                              velocity: 30.0,
                                              pauseAfterRound: const Duration(seconds: 2),
                                              startPadding: 0.0,
                                              accelerationDuration: const Duration(milliseconds: 800),
                                              accelerationCurve: Curves.easeOut,
                                              decelerationDuration: const Duration(milliseconds: 400),
                                              decelerationCurve: Curves.easeIn,
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(
                                        currentSong.artist ?? "Unknown Artist",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: IconButton(
                                    onPressed: _showSleepTimerSheet,
                                    icon: const Icon(Icons.timer_outlined),
                                    color: _sleepTimer != null ? Colors.white : Colors.grey,
                                  ),
                                ),
                                Spacer(),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: IconButton(
                                    onPressed: _cycleRepeatMode,
                                    icon: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        SvgPicture.asset(
                                          "assets/icons/media-player-music-player-svgrepo-com.svg",
                                          color: _loopMode == LoopMode.off ? Colors.grey : Colors.white,
                                        ),
                                        if (_loopMode == LoopMode.one)
                                          Positioned(
                                            right: -2,
                                            top: -2,
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: const BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Text(
                                                '1',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: IconButton(
                                    iconSize: 30,
                                    onPressed: _toggleShuffle,
                                    icon: SvgPicture.asset(
                                      "assets/icons/music-player-random-svgrepo-com.svg",
                                      color: _isShuffleEnabled ? Colors.white : Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(
                            height: 256,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Positioned.fill(
                                  child: StreamBuilder<Duration>(
                                    stream: _audioPlayer.positionStream,
                                    builder: (context, snapshot) {
                                      return WaveformSeekbar(
                                        position: snapshot.data ?? Duration.zero,
                                        duration: _audioPlayer.duration ?? Duration.zero,
                                        onSeek: (pos) => _audioPlayer.seek(pos),
                                        customAmplitudes: _waveformCache[currentSong.id],
                                        isLoading: _waveformLoadingId == currentSong.id,
                                      );
                                    },
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      iconSize: 50,
                                      icon: CircleAvatar(
                                        backgroundColor: Colors.black,
                                        radius: 37,
                                        child: Center(child: SvgPicture.asset("assets/icons/music-music-player-player-2-svgrepo-com.svg", color: Colors.white, width: 50, height: 50)),
                                      ),
                                      onPressed: () => _audioPlayer.seekToPrevious(),
                                    ),
                                    const SizedBox(width: 6),
                                    StreamBuilder<PlayerState>(
                                      stream: _audioPlayer.playerStateStream,
                                      builder: (context, snapshot) {
                                        final isPlaying = snapshot.data?.playing ?? false;
                                        return IconButton(
                                          iconSize: 80,
                                          icon: CircleAvatar(
                                            backgroundColor: Colors.black,
                                            radius: 47,
                                            child: isPlaying ? SvgPicture.asset("assets/icons/media-player-music-pause-svgrepo-com.svg", color: Colors.white, width: 50, height: 50) :
                                            Padding(
                                              padding: const EdgeInsets.only(left: 4),
                                              child: SvgPicture.asset("assets/icons/music-play-play-button-svgrepo-com.svg", color: Colors.white, width: 50, height: 50),
                                            ),),
                                          onPressed: () {
                                            if (isPlaying) {
                                              _audioPlayer.pause();
                                            } else {
                                              _audioPlayer.play();
                                            }
                                          },
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      iconSize: 50,
                                      icon: CircleAvatar(
                                        backgroundColor: Colors.black,
                                        radius: 37,
                                        child: SvgPicture.asset("assets/icons/music-next-next-button-svgrepo-com.svg", color: Colors.white, width: 50, height: 50),
                                      ),
                                      onPressed: () => _audioPlayer.seekToNext(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}