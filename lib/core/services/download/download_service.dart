import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:u_player/core/services/download/ffmpeg_service.dart';
import 'package:u_player/core/services/download/saavn_resolver.dart';
import 'package:u_player/core/services/download/youtube_resolver.dart';
import 'package:u_player/core/services/extension/extension_service.dart';
import 'package:u_player/core/services/go/go_backend_bridge.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/services/tag_editor/tag_editor_service.dart';
import 'package:u_player/core/navigation/app_keys.dart';
import 'package:u_player/core/utils/app_snackbar.dart';

class DownloadTask {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? deezerTrackId;
  final String? coverUrl;
  final DownloadQuality quality;
  final String? downloadUrl;
  final int? trackNumber;
  final String? releaseYear;
  final int durationMs;

  /// Provider-specific quality token picked for this download (e.g.
  /// "DOLBY_ATMOS", "HI_RES_LOSSLESS", "LOSSLESS"). Null when the generic
  /// app quality ([quality]) should drive the request.
  final String? providerQualityId;
  double progress;
  bool isCompleted;
  bool hasFailed;
  String status;
  String stage;

  /// Provider that rejected this item (e.g. a verification wall); used to
  /// auto-retry once the provider's session grant lands.
  String? failedService;
  VoidCallback? onUpdate;

