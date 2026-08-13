import 'package:flutter/material.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';

/// Full-screen view of the playback queue: current song highlighted, tap to
/// jump, swipe left to remove.
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  static const String routeName = '/queue';

  @override
  Widget build(BuildContext context) {
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Queue',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: AnimatedBuilder(
          animation: PlaybackController.instance,
          builder: (context, _) {
            final controller = PlaybackController.instance;
            final queue = controller.queue;

            if (queue.isEmpty) {
              return const Center(
                child: Text(
                  'Queue is empty.\nSwipe a song left or right to add it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, height: 1.6),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 160),
              itemCount: queue.length,
              itemBuilder: (context, index) {
                final song = queue[index];
                final isCurrent = index == controller.currentIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: Dismissible(
                    key: ValueKey('queue-${song.id}-$index'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.remove_circle_outline, color: Colors.white),
                    ),
                    confirmDismiss: (_) async {
                      await controller.removeFromQueue(index);
                      return false;
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => controller.jumpToQueueIndex(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isCurrent ? Colors.white.withAlpha(25) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: isCurrent
                                ? Border.all(color: Colors.white.withAlpha(38), width: 1)
                                : null,
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: isCurrent ? Colors.greenAccent : Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent ? Colors.greenAccent : Colors.white,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      song.artist ?? 'Unknown Artist',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              if (isCurrent) ...[
                                const Icon(Icons.graphic_eq_rounded, size: 16, color: Colors.greenAccent),
                                const SizedBox(width: 6),
                              ],
                              Icon(
                                isCurrent ? Icons.play_circle_fill_rounded : Icons.music_note_rounded,
                                size: 18,
                                color: isCurrent ? Colors.greenAccent : Colors.white38,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}