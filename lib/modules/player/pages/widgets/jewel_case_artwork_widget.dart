import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/modules/library/widgets/smart_artwork_widget.dart';

/// A jewel-case CD look: the square album cover sits in a transparent plastic
/// case with a glossy border, and a silver CD peeks out from behind the right
/// edge. The exposed CD spins when [isPlaying] is true.
class JewelCaseArtworkWidget extends StatefulWidget {
  final SongModel song;
  final double size;
  final bool isPlaying;

  const JewelCaseArtworkWidget({
    super.key,
    required this.song,
    required this.size,
    required this.isPlaying,
  });

  @override
  State<JewelCaseArtworkWidget> createState() => _JewelCaseArtworkWidgetState();
}

class _JewelCaseArtworkWidgetState extends State<JewelCaseArtworkWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _discController;

  @override
  void initState() {
    super.initState();
    _discController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (widget.isPlaying) _discController.repeat();
  }

  @override
  void didUpdateWidget(covariant JewelCaseArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _discController.repeat();
      } else {
        _discController.stop();
      }
    }
  }

  @override
  void dispose() {
    _discController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.size;
    final double coverSize = size * 0.78;
    final double discSize = size * 0.62;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // ── The CD peeking out from behind the case (right side) ──
          Positioned(
            right: -discSize * 0.42,
            child: AnimatedBuilder(
              animation: _discController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _discController.value * 2 * math.pi,
                  child: child,
                );
              },
              child: SizedBox(
                width: discSize,
                height: discSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Silver reflective body
                    Container(
                      width: discSize,
                      height: discSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.grey.shade100,
                            Colors.grey.shade300,
                            Colors.grey.shade400,
                            Colors.grey.shade600,
                            Colors.grey.shade500,
                          ],
                          stops: const [0.0, 0.3, 0.55, 0.8, 1.0],
                        ),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                    ),
                    // Metallic sheen
                    Container(
                      width: discSize * 0.99,
                      height: discSize * 0.99,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.45),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.grey.shade700.withValues(alpha: 0.35),
                            Colors.white.withValues(alpha: 0.45),
                          ],
                        ),
                      ),
                    ),
                    // Data grooves
                    CustomPaint(
                      size: Size(discSize, discSize),
                      painter: const _JewelGroovesPainter(),
                    ),
                    // Printed label
                    ClipOval(
                      child: SizedBox(
                        width: discSize * 0.55,
                        height: discSize * 0.55,
                        child: SmartArtworkWidget(
                          song: widget.song,
                          width: discSize * 0.55,
                          height: discSize * 0.55,
                          borderRadius: BorderRadius.circular(discSize),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    // Spindle hole
                    Container(
                      width: discSize * 0.06,
                      height: discSize * 0.06,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1A1A1A),
                        border: Border.all(color: Colors.grey.shade500, width: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── The jewel case (transparent plastic shell) ──
          Container(
            width: coverSize,
            height: coverSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(coverSize * 0.07),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.32),
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.18),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.55),
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: coverSize * 0.05,
                  spreadRadius: coverSize * 0.01,
                  offset: Offset(0, coverSize * 0.02),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.12),
                  blurRadius: coverSize * 0.015,
                  spreadRadius: -coverSize * 0.01,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(coverSize * 0.065),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Album cover
                  SmartArtworkWidget(
                    song: widget.song,
                    width: coverSize,
                    height: coverSize,
                    borderRadius: BorderRadius.circular(coverSize * 0.065),
                    fit: BoxFit.cover,
                  ),
                  // Glossy plastic reflection
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white,
                            Colors.white,
                            Colors.white12,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.08, 0.45, 0.8],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Spindle hub + hinge peeking at the case edges ──
          Positioned(
            left: -coverSize * 0.03,
            child: Transform.translate(
              offset: Offset(0, -coverSize * 0.08),
              child: Container(
                width: coverSize * 0.05,
                height: coverSize * 0.4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint data grooves for the jewel-case's exposed CD.
class _JewelGroovesPainter extends CustomPainter {
  const _JewelGroovesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0xFF40444A).withValues(alpha: 0.10);

    for (double r = maxRadius * 0.4; r < maxRadius * 0.88; r += 3) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