  DownloadTask({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.deezerTrackId,
    this.coverUrl,
    required this.quality,
    this.providerQualityId,
    this.downloadUrl,
    this.trackNumber,
    this.releaseYear,
    this.durationMs = 0,
    this.progress = 0.0,
    this.isCompleted = false,
    this.hasFailed = false,
    this.status = '',
    this.stage = '',
    this.failedService,
    this.onUpdate,
  });
}

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  static const String _prefDownloadFolderKey = 'download_destination_folder';
  static const Map<String, String> _networkHeaders = {
    'User-Agent':
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Range': 'bytes=0-',
  };

  final Map<String, DownloadTask> activeDownloads = {};
  final ValueNotifier<int> activeDownloadCountNotifier = ValueNotifier<int>(0);

  Timer? _progressTimer;
  int _progressSeq = 0;
  bool _goDownloadsActive = false;
  static const String goFilenameFormat = '{artist} - {title}';

  /// Launches a web browser page for the track if background downloading requires
  /// manual Cloudflare verification or web browser interaction.
  static Future<void> openWebDownloadPage(String artist, String title) async {
    final query = Uri.encodeComponent('$artist $title');
    final webUrl = 'https://www.youtube.com/results?search_query=$query';
    final uri = Uri.parse(webUrl);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('[DownloadService] Could not launch web browser page: $e');
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
  }

  /// True when the app can write anywhere on shared storage (Android 10+
  /// "All files access"). Without it, public paths like /storage/emulated/0
  /// are read-only for apps and the Go backend reports permission errors.
  static Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  }

  /// Requests "All files access" so downloads can land in the public Music
  /// folder. Returns true when usable; false when denied (callers then fall
  /// back to the app-scoped directory).
  static Future<bool> ensureAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    if (await hasAllFilesAccess()) return true;
    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return false;
  }

  /// The public Music folder the app has always targeted:
  /// /storage/emulated/0/Music/uPlayer (created on demand).
  static Future<String> ensureMusicUPlayerFolder() async {
    final dir = Directory('/storage/emulated/0/Music/uPlayer');
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {}
    }
    return dir.path;
  }

  Future<String> getDownloadDirectoryPath() async {
    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString(_prefDownloadFolderKey);
    if (customPath != null && customPath.isNotEmpty) {
      return customPath;
    }

    // Prefer the public Music/uPlayer folder when All files access is
    // granted; otherwise fall back to the app-scoped dir (always writable).
    if (await hasAllFilesAccess()) {
      return ensureMusicUPlayerFolder();
    }
    final bridgeDir = await GoBackendBridge.instance.defaultDownloadDir();
    final dir = Directory(
      (bridgeDir != null && bridgeDir.isNotEmpty)
          ? bridgeDir
          : await ensureMusicUPlayerFolder(),
    );
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {}
    }
    return dir.path;
  }

  Future<void> setDownloadDirectoryPath(String path) async {
    // Public storage paths need "All files access" on Android 10+; ask for it
    // up-front so a later Go download doesn't fail with a permission error.
    if (path.startsWith('/storage/emulated/0/')) {
      await ensureAllFilesAccess();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefDownloadFolderKey, path);
    final bridge = GoBackendBridge.instance;
    if (bridge.isAvailable) {
      try {
        await bridge.setDownloadDirectory(path);
      } catch (_) {}
    }
  }

  Future<Map<String, String>?> _fetchDeezerTrackMeta(String trackId) async {
    try {
      final uri = Uri.parse('https://api.deezer.com/track/$trackId');
      final res = await http
          .get(uri, headers: _networkHeaders)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        'title': (data['title'] ?? '').toString(),
        'artist': (data['artist']?['name'] ?? '').toString(),
        'album': (data['album']?['title'] ?? '').toString(),
        'cover': (data['album']?['cover_xl'] ?? data['album']?['cover_medium'] ?? '').toString(),
        'releaseYear': _yearFromDate(data['album']?['release_date']),
      };
    } catch (e) {
      debugPrint('[DownloadService] Deezer track meta error: $e');
      return null;
    }
  }

  static String _yearFromDate(dynamic dateStr) {
    if (dateStr == null) return '';
    final s = dateStr.toString();
    return s.length >= 4 ? s.substring(0, 4) : '';
  }

  Future<Uint8List?> _resolveCoverBytes({
    required String artist,
    required String title,
    String? initialCoverUrl,
    String? deezerTrackId,
  }) async {
    final candidates = <String>[];

    if (initialCoverUrl != null && initialCoverUrl.isNotEmpty) {
      candidates.add(initialCoverUrl);
    }

    if (deezerTrackId != null && deezerTrackId.isNotEmpty) {
      final meta = await _fetchDeezerTrackMeta(deezerTrackId);
      final dzCover = meta?['cover'];
      if (dzCover != null && dzCover.isNotEmpty) {
        candidates.add(dzCover);
      }
    }

    try {
      final q = Uri.encodeComponent('$artist $title');
      final uri = Uri.parse(
          'https://itunes.apple.com/search?term=$q&entity=song&limit=1&lang=en_us&country=US');
      final res = await http
          .get(uri, headers: _networkHeaders)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = res.body;
        final match = RegExp(r'"artworkUrl100":"([^"]+)"').firstMatch(data);
        if (match != null) {
          final art100 = match.group(1)!;
          candidates.add(art100.replaceAll('100x100bb', '600x600bb'));
        }
      }
    } catch (_) {}

    for (final url in candidates.toSet()) {
      try {
        final imgRes = await http
            .get(Uri.parse(url), headers: _networkHeaders)
            .timeout(const Duration(seconds: 10));
        if (imgRes.statusCode == 200 && imgRes.bodyBytes.length > 2048) {
          return imgRes.bodyBytes;
        }
      } catch (_) {}
    }

    return null;
  }

  // ─── Download entrypoint ────────────────────────────────────────────────
  // Go backend (extension pipeline) is the primary path. When the gomobile
  // AAR is not linked (bridge unavailable), falls back to the legacy
  // JioSaavn/YouTube scraping path so the app never hard-fails.

  Future<void> startDownload({
    required String trackId,
    required String title,
    required String artist,
    required String album,
    String? downloadUrl,
    String? deezerTrackId,
    String? coverUrl,
    int? trackNumber,
    String? releaseYear,
    int durationMs = 0,
    DownloadQualityChoice? qualityChoice,
    VoidCallback? onProgressUpdate,
  }) async {
    if (activeDownloads.containsKey(trackId) &&
        !activeDownloads[trackId]!.hasFailed &&
        !activeDownloads[trackId]!.isCompleted) {
      return;
    }

    // Make sure the download folder is writable before queueing: the default
    // is Music/uPlayer, which needs "All files access" on Android 10+. If the
    // user denies it, downloads fall back to the app-scoped dir instead of
    // erroring with a permission failure.
    final effectiveDir = await getDownloadDirectoryPath();
    if (effectiveDir.startsWith('/storage/emulated/0/') && !await hasAllFilesAccess()) {
      await ensureAllFilesAccess();
    }

    final targetChoice = qualityChoice ??
        DownloadQualityChoice.app(ExtensionService().selectedQuality);
    final task = DownloadTask(
      id: trackId,
      title: title,
      artist: artist,
      album: album,
      deezerTrackId: deezerTrackId,
      coverUrl: coverUrl,
      quality: targetChoice.appQuality ?? ExtensionService().selectedQuality,
      providerQualityId: targetChoice.providerQualityId,
      downloadUrl: downloadUrl,
      trackNumber: trackNumber,
      releaseYear: releaseYear,
      durationMs: durationMs,
      onUpdate: onProgressUpdate,
    );

    activeDownloads[trackId] = task;
    activeDownloadCountNotifier.value = activeDownloads.length;
    onProgressUpdate?.call();

    final bridge = GoBackendBridge.instance;
    if (!bridge.isAvailable) {
      debugPrint('[DownloadService] Go bridge unavailable (${bridge.lastError}); '
          'falling back to legacy path');
      await _startDownloadLegacy(
        task: task,
        downloadUrl: downloadUrl,
        trackNumber: trackNumber,
        releaseYear: releaseYear,
      );
      return;
    }

    try {
      await _startDownloadWithGo(
        task: task,
        deezerTrackId: deezerTrackId,
        coverUrl: coverUrl,
        trackNumber: trackNumber,
        releaseYear: releaseYear,
        durationMs: durationMs,
      );
    } on GoBackendUnavailableException {
      // Bridge went away mid-flight (shouldn't happen) — safe legacy retry.
      task.hasFailed = false;
      task.progress = 0.0;
      await _startDownloadLegacy(
        task: task,
        downloadUrl: downloadUrl,
        trackNumber: trackNumber,
        releaseYear: releaseYear,
      );
    } catch (e) {
      debugPrint('[DownloadService] Go download error: $e');
      task.hasFailed = true;
      task.status = 'error';
      onProgressUpdate?.call();
    } finally {
      activeDownloadCountNotifier.value = activeDownloads.length;
    }
  }

  /// Builds the Go download request payload exactly like the reference
  /// SpotiFLAC pipeline: output extension + container-conversion flags for
  /// the selected provider, post-processing toggle, lyrics embedding mode
  /// and the Tidal HIGH-quality lossy target format.
  Map<String, dynamic> _buildGoDownloadRequest({
    required DownloadTask task,
    required String folderPath,
    required String quality,
    String? deezerTrackId,
    String? coverUrl,
    int? trackNumber,
    String? releaseYear,
    int durationMs = 0,
    String service = '',
  }) {
    final extensionService = ExtensionService();
    final effectiveService = service.isNotEmpty
        ? service
        : (extensionService.selectedProviderId ?? '');
    final outputExt = _determineOutputExt(quality, effectiveService);

    return <String, dynamic>{
      'contract_version': 1,
      'isrc': '',
      'service': effectiveService,
      'spotify_id': '',
      'track_name': task.title,
      'artist_name': task.artist,
      'album_name': task.album,
      'album_artist': '',
      'cover_url': coverUrl ?? '',
      'output_dir': folderPath,
      'filename_format': goFilenameFormat,
      'quality': quality,
      'embed_metadata': true,
      'artist_tag_mode': 'joined',
      'embed_lyrics': true,
      'embed_max_quality_cover': true,
      'embed_replaygain': false,
      'post_processing_enabled': extensionService.hasEnabledPostProcessing(),
      'tidal_high_format': 'mp3_320',
      'track_number': (trackNumber != null && trackNumber > 0) ? trackNumber : 0,
      'playlist_position': 0,
      'disc_number': 0,
      'total_tracks': 0,
      'total_discs': 0,
      'release_date': releaseYear ?? '',
      'item_id': task.id,
      'duration_ms': durationMs,
      'source': deezerTrackId != null ? 'deezer' : '',
      'genre': '',
      'label': '',
      'copyright': '',
      'composer': '',
      'tidal_id': '',
      'qobuz_id': '',
      'deezer_id': deezerTrackId ?? '',
      'lyrics_mode': 'embed',
      'use_extensions': true,
      'use_fallback': true,
      'output_ext': outputExt,
      'requires_container_conversion':
          extensionService.requiresNativeContainerConversionFor(service),
      'allow_quality_variant': false,
      'quality_variant': '',
      'songlink_region': 'US',
    };
  }

  /// Mirrors the reference `_determineOutputExt`, hardened so the quality
  /// the user picked is the quality that gets written:
  /// - Dolby/spatial tokens keep their native M4A container.
  /// - Lossless tokens always ask for FLAC unless the serving extension
  ///   must keep a native container (Dolby/DASH streams).
  /// - MP3 tokens ask for MP3.
  String _determineOutputExt(String quality, String service) {
    final extensionService = ExtensionService();
    final category = _qualityCategory(quality);
    if (category == 'DOLBY') return '.m4a';
    if (category == 'LOSSLESS') {
      for (final ext in const ['.m4a', '.opus', '.mp3']) {
        if (extensionService.preservesNativeOutputExtension(service, ext)) {
          return ext;
        }
      }
      return '.flac';
    }
    final extensionPreferred =
        extensionService.preferredDownloadOutputExtensionFor(service);
    if (extensionPreferred != null) return extensionPreferred;
    if (extensionService.replacesBuiltInProvider(service, 'tidal') &&
        category == 'HIGH') {
      return '.m4a';
    }
    final q = quality.toLowerCase();
    if (q == 'alac' || q.startsWith('aac')) return '.m4a';
    if (q.startsWith('opus')) return '.opus';
    return '.mp3';
  }

  /// Output extension implied by the Go result (explicit fields first, then
  /// the file names), or null when nothing indicates one.
  String? _downloadResultOutputExt(
    Map<String, dynamic> result, {
    String? filePath,
  }) {
    String? explicit = _normalizeAudioExt(result['actual_extension']);
    explicit ??= _normalizeAudioExt(result['output_extension']);
    explicit ??= _normalizeAudioExt(result['actual_container']);
    explicit ??= _normalizeAudioExt(result['container']);
    if (explicit != null) return explicit;

    for (final candidate in <String?>[
      result['file_name'] as String?,
      filePath,
      result['file_path'] as String?,
    ]) {
      if (candidate == null) continue;
      final lower = candidate.trim().toLowerCase();
      for (final ext in const [
        '.flac',
        '.m4a',
        '.mp4',
        '.mp3',
        '.opus',
        '.ogg',
        '.aac',
      ]) {
        if (lower.endsWith(ext)) return ext;
      }
    }
    return null;
  }

  static String? _normalizeAudioExt(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim().toLowerCase();
    if (raw.isEmpty) return null;
    if (raw == '.mp4') return '.m4a';
    switch (raw) {
      case 'flac' || '.flac':
        return '.flac';
      case 'm4a' || '.m4a' || 'mp4' || '.mp4':
        return '.m4a';
      case 'mp3' || '.mp3' || 'mpeg' || 'mpeg_audio':
        return '.mp3';
      case 'opus' || '.opus' || 'ogg' || '.ogg':
        return '.opus';
      case 'aac' || '.aac':
        return '.aac';
    }
    return null;
  }

  static String? _normalizeAudioFormatValue(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim().toLowerCase().replaceAll('-', '_');
    return switch (normalized) {
      'flac' => 'flac',
      'alac' => 'alac',
      'wav' || 'wave' => 'wav',
      'aiff' || 'aif' || 'aifc' => 'aiff',
      'aac' || 'mp4a' => 'aac',
      'eac3' || 'ec_3' => 'eac3',
      'ac3' || 'ac_3' => 'ac3',
      'ac4' || 'ac_4' => 'ac4',
      'mp3' => 'mp3',
      'opus' || 'ogg' => 'opus',
      'm4a' || 'mp4' => 'm4a',
      _ => null,
    };
  }

  static bool _isLossyAudioFormat(String? value) {
    return const {
      'aac',
      'eac3',
      'ac3',
      'ac4',
      'mp3',
      'opus',
      'm4a',
    }.contains(_normalizeAudioFormatValue(value));
  }

  Future<void> _startDownloadWithGo({
    required DownloadTask task,
    String? deezerTrackId,
    String? coverUrl,
    int? trackNumber,
    String? releaseYear,
    int durationMs = 0,
  }) async {
    final bridge = GoBackendBridge.instance;
    final folderPath = await getDownloadDirectoryPath();

    try {
      await bridge.setDownloadDirectory(folderPath);
    } catch (_) {}

    // Drop a stale cancelled flag from a previous attempt of this item.
    try {
      await bridge.resetDownloadCancel(task.id);
    } catch (_) {}

    final quality = _resolveQualityToken(task);
    final effectiveService = _resolveEffectiveService(quality);
    final request = _buildGoDownloadRequest(
      task: task,
      folderPath: folderPath,
      quality: quality,
      deezerTrackId: deezerTrackId,
      coverUrl: coverUrl,
      trackNumber: trackNumber,
      releaseYear: releaseYear,
      durationMs: durationMs,
      service: effectiveService,
    );

    await _preflightProviderVerification(effectiveService);

    _goDownloadsActive = true;
    _ensureProgressPolling();

    try {
      await bridge.initItemProgress(task.id);
      final response = await bridge.downloadByStrategy(request);

      if (response['success'] == true) {
        var filePath = response['file_path']?.toString() ?? '';
        if (filePath.isNotEmpty) {
          final finalizedPath = await _finalizeGoDownload(
            task: task,
            response: response,
            filePath: filePath,
            quality: quality,
            requestedOutputExt: request['output_ext']?.toString() ?? '',
            service: response['service']?.toString() ?? '',
            deezerTrackId: deezerTrackId,
          );
          if (finalizedPath == null) {
            task.hasFailed = true;
            task.status = 'failed';
            task.stage = '';
            debugPrint('[DownloadService] Go download finalization failed for "${task.title}"');
            task.onUpdate?.call();
            return;
          }
          filePath = finalizedPath;
        }
        task.progress = 1.0;
        task.isCompleted = true;
        task.status = 'completed';
        task.stage = '';
        if (filePath.isNotEmpty) {
          try {
            await OnAudioQuery().scanMedia(filePath);
          } catch (scanErr) {
            debugPrint('[DownloadService] Media scan error: $scanErr');
          }
        }
        await PlaybackController.instance.refreshLibrary();
        debugPrint('[DownloadService] ✓ Go download complete for "${task.title}": $filePath');
      } else {
        final error = response['error']?.toString() ?? 'Unknown error';
        final errorType = response['error_type']?.toString() ?? '';
        final service = response['service']?.toString() ?? '';
        debugPrint('[DownloadService] Go download failed ($errorType): $error');
        task.hasFailed = true;
        task.status = 'failed';
        task.stage = '';
        task.failedService = service;
        await _showGoError(error, errorType, task.title, service);
      }
    } finally {
      try {
        await bridge.clearItemProgress(task.id);
      } catch (_) {}
      _goDownloadsActive = activeDownloads.values.any((t) => !t.isCompleted && !t.hasFailed);
      task.onUpdate?.call();
    }
  }

  /// Post-download finalization, mirroring the reference pipeline:
  /// MP3 choices (HIGH/MEDIUM) that landed in a lossy native container get
  /// transcoded to the picked MP3 bitrate, lossless choices get container-
  /// converted to FLAC when the provider stream needs it, then extension
  /// post-processing hooks run. Finishes with an unconditional metadata
  /// embed so every final audio file leaves here tagged (metadata guarantee,
  /// covers conversion tag loss and providers that write bare files).
  /// Returns the final path, or null when a conversion failed.
  Future<String?> _finalizeGoDownload({
    required DownloadTask task,
    required Map<String, dynamic> response,
    required String filePath,
    required String quality,
    required String requestedOutputExt,
    required String service,
    String? deezerTrackId,
  }) async {
    if (response['native_finalized'] == true) {
      return filePath;
    }

    final genre = response['genre'] as String?;
    final label = response['label'] as String?;
    final copyright = response['copyright'] as String?;

    var path = filePath;
    final category = _qualityCategory(quality);
    if (category == 'HIGH' || category == 'MEDIUM') {
      final converted = await _finalizeLossyConversion(
        filePath: path,
        quality: category,
      );
      if (converted == null) return null;
      path = converted;
    } else if (category == 'LOSSLESS') {
      final converted = await _finalizeContainerConversion(
        response: response,
        filePath: path,
        requestedOutputExt: requestedOutputExt,
      );
      if (converted == null) return null;
      path = converted;
    }
    // DOLBY category: spatial M4A is preserved as-is.

    final postProcessed = await _runPostProcessingHooks(
      path,
      task,
      response,
      deezerTrackId,
    );
    if (postProcessed != null && postProcessed.isNotEmpty && postProcessed != path) {
      debugPrint('[DownloadService] File path changed by post-processing: $postProcessed');
      path = postProcessed;
    }

    // Metadata guarantee: whatever path the file took (provider wrote it
    // without tags, Go skipped the embed because the output already existed,
    // conversion dropped the tags, ...), the final file always leaves here
    // with tags + cover (+ lyrics) freshly embedded.
    final lowerFinal = path.toLowerCase();
    final String? resolvedExt;
    if (lowerFinal.endsWith('.flac')) {
      resolvedExt = '.flac';
    } else if (lowerFinal.endsWith('.mp3')) {
      resolvedExt = '.mp3';
    } else if (lowerFinal.endsWith('.m4a') || lowerFinal.endsWith('.mp4')) {
      resolvedExt = '.m4a';
    } else {
      resolvedExt = _downloadResultOutputExt(response, filePath: path);
    }
    final format = switch (resolvedExt) {
      '.flac' => 'flac',
      '.m4a' => 'm4a',
      '.mp3' => 'mp3',
      _ => null,
    };
    if (format != null) {
      await _embedMetadataToFile(
        path,
        task,
        format: format,
        genre: genre,
        label: label,
        copyright: copyright,
        deezerTrackId: deezerTrackId,
      );
    }

    return path;
  }

  /// MP3 choices (HIGH/MEDIUM) that landed in any other container (M4A/AAC/
  /// Opus/FLAC from the provider) are transcoded to the MP3 bitrate the user
  /// picked — chosen quality == written quality.
  Future<String?> _finalizeLossyConversion({
    required String filePath,
    required String quality,
  }) async {
    const tidalHighFormat = 'mp3_320';
    const tidalMediumFormat = 'mp3_128';
    const format = 'mp3';
    final lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.mp3')) return filePath;
    if (lowerPath.endsWith('.flac') ||
        lowerPath.endsWith('.m4a') ||
        lowerPath.endsWith('.mp4') ||
        lowerPath.endsWith('.aac') ||
        lowerPath.endsWith('.opus') ||
        lowerPath.endsWith('.ogg') ||
        lowerPath.endsWith('.wav') ||
        lowerPath.endsWith('.alac')) {
      final bitrate = quality == 'HIGH' ? tidalHighFormat : tidalMediumFormat;
      debugPrint('[DownloadService] Converting to $format ($bitrate)...');
      final convertedPath = await FFmpegService.convertM4aToLossy(
        filePath,
        format: format,
        bitrate: bitrate,
        deleteOriginal: true,
      );
      if (convertedPath == null) {
        return null;
      }
      return convertedPath;
    }
    return filePath;
  }

  /// Non-HIGH downloads that asked for FLAC but the provider stream is not
  /// native FLAC get container-converted (reference
  /// `_finalizeNativeWorkerContainerConversion`). Lossy payloads are
  /// preserved as-is.
  Future<String?> _finalizeContainerConversion({
    required String filePath,
    required Map<String, dynamic> response,
    required String requestedOutputExt,
  }) async {
    if (requestedOutputExt != '.flac') return filePath;

    final resultAudioFormat = _normalizeAudioFormatValue(
      response['audio_codec']?.toString() ??
          response['actual_audio_codec']?.toString(),
    );
    // A codec value of m4a/mp4 is container-only (it can hold ALAC);
    // decide via the real codec probe below instead of preserving blindly.
    if (resultAudioFormat != null &&
        resultAudioFormat != 'm4a' &&
        _isLossyAudioFormat(resultAudioFormat)) {
      debugPrint('[DownloadService] Output is $resultAudioFormat; preserving native container.');
      return filePath;
    }
    final requiresContainerConversion =
        response['requires_container_conversion'] == true ||
            response['requiresContainerConversion'] == true;
    final resultOutputExt = _downloadResultOutputExt(response, filePath: filePath);
    final lowerPath = filePath.toLowerCase();
    final resultFileName = (response['file_name'] as String?)?.toLowerCase();
    final mayNeedContainerConversion =
        requiresContainerConversion ||
        lowerPath.endsWith('.m4a') ||
        lowerPath.endsWith('.mp4') ||
        resultOutputExt == '.m4a' ||
        resultOutputExt == '.mp4';
    if (!mayNeedContainerConversion) return filePath;
    final looksLikeM4a =
        lowerPath.endsWith('.m4a') ||
        lowerPath.endsWith('.mp4') ||
        resultOutputExt == '.m4a' ||
        resultOutputExt == '.mp4' ||
        (resultFileName != null &&
            (resultFileName.endsWith('.m4a') || resultFileName.endsWith('.mp4')));
    if (!requiresContainerConversion && !looksLikeM4a) return filePath;

    final codec = await FFmpegService.probePrimaryAudioCodec(filePath);
    final isAlreadyNativeFlac =
        codec == 'flac' && await FFmpegService.isNativeFlacFile(filePath);
    if (!FFmpegService.isLosslessAudioCodec(codec)) {
      debugPrint('[DownloadService] Preserving native container; audio codec is '
          '${codec ?? 'unknown'} — no FLAC conversion needed.');
      return filePath;
    }
    if (isAlreadyNativeFlac) {
      var flacPath = filePath;
      if (!filePath.toLowerCase().endsWith('.flac')) {
        final renamedPath = filePath.replaceAll(RegExp(r'\.[^.]+$'), '.flac');
        final targetPath = renamedPath == filePath ? '$filePath.flac' : renamedPath;
        try {
          await File(filePath).rename(targetPath);
        } catch (e) {
          debugPrint('[DownloadService] Native FLAC rename failed: $e');
          return null;
        }
        flacPath = targetPath;
      }
      return flacPath;
    }
    debugPrint('[DownloadService] Converting to FLAC: $filePath');
    final flacPath = await FFmpegService.convertM4aToFlac(filePath);
    if (flacPath == null) return null;
    return flacPath;
  }

  /// Embeds tags + cover + lyrics on [filePath] via the Go native tag
  /// writers (reference `_embedMetadataToFile`). Used after conversions so
  /// the tags the Go download already embedded survive the remux, and as the
  /// unconditional final guarantee pass. Falls back to the Dart
  /// TagEditorService when the Go tagger rejects the file.
  Future<void> _embedMetadataToFile(
    String filePath,
    DownloadTask task, {
    required String format,
    String? genre,
    String? label,
    String? copyright,
    String? deezerTrackId,
  }) async {
    final isFlac = format == 'flac';
    final isM4a = format == 'm4a' || format == 'alac';

    String coverPath = '';
    try {
      final coverBytes = await _resolveCoverBytes(
        artist: task.artist,
        title: task.title,
        initialCoverUrl: task.coverUrl,
        deezerTrackId: deezerTrackId,
      );
      if (coverBytes != null && coverBytes.isNotEmpty) {
        final coverFile = File(
          '${Directory.systemTemp.path}/uplayer_cover_${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await coverFile.writeAsBytes(coverBytes, flush: true);
        coverPath = coverFile.path;
      }
    } catch (e) {
      debugPrint('[DownloadService] Cover fetch failed: $e');
    }

    final fields = <String, String>{
      'title': task.title,
      'artist': task.artist,
      'album': task.album,
      'artist_tag_mode': 'joined',
      if (task.releaseYear != null && task.releaseYear!.isNotEmpty)
        'date': task.releaseYear!,
      if (task.trackNumber != null && task.trackNumber! > 0)
        'track_number': task.trackNumber!.toString(),
      if (genre != null && genre.isNotEmpty) 'genre': genre,
      if (label != null && label.isNotEmpty) 'label': label,
      if (copyright != null && copyright.isNotEmpty) 'copyright': copyright,
      if (coverPath.isNotEmpty) 'cover_path': coverPath,
    };

    final source = task.deezerTrackId != null ? 'deezer' : '';
    final skipLyrics =
        ExtensionService().skipLyricsFor(source, ExtensionService().selectedProviderId);
    if (!skipLyrics) {
      String? lyrics;
      try {
        final fetched = await GoBackendBridge.instance.getLyricsLRC(
          trackName: task.title,
          artistName: task.artist,
          durationMs: task.durationMs,
        );
        if (fetched.isNotEmpty && fetched != '[instrumental:true]') {
          lyrics = fetched;
        }
      } catch (e) {
        debugPrint('[DownloadService] Lyrics fetch failed: $e');
      }
      if (lyrics != null) {
        fields['lyrics'] = lyrics;
        if (isFlac) fields['unsyncedlyrics'] = lyrics;
      } else if (isFlac || isM4a) {
        fields['lyrics'] = '';
        if (isFlac) fields['unsyncedlyrics'] = '';
      }
    }

    try {
      final response = await GoBackendBridge.instance.editFileMetadata(filePath, fields);
      if (response['success'] == true) {
        debugPrint('[DownloadService] Metadata embedded ($format) for "${task.title}"');
      } else {
        debugPrint('[DownloadService] Go metadata embed failed: ${response['error']}');
        await _fallbackTagEmbed(filePath, task, format,
            genre: genre, label: label, copyright: copyright);
      }
    } catch (e) {
      debugPrint('[DownloadService] Metadata embed failed: $e');
      await _fallbackTagEmbed(filePath, task, format,
          genre: genre, label: label, copyright: copyright);
    } finally {
      if (coverPath.isNotEmpty) {
        try {
          await File(coverPath).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _fallbackTagEmbed(
    String filePath,
    DownloadTask task,
    String format, {
    String? genre,
    String? label,
    String? copyright,
  }) async {
    try {
      final tagEditor = TagEditorService();
      var coverBytes = await _resolveCoverBytes(
        artist: task.artist,
        title: task.title,
        initialCoverUrl: task.coverUrl,
        deezerTrackId: task.deezerTrackId,
      );
      final ok = await tagEditor.writeTagsAndArtwork(
        filePath: filePath,
        title: task.title,
        artist: task.artist,
        album: task.album,
        year: task.releaseYear ?? '',
        genre: genre ?? '',
        trackNumber: task.trackNumber?.toString() ?? '',
        artworkBytes: coverBytes,
      );
      debugPrint('[DownloadService] Fallback tag embed done ($format) for '
          '"${task.title}": $ok (label=$label, copyright=$copyright)');
    } catch (e) {
      debugPrint('[DownloadService] Fallback tag embed failed ($format): $e');
    }
  }

  /// Invokes the enabled extensions' post-processing hooks (reference
  /// `_runPostProcessingHooks`). Returns the (possibly moved) path, or null
  /// when no hooks ran.
  Future<String?> _runPostProcessingHooks(
    String filePath,
    DownloadTask task,
    Map<String, dynamic> response,
    String? deezerTrackId,
  ) async {
    final extensionService = ExtensionService();
    if (!extensionService.hasEnabledPostProcessing()) return null;
    debugPrint('[DownloadService] Running post-processing hooks on: $filePath');

    final metadata = <String, dynamic>{
      'title': task.title,
      'artist': task.artist,
      'album': task.album,
      'track_number': task.trackNumber ?? 0,
      'disc_number': (response['disc_number'] as num?)?.toInt() ?? 0,
      'isrc': response['isrc']?.toString() ?? '',
      'release_date': response['release_date']?.toString() ??
          (task.releaseYear ?? ''),
      'duration_ms': task.durationMs,
      'cover_url': task.coverUrl ?? '',
    };
    final albumArtist = response['album_artist']?.toString();
    if (albumArtist != null && albumArtist.isNotEmpty) {
      metadata['album_artist'] = albumArtist;
    }

    try {
      final bridge = GoBackendBridge.instance;
      final result = await bridge.runPostProcessingV2(filePath, metadata: metadata);
      if (result['success'] == true) {
        final hooksRun = (result['hooks_run'] as num?)?.toInt() ?? 0;
        final newPath = result['file_path']?.toString();
        debugPrint('[DownloadService] Post-processing completed: $hooksRun hook(s) executed');
        if (newPath != null && newPath.isNotEmpty && newPath != filePath) {
          return newPath;
        }
        return filePath;
      }
      final error = result['error']?.toString() ?? 'Unknown error';
      debugPrint('[DownloadService] Post-processing failed: $error');
    } catch (e) {
      debugPrint('[DownloadService] Post-processing error: $e');
    }
    return null;
  }

  /// Quality token sent to Go for this task. A provider-specific pick
  /// ("DOLBY_ATMOS", "HI_RES_LOSSLESS", ...) is passed verbatim — Go honors
  /// it when the provider recognizes it. Otherwise the generic tokens are
  /// upgraded to the closest tier the chosen provider advertises (FLAC
  /// 24-bit -> hi-res tier, MP3 128k -> LOW tier when available).
  static String _resolveQualityToken(DownloadTask task) {
    final providerToken = task.providerQualityId?.trim();
    if (providerToken != null && providerToken.isNotEmpty) {
      return providerToken;
    }
    final optionIds = _providerQualityOptionIds();
    switch (task.quality) {
      case DownloadQuality.flac24:
        for (final id in const ['HI_RES_LOSSLESS', 'HI_RES', 'FLAC24']) {
          if (optionIds.contains(id)) return id;
        }
        return 'LOSSLESS';
      case DownloadQuality.flac16:
        return 'LOSSLESS';
      case DownloadQuality.mp3320:
        return 'HIGH';
      case DownloadQuality.mp3128:
        if (optionIds.contains('LOW')) return 'LOW';
        return 'MEDIUM';
    }
  }

  /// Quality option ids advertised by the enabled download extensions.
  static Set<String> _providerQualityOptionIds() {
    final ids = <String>{};
    for (final ext in ExtensionService().installedExtensions) {
      if (!ext.isEnabled || !ext.hasDownloadProvider) continue;
      final rawOptions = ext.raw['quality_options'];
      if (rawOptions is! List) continue;
      for (final option in rawOptions) {
        if (option is! Map) continue;
        final id = option['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  /// Broad bucket used to pick the finalization pipeline for a quality
  /// token: DOLBY (spatial M4A, preserved as-is), LOSSLESS (FLAC), HIGH /
  /// MEDIUM (transcoded to the chosen MP3 bitrate).
  static String _qualityCategory(String quality) {
    final q = quality.trim().toLowerCase();
    if (q.contains('dolby') || q == 'atmos' || q.contains('atmos')) return 'DOLBY';
    if (q.contains('hi_res') ||
        q.contains('hires') ||
        q.contains('flac') ||
        q.contains('lossless') ||
        q.contains('alac') ||
        q.contains('master')) {
      return 'LOSSLESS';
    }
    if (q.contains('high') || q.contains('320') || q == 'mp3') return 'HIGH';
    return 'MEDIUM';
  }

  /// Provider to send the Go download request to: the user's explicit pick,
  /// otherwise Tidal/Qobuz (or the first lossless-capable extension) for
  /// lossless quality, otherwise empty (Go walks its priority list).
  static String _resolveEffectiveService(String quality) {
    final extensionService = ExtensionService();
    final explicit = extensionService.selectedProviderId;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (_qualityCategory(quality) == 'LOSSLESS') {
      return extensionService.losslessPreferredProvider() ?? '';
    }
    return '';
  }

  /// Tidal/Qobuz-style providers require a fresh signed-session verification.
  /// Ask Go whether the challenge is currently outstanding *before* hitting
  /// downloadByStrategy so the web flow runs first and the download proceeds
  /// on the verified session instead of failing and round-tripping.
  static Future<void> _preflightProviderVerification(String service) async {
    if (service.isEmpty) return;
    final bridge = GoBackendBridge.instance;
    try {
      final pending = await bridge.getExtensionPendingAuth(service);
      final authUrl = pending?['auth_url']?.toString().trim() ?? '';
      if (authUrl.isNotEmpty) {
        debugPrint('[DownloadService] Pre-flight verification required for $service');
        AppSnackBar.show('Verifying $service — complete the browser flow, then downloads run');
        await _openProviderVerification(service);
      }
    } catch (e) {
      debugPrint('[DownloadService] Preflight verification lookup failed: $e');
    }
  }

  static Future<void> _showGoError(
    String error,
    String errorType,
    String title,
    String service,
  ) async {
    if (errorType == 'verification_required') {
      await _openProviderVerification(service);
      return;
    }
    String message;
    switch (errorType) {
      case 'isp_blocked':
        message = '"$title": blocked by your ISP — try a VPN';
        break;
      case 'rate_limit':
        message = '"$title": provider rate limit hit — retry later';
        break;
      case 'not_found':
        message = '"$title": not found on any enabled provider';
        break;
      case 'network':
        message = '"$title": network error — trying longer may help';
        break;
      case 'permission':
        message = '"$title": download folder not writable';
        break;
      case 'cancelled':
        return; // user-cancelled: silent
      default:
        message = 'Download failed for "$title"';
    }
    AppSnackBar.show(message);
  }

  /// Provider asked for a signed-session login. Fetch the pending auth URL
  /// from Go, offer to open it in the browser (or copy it).
  static Future<void> _openProviderVerification(String service) async {
    final bridge = GoBackendBridge.instance;
    if (service.isEmpty) {
      AppSnackBar.show('Provider needs login/verification — retry after verifying');
      return;
    }
    Map<String, dynamic>? pending;
    try {
      pending = await bridge.getExtensionPendingAuth(service);
    } catch (e) {
      debugPrint('[DownloadService] pending auth lookup failed: $e');
    }
    final authUrl = pending?['auth_url']?.toString().trim() ?? '';
    final context = rootNavigatorKey.currentContext;
    if (context == null || authUrl.isEmpty) {
      AppSnackBar.show('"$service" needs login/verification — retry after verifying');
      return;
    }
    final uri = Uri.tryParse(authUrl);
    if (uri == null) {
      AppSnackBar.show('"$service" needs login/verification — retry after verifying');
      return;
    }

    // Wait for the deep-link grant (`uplayer://session-grant`) that the
    // verification page redirects to once the challenge is done.
    final grantCompleter = Completer<GoSessionGrantEvent>();
    late final StreamSubscription<GoSessionGrantEvent> grantSub;
    grantSub = bridge.sessionGrantEvents
        .where((e) => e.extensionId.trim().toLowerCase() == service.toLowerCase())
        .listen((event) {
      if (!grantCompleter.isCompleted) grantCompleter.complete(event);
    });

    // Auto-open the challenge in the browser.
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      await grantSub.cancel();
      AppSnackBar.show('Could not open the browser — copy the link and retry');
      return;
    }

    unawaited(showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Verify provider',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Complete the verification in the browser that just opened. Downloads for this provider will resume automatically.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'If nothing opened, tap the link below. After verifying, come back to this screen — downloads resume on their own.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(uri.toString(),
                  style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white70),
            label: const Text('Copy link', style: TextStyle(color: Colors.white70)),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: uri.toString()));
              AppSnackBar.show('Verification link copied');
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_browser_rounded, size: 18),
            label: const Text('Open again'),
            onPressed: () async {
              final reopened = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!reopened) {
                AppSnackBar.show('Could not open the browser');
              }
            },
          ),
        ],
      ),
    ));

    // Wait up to 5 minutes for the grant; auto-retry the affected downloads.
    try {
      final event = await grantCompleter.future.timeout(const Duration(minutes: 5));
      if (event.success) {
        debugPrint('[DownloadService] Grant received for $service — resuming downloads');
        AppSnackBar.show('$service verified — resuming downloads');
        await _retryDownloadsForProvider(service);
      } else {
        AppSnackBar.show('$service verification was not accepted — retry the download');
      }
    } on TimeoutException {
      AppSnackBar.show('$service verification timed out — tap a failed download to retry');
    } finally {
      await grantSub.cancel();
    }
  }

  /// Re-queues every failed download that was rejected by [service].
  static Future<void> _retryDownloadsForProvider(String service) async {
    final tasks = DownloadService().activeDownloads.values
        .where((t) =>
            t.hasFailed &&
            !t.isCompleted &&
            (t.failedService ?? '').trim().toLowerCase() == service.toLowerCase())
        .toList();
    for (final task in tasks) {
      final ds = DownloadService();
      ds.activeDownloads.remove(task.id);
      await ds.startDownload(
        trackId: task.id,
        title: task.title,
        artist: task.artist,
        album: task.album,
        downloadUrl: task.downloadUrl,
        deezerTrackId: task.deezerTrackId,
        coverUrl: task.coverUrl,
        trackNumber: task.trackNumber,
        releaseYear: task.releaseYear,
        durationMs: task.durationMs,
        qualityChoice: DownloadQualityChoice.fromTask(task.quality, task.providerQualityId),
        onProgressUpdate: task.onUpdate,
      );
    }
  }

  /// One shared progress poller for all Go downloads; Go coalesces updates
  /// into a monotonic seq we track via delta requests.
  void _ensureProgressPolling() {
    if (_progressTimer != null) return;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _pollGoProgress();
    });
  }

  Future<void> _pollGoProgress() async {
    if (!_goDownloadsActive || activeDownloads.isEmpty) {
      _progressTimer?.cancel();
      _progressTimer = null;
      return;
    }
    final bridge = GoBackendBridge.instance;
    if (!bridge.isAvailable) return;
    try {
      final delta = await bridge.progressDelta(_progressSeq);
      if (delta.isEmpty) return;
      _progressSeq = (delta['seq'] as num?)?.toInt() ?? _progressSeq;

      final items = delta['items'];
      if (items is Map) {
        items.forEach((key, raw) {
          final id = key?.toString() ?? '';
          final task = activeDownloads[id];
          if (task == null) return;
          final p = GoDownloadProgress.fromJson(raw);
          if (p == null) return;
          task.status = p.status;
          task.stage = p.stage;
          if (p.progress > 0) {
            task.progress = (p.progress / 100).clamp(0.0, 1.0);
          }
          task.onUpdate?.call();
        });
      }

      final removed = delta['removed'];
      if (removed is List) {
        for (final id in removed) {
          final task = activeDownloads[id?.toString() ?? ''];
          if (task == null) continue;
          if (!task.isCompleted && !task.hasFailed) {
            task.progress = 1.0;
            task.isCompleted = true;
            task.status = 'completed';
            task.onUpdate?.call();
          }
        }
      }
    } catch (e) {
      debugPrint('[DownloadService] progress poll error: $e');
    }
  }

  // ─── Legacy Dart scraping path (used only when the Go AAR is absent) ────

  Future<void> _startDownloadLegacy({
    required DownloadTask task,
    String? downloadUrl,
    int? trackNumber,
    String? releaseYear,
  }) async {
    final String title = task.title;
    final String artist = task.artist;
    final String album = task.album;
    final String? deezerTrackId = task.deezerTrackId;
    final String? coverUrl = task.coverUrl;
    final VoidCallback? onProgressUpdate = task.onUpdate;

    try {
      String searchArtist = artist;
      String searchTitle = title;
      String searchAlbum = album;

      if (deezerTrackId != null && deezerTrackId.isNotEmpty) {
        final meta = await _fetchDeezerTrackMeta(deezerTrackId);
        if (meta != null) {
          if (searchTitle.isEmpty && meta['title'] != null && meta['title']!.isNotEmpty) {
            searchTitle = meta['title']!;
          }
          if ((searchArtist.isEmpty || searchArtist == 'Unknown Artist') &&
              meta['artist'] != null &&
              meta['artist']!.isNotEmpty) {
            searchArtist = meta['artist']!;
          }
          if ((searchAlbum.isEmpty || searchAlbum == 'Single') &&
              meta['album'] != null &&
              meta['album']!.isNotEmpty) {
            searchAlbum = meta['album']!;
          }
        }
      }

      final folderPath = await getDownloadDirectoryPath();
      final sanitizedTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final sanitizedArtist = artist.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      const ext = 'mp3';
      final filePath = '$folderPath/$sanitizedArtist - $sanitizedTitle.$ext';
      final file = File(filePath);

      bool downloadSuccess = false;

      // ── Strategy 1: Try JioSaavn Direct Audio Stream FIRST (Fastest & No Anti-Bot) ──
      final saavnUrl = await SaavnResolver.resolveStreamUrl(artist: searchArtist, title: searchTitle);
      final fallbackUrl = saavnUrl ?? downloadUrl;

      if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
        final urlsToTry = <String>[fallbackUrl];
        if (fallbackUrl.contains('_320.mp4')) {
          urlsToTry.add(fallbackUrl.replaceAll('_320.mp4', '_160.mp4'));
          urlsToTry.add(fallbackUrl.replaceAll('_320.mp4', '_96.mp4'));
          urlsToTry.add(fallbackUrl.replaceAll('aac.saavncdn.com', 'preview.saavncdn.com').replaceAll('_320.mp4', '_96_p.mp4'));
        }

        for (final tryUrl in urlsToTry) {
          final client = http.Client();
          try {
            final request = http.Request('GET', Uri.parse(tryUrl));
            request.headers['User-Agent'] =
                'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36';
            request.headers['Accept'] = '*/*';

            final response = await client.send(request).timeout(const Duration(seconds: 6));
            if (response.statusCode == 200 || response.statusCode == 206) {
              final contentLength = response.contentLength ?? 0;
              final sink = file.openWrite();
              int downloadedBytes = 0;

              final streamFuture = response.stream.listen((chunk) {
                sink.add(chunk);
                downloadedBytes += chunk.length;
                if (contentLength > 0) {
                  task.progress = (downloadedBytes / contentLength).clamp(0.05, 0.95);
                } else {
                  task.progress = 0.5;
                }
                onProgressUpdate?.call();
              }).asFuture();

              await streamFuture.timeout(const Duration(seconds: 10));
              await sink.flush();
              await sink.close();
              if (downloadedBytes > 50000) {
                downloadSuccess = true;
                break;
              }
            }
          } catch (e) {
            debugPrint('[DownloadService] Direct HTTP stream error ($tryUrl): $e');
          } finally {
            client.close();
          }
        }
      }

      // ── Strategy 2: Youtube Resolver Fallback (With 8s Stream Read Timeout) ───────
      if (!downloadSuccess) {
        final ytResult = await YoutubeResolver.resolveStream(
          artist: searchArtist,
          title: searchTitle,
          album: searchAlbum,
        );

        if (ytResult != null && ytResult.streamInfo != null && ytResult.ytClient != null) {
          IOSink? sink;
          try {
            final stream = ytResult.ytClient!.videos.streamsClient.get(ytResult.streamInfo!);
            sink = file.openWrite();
            final totalBytes = ytResult.streamInfo!.size.totalBytes;
            int downloadedBytes = 0;

            final forEachFuture = stream.forEach((chunk) {
              sink!.add(chunk);
              downloadedBytes += chunk.length;
              if (totalBytes > 0) {
                task.progress = (downloadedBytes / totalBytes).clamp(0.05, 0.95);
              } else {
                task.progress = 0.5;
              }
              onProgressUpdate?.call();
            });

            // Strict 10-second timeout on socket read events
            await forEachFuture.timeout(const Duration(seconds: 10));
            await sink.flush();
            if (downloadedBytes > 50000) {
              downloadSuccess = true;
            }
          } catch (e) {
            debugPrint('[DownloadService] YoutubeExplode native download error: $e');
          } finally {
            await sink?.close();
            ytResult.ytClient!.close();
          }
        } else if (ytResult?.url != null) {
          // Try HTTP request to resolved Youtube stream URL
          final client = http.Client();
          try {
            final request = http.Request('GET', Uri.parse(ytResult!.url));
            request.headers['User-Agent'] =
                'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36';

            final response = await client.send(request).timeout(const Duration(seconds: 8));
            if (response.statusCode == 200 || response.statusCode == 206) {
              final contentLength = response.contentLength ?? 0;
              final sink = file.openWrite();
              int downloadedBytes = 0;

              final streamFuture = response.stream.listen((chunk) {
                sink.add(chunk);
                downloadedBytes += chunk.length;
                if (contentLength > 0) {
                  task.progress = (downloadedBytes / contentLength).clamp(0.05, 0.95);
                } else {
                  task.progress = 0.5;
                }
                onProgressUpdate?.call();
              }).asFuture();

              await streamFuture.timeout(const Duration(seconds: 10));
              await sink.flush();
              await sink.close();
              if (downloadedBytes > 50000) {
                downloadSuccess = true;
              }
            }
          } catch (e) {
            debugPrint('[DownloadService] Youtube direct URL HTTP stream error: $e');
          } finally {
            client.close();
          }
        }
      }

      final fileSize = await file.length().catchError((_) => 0);
      if (!downloadSuccess || fileSize < 50000) {
        debugPrint('[DownloadService] Download failed or payload too small (${fileSize}B)');
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
        task.hasFailed = true;
        onProgressUpdate?.call();
        AppSnackBar.show('Download failed for "$title"');
        activeDownloadCountNotifier.value = activeDownloads.length;
        return;
      }

      // Embed Metadata and Artwork
      final artworkBytes = await _resolveCoverBytes(
        artist: artist,
        title: title,
        initialCoverUrl: coverUrl,
        deezerTrackId: deezerTrackId,
      );

      if (artworkBytes != null && artworkBytes.isNotEmpty) {
        try {
          final jpgFile = File('$folderPath/$sanitizedArtist - $sanitizedTitle.jpg');
          await jpgFile.writeAsBytes(artworkBytes, flush: true);
        } catch (_) {}
      }

      var yearStr = releaseYear ?? '';
      if (yearStr.isEmpty && deezerTrackId != null) {
        final meta = await _fetchDeezerTrackMeta(deezerTrackId);
        yearStr = meta?['releaseYear'] ?? '';
      }
      if (yearStr.isEmpty) yearStr = DateTime.now().year.toString();
      final trackNumStr = trackNumber?.toString() ?? '';

      await TagEditorService().writeTagsAndArtwork(
        filePath: filePath,
        title: title,
        artist: artist,
        album: album,
        year: yearStr,
        genre: 'Music',
        trackNumber: trackNumStr,
        artworkBytes: artworkBytes,
      );

      try {
        await OnAudioQuery().scanMedia(filePath);
      } catch (scanErr) {
        debugPrint('[DownloadService] Media scan error: $scanErr');
      }

      task.progress = 1.0;
      task.isCompleted = true;
      onProgressUpdate?.call();

      await PlaybackController.instance.refreshLibrary();
      debugPrint('[DownloadService] ✓ Downloaded "$title" to $filePath');
    } catch (e) {
      debugPrint('[DownloadService] Error downloading "$title": $e');
      task.hasFailed = true;
      onProgressUpdate?.call();
    } finally {
      activeDownloadCountNotifier.value = activeDownloads.length;
    }
  }

  Future<void> batchDownload(
      List<SearchResultTrack> tracks, {
        DownloadQualityChoice? qualityChoice,
        VoidCallback? onProgressUpdate,
      }) async {
    for (final track in tracks) {
      await startDownload(
        trackId: track.id,
        title: track.name,
        artist: track.artist,
        album: track.album,
        downloadUrl: track.downloadUrl,
        deezerTrackId: track.deezerTrackId,
        coverUrl: track.coverUrl,
        trackNumber: track.trackNumber,
        releaseYear: track.releaseYear,
        durationMs: track.durationMs,
        qualityChoice: qualityChoice,
        onProgressUpdate: onProgressUpdate,
      );
    }
  }
}