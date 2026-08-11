import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Resolves full-length (3–5 min) audio stream URLs from JioSaavn and public API mirrors.
class SaavnResolver {
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Origin': 'https://www.jiosaavn.com',
    'Referer': 'https://www.jiosaavn.com/',
  };

  /// Live public mirrors for JioSaavn API
  static const List<String> _apiMirrors = [
    'https://saavn.dev',
    'https://jiosaavn-api-eight.vercel.app',
    'https://jiosaavn-api-sigma-five.vercel.app',
    'https://saavn.me',
    'https://jiosaavn-api-v2.vercel.app',
  ];

  static const Duration _timeout = Duration(seconds: 5);

  static Future<String?> resolveStreamUrl({
    required String artist,
    required String title,
  }) async {
    final cleanArtist = _extractPrimaryArtist(artist);
    final cleanTitle = _cleanTitle(title);
    final queries = _buildQueries(cleanArtist, cleanTitle, title);

    for (final query in queries) {
      // Strategy 1: Direct JioSaavn Web API
      final directResult = await _searchDirectJioSaavn(query, cleanArtist, cleanTitle);
      if (directResult != null && directResult.isNotEmpty) {
        debugPrint('[SaavnResolver] Resolved via Direct JioSaavn: $directResult');
        return directResult;
      }

      // Strategy 2: API Mirrors
      final results = await Future.wait(
        _apiMirrors.map((mirror) => _searchMirror(mirror, query)),
      );

      for (final list in results) {
        if (list.isEmpty) continue;

        final best = _pickBestMatch(list, cleanArtist, cleanTitle);
        if (best == null) continue;

        final streamUrl = _extract320kbpsUrl(best);
        if (streamUrl != null && streamUrl.isNotEmpty) {
          debugPrint('[SaavnResolver] Resolved via Mirror: $streamUrl');
          return streamUrl;
        }
      }
    }

    return null;
  }

  static Future<String?> _searchDirectJioSaavn(
    String query,
    String artist,
    String title,
  ) async {
    try {
      final url = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&q=${Uri.encodeComponent(query)}',
      );
      final res = await http.get(url, headers: _headers).timeout(_timeout);
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      final list = _extractResults(data);
      if (list.isEmpty) return null;

      final best = _pickBestMatch(list, artist, title);
      if (best == null || best is! Map) return null;

      final songId = best['id']?.toString();
      if (songId != null && songId.isNotEmpty) {
        final detailsUrl = Uri.parse(
          'https://www.jiosaavn.com/api.php?__call=song.getDetails&cc=in&_marker=0&_format=json&pids=${Uri.encodeComponent(songId)}',
        );
        final detailsRes = await http.get(detailsUrl, headers: _headers).timeout(_timeout);
        if (detailsRes.statusCode == 200) {
          final detailsData = jsonDecode(detailsRes.body);
          if (detailsData is Map && detailsData[songId] is Map) {
            final songDetails = detailsData[songId] as Map;
            final streamUrl = _extract320kbpsUrl(songDetails);
            if (streamUrl != null && streamUrl.isNotEmpty) return streamUrl;
          }
        }
      }

      return _extract320kbpsUrl(best);
    } catch (e) {
      debugPrint('[SaavnResolver] Direct JioSaavn search error: $e');
      return null;
    }
  }

  static Future<List<dynamic>> _searchMirror(String mirror, String query) async {
    try {
      final url = Uri.parse(
        '$mirror/api/search/songs?query=${Uri.encodeComponent(query)}&limit=5',
      );
      final res = await http.get(url, headers: _headers).timeout(_timeout);
      if (res.statusCode != 200) return [];

      final body = res.body.trimLeft();
      if (!body.startsWith('{') && !body.startsWith('[')) return [];

      final data = jsonDecode(res.body);
      return _extractResults(data);
    } catch (_) {
      return [];
    }
  }

  static String _extractPrimaryArtist(String rawArtist) {
    if (rawArtist.contains('•')) {
      return rawArtist.split('•').first.trim();
    }
    if (rawArtist.contains(',')) {
      return rawArtist.split(',').first.trim();
    }
    return rawArtist.trim();
  }

  static String _cleanTitle(String rawTitle) {
    return rawTitle
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\s*-\s*(Remaster|Live|Radio Edit|Version)[^-]*$', caseSensitive: false), '')
        .trim();
  }

  static List<String> _buildQueries(
      String cleanArtist, String cleanTitle, String fullTitle) {
    return [
      '$cleanArtist $fullTitle',
      '$cleanArtist $cleanTitle',
      cleanTitle,
      fullTitle,
    ].where((q) => q.trim().isNotEmpty).toSet().toList();
  }

  static List<dynamic> _extractResults(dynamic data) {
    if (data == null) return [];
    if (data is Map && data['data'] is Map) {
      final inner = data['data'];
      if (inner['results'] is List) return inner['results'] as List;
    }
    if (data is Map && data['results'] is List) {
      return data['results'] as List;
    }
    if (data is List) return data;
    return [];
  }

  static dynamic _pickBestMatch(
    List<dynamic> results,
    String artist,
    String title,
  ) {
    final normArtist = _normalize(artist);
    final normTitle = _normalize(title);

    for (final r in results) {
      if (r is! Map) continue;
      final rTitle = _normalize(_saavnTitle(r));
      final rArtist = _normalize(_saavnArtist(r));
      if ((rTitle.contains(normTitle) || normTitle.contains(rTitle)) &&
          (rArtist.contains(normArtist) || normArtist.contains(rArtist))) {
        return r;
      }
    }

    for (final r in results) {
      if (r is! Map) continue;
      final rTitle = _normalize(_saavnTitle(r));
      if (rTitle.contains(normTitle) || normTitle.contains(rTitle)) return r;
    }

    return results.isNotEmpty ? results.first : null;
  }

  static String _saavnTitle(Map r) {
    return (r['name'] ?? r['title'] ?? r['song'] ?? '').toString();
  }

  static String _saavnArtist(Map r) {
    final a = r['artists'];
    if (a is Map) {
      final primary = a['primary'];
      if (primary is List && primary.isNotEmpty) {
        return (primary.first['name'] ?? '').toString();
      }
    }
    return (r['primaryArtists'] ?? r['artist'] ?? '').toString();
  }

  static String? _extract320kbpsUrl(Map result) {
    final dlList = result['downloadUrl'];
    if (dlList is List && dlList.isNotEmpty) {
      final q320 = dlList.lastWhere(
        (d) => d is Map && (d['quality']?.toString() == '320kbps' || d['quality']?.toString() == '320'),
        orElse: () => dlList.last,
      );
      final url = (q320 is Map) ? q320['url']?.toString() : null;
      if (url != null && url.startsWith('http')) return url;
    }

    final Map moreInfo = (result['more_info'] is Map) ? (result['more_info'] as Map) : result;
    final preview = (moreInfo['media_preview_url'] ?? result['media_preview_url'])?.toString();
    if (preview != null && preview.startsWith('http')) {
      final fullUrl = preview
          .replaceAll('preview.saavncdn.com', 'aac.saavncdn.com')
          .replaceAll('_96_p.mp4', '_320.mp4')
          .replaceAll('_96.mp4', '_320.mp4');
      return fullUrl;
    }

    final direct =
        result['url']?.toString() ?? result['media_url']?.toString();
    if (direct != null && direct.startsWith('http')) return direct;

    return null;
  }

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}