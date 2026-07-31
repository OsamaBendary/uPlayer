import 'dart:async';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/lyrics/lyrics_service.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class LyricsScreen extends StatefulWidget {
  final SongModel song;
  final String heroTag;

  /// Stream providing audio playback progress to power auto-scrolling
  final Stream<Duration>? positionStream;

  const LyricsScreen({
    super.key,
    required this.song,
    required this.heroTag,
    this.positionStream,
  });

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  final LyricsService _lyricsService = LyricsService();
  late Future<LyricsResult?> _lyricsFuture;
  final ItemScrollController _itemScrollController = ItemScrollController();

  StreamSubscription<Duration>? _positionSubscription;
  List<LyricLine> _syncedLyrics = [];
  int _currentActiveLyricIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchLyrics();
  }

  void _fetchLyrics() {
    _lyricsFuture = _lyricsService.fetchLyrics(
      title: widget.song.title,
      artist: widget.song.artist ?? '',
      album: widget.song.album,
      duration: Duration(milliseconds: widget.song.duration ?? 0),
    ).then((result) {
      // If we have synced lyrics, store them and listen to playback position
      if (result != null && result.hasSynced) {
        _syncedLyrics = result.synced!;
        _listenToAudioPosition();
      }
      return result;
    });
  }

  void _listenToAudioPosition() {
    if (widget.positionStream == null) return;

    _positionSubscription = widget.positionStream!.listen((position) {
      if (_syncedLyrics.isEmpty) return;

      int newIndex = -1;
      for (int i = 0; i < _syncedLyrics.length; i++) {
        if (position >= _syncedLyrics[i].time) {
          newIndex = i;
        } else {
          break;
        }
      }

      // Scroll and highlight only when the active line index actually changes
      if (newIndex != -1 && newIndex != _currentActiveLyricIndex) {
        setState(() {
          _currentActiveLyricIndex = newIndex;
        });

        if (_itemScrollController.isAttached) {
          _itemScrollController.scrollTo(
            index: _currentActiveLyricIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: 0.4, // Keeps active line slightly above center
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _handleVerticalDragEnd(BuildContext context, DragEndDetails details) {
    if ((details.primaryVelocity ?? 0) > 250) {
      Navigator.of(context).maybePop();
    }
  }

  void _handleHorizontalDragEnd(BuildContext context, DragEndDetails details) {
    if ((details.primaryVelocity ?? 0).abs() > 250) {
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
              // --- Header ---
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

              // --- Lyrics Body ---
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

                      // 1. No lyrics found at all
                      if (result == null || !result.hasAny) {
                        return const Center(
                          child: Text(
                            'No lyrics found for this track',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        );
                      }

                      // 2. CASE A: Synced Lyrics Available -> Auto-scrolling List
                      if (result.hasSynced) {
                        return ScrollablePositionedList.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 100),
                          itemCount: _syncedLyrics.length,
                          itemScrollController: _itemScrollController,
                          itemBuilder: (context, index) {
                            final line = _syncedLyrics[index];
                            final isActive = index == _currentActiveLyricIndex;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 250),
                                style: TextStyle(
                                  color: isActive ? Colors.white : Colors.white38,
                                  fontSize: isActive ? 24 : 20,
                                  height: 1.5,
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                                child: Text(
                                  line.text,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          },
                        );
                      }

                      // 3. CASE B: Plain (Unsynced) Lyrics Fallback -> Standard ScrollView
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                        child: Text(
                          result.plain ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 20,
                            height: 1.8,
                            fontWeight: FontWeight.w500,
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