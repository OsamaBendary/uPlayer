import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

class AlbumCard extends StatelessWidget {
  final AlbumGroup album;
  final VoidCallback onTap;
  final bool isPlaying;

  const AlbumCard({
    super.key,
    required this.album,
    required this.onTap,
    this.isPlaying = false,
  });

  static double estimatedHeightForWidth(double itemWidth) {
    const artworkSpacing = 8.0;
    const titleHeight = 20.0;
    const titleGap = 2.0;
    const artistHeight = 16.0;
    const artistGap = 4.0;
    const durationHeight = 12.0;
    const buffer = 12.0;

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
    final heroArtTag = 'album-art-${album.name}-${album.artist}';
    final heroTitleTag = 'album-title-${album.name}-${album.artist}';

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isPlaying ? Colors.white.withAlpha(25) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: isPlaying
                  ? Border.all(color: Colors.white.withAlpha(38), width: 1)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: heroArtTag,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: QueryArtworkWidget(
                        id: album.representativeSong.id,
                        type: ArtworkType.AUDIO,
                        artworkFit: BoxFit.cover,
                        artworkBorder: BorderRadius.zero,
                        quality: 85,
                        format: ArtworkFormat.JPEG,
                        size: 300,
                        nullArtworkWidget: Container(
                          color: const Color(0xFF1A1A1A),
                          child: const Icon(Icons.album_rounded, color: Colors.white38, size: 48),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (isPlaying) ...[
                      const Icon(
                        Icons.graphic_eq_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Hero(
                        tag: heroTitleTag,
                        child: Material(
                          color: Colors.transparent,
                          child: LabelChip(
                            album.name,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: isPlaying ? FontWeight.bold : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                LabelChip(
                  album.artist,
                  style: TextStyle(
                    color: isPlaying ? Colors.white70 : Colors.white54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                LabelChip(
                  formatDuration(album.totalDuration),
                  style: TextStyle(
                    color: isPlaying ? Colors.white70 : Colors.white38,
                    fontSize: 11,
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