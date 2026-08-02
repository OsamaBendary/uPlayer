import 'package:shared_preferences/shared_preferences.dart';

/// Saves and restores "what was playing and where" across app restarts.
/// Unlike PlayCountService/FavoritesService, this data changes constantly
/// during playback, so PlaybackController saves it on a light timer rather
/// than on every position tick.
class PlaybackStateService {
  static const String _songIdKey = 'last_played_song_id';
  static const String _positionKey = 'last_played_position_ms';

  Future<void> saveState({required int songId, required Duration position}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_songIdKey, songId);
    await prefs.setInt(_positionKey, position.inMilliseconds);
  }

  Future<int?> getLastSongId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_songIdKey);
  }

  Future<Duration> getLastPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_positionKey) ?? 0;
    return Duration(milliseconds: ms);
  }
}