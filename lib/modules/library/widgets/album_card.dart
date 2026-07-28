import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

class AlbumCard extends StatelessWidget {
  final AlbumGroup album;
  final VoidCallback onTap;

  const AlbumCard({super.key, required this.album, required this.onTap});

  /// The overflow bug came from grids using a fixed childAspectRatio: at
  /// narrow item widths, the reserved height below the square artwork
  /// (title + artist + duration + spacing) didn't scale with it, so on
  /// smaller screens the text block ran out of room. This gives both grids
  /// (library_screen's album grid and artist_screen's album grid) an exact
  /// height for a given item width instead of guessing via aspect ratio, so
  /// there's always exactly enough room and never wasted space either.
  static double estimatedHeightForWidth(double itemWidth) {
    const artworkSpacing = 8.0;
    const titleHeight = 20.0;
    const titleGap = 4.0;
    const artistHeight = 16.0;
    const artistGap = 4.0;
    const durationHeight = 14.0;
    const buffer = 6.0; // small safety margin against font metric rounding

    return itemWidth +
        artworkSpacing +
        titleHeight +
        titleGap +
        artistHeight +
        artistGap +
        durationHeight +
        buffer;
  }

  @override
  Widget build(BuildContext context) {
    final heroTag = 'album-art-${album.name}-${album.artist}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: heroTag,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: QueryArtworkWidget(
                    id: album.representativeSong.id,
                    type: ArtworkType.AUDIO,
                    artworkFit: BoxFit.cover,
                    artworkBorder: BorderRadius.zero,
                    quality: 100,
                    format: ArtworkFormat.PNG,
                    size: 600,
                    nullArtworkWidget: Container(
                      color: const Color(0xFF1A1A1A),
                      child: const Icon(Icons.album_rounded, color: Colors.white38, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            LabelChip(
              album.name,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            LabelChip(
              album.artist,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            LabelChip(
              formatDuration(album.totalDuration),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
