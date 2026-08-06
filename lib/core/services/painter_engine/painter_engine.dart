import 'dart:ui';
import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final Color indicatorColor;
  final double barWidth;
  final double spacing;
  final double translateX; // horizontal scroll offset (from seekbar)

  WaveformPainter({
    required this.amplitudes,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.translateX,
    this.indicatorColor = Colors.black,
    this.barWidth = 7.0,
    this.spacing = 9.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final double contentWidth = amplitudes.length * spacing;
    final double splitX = contentWidth * progress; // in content space

    final Paint playedPaint = Paint()
      ..color = playedColor
      ..style = PaintingStyle.fill;

    final Paint unplayedPaint = Paint()
      ..color = unplayedColor
      ..style = PaintingStyle.fill;

    // Only iterate bars that can actually land inside the visible canvas.
    // This is the fix for the lag — previously every bar in the whole
    // song was drawn every frame regardless of what was on screen.
    final int startIndex = (((-translateX - barWidth) / spacing).floor()).clamp(0, amplitudes.length);
    final int endIndex = (((size.width - translateX + barWidth) / spacing).ceil()).clamp(0, amplitudes.length);

    for (int i = startIndex; i < endIndex; i++) {
      final double contentX = i * spacing;
      final double screenX = contentX + translateX;
      final double amplitude = amplitudes[i];

      final double barHeight = (size.height * 0.75) * amplitude;
      final double yTop = (size.height - barHeight) / 2;

      final RRect barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(screenX, yTop, barWidth, barHeight),
        const Radius.circular(3),
      );

      canvas.drawRRect(barRect, contentX <= splitX ? playedPaint : unplayedPaint);
    }

    // No center indicator line — split between played and unplayed bars defines the playhead position
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.translateX != translateX ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.unplayedColor != unplayedColor ||
        oldDelegate.indicatorColor != indicatorColor ||
        oldDelegate.amplitudes != amplitudes;
  }
}