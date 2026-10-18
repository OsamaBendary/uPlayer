/// Cross-platform replacement for the parts of `package:on_audio_query`
/// that uPlayer uses.
///
/// On Android everything delegates to the real plugin (MediaStore). On Linux
/// desktop — where no MediaStore exists — [SongModel]s are built from the Go
/// backend's filesystem scan and artwork comes from [ArtworkRegistry].
///
/// Every app file imports THIS library instead of `package:on_audio_query`,
/// so widget/UI code is written once and works on both platforms.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

import 'package:u_player/platform/artwork/artwork_registry.dart';
import 'package:u_player/platform/platform_env.dart';

export 'package:u_player/platform/artwork/artwork_registry.dart'
    show ArtworkRegistry;

/// Stable positive 31-bit ID for a file path (FNV-1a), used on Linux where
/// MediaStore row IDs don't exist. Persisted prefs (favorites, playlists,
/// play counts) key on this integer, so it must stay stable across runs —
/// it is derived purely from the path, never from scan order.
int linuxSongId(String path) {
  var hash = 0x811c9dc5;
  for (final code in path.codeUnits) {
    hash ^= code;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  final id = hash & 0x7FFFFFFF;
  return id == 0 ? 1 : id;
}

/// Same idea for album/artist grouping keys (name-based, not path-based).
int _stableNameId(String input) => linuxSongId('name:$input');

/// Mirrors `on_audio_query`'s SongModel (a mutable map wrapper) so the rest
/// of the app is unchanged. [getMap] returns the live map — callers like
/// `LocalAudioRepository` write disc/track enrichment straight into it.
class SongModel {
  SongModel(this._info);

  /// Wraps a MediaStore-backed song (Android).
  factory SongModel.fromAndroid(oaq.SongModel source) {
    return SongModel(Map<String, dynamic>.from(source.getMap));
  }

  /// Builds a song from one Go `LibraryScanResult` JSON entry (Linux).
  ///
  /// Field mapping notes:
  ///  * Go durations are in seconds; MediaStore durations are milliseconds.
  ///  * CUE virtual tracks (`path#trackNN`) keep their unique ID but play
  ///    the underlying audio file from the start.
  ///  * `album_id`/`artist_id` are stable hashes of the displayed name.
  factory SongModel.fromLinuxScan(Map<String, dynamic> track) {
    final rawPath = (track['filePath'] ?? '').toString();
    final playPath = rawPath.contains('#track')
        ? rawPath.substring(0, rawPath.indexOf('#track'))
        : rawPath;

    final fileName = playPath.split('/').last;
    final dotIndex = fileName.lastIndexOf('.');
    final nameNoExt = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final ext = dotIndex > 0 ? fileName.substring(dotIndex + 1) : '';

    var title = (track['trackName'] ?? '').toString().trim();
    if (title.isEmpty) title = nameNoExt;

    final artist = (track['artistName'] ?? '').toString().trim();
    var album = (track['albumName'] ?? '').toString().trim();
    if (album.isEmpty) album = 'Unknown Album';

    final durationSec = (track['duration'] as num?)?.toInt() ?? 0;
    final modMs = (track['fileModTime'] as num?)?.toInt() ?? 0;
    final trackNumber = (track['trackNumber'] as num?)?.toInt() ?? 0;
    final discNumber = (track['discNumber'] as num?)?.toInt() ?? 0;

    final info = <String, dynamic>{
      '_id': linuxSongId(rawPath),
      '_data': playPath,
      '_uri': Uri.file(playPath).toString(),
      '_display_name': fileName,
      '_display_name_wo_ext': nameNoExt,
      '_size': 0,
      'title': title,
      'artist': artist.isEmpty ? null : artist,
      'album': album,
      'album_id': _stableNameId('$album\u0000$artist'),
      'artist_id': _stableNameId(artist),
      'duration': durationSec * 1000,
      'track': trackNumber,
      'num_tracks': (track['totalTracks'] as num?)?.toInt(),
      'disc_number': discNumber,
      'total_discs': (track['totalDiscs'] as num?)?.toInt(),
      'genre': track['genre'],
      'composer': (track['composer'] ?? '').toString().isEmpty ? null : track['composer'],
      'album_artist': (track['albumArtist'] ?? '').toString().isEmpty ? null : track['albumArtist'],
      'file_extension': ext,
      'date_added': modMs,
      'date_modified': modMs,
      'is_music': true,
      'is_alarm': false,
      'is_notification': false,
      'is_podcast': false,
      'is_ringtone': false,
      // The raw scan entry is kept so richer metadata (bit depth, format,
      // ISRC, cover path) stays accessible without a re-scan.
      'linux_scan': track,
    };

    // The enrichment step in LocalAudioRepository reads these keys.
    if (trackNumber > 0) info['tag_track_number'] = trackNumber;
    info['tag_disc_number'] = discNumber;

    return SongModel(info);
  }

  final Map<String, dynamic> _info;

  int get id => (_info['_id'] as num).toInt();
  String get data => _info['_data'] as String;
  String? get uri => _info['_uri'] as String?;
  String get displayName => (_info['_display_name'] ?? '') as String;
  String get displayNameWOExt => (_info['_display_name_wo_ext'] ?? '') as String;
  int get size => (_info['_size'] as num?)?.toInt() ?? 0;
  String? get album => _info['album'] as String?;
  int? get albumId => (_info['album_id'] as num?)?.toInt();
  String? get artist => _info['artist'] as String?;
  int? get artistId => (_info['artist_id'] as num?)?.toInt();
  String? get genre => _info['genre'] as String?;
  int? get genreId => (_info['genre_id'] as num?)?.toInt();
  String? get albumArtist => _info['album_artist'] as String?;
  int? get bookmark => (_info['bookmark'] as num?)?.toInt();
  String? get composer => _info['composer'] as String?;
  int? get dateAdded => (_info['date_added'] as num?)?.toInt();
  int? get dateModified => (_info['date_modified'] as num?)?.toInt();
  int? get duration => (_info['duration'] as num?)?.toInt();
  String get title => (_info['title'] ?? '') as String;
  int? get track => (_info['track'] as num?)?.toInt();
  String get fileExtension => (_info['file_extension'] ?? '') as String;
  bool? get isAlarm => _info['is_alarm'] as bool?;
  bool? get isAudioBook => _info['is_audiobook'] as bool?;
  bool? get isMusic => _info['is_music'] as bool?;
  bool? get isNotification => _info['is_notification'] as bool?;
  bool? get isPodcast => _info['is_podcast'] as bool?;
  bool? get isRingtone => _info['is_ringtone'] as bool?;

  /// The raw scan entry (Linux only; null on Android).
  Map<String, dynamic>? get linuxScan =>
      (_info['linux_scan'] as Map?)?.cast<String, dynamic>();

  Map get getMap => _info;

  @override
  String toString() => _info.toString();
}

/// Mirrors `on_audio_query`'s ArtworkType enum.
enum ArtworkType { AUDIO, ALBUM, PLAYLIST, ARTIST, GENRE }

/// Mirrors `on_audio_query`'s ArtworkFormat enum.
enum ArtworkFormat { JPEG, PNG, WEBP }

oaq.ArtworkType _toOaqArtworkType(ArtworkType type) => oaq.ArtworkType.values
    .firstWhere((e) => e.name == type.name, orElse: () => oaq.ArtworkType.AUDIO);

oaq.ArtworkFormat? _toOaqArtworkFormat(ArtworkFormat? format) => format == null
    ? null
    : oaq.ArtworkFormat.values
        .firstWhere((e) => e.name == format.name, orElse: () => oaq.ArtworkFormat.JPEG);

/// Drop-in replacement for `on_audio_query`'s QueryArtworkWidget.
///
/// Android: renders the real plugin widget (MediaStore artwork).
/// Linux: renders the cached embedded cover / sidecar image for [id],
/// falling back to [nullArtworkWidget] when nothing is found. Sizing and
/// clipping behavior is kept identical to the plugin's implementation.
class QueryArtworkWidget extends StatelessWidget {
  const QueryArtworkWidget({
    super.key,
    required this.id,
    required this.type,
    this.quality = 50,
    this.controller,
    this.format = ArtworkFormat.JPEG,
    this.size = 200,
    this.artworkQuality = FilterQuality.low,
    this.artworkBorder,
    this.artworkWidth = 50,
    this.artworkHeight = 50,
    this.artworkFit = BoxFit.cover,
    this.artworkClipBehavior = Clip.antiAlias,
    this.artworkScale = 1.0,
    this.artworkRepeat = ImageRepeat.noRepeat,
    this.artworkColor,
    this.artworkBlendMode,
    this.keepOldArtwork = false,
    this.nullArtworkWidget,
    this.errorBuilder,
    this.frameBuilder,
  }) : assert(quality <= 100);

  final int id;
  final ArtworkType type;
  final int quality;
  final OnAudioQuery? controller;
  final ArtworkFormat format;
  final int size;
  final FilterQuality artworkQuality;
  final BorderRadius? artworkBorder;
  final double artworkWidth;
  final double artworkHeight;
  final BoxFit artworkFit;
  final Clip artworkClipBehavior;
  final double artworkScale;
  final ImageRepeat artworkRepeat;
  final Color? artworkColor;
  final BlendMode? artworkBlendMode;
  final bool keepOldArtwork;
  final Widget? nullArtworkWidget;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext, Widget, int?, bool)? frameBuilder;

  Widget _nullArtwork() =>
      nullArtworkWidget ?? const Icon(Icons.image_not_supported, size: 50);

  @override
  Widget build(BuildContext context) {
    if (!isLinuxDesktop) {
      return oaq.QueryArtworkWidget(
        id: id,
        type: _toOaqArtworkType(type),
        quality: quality,
        controller: controller == null ? null : OnAudioQuery._real,
        format: _toOaqArtworkFormat(format) ?? oaq.ArtworkFormat.JPEG,
        size: size,
        artworkQuality: artworkQuality,
        artworkBorder: artworkBorder,
        artworkWidth: artworkWidth,
        artworkHeight: artworkHeight,
        artworkFit: artworkFit,
        artworkClipBehavior: artworkClipBehavior,
        artworkScale: artworkScale,
        artworkRepeat: artworkRepeat,
        artworkColor: artworkColor,
        artworkBlendMode: artworkBlendMode,
        keepOldArtwork: keepOldArtwork,
        nullArtworkWidget: nullArtworkWidget,
        errorBuilder: errorBuilder,
        frameBuilder: frameBuilder,
      );
    }

    final file = ArtworkRegistry.instance.artworkFileForSong(id);
    if (file == null) {
      return _nullArtwork();
    }

    return ClipRRect(
      borderRadius: artworkBorder ?? BorderRadius.circular(50),
      clipBehavior: artworkClipBehavior,
      child: Image.file(
        file,
        gaplessPlayback: keepOldArtwork,
        repeat: artworkRepeat,
        scale: artworkScale,
        width: artworkWidth,
        height: artworkHeight,
        fit: artworkFit,
        color: artworkColor,
        colorBlendMode: artworkBlendMode,
        filterQuality: artworkQuality,
        frameBuilder: frameBuilder,
        errorBuilder: errorBuilder ?? (context, exception, stackTrace) {
          return _nullArtwork();
        },
      ),
    );
  }
}

/// Drop-in replacement for `on_audio_query`'s OnAudioQuery controller covering
/// the methods this app actually calls outside of the initial library scan.
class OnAudioQuery {
  OnAudioQuery({this.logConfig});

  /// Kept for API parity; unused on Linux.
  final dynamic logConfig;

  static final oaq.OnAudioQuery _real = oaq.OnAudioQuery();

  /// Artwork bytes for [id]. On Linux this reads the scanned cover cache or a
  /// sidecar image; returns null when unavailable.
  Future<Uint8List?> queryArtwork(
    int id,
    ArtworkType type, {
    int? size,
    int? quality,
    ArtworkFormat? format,
  }) {
    if (!isLinuxDesktop) {
      return _real.queryArtwork(
        id,
        _toOaqArtworkType(type),
        size: size,
        quality: quality,
        format: _toOaqArtworkFormat(format),
      );
    }
    return ArtworkRegistry.instance.readArtworkBytes(id);
  }

  /// Tells the platform media database about a new file. Android only — on
  /// Linux the next library refresh picks files up directly from disk.
  Future<void> scanMedia(String path) async {
    if (!isAndroidMobile) return;
    await _real.scanMedia(path);
  }
}
