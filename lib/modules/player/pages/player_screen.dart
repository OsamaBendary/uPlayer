import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:marquee/marquee.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/services/player/artwork_style_preference.dart';
import 'package:u_player/core/services/player/seekbar_preference.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';
import 'package:u_player/modules/library/pages/library_nav_screen.dart';
import 'package:u_player/modules/library/widgets/hero_flight_shuttles.dart';
import 'package:u_player/modules/library/widgets/smart_artwork_widget.dart';
import 'package:u_player/modules/player/pages/lyrics_screen.dart';
import 'package:u_player/modules/player/pages/queue_screen.dart';
import 'package:u_player/modules/player/pages/widgets/artwork_swipe_detector.dart';
import 'package:u_player/modules/player/pages/widgets/cd_artwork_widget.dart';
import 'package:u_player/modules/player/pages/widgets/fav_button.dart';
import 'package:u_player/modules/player/pages/widgets/jewel_case_artwork_widget.dart';
import 'package:u_player/modules/player/pages/widgets/seek_bar.dart';

class PlayerScreen extends StatefulWidget {
  static const routeName = '/player';

  final String? heroArtTag;
  final String? heroTitleTag;
  final String? heroArtistTag;
  final String? heroPlayTag;

  const PlayerScreen({
    super.key,
    this.heroArtTag,
    this.heroTitleTag,
    this.heroArtistTag,
    this.heroPlayTag,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final PlaybackController _controller = PlaybackController.instance;

  late final String _heroArtTag =
      widget.heroArtTag ?? 'player-art-${identityHashCode(this)}';
  late final String _heroTitleTag =
      widget.heroTitleTag ?? 'player-title-${identityHashCode(this)}';
  late final String _heroArtistTag =
      widget.heroArtistTag ?? 'player-artist-${identityHashCode(this)}';
  late final String _heroPlayTag =
      widget.heroPlayTag ?? 'player-play-${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    _controller.ensureInitialized();
  }

  void _handleArtworkSwipeDown() {
    _controller.isMiniPlayerDismissed.value = false;

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const LibraryNavScreen()),
      );
    }
  }

  void _handleArtworkSwipeLeft() => _controller.audioPlayer.seekToNext();

  void _handleArtworkSwipeRight() => _controller.audioPlayer.seekToPrevious();

  Future<void> _showSleepTimerSheet() async {
    const presets = [
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(minutes: 45),
      Duration(minutes: 60),
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF222222),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Sleep Timer',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final preset in presets)
                ListTile(
                  leading: const Icon(
                    Icons.timer_outlined,
                    color: Colors.white70,
                  ),
                  title: Text(
                    '${preset.inMinutes} minutes',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _controller.startSleepTimer(preset);
                  },
                ),
              if (_controller.hasSleepTimer)
                ListTile(
                  leading: const Icon(
                    Icons.timer_off_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Turn off timer',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _controller.cancelSleepTimer();
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openQueue() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QueueScreen()),
    );
  }

  Future<void> _handleShuffleTap() async {
    final bool wholeLibraryAvailable = !_controller.queueIsWholeLibrary;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF222222),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Shuffle',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Shuffle this list',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _controller.shuffleThisList();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.library_music_rounded,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Shuffle all songs on device',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _controller.shuffleAllSongs();
                },
              ),
              if (_controller.isShuffleEnabled)
                ListTile(
                  leading: const Icon(
                    Icons.shuffle_on_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Turn off shuffle',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _controller.turnOffShuffle();
                  },
                ),
              if (!wholeLibraryAvailable)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'You\'re already playing every song on the device.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleRepeatTap() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF222222),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Repeat Mode',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Repeat this list',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Loops current album / playlist',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                trailing:
                    (_controller.loopMode == LoopMode.all &&
                        !_controller.queueIsWholeLibrary &&
                        !_controller.isPlayOnce)
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : null,
                onTap: () {
                  Navigator.pop(dialogContext);
                  _controller.repeatThisList();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.library_music_rounded,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Repeat all songs on device',
                  style: TextStyle(color: Colors.white),
                ),
                trailing:
                    (_controller.loopMode == LoopMode.all &&
                        _controller.queueIsWholeLibrary &&
                        !_controller.isPlayOnce)
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : null,
                onTap: () {
                  Navigator.pop(dialogContext);
                  _controller.repeatAllSongs();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.repeat_one_rounded,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Repeat one song',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Loops current song continuously',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                trailing:
                    (_controller.loopMode == LoopMode.one &&
                        !_controller.isPlayOnce)
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : null,
                onTap: () {
                  Navigator.pop(dialogContext);
                  _controller.repeatOneSong();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.looks_one_rounded,
                  color: Colors.amberAccent,
                ),
                title: const Text(
                  'Play once (this song only)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Stops playback after this song finishes',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                trailing: _controller.isPlayOnce
                    ? const Icon(Icons.check_rounded, color: Colors.amberAccent)
                    : null,
                onTap: () {
                  Navigator.pop(dialogContext);
                  _controller.playOnce();
                },
              ),
              if (_controller.loopMode != LoopMode.off ||
                  _controller.isPlayOnce)
                ListTile(
                  leading: const Icon(
                    Icons.close_rounded,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Turn off repeat',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _controller.repeatOff();
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
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
        final lyricsHeroTag = 'lyrics-button-${currentSong.id}';

        final Widget playbackControls = Row(
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
                return Hero(
                  tag: _heroPlayTag,
                  child: Material(
                    color: Colors.transparent,
                    child: IconButton(
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
                    ),
                  ),
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
        );

        return Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: DynamicGradientBackground(
              songId: currentSong.id,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double maxContentWidth = constraints.maxWidth;
                    final double labelWidth = maxContentWidth - 56;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          // Artwork area flexes to fill whatever space is left
                          // over by the fixed-size title/controls/seekbar below,
                          // so nothing ever gets scaled down to fit.
                          Expanded(
                            child: Center(
                              child: LayoutBuilder(
                                builder: (context, artConstraints) {
                                  final double artSize =
                                      artConstraints.maxHeight <
                                          artConstraints.maxWidth
                                      ? artConstraints.maxHeight
                                      : artConstraints.maxWidth;
                                  final double cdSize = artSize;
                                  final double artworkSize = artSize;

                                  return ValueListenableBuilder<
                                    PlayerArtworkStyle
                                  >(
                                    valueListenable: playerArtworkStyle,
                                    builder: (context, style, _) {
                                      if (style != PlayerArtworkStyle.normal) {
                                        // ── CD Player mode ──
                                        return ArtworkSwipeDetector(
                                          onSwipeDown: _handleArtworkSwipeDown,
                                          onSwipeLeft: _handleArtworkSwipeLeft,
                                          onSwipeRight:
                                              _handleArtworkSwipeRight,
                                          child: SizedBox(
                                            width: cdSize,
                                            height: cdSize,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                // Spinning CD
                                                Positioned.fill(
                                                  child: StreamBuilder<PlayerState>(
                                                    stream: _controller
                                                        .audioPlayer
                                                        .playerStateStream,
                                                    builder: (context, snapshot) {
                                                      final isPlaying =
                                                          snapshot
                                                              .data
                                                              ?.playing ??
                                                          false;
                                                      if (style ==
                                                          PlayerArtworkStyle
                                                              .jewelCase) {
                                                        return JewelCaseArtworkWidget(
                                                          song: currentSong,
                                                          size: cdSize,
                                                          isPlaying: isPlaying,
                                                        );
                                                      }
                                                      final cdStyle =
                                                          switch (style) {
                                                            PlayerArtworkStyle
                                                                .silver =>
                                                              CdDiscStyle
                                                                  .silver,
                                                            PlayerArtworkStyle
                                                                .minimal =>
                                                              CdDiscStyle
                                                                  .minimal,
                                                            _ =>
                                                              CdDiscStyle
                                                                  .pictureDisc,
                                                          };
                                                      return CdArtworkWidget(
                                                        song: currentSong,
                                                        size: cdSize,
                                                        isPlaying: isPlaying,
                                                        style: cdStyle,
                                                      );
                                                    },
                                                  ),
                                                ),
                                                // Fav + Lyrics buttons overlaid at the bottom
                                                Positioned(
                                                  left: 12,
                                                  right: 12,
                                                  bottom: 8,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      FavoriteButton(
                                                        songId: currentSong.id,
                                                        songTitle:
                                                            currentSong.title,
                                                      ),
                                                      Container(
                                                        decoration:
                                                            BoxDecoration(
                                                              color: Colors
                                                                  .black
                                                                  .withValues(
                                                                    alpha: 0.35,
                                                                  ),
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                        child: Hero(
                                                          tag: lyricsHeroTag,
                                                          child: Material(
                                                            color: Colors
                                                                .transparent,
                                                            child: IconButton(
                                                              iconSize: 26,
                                                              color: Colors
                                                                  .white70,
                                                              icon: const Icon(
                                                                Icons
                                                                    .lyrics_rounded,
                                                              ),
                                                              tooltip: 'Lyrics',
                                                              onPressed: () {
                                                                Navigator.of(
                                                                  context,
                                                                ).push(
                                                                  PageRouteBuilder(
                                                                    transitionDuration:
                                                                        const Duration(
                                                                          milliseconds:
                                                                              350,
                                                                        ),
                                                                    reverseTransitionDuration:
                                                                        const Duration(
                                                                          milliseconds:
                                                                              300,
                                                                        ),
                                                                    pageBuilder:
                                                                        (
                                                                          _,
                                                                          animation,
                                                                          __,
                                                                        ) => LyricsScreen(
                                                                          song:
                                                                              currentSong,
                                                                          heroTag:
                                                                              lyricsHeroTag,
                                                                          positionStream: _controller
                                                                              .audioPlayer
                                                                              .positionStream,
                                                                        ),
                                                                    transitionsBuilder:
                                                                        (
                                                                          _,
                                                                          animation,
                                                                          __,
                                                                          child,
                                                                        ) {
                                                                          final scaleAnimation = CurvedAnimation(
                                                                            parent:
                                                                                animation,
                                                                            curve:
                                                                                Curves.fastOutSlowIn,
                                                                            reverseCurve:
                                                                                Curves.easeInCubic,
                                                                          );
                                                                          return FadeTransition(
                                                                            opacity:
                                                                                animation,
                                                                            child: ScaleTransition(
                                                                              scale:
                                                                                  Tween<
                                                                                        double
                                                                                      >(
                                                                                        begin: 0.8,
                                                                                        end: 1.0,
                                                                                      )
                                                                                      .animate(
                                                                                        scaleAnimation,
                                                                                      ),
                                                                              child: child,
                                                                            ),
                                                                          );
                                                                        },
                                                                  ),
                                                                );
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      // ── Normal artwork mode ──
                                      return ArtworkSwipeDetector(
                                        onSwipeDown: _handleArtworkSwipeDown,
                                        onSwipeLeft: _handleArtworkSwipeLeft,
                                        onSwipeRight: _handleArtworkSwipeRight,
                                        child: SizedBox(
                                          width: artworkSize,
                                          height: artworkSize,
                                          child: Stack(
                                            children: [
                                              Positioned.fill(
                                                child: Hero(
                                                  tag: _heroArtTag,
                                                  flightShuttleBuilder:
                                                      artworkFlightShuttleBuilder,
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                    child: SmartArtworkWidget(
                                                      song: currentSong,
                                                      width: artworkSize,
                                                      height: artworkSize,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            20,
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
                                                    borderRadius:
                                                        const BorderRadius.only(
                                                          bottomLeft:
                                                              Radius.circular(
                                                                20,
                                                              ),
                                                          bottomRight:
                                                              Radius.circular(
                                                                20,
                                                              ),
                                                        ),
                                                    gradient: LinearGradient(
                                                      begin: Alignment
                                                          .bottomCenter,
                                                      end: Alignment.topCenter,
                                                      colors: [
                                                        Colors.black.withValues(
                                                          alpha: 0.7,
                                                        ),
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
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    FavoriteButton(
                                                      songId: currentSong.id,
                                                      songTitle:
                                                          currentSong.title,
                                                    ),
                                                    Container(
                                                      decoration: BoxDecoration(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.35,
                                                            ),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Hero(
                                                        tag: lyricsHeroTag,
                                                        child: Material(
                                                          color: Colors
                                                              .transparent,
                                                          child: IconButton(
                                                            iconSize: 26,
                                                            color:
                                                                Colors.white70,
                                                            icon: const Icon(
                                                              Icons
                                                                  .lyrics_rounded,
                                                            ),
                                                            tooltip: 'Lyrics',
                                                            onPressed: () {
                                                              Navigator.of(
                                                                context,
                                                              ).push(
                                                                PageRouteBuilder(
                                                                  transitionDuration:
                                                                      const Duration(
                                                                        milliseconds:
                                                                            350,
                                                                      ),
                                                                  reverseTransitionDuration:
                                                                      const Duration(
                                                                        milliseconds:
                                                                            300,
                                                                      ),
                                                                  pageBuilder:
                                                                      (
                                                                        _,
                                                                        animation,
                                                                        __,
                                                                      ) => LyricsScreen(
                                                                        song:
                                                                            currentSong,
                                                                        heroTag:
                                                                            lyricsHeroTag,
                                                                        positionStream: _controller
                                                                            .audioPlayer
                                                                            .positionStream,
                                                                      ),
                                                                  transitionsBuilder:
                                                                      (
                                                                        _,
                                                                        animation,
                                                                        __,
                                                                        child,
                                                                      ) {
                                                                        final scaleAnimation = CurvedAnimation(
                                                                          parent:
                                                                              animation,
                                                                          curve:
                                                                              Curves.fastOutSlowIn,
                                                                          reverseCurve:
                                                                              Curves.easeInCubic,
                                                                        );

                                                                        return FadeTransition(
                                                                          opacity:
                                                                              animation,
                                                                          child: ScaleTransition(
                                                                            scale:
                                                                                Tween<
                                                                                      double
                                                                                    >(
                                                                                      begin: 0.8,
                                                                                      end: 1.0,
                                                                                    )
                                                                                    .animate(
                                                                                      scaleAnimation,
                                                                                    ),
                                                                            child:
                                                                                child,
                                                                          ),
                                                                        );
                                                                      },
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: EdgeInsets.zero,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Hero(
                                      tag: _heroTitleTag,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: _ScrollingLabel(
                                          text: currentSong.title,
                                          width: labelWidth,
                                          height: 28,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 21,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Hero(
                                      tag: _heroArtistTag,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: _ScrollingLabel(
                                          text:
                                              currentSong.artist ??
                                              "Unknown Artist",
                                          width: labelWidth,
                                          height: 24,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
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
                                    color: _controller.hasSleepTimer
                                        ? Colors.white
                                        : Colors.grey,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: IconButton(
                                    onPressed: _handleRepeatTap,
                                    icon: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        SvgPicture.asset(
                                          "assets/icons/media-player-music-player-svgrepo-com.svg",
                                          color:
                                              (_controller.loopMode ==
                                                      LoopMode.off &&
                                                  !_controller.isPlayOnce)
                                              ? Colors.grey
                                              : (_controller.isPlayOnce
                                                    ? Colors.amberAccent
                                                    : Colors.white),
                                        ),
                                        if (_controller.loopMode ==
                                            LoopMode.one)
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
                                        if (_controller.isPlayOnce)
                                          Positioned(
                                            right: -2,
                                            top: -2,
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: const BoxDecoration(
                                                color: Colors.amberAccent,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.looks_one_rounded,
                                                size: 10,
                                                color: Colors.black,
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
                                    onPressed: _handleShuffleTap,
                                    icon: SvgPicture.asset(
                                      "assets/icons/music-player-random-svgrepo-com.svg",
                                      color: _controller.isShuffleEnabled
                                          ? Colors.white
                                          : Colors.grey,
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
                                    onPressed: _openQueue,
                                    icon: const Icon(
                                      Icons.queue_music_rounded,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: useWaveformSeekbar,
                            builder: (context, useWaveform, _) {
                              if (useWaveform) {
                                return SizedBox(
                                  height: 256,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Positioned.fill(
                                        child: StreamBuilder<PlayerState>(
                                          stream: _controller
                                              .audioPlayer
                                              .playerStateStream,
                                          builder: (context, stateSnapshot) {
                                            final isPlaying =
                                                stateSnapshot.data?.playing ??
                                                false;
                                            return StreamBuilder<Duration>(
                                              stream: _controller
                                                  .audioPlayer
                                                  .positionStream,
                                              builder: (context, snapshot) {
                                                final position =
                                                    snapshot.data ??
                                                    Duration.zero;
                                                final duration =
                                                    _controller
                                                        .audioPlayer
                                                        .duration ??
                                                    Duration.zero;

                                                return WaveformSeekbar(
                                                  position: position,
                                                  duration: duration,
                                                  isPlaying: isPlaying,
                                                  onSeek: (pos) => _controller
                                                      .audioPlayer
                                                      .seek(pos),
                                                  customAmplitudes:
                                                      _controller
                                                          .waveformCache[currentSong
                                                          .id],
                                                  isLoading:
                                                      _controller
                                                          .waveformLoadingId ==
                                                      currentSong.id,
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                      playbackControls,
                                    ],
                                  ),
                                );
                              }

                              return SizedBox(
                                height: 256,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    StreamBuilder<Duration>(
                                      stream: _controller
                                          .audioPlayer
                                          .positionStream,
                                      builder: (context, snapshot) {
                                        final position =
                                            snapshot.data ?? Duration.zero;
                                        final duration =
                                            _controller.audioPlayer.duration ??
                                            Duration.zero;

                                        return _SimpleSeekBar(
                                          position: position,
                                          duration: duration,
                                          onSeek: (pos) =>
                                              _controller.audioPlayer.seek(pos),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    playbackControls,
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                        ],
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

class _ScrollingLabel extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double width;
  final double height;

  const _ScrollingLabel({
    required this.text,
    required this.style,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textPainter = TextPainter(
            text: TextSpan(text: text, style: style),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout();

          final bool overflows = textPainter.width > constraints.maxWidth;

          if (!overflows) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            );
          }

          return Marquee(
            text: text,
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
    );
  }
}

class _SimpleSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const _SimpleSeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<_SimpleSeekBar> createState() => _SimpleSeekBarState();
}

class _SimpleSeekBarState extends State<_SimpleSeekBar> {
  double? _dragValueMs;

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds > 0
        ? widget.duration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs =
        (_dragValueMs ?? widget.position.inMilliseconds.toDouble()).clamp(
          0.0,
          totalMs,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
          ),
          child: Slider(
            min: 0,
            max: totalMs,
            value: currentMs,
            onChanged: (value) => setState(() => _dragValueMs = value),
            onChangeEnd: (value) {
              widget.onSeek(Duration(milliseconds: value.round()));
              setState(() => _dragValueMs = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _format(Duration(milliseconds: currentMs.round())),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                _format(widget.duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
