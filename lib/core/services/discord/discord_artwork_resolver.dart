import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:u_player/platform/audio_query_compat.dart';

/// Resolves a public, Discord-fetchable cover URL for a local song.
///
/// Discord Rich Presence cannot display local image files — the IPC activity
/// only accepts uploaded application assets or URLs its servers can reach.
/// So the album is matched against public metadata APIs (iTunes first, then
/// Deezer) and the returned square 1000×1000 cover URL is handed to Discord.
///
/// Lookups are cached per album (and de-duplicated while in flight), so each
/// album costs at most one network round-trip per app session. Every failure
/// path returns null: the presence then simply carries no artwork instead of
/// breaking the update.
class DiscordArtworkResolver {
  DiscordArtworkResolver({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 8);
  static const String _userAgent = 'uPlayer Discord Presence';

  final Map<String, String?> _resolved = {};
  final Map<String, Future<String?>> _inFlight = {};

  /// Returns an https cover URL for [song], or null when none was found.
  Future<String?> resolve(SongModel song) {
    final key = _cacheKey(song);
    if (_resolved.containsKey(key)) {
      return Future.value(_resolved[key]);
    }
    return _inFlight.putIfAbsent(key, () async {
      String? url;
      try {
        url = await _lookup(song);
      } catch (e) {
        debugPrint('[DiscordArtwork] lookup failed for "${song.title}": $e');
        url = null;
      }
      _resolved[key] = url;
      _inFlight.remove(key);
      return url;
    });
  }

  String _cacheKey(SongModel song) {
    final artist = _clean(song.artist).toLowerCase();
    final album = _clean(song.album).toLowerCase();
    if (album.isNotEmpty) return 'album:$artist\u0000$album';
    return 'song:${song.id}';
  }

  Future<String?> _lookup(SongModel song) async {
    final title = song.title.trim();
    final artist = _clean(song.artist);
    final album = _clean(song.album);

    final fromItunes = await _searchItunes(title, artist, album);
    if (fromItunes != null) return fromItunes;
    return _searchDeezer(title, artist, album);
  }

  Future<String?> _searchItunes(
    String title,
    String artist,
    String album,
  ) async {
    final term = [title, artist].where((s) => s.isNotEmpty).join(' ').trim();
    if (term.isEmpty) return null;

    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'entity': 'song',
      'limit': '25',
    });

    final res = await _client
        .get(uri, headers: const {'User-Agent': _userAgent})
        .timeout(_timeout);
    if (res.statusCode != 200) return null;

    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) return null;
    final results = body['results'];
    if (results is! List) return null;

    final candidates = <_CoverCandidate>[];
    for (final item in results) {
      if (item is! Map) continue;
      final artwork = item['artworkUrl100']?.toString() ?? '';
      if (artwork.isEmpty) continue;
      candidates.add(
        _CoverCandidate(
          title: item['trackName']?.toString() ?? '',
          artist: item['artistName']?.toString() ?? '',
          album: item['collectionName']?.toString() ?? '',
          artworkUrl: artwork,
        ),
      );
    }

    final best = _pickBest(candidates, title, artist, album);
    if (best == null) return null;
    return _upgradeItunesArtwork(best.artworkUrl);
  }

  Future<String?> _searchDeezer(
    String title,
    String artist,
    String album,
  ) async {
    final query = [
      if (title.isNotEmpty) 'track:"${_stripQuotes(title)}"',
      if (artist.isNotEmpty) 'artist:"${_stripQuotes(artist)}"',
    ].join(' ');
    if (query.isEmpty) return null;

    final uri = Uri.https('api.deezer.com', '/search', {
      'q': query,
      'limit': '10',
    });

    final res = await _client
        .get(uri, headers: const {'User-Agent': _userAgent})
        .timeout(_timeout);
    if (res.statusCode != 200) return null;

    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) return null;
    final data = body['data'];
    if (data is! List) return null;

    final candidates = <_CoverCandidate>[];
    for (final item in data) {
      if (item is! Map) continue;
      final albumMap = item['album'];
      if (albumMap is! Map) continue;
      final artwork =
          (albumMap['cover_xl'] ??
                  albumMap['cover_big'] ??
                  albumMap['cover_medium'])
              ?.toString() ??
          '';
      if (artwork.isEmpty) continue;
      candidates.add(
        _CoverCandidate(
          title: item['title']?.toString() ?? '',
          artist:
              (item['artist'] is Map ? (item['artist'] as Map)['name'] : null)
                  ?.toString() ??
              '',
          album: albumMap['title']?.toString() ?? '',
          artworkUrl: artwork,
        ),
      );
    }

    final best = _pickBest(candidates, title, artist, album);
    return best == null ? null : _validHttpsUrl(best.artworkUrl);
  }

  /// Scores candidates so an exact album/artist match beats a loose one.
  /// Falls back to the first candidate when nothing matches textually — the
  /// search term already contained title + artist, so it is still the best
  /// guess available.
  _CoverCandidate? _pickBest(
    List<_CoverCandidate> candidates,
    String title,
    String artist,
    String album,
  ) {
    if (candidates.isEmpty) return null;

    _CoverCandidate? best;
    var bestScore = -1;
    for (final candidate in candidates) {
      var score = 0;
      if (album.isNotEmpty &&
          _normalize(candidate.album) == _normalize(album)) {
        score += 3;
      }
      if (artist.isNotEmpty &&
          _normalize(candidate.artist) == _normalize(artist)) {
        score += 2;
      }
      if (title.isNotEmpty &&
          _normalize(candidate.title) == _normalize(title)) {
        score += 1;
      }
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  /// iTunes serves every size from the same URL up to the source resolution;
  /// swapping the 100×100 token for 1000×1000 gets Discord a crisp cover.
  String? _upgradeItunesArtwork(String url) {
    final upgraded = url.replaceAll('100x100bb', '1000x1000bb');
    return _validHttpsUrl(upgraded);
  }

  String? _validHttpsUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) return null;
    return uri.toString();
  }

  String _clean(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == '<unknown>') return '';
    return trimmed;
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  String _stripQuotes(String value) => value.replaceAll('"', '');
}

class _CoverCandidate {
  const _CoverCandidate({
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkUrl,
  });

  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
}
