import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

class ArtistCard extends StatelessWidget {
  final ArtistGroup artist;
  final VoidCallback onTap;

  const ArtistCard({super.key, required this.artist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final artHeroTag = 'artist-art-${artist.name}';
    final nameHeroTag = 'artist-name-${artist.name}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Hero(
                tag: artHeroTag,
                child: ClipOval(
                  child: QueryArtworkWidget(
                    id: artist.representativeSong.id,
                    type: ArtworkType.AUDIO,
                    artworkWidth: 56,
                    artworkHeight: 56,
                    artworkFit: BoxFit.cover,
                    quality: 100,
                    format: ArtworkFormat.PNG,
                    size: 300,
                    nullArtworkWidget: Container(
                      width: 56,
                      height: 56,
                      color: const Color(0xFF1A1A1A),
                      child: const Icon(Icons.person_rounded, color: Colors.white38),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Hero(
                      tag: nameHeroTag,
                      child: Material(
                        color: Colors.transparent,
                        child: LabelChip(
                          artist.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    LabelChip(
                      '${artist.songCount} song${artist.songCount == 1 ? '' : 's'} • '
                          '${formatDuration(artist.totalDuration)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
