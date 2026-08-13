import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One iTunes Search API hit with a downloadable artwork URL.
class CoverCandidate {
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;

  const CoverCandidate({
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkUrl,
  });
}

/// Searches the iTunes Search API for album art by track title + artist.
class CoverSearchService {
  static const Duration _timeout = Duration(seconds: 8);

  Future<List<CoverCandidate>> search({
    required String title,
    required String artist,
  }) async {
    final term = [title, artist].where((s) => s.trim().isNotEmpty).join(' ');
    if (term.trim().isEmpty) return [];

    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'entity': 'song',
      'limit': '25',
    });

    try {
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return [];
      final results = body['results'];
      if (results is! List) return [];

      return [
        for (final item in results)
          if (item is Map<String, dynamic> && item['artworkUrl100'] is String)
            CoverCandidate(
              title: item['trackName']?.toString() ?? '',
              artist: item['artistName']?.toString() ?? '',
              album: item['collectionName']?.toString() ?? '',
              artworkUrl: (item['artworkUrl100'] as String)
                  .replaceAll('100x100bb', '600x600bb'),
            ),
      ];
    } catch (e) {
      debugPrint('CoverSearchService search error: $e');
      return [];
    }
  }

  Future<Uint8List?> fetchArtwork(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(_timeout);
      if (res.statusCode != 200) return null;
      return res.bodyBytes;
    } catch (e) {
      debugPrint('CoverSearchService fetchArtwork error: $e');
      return null;
    }
  }
}
