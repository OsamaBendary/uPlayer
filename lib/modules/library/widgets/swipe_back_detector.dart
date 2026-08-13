import 'package:flutter/material.dart';

/// Pops the current route on a deliberate horizontal swipe, without
/// competing with taps on anything inside it.
///
/// The previous approach was `GestureDetector(onHorizontalDragEnd: ...)`
/// wrapping the whole screen body — including every tappable song row,
/// album card, and bar inside it. Any `GestureDetector` with a
/// horizontal-drag callback registers a `HorizontalDragGestureRecognizer`,
/// which competes in the same gesture arena as every descendant's tap
/// recognizer. Real fingers essentially never tap with truly zero
/// movement, so that tiny wobble could get claimed by the drag recognizer
/// instead of the tap — silently swallowing it. That's the "have to press
/// twice" symptom: the first tap wasn't slow, it just never fired.
///
/// `Listener` doesn't participate in gesture-arena disambiguation at all —
/// it just reports raw pointer events — so it can watch for the swipe
/// gesture without ever competing with (or eating) a descendant's tap.
/// Pointer ids currently being tracked as a horizontal row swipe (e.g. the
/// swipe-to-queue gesture on song rows). [SwipeBackDetector] consults this
/// before popping: a row swipe is horizontal too, so without this a song
/// being added to the queue would also pop the screen.
final Set<int> _rowSwipePointers = <int>{};

void claimRowSwipePointer(int pointer) => _rowSwipePointers.add(pointer);

void releaseRowSwipePointer(int pointer) => _rowSwipePointers.remove(pointer);

bool isRowSwipePointer(int pointer) => _rowSwipePointers.contains(pointer);

class SwipeBackDetector extends StatefulWidget {
  final Widget child;

  /// Minimum horizontal travel (px) before this counts as a swipe.
  final double threshold;

  const SwipeBackDetector({super.key, required this.child, this.threshold = 60});

  @override
  State<SwipeBackDetector> createState() => _SwipeBackDetectorState();
}

class _SwipeBackDetectorState extends State<SwipeBackDetector> {
  Offset? _startPosition;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _startPosition = event.position,
      onPointerUp: (event) {
        final start = _startPosition;
        _startPosition = null;
        if (start == null) return;

        final dx = event.position.dx - start.dx;
        final dy = event.position.dy - start.dy;

        // A row-level swipe (swipe-to-queue) is handled by the row itself —
        // don't also pop the route for it.
        if (isRowSwipePointer(event.pointer)) return;

        // Only counts as a swipe-back if horizontal movement clearly
        // dominates — otherwise a vertical scroll, or a diagonal flick
        // while scrolling a list, would trigger a false pop.
        if (dx.abs() > widget.threshold && dx.abs() > dy.abs() * 1.5) {
          Navigator.of(context).maybePop();
        }
      },
      child: widget.child,
    );
  }
}