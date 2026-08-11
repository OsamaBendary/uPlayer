import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeStreamResult {
  final String url;
  final AudioStreamInfo? streamInfo;
  final YoutubeExplode? ytClient;

  YoutubeStreamResult({
    required this.url,
    this.streamInfo,
    this.ytClient,
  });
}

/// Resolves full-length audio stream URLs directly from YouTube.
class YoutubeResolver {
  static const Map<String, String> _headers = {
    'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  static const List<String> _invidiousInstances = [
    'https://yewtu.be',
    'https://inv.nadeko.net',
    'https://invidious.privacydev.net',
  ];

  static const Duration _timeout = Duration(seconds: 6);

  static Future<YoutubeStreamResult?> resolveStream({
    required String artist,
    required String title,
    String? album,
  }) async {
    final cleanArtist = _sanitize(artist.split('•').first.split(',').first);
    final coreTitle = _extractCoreTitle(title);

    final List<String> queries = [
      '$cleanArtist $coreTitle'.trim(),
      '$cleanArtist $title'.trim(),
      '$cleanArtist $coreTitle audio'.trim(),
    ].where((q) => q.isNotEmpty).toSet().toList();

    for (final query in queries) {
      debugPrint('[YoutubeResolver] Searching: "$query"');

      // ── Strategy 1: Direct YouTube Explode (With Native Stream Client) ──────
      try {
        final yt = YoutubeExplode();
        final searchResults = await yt.search.search(query);
        if (searchResults.isNotEmpty) {
          final videoId = searchResults.first.id.value;
          final manifest = await yt.videos.streamsClient.getManifest(videoId);
          final audioStream = manifest.audioOnly.withHighestBitrate();

          debugPrint('[YoutubeResolver] Resolved via YoutubeExplode Direct!');
          return YoutubeStreamResult(
            url: audioStream.url.toString(),
            streamInfo: audioStream,
            ytClient: yt,
          );
        }
        yt.close();
      } catch (e) {
        debugPrint('[YoutubeResolver] YoutubeExplode error: $e');
      }

      // ── Strategy 2: Invidious Instances Fallback ────────────────────────────
      for (final instance in _invidiousInstances) {
        try {
          final videoId = await _searchInvidiousVideoId(instance, query);
          if (videoId == null) continue;

          final streamUrl = await _fetchInvidiousAudioStreamUrl(instance, videoId);
          if (streamUrl != null) {
            debugPrint('[YoutubeResolver] Resolved via Invidious ($instance): $streamUrl');
            return YoutubeStreamResult(url: streamUrl);
          }
        } catch (e) {
          debugPrint('[YoutubeResolver] Invidious instance $instance failed: $e');
        }
      }
    }

    return null;
  }

  // ─── Invidious Helpers ───────────────────────────────────────────────────

  static Future<String?> _searchInvidiousVideoId(String instance, String query) async {
    try {
      final uri = Uri.parse(
        '$instance/api/v1/search?q=${Uri.encodeComponent(query)}&type=video',
      );
      final res = await http.get(uri, headers: _headers).timeout(_timeout);
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) return null;

      for (final item in data) {
        if (item is Map && item['videoId'] != null) {
          return item['videoId'].toString();
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _fetchInvidiousAudioStreamUrl(
      String instance, String videoId) async {
    try {
      final uri = Uri.parse('$instance/api/v1/videos/$videoId');
      final res = await http.get(uri, headers: _headers).timeout(_timeout);
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      if (data is! Map) return null;

      final adaptiveFormats = data['adaptiveFormats'];
      if (adaptiveFormats is! List) return null;

      final audioStreams = adaptiveFormats.where((f) {
        if (f is! Map) return false;
        final type = (f['type'] ?? '').toString();
        return type.startsWith('audio/');
      }).toList();

      if (audioStreams.isEmpty) return null;

      audioStreams.sort((a, b) {
        final bitrateA = int.tryParse((a['bitrate'] ?? '0').toString()) ?? 0;
        final bitrateB = int.tryParse((b['bitrate'] ?? '0').toString()) ?? 0;
        return bitrateB.compareTo(bitrateA);
      });

      final best = audioStreams.first as Map;
      final url = (best['url'] ?? '').toString();
      if (url.startsWith('http')) return url;
    } catch (_) {}
    return null;
  }

  // ─── Sanitizers ──────────────────────────────────────────────────────────

  static String _sanitize(String input) {
    return input
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _extractCoreTitle(String input) {
    return input
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\s*-\s*(Remaster|Live|Radio Edit|Version)[^-]*$', caseSensitive: false), '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}