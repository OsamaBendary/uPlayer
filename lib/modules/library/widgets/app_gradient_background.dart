import 'package:flutter/material.dart';
import 'package:animate_gradient/animate_gradient.dart';

/// The library list screen doesn't have a single "song" to derive a palette
/// from (that's what DynamicGradientBackground does for the player/detail
/// screens), so it uses the same static animated gradient as the splash
/// screen instead — same colors, so the app feels continuous.
class AppGradientBackground extends StatelessWidget {
  final Widget child;

  const AppGradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimateGradient(
      animateAlignments: true,
      repeat: true,
      primaryColors: [Colors.black, Colors.deepPurple.withValues(alpha: 0.002)],
      secondaryColors: [Colors.black, const Color(591678)],
      child: child,
    );
  }
}