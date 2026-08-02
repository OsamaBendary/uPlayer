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
class LyricsService {
  static const String _base = 'https://lrclib.net/api';

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
      print('[LyricsService] ERROR: $e');
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

    print('[LyricsService] GET $uri');

    final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));

    print('[LyricsService] /get -> ${response.statusCode}');
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

    print('[LyricsService] GET $uri');

    final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));

    print('[LyricsService] /search -> ${response.statusCode}');
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

    // Matches a single leading timestamp tag, e.g. "[01:23.45]". Lines can
    // carry more than one of these (repeated-line LRC syntax), so we scan
    // for all of them per line rather than just the first.
    final tagExp = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

    // Normalize line endings first: if the source uses CRLF, splitting on
    // '\n' alone leaves a trailing '\r' on every line, which breaks a
    // '$'-anchored match and silently drops every single line.
    final normalized = syncedRaw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    for (final rawLine in normalized.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final tags = tagExp.allMatches(line).toList();
      if (tags.isEmpty) continue;

      // The lyric text is whatever follows the last timestamp tag.
      final text = line.substring(tags.last.end).trim();
      if (text.isEmpty) continue;

      // Emit one LyricLine per tag, so repeated-line syntax like
      // "[00:12.00][00:45.00]same line" produces two synced entries.
      for (final tag in tags) {
        final minutes = int.parse(tag.group(1)!);
        final seconds = int.parse(tag.group(2)!);
        final fraction = tag.group(3)!;
        final millis = fraction.length == 2 ? int.parse(fraction) * 10 : int.parse(fraction);
        lines.add(LyricLine(
          Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
          text,
        ));
      }
    }

    if (lines.isEmpty) return LyricsResult(plain: plain);

    // Guarantee chronological order regardless of source formatting —
    // both the overlay and the full-screen view assume ascending time.
    lines.sort((a, b) => a.time.compareTo(b.time));

    return LyricsResult(synced: lines, plain: plain);
  }
}