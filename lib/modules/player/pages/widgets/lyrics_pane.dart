import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:u_player/platform/audio_query_compat.dart';
import 'package:u_player/core/services/lyrics/lyrics_service.dart';
import 'package:u_player/core/services/player/playback_controller.dart';

/// The desktop player's lyrics body — the pane it sits in owns the header
/// and the Queue | Lyrics switch above it.
///
/// Unlike the phone's lyrics overlay there is no toggle: the widget reloads
/// whenever the playing track changes. Synced lyrics highlight and
/// auto-scroll with playback; plain lyrics fall back to a scrollable block;
/// missing lyrics say so.
class LyricsPane extends StatefulWidget {
  final SongModel song;

  const LyricsPane({super.key, required this.song});

  @override
  State<LyricsPane> createState() => _LyricsPaneState();
}

class _LyricsPaneState extends State<LyricsPane> {
  final LyricsService _lyricsService = LyricsService();
  final ItemScrollController _itemScrollController = ItemScrollController();

  StreamSubscription<Duration>? _positionSubscription;
  LyricsResult? _result;
  bool _isLoading = true;
  List<LyricLine> _synced = const [];
  // -1 means "no line active yet" — avoids highlighting line 0 prematurely.
  int _activeIndex = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LyricsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) _load();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _positionSubscription?.cancel();
    _positionSubscription = null;

    final songId = widget.song.id;
    setState(() {
      _isLoading = true;
      _result = null;
      _synced = const [];
      _activeIndex = -1;
    });

    final result = await _lyricsService.fetchLyrics(
      title: widget.song.title,
      artist: widget.song.artist ?? '',
      album: widget.song.album,
      duration: Duration(milliseconds: widget.song.duration ?? 0),
    );

    // A newer track may have been requested while this fetch was in flight.
    if (!mounted || songId != widget.song.id) return;

    setState(() {
      _result = result;
      _isLoading = false;
      _synced = result?.synced ?? const [];
      _activeIndex = _synced.isEmpty
          ? -1
          : _indexFor(PlaybackController.instance.audioPlayer.position);
    });

    if (_synced.isEmpty) return;

    _listenToPosition();

    // Lyrics for a track that is already mid-playback: land on the right
    // line instead of starting the list at the top.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollController.isAttached || _activeIndex <= 0) {
        return;
      }
      _itemScrollController.jumpTo(index: _activeIndex, alignment: 0.42);
    });
  }

  int _indexFor(Duration position) {
    var index = -1;
    for (var i = 0; i < _synced.length; i++) {
      if (position >= _synced[i].time) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _listenToPosition() {
    _positionSubscription =
        PlaybackController.instance.audioPlayer.positionStream.listen((position) {
      if (!mounted || _synced.isEmpty) return;

      final index = _indexFor(position);
      if (index == -1 || index == _activeIndex) return;

      setState(() => _activeIndex = index);
      if (_itemScrollController.isAttached) {
        _itemScrollController.scrollTo(
          index: index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: 0.42,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _body();
  }

  Widget _body() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
        ),
      );
    }

    final result = _result;
    if (result == null || !result.hasAny) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No lyrics found for this track',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

    if (result.hasSynced) {
      return ScrollablePositionedList.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 90),
        itemCount: _synced.length,
        itemScrollController: _itemScrollController,
        itemBuilder: (context, index) {
          final isActive = index == _activeIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white38,
                fontSize: isActive ? 18 : 15,
                height: 1.4,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              ),
              child: Text(
                _synced[index].text,
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
    }

    // Plain, unsynced lyrics — just a scrollable block of text.
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Text(
        result.plain ?? '',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.7),
      ),
    );
  }
}
