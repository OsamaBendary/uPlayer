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