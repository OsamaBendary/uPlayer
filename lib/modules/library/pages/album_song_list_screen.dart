import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';
import 'package:u_player/modules/library/widgets/library_detail_header.dart';
import 'package:u_player/modules/library/widgets/swipe_back_detector.dart';
import 'package:u_player/modules/player/pages/player_screen.dart';

/// One screen, two uses: an album's tracklist, and an artist's "all songs"
/// bar. Both need the same top-third-hero-header + song-list layout, just
/// with different data feeding it.
class AlbumSongListScreen extends StatefulWidget {
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
  State<AlbumSongListScreen> createState() => _AlbumSongListScreenState();
}

class _AlbumSongListScreenState extends State<AlbumSongListScreen> {
  late final Future<Uint8List?> _artworkFuture;
  late final bool _isSingleAlbum = _computeIsSingleAlbum();

  bool _computeIsSingleAlbum() {
    if (widget.songs.isEmpty) return true;
    final firstAlbumId = widget.songs.first.albumId;
    return widget.songs.every((s) => s.albumId == firstAlbumId);
  }

  @override
  void initState() {
    super.initState();
    // Fetched exactly once for the whole screen — every track's tile used
    // to independently call QueryArtworkWidget(id: song.id, ...), which for
    // an album means N separate on_audio_query round-trips for what's
    // almost always the exact same embedded image. This fetches the
    // representative track's artwork a single time and every tile below
    // just paints the same bytes via Image.memory.
    _artworkFuture = OnAudioQuery().queryArtwork(
      widget.artworkSongId,
      ArtworkType.AUDIO,
      size: 300,
      quality: 100,
      format: ArtworkFormat.PNG,
    );
  }

  Future<void> _playSong(SongModel song) async {
    // Queue exactly this screen's list (the album, or the artist's "all
    // songs") in order, starting at the tapped track — instead of jumping
    // into the full device library, which is what made playback feel like
    // it was skipping to random albums before.
    final startIndex = widget.songs.indexWhere((s) => s.id == song.id);
    await PlaybackController.instance.playQueue(widget.songs, startIndex: startIndex == -1 ? 0 : startIndex);
    if (!mounted) return;
    // Prevent opening a second PlayerScreen
    if (PlaybackController.instance.isPlayerScreenVisible.value) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: PlayerScreen.routeName),
        // These are the same tags LibraryDetailHeader is using below, on
        // this exact screen. Handing them to PlayerScreen is what lets the
        // artwork/title fly from this header into the player on the way
        // in, and back into it here when you swipe the player down.
        builder: (_) => PlayerScreen(
          heroArtTag: widget.heroArtTag,
          heroTitleTag: widget.heroTitleTag,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SwipeBackDetector(
        child: DynamicGradientBackground(
          songId: widget.artworkSongId,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                LibraryDetailHeader(
                  artworkSongId: widget.artworkSongId,
                  title: widget.title,
                  subtitle: widget.subtitle,
                  heroArtTag: widget.heroArtTag,
                  heroTitleTag: widget.heroTitleTag,
                ),
                Expanded(
                  child: FutureBuilder<Uint8List?>(
                    future: _artworkFuture,
                    builder: (context, artworkSnapshot) {
                      final sharedArtwork = artworkSnapshot.data;
                      return ListView.separated(
                        padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 160),
                        itemCount: widget.songs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) => _SongTile(
                          song: widget.songs[index],
                          sharedArtwork: sharedArtwork,
                          usePerSongArtwork: !_isSingleAlbum,
                          onTap: () => _playSong(widget.songs[index]),
                        ),
                      );
                    },
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
  final Uint8List? sharedArtwork;
  final bool usePerSongArtwork;
  final VoidCallback onTap;

  const _SongTile({required this.song, required this.sharedArtwork, this.usePerSongArtwork = false, required this.onTap});

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
                    child: usePerSongArtwork
                        ? QueryArtworkWidget(
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            artworkWidth: 56,
                            artworkHeight: 56,
                            artworkFit: BoxFit.cover,
                            quality: 85,
                            format: ArtworkFormat.JPEG,
                            size: 300,
                            nullArtworkWidget: Container(
                              width: 56,
                              height: 56,
                              color: const Color(0xFF1A1A1A),
                              child: const Icon(Icons.music_note_rounded, color: Colors.white38),
                            ),
                          )
                        : sharedArtwork != null
                        ? Image.memory(
                      sharedArtwork!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    )
                        : Container(
                      width: 56,
                      height: 56,
                      color: const Color(0xFF1A1A1A),
                      child: const Icon(Icons.music_note_rounded, color: Colors.white38),
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