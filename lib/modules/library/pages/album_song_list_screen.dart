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
    await PlaybackController.instance.playSong(song);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
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
    final duration = Duration(milliseconds: song.duration ?? 0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
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
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist ?? 'Unknown Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder<int>(
                    future: PlaybackController.instance.getPlayCount(song.id),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white38),
                          const SizedBox(width: 2),
                          Text(
                            '$count',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
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
  }
}
