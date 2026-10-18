import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:u_player/core/services/player/playback_controller.dart';

/// Shared transport pieces for the Linux desktop layouts (the shell's bottom
/// bar and the full-screen player). The phone UI keeps its own widgets; these
/// exist because a mouse-and-keyboard layout wants compact, hoverable controls
/// instead of the phone's large circular buttons.

/// Formats a duration as `m:ss` (or `h:mm:ss` for long tracks).
String formatPlaybackTime(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final mm = hours > 0 ? minutes.toString().padLeft(2, '0') : minutes.toString();
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// Speaker toggle plus a level slider.
class VolumeControl extends StatelessWidget {
  final double sliderWidth;
  final double iconSize;
  final Color color;

  const VolumeControl({
    super.key,
    this.sliderWidth = 110,
    this.iconSize = 22,
    this.color = Colors.white,
  });

  IconData _iconFor(double volume) {
    if (volume <= 0.001) return Icons.volume_off_rounded;
    if (volume < 0.4) return Icons.volume_mute_rounded;
    if (volume < 0.7) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final effective = controller.isMuted ? 0.0 : controller.volume;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: effective <= 0.001 ? 'Unmute' : 'Mute',
              child: IconButton(
                iconSize: iconSize,
                color: color,
                icon: Icon(_iconFor(effective)),
                onPressed: controller.toggleMute,
              ),
            ),
            SizedBox(
              width: sliderWidth,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: color,
                  inactiveTrackColor: color.withValues(alpha: 0.24),
                  thumbColor: color,
                  overlayColor: color.withValues(alpha: 0.12),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: effective.clamp(0.0, 1.0),
                  onChanged: controller.setVolume,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Shuffle / previous / play-pause / next / repeat, sized for a desktop bar.
class TransportButtons extends StatelessWidget {
  final double buttonSize;
  final double playButtonSize;
  final Color accentColor;

  const TransportButtons({
    super.key,
    this.buttonSize = 22,
    this.playButtonSize = 30,
    this.accentColor = Colors.greenAccent,
  });

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final repeatIcon = controller.loopMode == LoopMode.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded;
        final repeatActive =
            controller.loopMode != LoopMode.off || controller.isPlayOnce;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: controller.isShuffleEnabled ? 'Shuffle on' : 'Shuffle',
              child: IconButton(
                iconSize: buttonSize,
                color: controller.isShuffleEnabled ? accentColor : Colors.white70,
                icon: const Icon(Icons.shuffle_rounded),
                onPressed: controller.toggleShuffle,
              ),
            ),
            Tooltip(
              message: 'Previous',
              child: IconButton(
                iconSize: buttonSize,
                color: Colors.white,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: () => controller.audioPlayer.seekToPrevious(),
              ),
            ),
            StreamBuilder<PlayerState>(
              stream: controller.audioPlayer.playerStateStream,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data?.playing ?? false;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Tooltip(
                    message: isPlaying ? 'Pause' : 'Play',
                    child: IconButton(
                      iconSize: playButtonSize,
                      color: Colors.white,
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          controller.audioPlayer.pause();
                        } else {
                          controller.audioPlayer.play();
                        }
                      },
                    ),
                  ),
                );
              },
            ),
            Tooltip(
              message: 'Next',
              child: IconButton(
                iconSize: buttonSize,
                color: Colors.white,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: () => controller.audioPlayer.seekToNext(),
              ),
            ),
            Tooltip(
              message: 'Repeat',
              child: IconButton(
                iconSize: buttonSize,
                color: repeatActive ? accentColor : Colors.white70,
                icon: Icon(repeatIcon),
                onPressed: controller.cycleRepeatMode,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Position / duration readout with a draggable seek bar.
///
/// The slider keeps its own drag value so a seek is only issued when the
/// drag ends (or the user taps the track), instead of on every frame of the
/// drag — which on media_kit meant a flood of seeks and audible stutter.
class SeekBarRow extends StatefulWidget {
  final Color color;
  final bool showLabels;
  final double horizontalPadding;

  const SeekBarRow({
    super.key,
    this.color = Colors.white,
    this.showLabels = true,
    this.horizontalPadding = 0,
  });

  @override
  State<SeekBarRow> createState() => _SeekBarRowState();
}

class _SeekBarRowState extends State<SeekBarRow> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return StreamBuilder<Duration>(
      stream: controller.audioPlayer.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = controller.audioPlayer.duration ??
            Duration(milliseconds: controller.currentSong?.duration ?? 0);
        final maxMs = duration.inMilliseconds.toDouble();
        final current = (_dragValue ??
                position.inMilliseconds.clamp(0, maxMs <= 0 ? 0 : maxMs).toDouble())
            .clamp(0.0, maxMs <= 0 ? 1.0 : maxMs);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
          child: Row(
            children: [
              if (widget.showLabels) ...[
                SizedBox(
                  width: 44,
                  child: Text(
                    formatPlaybackTime(
                      Duration(milliseconds: _dragValue?.round() ?? position.inMilliseconds),
                    ),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: widget.color,
                    inactiveTrackColor: widget.color.withValues(alpha: 0.24),
                    thumbColor: widget.color,
                    overlayColor: widget.color.withValues(alpha: 0.12),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: current,
                    max: maxMs <= 0 ? 1.0 : maxMs,
                    onChanged: (value) => setState(() => _dragValue = value),
                    onChangeEnd: (value) {
                      setState(() => _dragValue = null);
                      controller.audioPlayer
                          .seek(Duration(milliseconds: value.round()));
                    },
                  ),
                ),
              ),
              if (widget.showLabels) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 44,
                  child: Text(
                    formatPlaybackTime(duration),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
