import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

class ArtistCard extends StatelessWidget {
  final ArtistGroup artist;
  final VoidCallback onTap;
  final bool isPlaying;

  const ArtistCard({
    super.key,
    required this.artist,
    required this.onTap,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final artHeroTag = 'artist-art-${artist.name}';
    final nameHeroTag = 'artist-name-${artist.name}';

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
              Hero(
                tag: artHeroTag,
                flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                  final fromHero = fromHeroContext.widget as Hero;
                  return ClipOval(child: fromHero.child);
                },
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
                        child: Row(
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
                              child: LabelChip(
                                artist.name,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    LabelChip(
                      '${artist.songCount} song${artist.songCount == 1 ? '' : 's'} • '
                          '${formatDuration(artist.totalDuration)}',
                      style: TextStyle(
                        color: isPlaying ? Colors.white70 : Colors.white54,
                        fontSize: 12,
                      ),
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