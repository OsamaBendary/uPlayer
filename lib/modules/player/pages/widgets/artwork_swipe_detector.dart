import 'package:flutter/material.dart';

/// Same rationale as SwipeBackDetector in the library module: the artwork
/// Stack this wraps also contains real buttons (favorite, lyrics) — a
/// GestureDetector with onVerticalDragEnd/onHorizontalDragEnd registers
/// drag recognizers that compete with those buttons' tap recognizers in
/// the gesture arena, and any tiny finger movement during a tap can get
/// claimed by a drag recognizer instead, silently swallowing the tap.
///
/// `Listener` doesn't participate in that disambiguation at all, so it can
/// watch raw pointer movement for down/left/right swipes without ever
/// competing with (or eating) a tap on something inside it.
class ArtworkSwipeDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipeDown;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;

  /// Minimum travel (px) before this counts as a swipe rather than a tap.
  final double threshold;

  const ArtworkSwipeDetector({
    super.key,
    required this.child,
    required this.onSwipeDown,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    this.threshold = 60,
  });

  @override
  State<ArtworkSwipeDetector> createState() => _ArtworkSwipeDetectorState();
}

class _ArtworkSwipeDetectorState extends State<ArtworkSwipeDetector> {
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

        // Vertical wins only if it clearly dominates, and only downward —
        // matches the old velocity-down-only behavior.
        if (dy > widget.threshold && dy.abs() > dx.abs() * 1.5) {
          widget.onSwipeDown();
          return;
        }

        if (dx.abs() > widget.threshold && dx.abs() > dy.abs() * 1.5) {
          if (dx < 0) {
            widget.onSwipeLeft();
          } else {
            widget.onSwipeRight();
          }
        }
      },
      child: widget.child,
    );
  }
}