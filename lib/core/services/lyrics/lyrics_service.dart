import 'dart:convert';
import 'package:http/http.dart' as http;

/// One timed line of lyrics.
class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

class LyricsResult {
  /// Word/line-synced lyrics, sorted by time. Null if the source only had
  /// plain (unsynced) lyrics, or nothing at all.
  final List<LyricLine>? synced;

  /// Plain-text lyrics, used as a fallback when there's no synced version.
  final String? plain;

  const LyricsResult({this.synced, this.plain});

  bool get hasSynced => synced != null && synced!.isNotEmpty;

  bool get hasAny => hasSynced || (plain != null && plain!.trim().isNotEmpty);
}

/// Fetches lyrics from Lrclib (https://lrclib.net) — a free, open,
/// no-auth-required API.
class LyricsService {
  static const String _base = 'https://lrclib.net/api';

  // lrclib.net asks that clients identify themselves. Update the URL to
  // point at your actual repo/homepage if you have one.
  static const Map<String, String> _headers = {
    'User-Agent': 'UPlayer/1.0.0 (https://github.com/yourname/u_player)',
  };

  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    try {
      final exact = await _getExact(title: title, artist: artist, album: album, duration: duration);
      if (exact != null) return exact;
      return await _searchFallback(title: title, artist: artist);
    } catch (e, st) {
      // TEMP diagnostic logging — remove once root cause is confirmed.
      // ignore: avoid_print
      print('[LyricsService] ERROR: $e');
      // ignore: avoid_print
      print('[LyricsService] STACK: $st');
      return null;
    }
  }

  Future<LyricsResult?> _getExact({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    final params = <String, String>{
      'track_name': title,
      'artist_name': artist,
      if (album != null && album.isNotEmpty && album != 'Unknown Album') 'album_name': album,
      if (duration != null && duration.inSeconds > 0) 'duration': duration.inSeconds.toString(),
    };
    final uri = Uri.parse('$_base/get').replace(queryParameters: params);

    // ignore: avoid_print
    print('[LyricsService] GET $uri');

    final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));

    // ignore: avoid_print
    print('[LyricsService] /get -> ${response.statusCode}');
    // ignore: avoid_print
    print('[LyricsService] body: ${response.body}');

    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _parse(data);
  }

  Future<LyricsResult?> _searchFallback({required String title, required String artist}) async {
    final uri = Uri.parse('$_base/search').replace(queryParameters: {
      'track_name': title,
      'artist_name': artist,
    });

    // ignore: avoid_print
    print('[LyricsService] GET $uri');

    final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));

    // ignore: avoid_print
    print('[LyricsService] /search -> ${response.statusCode}');
    // ignore: avoid_print
    print('[LyricsService] body: ${response.body}');

    if (response.statusCode != 200) return null;

    final list = jsonDecode(response.body) as List<dynamic>;
    if (list.isEmpty) return null;
    return _parse(list.first as Map<String, dynamic>);
  }

  LyricsResult _parse(Map<String, dynamic> data) {
    final syncedRaw = data['syncedLyrics'] as String?;
    final plain = data['plainLyrics'] as String?;

    if (syncedRaw == null || syncedRaw.trim().isEmpty) {
      return LyricsResult(plain: plain);
    }

    final lines = <LyricLine>[];
    final lineExp = RegExp(r'^\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)$');
    for (final rawLine in syncedRaw.split('\n')) {
      final match = lineExp.firstMatch(rawLine);
      if (match == null) continue;
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fraction = match.group(3)!;
      final millis = fraction.length == 2 ? int.parse(fraction) * 10 : int.parse(fraction);
      final text = match.group(4)!.trim();
      if (text.isEmpty) continue;
      lines.add(LyricLine(Duration(minutes: minutes, seconds: seconds, milliseconds: millis), text));
    }

    if (lines.isEmpty) return LyricsResult(plain: plain);
    return LyricsResult(synced: lines, plain: plain);
  }
}