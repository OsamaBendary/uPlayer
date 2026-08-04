import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists how many times each song has been played, keyed by the
/// on_audio_query song id (same id scheme FavoritesService uses).
/// Stored as a single JSON-encoded map so we don't need one SharedPreferences
/// key per song.
class PlayCountService {
  static const String _key = 'song_play_counts';

  Future<Map<String, int>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, (value as num).toInt()));
    } catch (_) {
      // Corrupted/old data shouldn't crash the app — just start fresh.
      return {};
    }
  }

  Future<void> _save(Map<String, int> counts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(counts));
  }

  Future<int> getPlayCount(int songId) async {
    final counts = await _load();
    return counts[songId.toString()] ?? 0;
  }

  Future<Map<String, int>> getAllPlayCounts() async {
    return _load();
  }

  /// Increments and persists the count, returning the new value so callers
  /// (PlaybackController) can update their in-memory cache without an
  /// extra read.
  Future<int> incrementPlayCount(int songId) async {
    final counts = await _load();
    final key = songId.toString();
    final next = (counts[key] ?? 0) + 1;
    counts[key] = next;
    await _save(counts);
    return next;
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
