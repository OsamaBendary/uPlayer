import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:u_player/core/services/painter_engine/painter_engine.dart';

class WaveformSeekbar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Function(Duration) onSeek;
  final List<double>? customAmplitudes;
  final bool isLoading;
  final bool isPlaying;

  const WaveformSeekbar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.customAmplitudes,
    this.isLoading = false,
    this.isPlaying = false,
  });

  @override
  State<WaveformSeekbar> createState() => _WaveformSeekbarState();
}

class _WaveformSeekbarState extends State<WaveformSeekbar> with SingleTickerProviderStateMixin {
  static const double _barWidth = 6.0;
  static const double _barGap = 3.0;
  static const double _spacing = _barWidth + _barGap; // 9.0px per bar

  late List<double> _amplitudes;
  int _barCount = 0;

  bool _isDragging = false;
  double _scrubProgress = 0.0;

  // Smooth motion: positionStream only emits ~every 200ms, so without this
  // the waveform would jump column-to-column. Between samples we track the
  // measured playhead rate and let a ticker extrapolate continuously.
  late final Ticker _ticker;
  double _displayMs = 0;
  int? _lastSampleMs;
  DateTime? _lastSampleAt;
  double _rate = 1.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _rebuildAmplitudes();
    _displayMs = widget.position.inMilliseconds.toDouble();
    _lastSampleMs = widget.position.inMilliseconds;
    _lastSampleAt = DateTime.now();
    if (widget.isPlaying) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant WaveformSeekbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customAmplitudes != oldWidget.customAmplitudes ||
        widget.duration != oldWidget.duration) {
      _rebuildAmplitudes();
    }
    if (widget.position != oldWidget.position) {
      _recordSample(widget.position);
    }
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _lastSampleAt = DateTime.now();
        _ticker.start();
      } else {
        _ticker.stop();
        _displayMs = widget.position.inMilliseconds.toDouble();
      }
    }
  }

  void _recordSample(Duration position) {
    final now = DateTime.now();
    final ms = position.inMilliseconds.toDouble();
    final lastMs = _lastSampleMs;
    final lastAt = _lastSampleAt;
    _lastSampleMs = position.inMilliseconds;
    _lastSampleAt = now;
    if (lastMs != null && lastAt != null) {
      final deltaTime = now.difference(lastAt).inMilliseconds;
      if (deltaTime > 0) {
        final deltaMs = ms - lastMs.toDouble();
        if (deltaMs.abs() > 2000) {
          // A seek jump: follow it immediately and reset the rate baseline.
          _rate = 1.0;
          _displayMs = ms;
        } else {
          _rate = (deltaMs / deltaTime).clamp(0.0, 4.0);
        }
      }
    }
    if (!widget.isPlaying) {
      _displayMs = ms;
    }
  }

  void _onTick(Duration elapsed) {
    final lastSampleMs = _lastSampleMs;
    final lastAt = _lastSampleAt;
    if (_isDragging || lastSampleMs == null || lastAt == null) return;
    final durationMs = widget.duration.inMilliseconds;
    if (durationMs == 0) return;
    final elapsedMs = DateTime.now().difference(lastAt).inMilliseconds;
    final target = (lastSampleMs.toDouble() + elapsedMs * _rate)
        .clamp(0.0, durationMs.toDouble());
    if ((target - _displayMs).abs() < 0.5) return;
    setState(() => _displayMs = target);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _rebuildAmplitudes() {
    final targetBars = (widget.duration.inSeconds * 2).clamp(100, 250);

    if (widget.customAmplitudes != null && widget.customAmplitudes!.isNotEmpty) {
      _amplitudes = _processRawAmplitudes(widget.customAmplitudes!, targetBars);
      _barCount = _amplitudes.length;
      return;
    }

    _barCount = targetBars;
    _amplitudes = _generatePlaceholderWaveform(_barCount);
  }

  List<double> _processRawAmplitudes(List<double> raw, int targetBars) {
    if (raw.isEmpty) return [];
    
    // Find absolute values
    final absRaw = raw.map((e) => e.abs()).toList();

    if (absRaw.length <= targetBars) {
      return _normalize(absRaw);
    }

    final double blockSize = absRaw.length / targetBars;
    final List<double> result = [];

    for (int i = 0; i < targetBars; i++) {
      final int start = (i * blockSize).floor();
      final int end = ((i + 1) * blockSize).ceil().clamp(0, absRaw.length);

      double sumSquare = 0;
      double maxPeak = 0;
      int count = 0;

      for (int j = start; j < end; j++) {
        final double val = absRaw[j];
        sumSquare += val * val;
        if (val > maxPeak) maxPeak = val;
        count++;
      }

      if (count == 0) {
        result.add(0.15);
        continue;
      }

      final double rms = sqrt(sumSquare / count);
      // Combine 70% RMS (perceptual loudness) + 30% Peak (drum/transient punch)
      final double volume = (rms * 0.7) + (maxPeak * 0.3);
      result.add(volume);
    }

    return _normalize(result);
  }

  List<double> _normalize(List<double> list) {
    if (list.isEmpty) return list;
    double maxVal = list.reduce(max);
    if (maxVal <= 0.01) maxVal = 1.0;

    return list.map((val) {
      final double normalized = val / maxVal;
      return normalized.clamp(0.15, 1.0);
    }).toList();
  }

  List<double> _generatePlaceholderWaveform(int barCount) {
    final Random random = Random(42);
    return List.generate(barCount, (index) {
      double sinValue = sin(index * 0.15).abs();
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
    if (_ticker.isActive) {
      return (_displayMs / widget.duration.inMilliseconds).clamp(0.0, 1.0);
    }
    return (widget.position.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Duration get _displayedPosition {
    if (_isDragging) {
      return Duration(milliseconds: (widget.duration.inMilliseconds * _scrubProgress).round());
    }
    if (_ticker.isActive) {
      return Duration(milliseconds: _displayMs.round());
    }
    return widget.position;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double viewportWidth = constraints.maxWidth;
        final double contentWidth = _barCount * _spacing;
        final double progress = _currentProgress;
        final double translateX = viewportWidth / 2 - contentWidth * progress;

        // Effective scrub width: swiping full viewport width = 80% of total song duration
        final double dragSensitivityWidth = viewportWidth * 1.25;

        void handleTapDown(Offset localPosition) {
          if (widget.duration.inMilliseconds == 0) return;
          // Offset from center playhead (-0.5 to +0.5 of viewport)
          final double offsetFromCenter = localPosition.dx - (viewportWidth / 2);
          // Scale tap offset relative to viewport width (tapping near edge jumps ~20-25%)
          final double deltaProgress = offsetFromCenter / (viewportWidth * 1.5);
          final double newProgress = (_currentProgress + deltaProgress).clamp(0.0, 1.0);

          setState(() {
            _isDragging = true;
            _scrubProgress = newProgress;
          });

          widget.onSeek(
            Duration(milliseconds: (widget.duration.inMilliseconds * newProgress).round()),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => handleTapDown(details.localPosition),
          onHorizontalDragStart: (details) {
            setState(() {
              _isDragging = true;
              _scrubProgress = _currentProgress;
            });
          },
          onHorizontalDragUpdate: (details) {
            if (dragSensitivityWidth == 0) return;
            // Dragging left (negative dx) -> advance forward. Dragging right -> rewind back.
            final double deltaProgress = -details.delta.dx / dragSensitivityWidth;
            setState(() {
              _scrubProgress = (_scrubProgress + deltaProgress).clamp(0.0, 1.0);
            });
          },
          onHorizontalDragEnd: (details) {
            widget.onSeek(
              Duration(milliseconds: (widget.duration.inMilliseconds * _scrubProgress).round()),
            );
            setState(() => _isDragging = false);
          },
          onHorizontalDragCancel: () => setState(() => _isDragging = false),
          child: SizedBox(
            height: 140,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size(viewportWidth, 140),
                      painter: WaveformPainter(
                        amplitudes: _amplitudes,
                        progress: progress,
                        translateX: translateX,
                        playedColor: Colors.white.withValues(alpha: 0.35),
                        unplayedColor: Colors.white,
                        barWidth: _barWidth,
                        spacing: _spacing,
                      ),
                    ),
                  ),
                ),
                // Time position overlay labels
                Positioned(
                  left: 12,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12, width: 0.5),
                    ),
                    child: Text(
                      _formatDuration(_displayedPosition),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12, width: 0.5),
                    ),
                    child: Text(
                      _formatDuration(widget.duration),
                      style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
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