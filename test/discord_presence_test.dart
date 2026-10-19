import 'dart:convert';

import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:u_player/core/services/discord/discord_artwork_resolver.dart';
import 'package:u_player/core/services/discord/discord_rich_presence_service.dart';
import 'package:u_player/platform/audio_query_compat.dart';

void main() {
  group('buildDiscordPresence', () {
    final now = DateTime(2026, 1, 1, 12, 0, 0);

    DiscordPresenceSnapshot playingSnapshot({
      String title = 'Never Gonna Give You Up',
      String artist = 'Rick Astley',
      String album = 'Whenever You Need Somebody',
      Duration position = const Duration(seconds: 75),
      Duration? duration = const Duration(seconds: 213),
      bool isPlaying = true,
    }) {
      return DiscordPresenceSnapshot(
        hasTrack: true,
        songId: 1,
        title: title,
        artist: artist,
        album: album,
        position: position,
        duration: duration,
        isPlaying: isPlaying,
      );
    }

    test('playing track carries title, artist • album and a position bar', () {
      final presence = buildDiscordPresence(playingSnapshot(), now: now);

      expect(presence.type, DiscordActivityType.listening);
      expect(presence.statusDisplayType, DiscordStatusDisplayType.details);
      expect(presence.details, 'Never Gonna Give You Up');
      expect(presence.state, 'Rick Astley • Whenever You Need Somebody');

      final start = now.subtract(const Duration(seconds: 75));
      final end = start.add(const Duration(seconds: 213));
      expect(presence.timestamps!.start, start.millisecondsSinceEpoch ~/ 1000);
      expect(presence.timestamps!.end, end.millisecondsSinceEpoch ~/ 1000);
    });

    test('paused track drops timestamps and marks the state as paused', () {
      final presence = buildDiscordPresence(
        playingSnapshot(isPlaying: false),
        now: now,
      );

      expect(presence.timestamps, isNull);
      expect(presence.state, startsWith('Paused • '));
      expect(presence.details, 'Never Gonna Give You Up');
    });

    test('idle presence shows the library instead of a track', () {
      final presence = buildDiscordPresence(
        const DiscordPresenceSnapshot.idle(),
        now: now,
      );

      expect(presence.details, 'Browsing library');
      expect(presence.state, 'No track playing');
      expect(presence.statusDisplayType, DiscordStatusDisplayType.name);
      expect(presence.timestamps, isNull);
      expect(presence.largeAsset, isNull);
    });

    test('artwork URL becomes the large image with an album tooltip', () {
      final presence = buildDiscordPresence(
        playingSnapshot(),
        artworkUrl: 'https://example.com/cover.jpg',
        now: now,
      );

      expect(
        presence.largeAsset!.effectiveKey,
        'https://example.com/cover.jpg',
      );
      expect(
        presence.largeAsset!.text,
        'Whenever You Need Somebody • Rick Astley',
      );
    });

    test('overlong state drops the album but keeps the artist', () {
      final presence = buildDiscordPresence(
        playingSnapshot(artist: 'A' * 40, album: 'B' * 60),
        now: now,
      );

      expect(presence.state, 'A' * 40);
    });

    test('unknown / placeholder metadata is omitted from the state', () {
      final presence = buildDiscordPresence(
        playingSnapshot(artist: '<unknown>', album: 'Unknown Album'),
        now: now,
      );

      expect(presence.state, isNull);
      expect(presence.details, 'Never Gonna Give You Up');
    });

    test('control characters are flattened and field lengths clamped', () {
      final presence = buildDiscordPresence(
        playingSnapshot(title: 'Line\nOne\u0000Two'),
        now: now,
      );

      expect(presence.details, 'Line One Two');

      final long = buildDiscordPresence(
        playingSnapshot(title: 'T' * 300),
        now: now,
      );
      expect(long.details!.runes.length, 128);
    });

    test('unknown duration keeps the count-up timer without an end', () {
      final presence = buildDiscordPresence(
        playingSnapshot(duration: null),
        now: now,
      );

      expect(presence.timestamps!.start, isNotNull);
      expect(presence.timestamps!.end, isNull);
    });
  });

  group('DiscordArtworkResolver', () {
    SongModel song({
      String title = 'Never Gonna Give You Up',
      String artist = 'Rick Astley',
      String album = 'Whenever You Need Somebody',
    }) {
      return SongModel({
        '_id': 7,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': 213000,
      });
    }

    test(
      'upgrades the iTunes cover to 1000x1000 and picks the album match',
      () async {
        final resolver = DiscordArtworkResolver(
          client: MockClient((request) async {
            expect(request.url.host, 'itunes.apple.com');
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'trackName': 'Never Gonna Give You Up',
                    'artistName': 'Rick Astley',
                    'collectionName': 'Some Other Album',
                    'artworkUrl100':
                        'https://is1-ssl.mzstatic.com/image/thumb/other/100x100bb.jpg',
                  },
                  {
                    'trackName': 'Never Gonna Give You Up',
                    'artistName': 'Rick Astley',
                    'collectionName': 'Whenever You Need Somebody',
                    'artworkUrl100':
                        'https://is1-ssl.mzstatic.com/image/thumb/right/100x100bb.jpg',
                  },
                ],
              }),
              200,
            );
          }),
        );

        final url = await resolver.resolve(song());

        expect(
          url,
          'https://is1-ssl.mzstatic.com/image/thumb/right/1000x1000bb.jpg',
        );
      },
    );

    test('falls back to Deezer when iTunes has no results', () async {
      final resolver = DiscordArtworkResolver(
        client: MockClient((request) async {
          if (request.url.host == 'itunes.apple.com') {
            return http.Response(jsonEncode({'results': <Object>[]}), 200);
          }
          expect(request.url.host, 'api.deezer.com');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'title': 'Never Gonna Give You Up',
                  'artist': {'name': 'Rick Astley'},
                  'album': {
                    'title': 'Whenever You Need Somebody',
                    'cover_xl':
                        'https://cdn-images.dzcdn.net/images/cover/x/1000x1000-000000-80-0-0.jpg',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final url = await resolver.resolve(song());

      expect(
        url,
        'https://cdn-images.dzcdn.net/images/cover/x/1000x1000-000000-80-0-0.jpg',
      );
    });

    test(
      'returns null when no source has a cover and caches the miss',
      () async {
        var calls = 0;
        final resolver = DiscordArtworkResolver(
          client: MockClient((request) async {
            calls++;
            if (request.url.host == 'itunes.apple.com') {
              return http.Response(jsonEncode({'results': <Object>[]}), 200);
            }
            return http.Response(jsonEncode({'data': <Object>[]}), 200);
          }),
        );

        expect(await resolver.resolve(song()), isNull);
        expect(await resolver.resolve(song()), isNull);
        // One iTunes call + one Deezer call for the album, then the cached miss.
        expect(calls, 2);
      },
    );
  });
}
