import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';
import 'package:u_player/modules/library/widgets/library_detail_header.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: DynamicGradientBackground(
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
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (context, index) => _SongTile(song: songs[index], index: index + 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final SongModel song;
  final int index;

  const _SongTile({required this.song, required this.index});

  @override
  Widget build(BuildContext context) {
    final duration = Duration(milliseconds: song.duration ?? 0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // NOTE: not wired to actually play `song` yet — the AudioPlayer
          // instance currently lives inside PlayerScreen's own State, so
          // there's no shared controller this screen can reach yet. Once
          // there's a shared player/queue controller (Provider, Riverpod,
          // whatever you pick), this is where you'd tell it to jump to
          // `song` and pop back to the player.
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text('$index', style: const TextStyle(color: Colors.white38)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
              const SizedBox(width: 8),
              Text(formatDuration(duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}