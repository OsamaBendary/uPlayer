import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

/// Top 1/3-of-screen artwork with the title stacked over the bottom of it,
/// used by both ArtistScreen and AlbumSongListScreen so they look and feel
/// the same. The artwork and title are separate sibling Heroes (not nested)
/// so both can fly independently during the transition in from the card.
class LibraryDetailHeader extends StatelessWidget {
  final int artworkSongId;
  final String title;
  final String subtitle;
  final String heroArtTag;
  final String heroTitleTag;

  // Header sits flush against the top of the screen, so only the bottom
  // corners get rounded — matches the "rounded, modern" look everywhere
  // else without floating a gap at the very top of the screen.
  static const _headerRadius = BorderRadius.vertical(bottom: Radius.circular(24));

  const LibraryDetailHeader({
    super.key,
    required this.artworkSongId,
    required this.title,
    required this.subtitle,
    required this.heroArtTag,
    required this.heroTitleTag,
  });

  @override
  Widget build(BuildContext context) {
    final double headerHeight = MediaQuery.of(context).size.height / 3;

    return ClipRRect(
      borderRadius: _headerRadius,
      child: SizedBox(
        height: headerHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: heroArtTag,
              child: QueryArtworkWidget(
                id: artworkSongId,
                type: ArtworkType.AUDIO,
                artworkFit: BoxFit.cover,
                artworkBorder: _headerRadius,
                quality: 100,
                format: ArtworkFormat.PNG,
                size: 800,
                nullArtworkWidget: Container(
                  color: const Color(0xFF1A1A1A),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 80),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Hero(
                    tag: heroTitleTag,
                    child: Material(
                      color: Colors.transparent,
                      child: LabelChip(
                        title,
                        maxLines: 2,
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  LabelChip(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
