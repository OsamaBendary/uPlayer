import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/lyrics/lyrics_service.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';

class LyricsScreen extends StatefulWidget {
  final SongModel song;
  final String heroTag;

  const LyricsScreen({
    super.key,
    required this.song,
    required this.heroTag,
  });

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  final LyricsService _lyricsService = LyricsService();
  late Future<LyricsResult?> _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = _lyricsService.fetchLyrics(
      title: widget.song.title,
      artist: widget.song.artist ?? '',
      album: widget.song.album,
      duration: Duration(milliseconds: widget.song.duration ?? 0),
    );
  }

  void _handleVerticalDragEnd(BuildContext context, DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 250) {
      Navigator.of(context).maybePop();
    }
  }

  void _handleHorizontalDragEnd(BuildContext context, DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() > 250) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: DynamicGradientBackground(
        songId: widget.song.id,
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Hero(
                      tag: widget.heroTag,
                      child: Material(
                        color: Colors.transparent,
                        child: IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.song.artist ?? 'Unknown Artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Full Screen Lyrics Container with gesture detection
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragEnd: (details) => _handleVerticalDragEnd(context, details),
                  onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(context, details),
                  child: FutureBuilder<LyricsResult?>(
                    future: _lyricsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }

                      final result = snapshot.data;
                      if (result == null || !result.hasAny) {
                        return const Center(
                          child: Text(
                            'No lyrics found for this track',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        );
                      }

                      final String lyricsText = result.hasSynced
                          ? result.synced!.map((l) => l.text).join('\n\n')
                          : (result.plain ?? '');

                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                        child: Text(
                          lyricsText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            height: 1.8,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}