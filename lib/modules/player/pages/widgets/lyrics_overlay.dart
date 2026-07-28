import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/lyrics/lyrics_service.dart';
import 'package:u_player/core/services/player/playback_controller.dart';

/// Sits inside the same Stack as the album artwork on the player screen,
/// covering it when the lyrics button is toggled on. Fetches lyrics for
/// the current song once (cached per song id for the widget's lifetime)
/// and, if they're synced, highlights + auto-scrolls to the current line
/// as playback position advances.
class LyricsOverlay extends StatefulWidget {
  final SongModel song;
  final BorderRadius borderRadius;
  final VoidCallback onClose;

  const LyricsOverlay({
    super.key,
    required this.song,
    required this.borderRadius,
    required this.onClose,
  });

  @override
  State<LyricsOverlay> createState() => _LyricsOverlayState();
}

class _LyricsOverlayState extends State<LyricsOverlay> {
  final LyricsService _lyricsService = LyricsService();
  final ScrollController _scrollController = ScrollController();

  LyricsResult? _result;
  bool _isLoading = true;
  bool _hasError = false;
  int _lastHighlightedIndex = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LyricsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _lastHighlightedIndex = -1;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _result = null;
    });

    final duration = Duration(milliseconds: widget.song.duration ?? 0);
    final result = await _lyricsService.fetchLyrics(
      title: widget.song.title,
      artist: widget.song.artist ?? 'Unknown Artist',
      album: widget.song.album,
      duration: duration,
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _hasError = result == null;
      _isLoading = false;
    });
  }

  void _maybeAutoScroll(int index, List<LyricLine> lines) {
    if (index == _lastHighlightedIndex || !_scrollController.hasClients) return;
    _lastHighlightedIndex = index;

    // Roughly center the active line — exact height isn't critical here,
    // this just needs to keep the current line comfortably in view.
    const lineHeight = 40.0;
    final target = (index * lineHeight) - 100;
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Container(
        color: Colors.black.withValues(alpha: 0.88),
        child: Stack(
          children: [
            Positioned.fill(child: _buildBody()),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: widget.onClose,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasError || _result == null || !_result!.hasAny) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No lyrics found for this song',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    if (_result!.hasSynced) {
      final lines = _result!.synced!;
      return StreamBuilder<Duration>(
        stream: PlaybackController.instance.audioPlayer.positionStream,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          int activeIndex = 0;
          for (int i = 0; i < lines.length; i++) {
            if (lines[i].time <= position) {
              activeIndex = i;
            } else {
              break;
            }
          }
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoScroll(activeIndex, lines));

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 24),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final isActive = index == activeIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  lines[index].text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white38,
                    fontSize: isActive ? 18 : 15,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            },
          );
        },
      );
    }

    // Plain, unsynced lyrics — just a scrollable block of text.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Text(
        _result!.plain ?? '',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.6),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
