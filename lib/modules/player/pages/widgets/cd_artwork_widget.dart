import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/modules/library/widgets/smart_artwork_widget.dart';

/// The disc variant rendered by [CdArtworkWidget].
enum CdDiscStyle {
  /// Album art printed across the whole disc with a metallic rim — a
  /// "picture disc".
  pictureDisc,

  /// A reflective silver CD: thin rim rings, data grooves, and a small
  /// printed album-art label around the spindle hole.
  silver,

  /// A dark minimal disc: subtle radial gradient, thin elegant rings, and a
  /// small centered album-art label.
  minimal,
}

/// A spinning disc that looks like a real CD/vinyl with album artwork.
///
/// The whole disc spins clockwise when [isPlaying] is true. The disc style
/// is chosen from Settings → Customization → Artwork style.
class CdArtworkWidget extends StatefulWidget {
  final SongModel song;
  final double size;
  final bool isPlaying;
  final CdDiscStyle style;

  const CdArtworkWidget({
    super.key,
    required this.song,
    required this.size,
    required this.isPlaying,
    this.style = CdDiscStyle.pictureDisc,
  });

  @override
  State<CdArtworkWidget> createState() => _CdArtworkWidgetState();
}

class _CdArtworkWidgetState extends State<CdArtworkWidget>
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
  void didUpdateWidget(covariant CdArtworkWidget oldWidget) {
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

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft ambient glow behind the disc (outer border layer)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: size * 0.05,
                  spreadRadius: size * 0.01,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.06),
                  blurRadius: size * 0.02,
                  spreadRadius: -size * 0.005,
                ),
              ],
            ),
          ),
          // The spinning disc
          AnimatedBuilder(
            animation: _discController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _discController.value * 2 * math.pi,
                child: child,
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: _buildDisc(size),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDisc(double size) {
    switch (widget.style) {
      case CdDiscStyle.pictureDisc:
        return _buildPictureDisc(size);
      case CdDiscStyle.silver:
        return _buildSilverCd(size);
      case CdDiscStyle.minimal:
        return _buildMinimalDisc(size);
    }
  }

  // ─────────────────────────── Picture disc ───────────────────────────

  List<Widget> _buildPictureDisc(double size) {
    return [
      // Outer metallic rim with a crisp bright edge ring
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              Colors.grey.shade600,
              Colors.grey.shade300,
              Colors.grey.shade500,
              Colors.grey.shade200,
              Colors.grey.shade600,
            ],
          ),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
      ),
      // Inner highlight ring separating rim from artwork
      Container(
        width: size * 0.955,
        height: size * 0.955,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      // Album artwork filling the disc (inset for the rim)
      ClipOval(
        child: SizedBox(
          width: size * 0.93,
          height: size * 0.93,
          child: SmartArtworkWidget(
            song: widget.song,
            width: size * 0.93,
            height: size * 0.93,
            borderRadius: BorderRadius.circular(size),
            fit: BoxFit.cover,
          ),
        ),
      ),
      // Subtle vinyl groove rings
      CustomPaint(
        size: Size(size * 0.93, size * 0.93),
        painter: const _GrooveRingsPainter(alpha: 0.08),
      ),
      // Center hub
      Container(
        width: size * 0.14,
        height: size * 0.14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.grey.shade400,
              Colors.grey.shade600,
              Colors.grey.shade800,
            ],
            stops: const [0.0, 0.6, 1.0],
          ),
          border: Border.all(
            color: Colors.grey.shade400,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
      // Center spindle hole
      Container(
        width: size * 0.035,
        height: size * 0.035,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black,
          border: Border.all(
            color: Colors.grey.shade500,
            width: 1,
          ),
        ),
      ),
    ];
  }

  // ───────────────────────── Classic silver CD ─────────────────────────

  List<Widget> _buildSilverCd(double size) {
    return [
      // Reflective silver body
      Container(
        width: size,
        height: size,
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
            color: Colors.black.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
      ),
      // Metallic sheen sweep on top of the silver body
      Container(
        width: size * 0.99,
        height: size * 0.99,
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
      // Bright inner edge ring (the bevel of the disc)
      Container(
        width: size * 0.985,
        height: size * 0.985,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      // Data grooves (fine rings across the reflective band)
      CustomPaint(
        size: Size(size, size),
        painter: const _GrooveRingsPainter(
          alpha: 0.10,
          start: 0.45,
          end: 0.92,
          color: Color(0xFF40444A),
        ),
      ),
      // Printed label ring boundary
      Container(
        width: size * 0.62,
        height: size * 0.62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      // The printed label with album art
      ClipOval(
        child: SizedBox(
          width: size * 0.55,
          height: size * 0.55,
          child: SmartArtworkWidget(
            song: widget.song,
            width: size * 0.55,
            height: size * 0.55,
            borderRadius: BorderRadius.circular(size),
            fit: BoxFit.cover,
          ),
        ),
      ),
      // Label edge shadow for depth
      Container(
        width: size * 0.55,
        height: size * 0.55,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
      ),
      // Center spindle hole
      Container(
        width: size * 0.055,
        height: size * 0.055,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A1A1A),
          border: Border.all(color: Colors.grey.shade500, width: 1),
        ),
      ),
    ];
  }

  // ─────────────────────────── Minimal dark ───────────────────────────

  List<Widget> _buildMinimalDisc(double size) {
    return [
      // Dark body with a very subtle radial sheen
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              const Color(0xFF2C2C30),
              const Color(0xFF1A1A1D),
              const Color(0xFF0E0E10),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1.2,
          ),
        ),
      ),
      // Faint outer ring accent
      Container(
        width: size * 0.985,
        height: size * 0.985,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      // Soft top-light sheen
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.07),
              Colors.transparent,
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
      // Groove rings (barely visible)
      CustomPaint(
        size: Size(size, size),
        painter: const _GrooveRingsPainter(
          alpha: 0.05,
          start: 0.35,
          end: 0.88,
          color: Colors.white,
        ),
      ),
      // Small centered album-art label
      ClipOval(
        child: SizedBox(
          width: size * 0.42,
          height: size * 0.42,
          child: SmartArtworkWidget(
            song: widget.song,
            width: size * 0.42,
            height: size * 0.42,
            borderRadius: BorderRadius.circular(size),
            fit: BoxFit.cover,
          ),
        ),
      ),
      // Label ring
      Container(
        width: size * 0.42,
        height: size * 0.42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1.2,
          ),
        ),
      ),
      // Spindle hole
      Container(
        width: size * 0.045,
        height: size * 0.045,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
      ),
    ];
  }
}

/// Paints faint concentric rings across the disc surface to simulate the
/// grooves on a vinyl record / the data tracks of a CD.
class _GrooveRingsPainter extends CustomPainter {
  final double alpha;
  final double start;
  final double end;
  final Color color;

  const _GrooveRingsPainter({
    this.alpha = 0.06,
    this.start = 0.15,
    this.end = 0.95,
    this.color = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = color.withValues(alpha: alpha);

    for (double r = maxRadius * start; r < maxRadius * end; r += 3.5) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GrooveRingsPainter oldDelegate) =>
      oldDelegate.alpha != alpha ||
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.color != color;
}
