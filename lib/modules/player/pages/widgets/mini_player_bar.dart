import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/modules/player/pages/player_screen.dart';

/// A floating "now playing" card, pinned near the bottom of the screen over
/// whatever content is underneath — not a bottom navigation bar. Wired in
/// via MaterialApp's `builder` in main.dart so it appears above every
/// screen, and hides itself automatically while the full PlayerScreen is
/// already open (via PlaybackController.instance.isPlayerScreenVisible).
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: controller.isPlayerScreenVisible,
      builder: (context, onPlayerScreen, _) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final song = controller.currentSong;
            final visible = !onPlayerScreen && song != null && !controller.isLoading;

            return IgnorePointer(
              ignoring: !visible,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedSlide(
                  offset: visible ? Offset.zero : const Offset(0, 1),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: SafeArea(
                      minimum: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: song == null ? const SizedBox.shrink() : _MiniPlayerCard(song: song, controller: controller),
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
  }
}

class _MiniPlayerCard extends StatelessWidget {
  final SongModel song;
  final PlaybackController controller;

  const _MiniPlayerCard({required this.song, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlayerScreen()),
          );
        },
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
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: QueryArtworkWidget(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  artworkWidth: 44,
                  artworkHeight: 44,
                  artworkFit: BoxFit.cover,
                  artworkBorder: BorderRadius.circular(14),
                  quality: 100,
                  format: ArtworkFormat.PNG,
                  size: 200,
                  nullArtworkWidget: Container(
                    width: 44,
                    height: 44,
                    color: const Color(0xFF2A2A2A),
                    child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 20),
                  ),
                ),
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
                  return IconButton(
                    icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                    onPressed: () {
                      if (isPlaying) {
                        controller.audioPlayer.pause();
                      } else {
                        controller.audioPlayer.play();
                      }
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white70),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlayerScreen()),
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
