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

    // Playhead — drawn in the same pass as the bars, at the fixed center
    // of the viewport, sized to the waveform's own max possible height
    // (size.height * 0.75, same ceiling every bar uses) so it's never
    // shorter than a tall bar next to it, and reads as part of the
    // waveform rather than a UI element floating on top of it.
    final Paint indicatorPaint = Paint()
      ..color = indicatorColor
      ..style = PaintingStyle.fill;

    final double indicatorHeight = size.height * 0.75;
    final double indicatorX = size.width / 2;
    final RRect indicatorRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        indicatorX - (barWidth / 2),
        (size.height - indicatorHeight) / 2,
        barWidth,
        indicatorHeight,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(indicatorRect, indicatorPaint);
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