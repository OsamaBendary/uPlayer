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
    DownloadQuality? quality,
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

    final targetQuality = quality ?? ExtensionService().selectedQuality;
    final task = DownloadTask(
      id: trackId,
      title: title,
      artist: artist,
      album: album,
      deezerTrackId: deezerTrackId,
      coverUrl: coverUrl,
      quality: targetQuality,
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

    final request = <String, dynamic>{
      'contract_version': 1,
      'isrc': '',
      'service': ExtensionService().selectedProviderId ?? '',
      'track_name': task.title,
      'artist_name': task.artist,
      'album_name': task.album,
      'album_artist': '',
      'cover_url': coverUrl ?? '',
      'output_dir': folderPath,
      'filename_format': goFilenameFormat,
      'quality': _goQuality(task.quality),
      'embed_metadata': true,
      'artist_tag_mode': 'joined',
      'embed_lyrics': false,
      'embed_max_quality_cover': true,
      'post_processing_enabled': false,
      'track_number': trackNumber ?? 0,
      'total_tracks': 0,
      'disc_number': 0,
      'total_discs': 0,
      'release_date': releaseYear ?? '',
      'item_id': task.id,
      'duration_ms': durationMs,
      'source': deezerTrackId != null ? 'deezer' : '',
      'genre': '',
      'label': '',
      'deezer_id': deezerTrackId ?? '',
      'lyrics_mode': 'none',
      'use_extensions': true,
      'use_fallback': true,
      'allow_quality_variant': true,
      'songlink_region': 'US',
    };

    _goDownloadsActive = true;
    _ensureProgressPolling();

    try {
      await bridge.initItemProgress(task.id);
      final response = await bridge.downloadByStrategy(request);

      if (response['success'] == true) {
        final filePath = response['file_path']?.toString() ?? '';
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

  static String _goQuality(DownloadQuality quality) {
    switch (quality) {
      case DownloadQuality.flac24:
      case DownloadQuality.flac16:
        return 'LOSSLESS';
      case DownloadQuality.mp3320:
        return 'HIGH';
      case DownloadQuality.mp3128:
        return 'MEDIUM';
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
        quality: task.quality,
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
        DownloadQuality? quality,
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
        quality: quality,
        onProgressUpdate: onProgressUpdate,
      );
    }
  }
}