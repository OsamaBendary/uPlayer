import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether tapping a song in the library plays it and immediately opens the
/// full player screen (true, default) or just starts playback and shows it
/// in the mini player — the mini player tap is then the way to open the full
/// player (false).
final ValueNotifier<bool> songTapOpensPlayer = ValueNotifier<bool>(true);

const String _kSongTapOpensPlayer = 'song_tap_opens_player';

Future<void> loadSongTapPreference() async {
  final prefs = await SharedPreferences.getInstance();
  songTapOpensPlayer.value = prefs.getBool(_kSongTapOpensPlayer) ?? true;
}

Future<void> setSongTapOpensPlayer(bool value) async {
  songTapOpensPlayer.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kSongTapOpensPlayer, value);
}
