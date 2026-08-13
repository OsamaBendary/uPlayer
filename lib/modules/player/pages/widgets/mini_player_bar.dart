import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/modules/library/widgets/smart_artwork_widget.dart';
import 'package:u_player/core/navigation/app_keys.dart';
import 'package:u_player/modules/player/pages/player_screen.dart';
import 'package:u_player/modules/player/pages/queue_screen.dart';

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: controller.isPlayerScreenVisible,
      builder: (context, onPlayerScreen, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: controller.isMiniPlayerDismissed,
          builder: (context, isDismissed, _) {
            return AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final song = controller.currentSong;
                final visible = !onPlayerScreen && !isDismissed && song != null && !controller.isLoading;

                return IgnorePointer(
                  ignoring: !visible,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedSlide(
                      offset: visible ? Offset.zero : const Offset(0, 1.5),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.fastOutSlowIn,
                      child: AnimatedOpacity(
                        opacity: visible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom + 80,
                            left: 16,
                            right: 16,
                          ),
                          child: song == null
                              ? const SizedBox.shrink()
                              : GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onVerticalDragEnd: (details) {
                              if ((details.primaryVelocity ?? 0) > 200) {
                                controller.isMiniPlayerDismissed.value = true;
                              }
                            },
                            child: _MiniPlayerCard(song: song, controller: controller),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MiniPlayerCard extends StatelessWidget {
  final SongModel song;
  final PlaybackController controller;

  const _MiniPlayerCard({required this.song, required this.controller});

  void _openPlayerScreen() {
    // Prevent opening multiple instances of PlayerScreen
    if (PlaybackController.instance.isPlayerScreenVisible.value) return;
    
    rootNavigatorKey.currentState?.push(
      PageRouteBuilder(
        settings:  RouteSettings(name: PlayerScreen.routeName),
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const PlayerScreen();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.fastOutSlowIn,
            reverseCurve: Curves.easeInCubic,
          );

          // Smooth slide up from bottom paired with a subtle scale + fade
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.08),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _openPlayerScreen,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              SmartArtworkWidget(
                song: song,
                width: 44,
                height: 44,
                borderRadius: BorderRadius.circular(14),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist ?? 'Unknown Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              StreamBuilder<PlayerState>(
                stream: controller.audioPlayer.playerStateStream,
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data?.playing ?? false;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.queue_music_rounded, color: Colors.white70),
                        onPressed: () {
                          rootNavigatorKey.currentState?.push(
                            MaterialPageRoute(builder: (_) => const QueueScreen()),
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                        onPressed: () {
                          if (isPlaying) {
                            controller.audioPlayer.pause();
                          } else {
                            controller.audioPlayer.play();
                          }
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}