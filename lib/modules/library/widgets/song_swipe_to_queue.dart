import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/utils/app_snackbar.dart';
import 'package:u_player/modules/library/widgets/swipe_back_detector.dart';

/// Swipe-left-to-queue gesture for a song row.
///
/// Same interaction as the remove-from-queue swipe in [QueueScreen]: a
/// [Dismissible] whose background (here green, not red) is revealed while the
/// row follows the finger. Releasing past the dismiss threshold adds the song
/// to the queue and snaps the row back — the row never leaves the list.
///
/// The row claims its pointer (see [SwipeBackDetector]) as soon as it's
/// clearly dragging sideways, so the screen-level swipe-back doesn't also pop
/// the route every time a song is queued.
class SongSwipeToQueue extends StatefulWidget {
  final SongModel song;
  final Widget child;

  const SongSwipeToQueue({super.key, required this.song, required this.child});

  @override
  State<SongSwipeToQueue> createState() => _SongSwipeToQueueState();
}

class _SongSwipeToQueueState extends State<SongSwipeToQueue> {
  Offset? _startPosition;
  bool _claimed = false;

  void _onPointerDown(PointerDownEvent event) {
    _startPosition = event.position;
    _claimed = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final start = _startPosition;
    if (start == null || _claimed) return;

    final dx = event.position.dx - start.dx;
    final dy = event.position.dy - start.dy;
    if (dx.abs() > 12 && dx.abs() > dy.abs() * 1.2) {
      _claimed = true;
      claimRowSwipePointer(event.pointer);
    }
  }

  void _onPointerEnd(PointerEvent event) {
    // Release on a microtask: pointer-up fires on the row *before* the
    // screen-level SwipeBackDetector handles the same event (hit-test
    // dispatch goes leaf-first), so releasing synchronously would erase the
    // claim before it is consulted and the route would pop anyway.
    if (_claimed) {
      Future.microtask(() => releaseRowSwipePointer(event.pointer));
    }
    _claimed = false;
    _startPosition = null;
  }

  void _addToQueue(BuildContext context) {
    PlaybackController.instance.addToQueue(widget.song);
    AppSnackBar.show('"${widget.song.title}" added to queue', context: context);
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('swipe-queue-${widget.song.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: const Color(0xFF1DB954),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add_rounded, color: Colors.white, size: 22),
            SizedBox(width: 6),
            Text(
              'Add to queue',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        if (!context.mounted) return false;
        _addToQueue(context);
        return false;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerEnd,
        onPointerCancel: _onPointerEnd,
        child: widget.child,
      ),
    );
  }
}