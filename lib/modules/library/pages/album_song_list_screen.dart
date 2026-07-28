import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';
import 'package:u_player/modules/library/widgets/library_detail_header.dart';
import 'package:u_player/modules/player/pages/player_screen.dart';

/// One screen, two uses: an album's tracklist, and an artist's "all songs"
/// bar. Both need the same top-third-hero-header + song-list layout, just
/// with different data feeding it.
class AlbumSongListScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<SongModel> songs;
  final int artworkSongId;
  final String heroArtTag;
  final String heroTitleTag;

  const AlbumSongListScreen._({
    required this.title,
    required this.subtitle,
    required this.songs,
    required this.artworkSongId,
    required this.heroArtTag,
    required this.heroTitleTag,
  });

  factory AlbumSongListScreen({required AlbumGroup album}) {
    final artTag = 'album-art-${album.name}-${album.artist}';
    final titleTag = 'album-name-${album.name}-${album.artist}';
    return AlbumSongListScreen._(
      title: album.name,
      subtitle: '${album.artist} • ${formatDuration(album.totalDuration)}',
      songs: album.songs,
      artworkSongId: album.representativeSong.id,
      heroArtTag: artTag,
      heroTitleTag: titleTag,
    );
  }

  factory AlbumSongListScreen.fromSongs({
    required String title,
    required String subtitle,
    required List<SongModel> songs,
    required int artworkSongId,
    required String heroArtTag,
    required String heroTitleTag,
  }) {
    return AlbumSongListScreen._(
      title: title,
      subtitle: subtitle,
      songs: songs,
      artworkSongId: artworkSongId,
      heroArtTag: heroArtTag,
      heroTitleTag: heroTitleTag,
    );
  }

  // Swiping either direction here goes back to whatever screen pushed this
  // one (album grid, or the artist screen) — not all the way to the player.
  void _handleHorizontalSwipe(BuildContext context, DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() > 250) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _playSong(BuildContext context, SongModel song) async {
    // Queue exactly this screen's list (the album, or the artist's "all
    // songs") in order, starting at the tapped track — instead of jumping
    // into the full device library, which is what made playback feel like
    // it was skipping to random albums before.
    final startIndex = songs.indexWhere((s) => s.id == song.id);
    await PlaybackController.instance.playQueue(songs, startIndex: startIndex == -1 ? 0 : startIndex);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        // These are the same tags LibraryDetailHeader is using below, on
        // this exact screen. Handing them to PlayerScreen is what lets the
        // artwork/title fly from this header into the player on the way
        // in, and back into it here when you swipe the player down —
        // previously nothing was passed, so that transition never fired.
        builder: (_) => PlayerScreen(
          heroArtTag: heroArtTag,
          heroTitleTag: heroTitleTag,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) => _handleHorizontalSwipe(context, details),
        child: DynamicGradientBackground(
          songId: artworkSongId,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                LibraryDetailHeader(
                  artworkSongId: artworkSongId,
                  title: title,
                  subtitle: subtitle,
                  heroArtTag: heroArtTag,
                  heroTitleTag: heroTitleTag,
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: songs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) => _SongTile(
                      song: songs[index],
                      onTap: () => _playSong(context, songs[index]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;

  const _SongTile({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isPlaying = controller.currentSong?.id == song.id;
        final duration = Duration(milliseconds: song.duration ?? 0);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                color: isPlaying ? Colors.white.withAlpha(25) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: isPlaying
                    ? Border.all(color: Colors.white.withAlpha(38), width: 1)
                    : null,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: QueryArtworkWidget(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      artworkWidth: 56,
                      artworkHeight: 56,
                      artworkFit: BoxFit.cover,
                      artworkBorder: BorderRadius.circular(12),
                      quality: 100,
                      format: ArtworkFormat.PNG,
                      size: 300,
                      nullArtworkWidget: Container(
                        width: 56,
                        height: 56,
                        color: const Color(0xFF1A1A1A),
                        child: const Icon(Icons.music_note_rounded, color: Colors.white38),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (isPlaying) ...[
                              const Icon(
                                Icons.graphic_eq_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.artist ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPlaying ? Colors.white70 : Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatDuration(duration),
                        style: TextStyle(
                          color: isPlaying ? Colors.white70 : Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FutureBuilder<int>(
                        future: controller.getPlayCount(song.id),
                        builder: (context, snapshot) {
                          final count = snapshot.data ?? 0;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_arrow_rounded,
                                size: 12,
                                color: isPlaying ? Colors.white70 : Colors.white38,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '$count',
                                style: TextStyle(
                                  color: isPlaying ? Colors.white70 : Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}