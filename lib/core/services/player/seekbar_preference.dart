import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether PlayerScreen shows the animated waveform seek bar or a plain
/// linear one. Global (not screen-local state) so a choice made from the
/// customization screen sticks the next time the full player opens —
/// the waveform bar redraws every song's amplitude data and can stutter on
/// slower devices, this is the escape hatch for that.
final ValueNotifier<bool> useWaveformSeekbar = ValueNotifier<bool>(true);

const String _kUseWaveformSeekbar = 'use_waveform_seekbar';

Future<void> loadSeekbarPreference() async {
  final prefs = await SharedPreferences.getInstance();
  useWaveformSeekbar.value = prefs.getBool(_kUseWaveformSeekbar) ?? true;
}

Future<void> setUseWaveformSeekbar(bool value) async {
  useWaveformSeekbar.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kUseWaveformSeekbar, value);
}
