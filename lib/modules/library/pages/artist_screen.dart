import 'package:flutter/material.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';
import 'package:u_player/modules/library/pages/album_song_list_screen.dart';
import 'package:u_player/modules/library/widgets/album_card.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';
import 'package:u_player/modules/library/widgets/library_detail_header.dart';

class ArtistScreen extends StatelessWidget {
  final ArtistGroup artist;

  const ArtistScreen({super.key, required this.artist});

  void _handleHorizontalSwipe(BuildContext context, DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() > 250) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final albums = artist.albums;
    final artHeroTag = 'artist-art-${artist.name}';
    final nameHeroTag = 'artist-name-${artist.name}';

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) => _handleHorizontalSwipe(context, details),
        child: DynamicGradientBackground(
          songId: artist.representativeSong.id,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                LibraryDetailHeader(
                  artworkSongId: artist.representativeSong.id,
                  title: artist.name,
                  subtitle: '${artist.songCount} song${artist.songCount == 1 ? '' : 's'} • '
                      '${formatDuration(artist.totalDuration)}',
                  heroArtTag: artHeroTag,
                  heroTitleTag: nameHeroTag,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _AllSongsBar(
                        label: 'All songs by ${artist.name}',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AlbumSongListScreen.fromSongs(
                                title: artist.name,
                                subtitle: 'All Songs',
                                songs: artist.songs,
                                artworkSongId: artist.representativeSong.id,
                                heroArtTag: '$artHeroTag-all-songs',
                                heroTitleTag: '$nameHeroTag-all-songs',
                              ),
                            ),
                          );
                        },
                      ),
                      if (albums.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LabelChip(
                            'Albums',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const crossAxisCount = 2;
                            const spacing = 16.0;
                            final itemWidth =
                                (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
                            final itemHeight = AlbumCard.estimatedHeightForWidth(itemWidth);

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: spacing,
                                crossAxisSpacing: spacing,
                                mainAxisExtent: itemHeight,
                              ),
                              itemCount: albums.length,
                              itemBuilder: (context, index) {
                                final album = albums[index];

                                return AnimatedBuilder(
                                  animation: PlaybackController.instance,
                                  builder: (context, _) {
                                    final currentPlayingSong = PlaybackController.instance.currentSong;
                                    final isPlaying = currentPlayingSong != null &&
                                        album.songs.any((s) => s.id == currentPlayingSong.id);

                                    return AlbumCard(
                                      album: album,
                                      isPlaying: isPlaying,
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => AlbumSongListScreen(album: album),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ],
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

class _AllSongsBar extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AllSongsBar({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.queue_music_rounded, color: Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}