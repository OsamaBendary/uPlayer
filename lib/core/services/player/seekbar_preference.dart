import 'package:flutter/foundation.dart';

/// Whether PlayerScreen shows the animated waveform seek bar or a plain
/// linear one. Global (not screen-local state) so a choice made from the
/// mini-player's menu button sticks the next time the full player opens —
/// the waveform bar redraws every song's amplitude data and can stutter on
/// slower devices, this is the escape hatch for that.
final ValueNotifier<bool> useWaveformSeekbar = ValueNotifier<bool>(true);