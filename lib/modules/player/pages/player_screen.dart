import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:marquee/marquee.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';
import 'package:u_player/modules/library/pages/library_screen.dart';
import 'package:u_player/modules/player/pages/widgets/fav_button.dart';
import 'package:u_player/modules/player/pages/widgets/lyrics_overlay.dart';
import 'package:u_player/modules/player/pages/widgets/seek_bar.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final PlaybackController _controller = PlaybackController.instance;
  bool _showLyrics = false;

  @override
  void initState() {
    super.initState();
    // Cheap no-op if some other screen already triggered this.
    _controller.ensureInitialized();
    // Lets the floating mini-player know it should hide itself while this
    // screen is on top, instead of stacking above the full player.
    _controller.isPlayerScreenVisible.value = true;
  }

  @override
  void dispose() {
    _controller.isPlayerScreenVisible.value = false;
    super.dispose();
  }

  // --- Swipe handling ---

  void _handleArtworkVerticalSwipe(DragEndDetails details) {
    // Positive primaryVelocity means the drag ended moving downward.
    if ((details.primaryVelocity ?? 0) > 250) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LibraryScreen()),
      );
    }
  }

  void _handleArtworkHorizontalSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    // Negative primaryVelocity = swiped left (finger moved right-to-left) = next.
    // Positive primaryVelocity = swiped right = previous.
    if (velocity < -250) {
      _controller.audioPlayer.seekToNext();
    } else if (velocity > 250) {
      _controller.audioPlayer.seekToPrevious();
    }
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
                    _controller.startSleepTimer(preset);
                  },
                ),
              if (_controller.hasSleepTimer)
                ListTile(
                  title: const Text(
                    'Turn off timer',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _controller.cancelSleepTimer();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFF0D0D0D),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_controller.songs.isEmpty) {
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

        final currentSong = _controller.currentSong!;
        // Matches the tag ArtistCard builds ('artist-art-${artist.name}')
        // so swiping down flies the artwork into that artist's row in the
        // library if it's on screen. If your artist grouping normalizes
        // the name differently than this, the Hero just falls back to a
        // normal (non-animated) push — nothing breaks, tell me the exact
        // key your grouping uses and I'll line it up precisely.
        final heroArtTag = 'artist-art-${currentSong.artist ?? "Unknown Artist"}';

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
                                onVerticalDragEnd: _handleArtworkVerticalSwipe,
                                onHorizontalDragEnd: _handleArtworkHorizontalSwipe,
                                child: SizedBox(
                                  width: artworkSize,
                                  height: artworkSize,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: Hero(
                                          tag: heroArtTag,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(20),
                                            child: QueryArtworkWidget(
                                              id: currentSong.id,
                                              type: ArtworkType.AUDIO,
                                              artworkWidth: artworkSize,
                                              artworkHeight: artworkSize,
                                              artworkBorder: BorderRadius.circular(20),
                                              artworkFit: BoxFit.cover,
                                              quality: 100,
                                              format: ArtworkFormat.PNG,
                                              size: 1000,
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
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.35),
                                                shape: BoxShape.circle,
                                              ),
                                              child: IconButton(
                                                iconSize: 26,
                                                color: _showLyrics ? Colors.white : Colors.white70,
                                                icon: const Icon(Icons.lyrics_rounded),
                                                tooltip: 'Lyrics',
                                                onPressed: () => setState(() => _showLyrics = !_showLyrics),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Overlays the art (rather than replacing it in the tree)
                                      // so toggling it doesn't disturb the Hero above.
                                      if (_showLyrics)
                                        Positioned.fill(
                                          child: LyricsOverlay(
                                            song: currentSong,
                                            borderRadius: BorderRadius.circular(20),
                                            onClose: () => setState(() => _showLyrics = false),
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

                                                final textPainter = TextPainter(
                                                  text: TextSpan(text: currentSong.title, style: style),
                                                  maxLines: 1,
                                                  textDirection: TextDirection.ltr,
                                                )..layout();

                                                final bool overflows = textPainter.width > constraints.maxWidth;

                                                if (!overflows) {
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
                                        color: _controller.hasSleepTimer ? Colors.white : Colors.grey,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: IconButton(
                                        onPressed: _controller.cycleRepeatMode,
                                        icon: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            SvgPicture.asset(
                                              "assets/icons/media-player-music-player-svgrepo-com.svg",
                                              color: _controller.loopMode == LoopMode.off ? Colors.grey : Colors.white,
                                            ),
                                            if (_controller.loopMode == LoopMode.one)
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
                                    const SizedBox(width: 8),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: IconButton(
                                        iconSize: 30,
                                        onPressed: _controller.toggleShuffle,
                                        icon: SvgPicture.asset(
                                          "assets/icons/music-player-random-svgrepo-com.svg",
                                          color: _controller.isShuffleEnabled ? Colors.white : Colors.grey,
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
                                        stream: _controller.audioPlayer.positionStream,
                                        builder: (context, snapshot) {
                                          return WaveformSeekbar(
                                            position: snapshot.data ?? Duration.zero,
                                            duration: _controller.audioPlayer.duration ?? Duration.zero,
                                            onSeek: (pos) => _controller.audioPlayer.seek(pos),
                                            customAmplitudes: _controller.waveformCache[currentSong.id],
                                            isLoading: _controller.waveformLoadingId == currentSong.id,
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
                                            child: Center(
                                              child: SvgPicture.asset(
                                                "assets/icons/music-music-player-player-2-svgrepo-com.svg",
                                                color: Colors.white,
                                                width: 50,
                                                height: 50,
                                              ),
                                            ),
                                          ),
                                          onPressed: () => _controller.audioPlayer.seekToPrevious(),
                                        ),
                                        const SizedBox(width: 6),
                                        StreamBuilder<PlayerState>(
                                          stream: _controller.audioPlayer.playerStateStream,
                                          builder: (context, snapshot) {
                                            final isPlaying = snapshot.data?.playing ?? false;
                                            return IconButton(
                                              iconSize: 80,
                                              icon: CircleAvatar(
                                                backgroundColor: Colors.black,
                                                radius: 47,
                                                child: isPlaying
                                                    ? SvgPicture.asset(
                                                  "assets/icons/media-player-music-pause-svgrepo-com.svg",
                                                  color: Colors.white,
                                                  width: 50,
                                                  height: 50,
                                                )
                                                    : Padding(
                                                  padding: const EdgeInsets.only(left: 4),
                                                  child: SvgPicture.asset(
                                                    "assets/icons/music-play-play-button-svgrepo-com.svg",
                                                    color: Colors.white,
                                                    width: 50,
                                                    height: 50,
                                                  ),
                                                ),
                                              ),
                                              onPressed: () {
                                                if (isPlaying) {
                                                  _controller.audioPlayer.pause();
                                                } else {
                                                  _controller.audioPlayer.play();
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
                                            child: SvgPicture.asset(
                                              "assets/icons/music-next-next-button-svgrepo-com.svg",
                                              color: Colors.white,
                                              width: 50,
                                              height: 50,
                                            ),
                                          ),
                                          onPressed: () => _controller.audioPlayer.seekToNext(),
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
      },
    );
  }
}
