import 'dart:math';
import 'package:flutter/material.dart';
import 'package:u_player/core/services/painter_engine/painter_engine.dart';

class WaveformSeekbar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Function(Duration) onSeek;
  final List<double>? customAmplitudes; // Real extracted waveform, when available
  final bool isLoading; // True while the real waveform is still being decoded

  const WaveformSeekbar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.customAmplitudes,
    this.isLoading = false,
  });

  @override
  State<WaveformSeekbar> createState() => _WaveformSeekbarState();
}

class _WaveformSeekbarState extends State<WaveformSeekbar> {
  static const double _barWidth = 8.0;
  static const double _barGap = 2;
  static const double _spacing = _barWidth + _barGap;

  late List<double> _amplitudes;
  int _barCount = 0;

  bool _isDragging = false;
  double _scrubProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _rebuildAmplitudes();
  }

  @override
  void didUpdateWidget(covariant WaveformSeekbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customAmplitudes != oldWidget.customAmplitudes ||
        widget.duration != oldWidget.duration) {
      _rebuildAmplitudes();
    }
  }

  void _rebuildAmplitudes() {
    if (widget.customAmplitudes != null && widget.customAmplitudes!.isNotEmpty) {
      _amplitudes = widget.customAmplitudes!;
      _barCount = _amplitudes.length;
      return;
    }
    // Placeholder only — shown while the real waveform is being decoded,
    // or if extraction failed. Density scales with duration so it never
    // runs out of bars for long tracks (this was the original bug).
    _barCount = (widget.duration.inMilliseconds / 250).round().clamp(40, 2000);
    _amplitudes = _generatePlaceholderWaveform(_barCount);
  }

  List<double> _generatePlaceholderWaveform(int barCount) {
    final Random random = Random(42);
    return List.generate(barCount, (index) {
      double sinValue = sin(index * 0.2).abs();
      return (0.2 + (sinValue * 0.5) + (random.nextDouble() * 0.3)).clamp(0.15, 1.0);
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  double get _currentProgress {
    if (_isDragging) return _scrubProgress;
    if (widget.duration.inMilliseconds == 0) return 0.0;
    return (widget.position.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Duration get _displayedPosition {
    if (_isDragging) {
      return Duration(milliseconds: (widget.duration.inMilliseconds * _scrubProgress).round());
    }
    return widget.position;
  }

  @override
  Widget build(BuildContext context) {
    final double contentWidth = _barCount * _spacing;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double viewportWidth = constraints.maxWidth;
        final double progress = _currentProgress;
        final double translateX = viewportWidth / 2 - contentWidth * progress;

        void seekToLocalX(double localX) {
          final double contentX = localX - translateX;
          final double newProgress = (contentX / contentWidth).clamp(0.0, 1.0);
          widget.onSeek(
            Duration(
                milliseconds: (widget.duration.inMilliseconds * newProgress)
                    .round()),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seekToLocalX(details.localPosition.dx),
          onHorizontalDragStart: (details) {
            setState(() {
              _isDragging = true;
              _scrubProgress = _currentProgress;
            });
          },
          onHorizontalDragUpdate: (details) {
            setState(() {
              _scrubProgress =
                  (_scrubProgress - details.delta.dx / contentWidth).clamp(
                      0.0, 1.0);
            });
          },
          onHorizontalDragEnd: (details) {
            widget.onSeek(
              Duration(milliseconds: (widget.duration.inMilliseconds *
                  _scrubProgress).round()),
            );
            setState(() => _isDragging = false);
          },
          child: SizedBox(
            height: 140,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Waveform + playhead, painted together, viewport-sized
                // canvas only — no more giant offscreen content width.
                Positioned.fill(
                  child: ClipRect(
                    child: ShaderMask(
                      shaderCallback: (rect) {
                        return const LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black,
                            Colors.black,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.12, 0.88, 1.0],
                        ).createShader(rect);
                      },
                      blendMode: BlendMode.dstIn,
                      child: AnimatedOpacity(
                        opacity: widget.isLoading ? 0.4 : 1.0,
                        duration: const Duration(milliseconds: 250),
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: Size(viewportWidth, 140),
                            painter: WaveformPainter(
                              amplitudes: _amplitudes,
                              progress: progress,
                              translateX: translateX,
                              playedColor: Colors.grey.shade600,
                              // passed — dimmed
                              unplayedColor: Colors.white,
                              // upcoming — full white
                              indicatorColor: Colors.black,
                              barWidth: _barWidth,
                              spacing: _spacing,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Elapsed time badge
                Positioned(
                  left: 4,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDuration(_displayedPosition),
                      style: const TextStyle(color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                // Total duration badge
                Positioned(
                  right: 4,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDuration(widget.duration),
                      style: const TextStyle(color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}