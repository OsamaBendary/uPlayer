import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thrown when the go_backend bridge exists but the gomobile AAR is not
/// linked into the APK (android/app/libs/gobackend.aar missing).
class GoBackendUnavailableException implements Exception {
  final String message;
  const GoBackendUnavailableException([this.message = '']);
  @override
  String toString() => 'GoBackendUnavailableException: $message';
}

/// Thrown when Go reports a download/extension error (its `(string, error)`
/// contracts surface as method-channel errors).
class GoBackendCallException implements Exception {
  final String code;
  final String message;
  const GoBackendCallException(this.code, this.message);
  @override
  String toString() => 'GoBackendCallException($code): $message';
}

/// Thin Dart client for the Go backend (`go_backend/`, gomobile bind).
///
/// Bridge lifecycle:
///  1. `init()` in main() — resolves app dirs, initializes the extension
///     system + extension store, reloads previously installed extensions.
///  2. `setDownloadDirectory()` (wired into DownloadService) — tell Go where
///     downloads may be written.
///  3. Downloads go through [downloadByStrategy] (blocking in Go, so the
///     Kotlin side runs it on a background executor); progress is polled with
///     [allProgress] / [progressDelta].
class GoBackendBridge {
  GoBackendBridge._internal();

  static final GoBackendBridge instance = GoBackendBridge._internal();

  static const MethodChannel _channel =
      MethodChannel('com.uplayer.u_player/go_backend');

  final StreamController<GoSessionGrantEvent> _grantController =
      StreamController.broadcast();
  bool _grantListenerReady = false;

  /// Fired by native code when the provider verification page redirects back
  /// to the app via `uplayer://session-grant` with a grant for [extensionId].
  Stream<GoSessionGrantEvent> get sessionGrantEvents =>
      _grantController.stream;

  void _ensureGrantListener() {
    if (_grantListenerReady) return;
    _grantListenerReady = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'extensionSessionGrantCompleted') {
        final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
        final id = args['extension_id']?.toString() ?? '';
        final success = args['success'] == true;
        _grantController.add(GoSessionGrantEvent(id, success));
      }
      return null;
    });
  }

  bool _available = false;
  bool _probed = false;
  Future<bool>? _probeFuture;

  /// Last bridge failure reason ('' when healthy). Populated by probe/init
  /// so UI can explain why the legacy path is being used.
  String lastError = '';

  bool get isAvailable => _available;

  /// Only a missing channel or missing Go class proves the bridge is absent.
  /// Go-side errors (`go_backend_error`) actually confirm it is present.
  bool _isMissing(PlatformException e) => e.code == 'missing_go_backend';

  Future<Map<String, String>> _appDirs() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getAppDirs');
    if (raw == null) throw const GoBackendUnavailableException();
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  Future<bool> _probe() {
    if (_probed) return Future.value(_available);
    return _probeFuture ??= () async {
      try {
        await _channel.invokeMethod<String>('getAllDownloadProgress');
        _available = true;
      } on MissingPluginException {
        _available = false;
        lastError = 'native bridge not registered';
      } on PlatformException catch (e) {
        _available = !_isMissing(e);
        lastError = _available ? '' : (e.message ?? e.code);
      }
      _probed = true;
      return _available;
    }();
  }

  /// Initializes the extension system + extension store using app dirs.
  /// Best-effort: only a missing native bridge disables the backend.
  Future<void> init() async {
    String? failure;
    try {
      final dirs = await _appDirs();
      _appDirsResult = dirs;
      if (dirs['support_dir']?.isNotEmpty != true) {
        failure = 'no support dir';
      } else {
        final extensionsDir = '${dirs['support_dir']}/extensions';
        await _channel.invokeMethod<void>('initExtensionSystem', {
          'extensions_dir': extensionsDir,
          'data_dir': '${dirs['support_dir']}/data',
        });
        if (dirs['cache_dir']?.isNotEmpty == true) {
          try {
            await _channel.invokeMethod<void>('initExtensionRepo', {
              'cache_dir': dirs['cache_dir'],
            });
          } on PlatformException catch (e) {
            debugPrint('[GoBackendBridge] repo init failed: ${e.message}');
          }
        }
        try {
          await loadExtensionsFromDir(extensionsDir);
        } on PlatformException {
          // Directory may be empty on first launch — fine.
        } catch (e) {
          debugPrint('[GoBackendBridge] extension reload failed: $e');
        }
      }
    } on MissingPluginException {
      failure = 'native bridge not registered';
    } on PlatformException catch (e) {
      failure = _isMissing(e) ? (e.message ?? e.code) : null;
      if (failure != null) {
        debugPrint('[GoBackendBridge] init failed: $failure');
      } else {
        debugPrint('[GoBackendBridge] init Go error (bridge still up): '
            '${e.code}: ${e.message}');
      }
    }
    _available = failure == null;
    lastError = failure ?? '';
    _probed = true;
  }

  Map<String, String>? _appDirsResult;

  Map<String, String>? get appDirs => _appDirsResult;

  /// Cache of the default download dir reported by the platform, used by
  /// DownloadService before Go is available.
  Future<String?> defaultDownloadDir() async {
    final dirs = _appDirsResult ?? await _appDirs();
    return dirs['default_download_dir'];
  }

  // ─── Core lifecycle ─────────────────────────────────────────────────────

  Future<void> setMetadataLanguage(String tag) {
    return _call('setMetadataLanguage', {'tag': tag});
  }

  Future<void> setDownloadDirectory(String path) {
    return _call('setDownloadDirectory', {'path': path});
  }

  Future<void> setNetworkCompatibilityOptions({
    required bool allowHttp,
    required bool insecureTls,
  }) {
    return _call('setNetworkCompatibilityOptions', {
      'allow_http': allowHttp,
      'insecure_tls': insecureTls,
    });
  }

  Future<void> setAllowPrivateNetwork(bool allowed) {
    return _call('setAllowPrivateNetwork', {'allowed': allowed});
  }

  Future<void> releaseMemory({bool underPressure = false}) {
    return _call(underPressure ? 'releaseMemoryUnderPressure' : 'releaseMemory');
  }

  Future<void> cleanupConnections() => _call('cleanupConnections');

  Future<Map<String, dynamic>> getGoRuntimeMetrics() =>
      _callMap('getGoRuntimeMetrics');

  Future<Map<String, dynamic>> getGoLogsSince(int index) =>
      _callMap('getGoLogsSince', {'index': index});

  Future<String> getLyricsLRC({
    String spotifyId = '',
    String trackName = '',
    String artistName = '',
    String filePath = '',
    int durationMs = 0,
  }) async {
    final raw = await _call('getLyricsLRC', {
      'spotify_id': spotifyId,
      'track_name': trackName,
      'artist_name': artistName,
      'file_path': filePath,
      'duration_ms': durationMs,
    });
    return raw?.toString() ?? '';
  }

  // ─── Downloads ──────────────────────────────────────────────────────────

  /// Single blocking download through the extension-driven pipeline.
  /// Returns the DownloadResponse map (success/error/file_path/...).
  Future<Map<String, dynamic>> downloadByStrategy(
    Map<String, dynamic> request,
  ) async {
    final raw = await _call('downloadByStrategy', {
      'request_json': jsonEncode(request),
    });
    return _decodeRawMap(raw, 'downloadByStrategy');
  }

  Future<Map<String, dynamic>> allProgress() async {
    final raw = await _call('getAllDownloadProgress');
    return _decodeRawMap(raw, 'getAllDownloadProgress');
  }

  /// Progress delta since [sinceSeq]. Empty map when nothing changed.
  Future<Map<String, dynamic>> progressDelta(int sinceSeq) async {
    final raw = await _call('getAllDownloadProgressDelta', {
      'since_seq': sinceSeq,
    });
    if (raw == null) return const {};
    return _decodeRawMap(raw, 'getAllDownloadProgressDelta');
  }

  Future<void> initItemProgress(String itemId) =>
      _call('initItemProgress', {'item_id': itemId});

  Future<void> clearItemProgress(String itemId) =>
      _call('clearItemProgress', {'item_id': itemId});

  Future<void> cancelDownload(String itemId) =>
      _call('cancelDownload', {'item_id': itemId});

  Future<void> resetDownloadCancel(String itemId) =>
      _call('resetDownloadCancel', {'item_id': itemId});

  // ─── Extensions ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> loadExtensionsFromDir(String dirPath) async {
    final raw = await _call('loadExtensionsFromDir', {'dir_path': dirPath});
    return _decodeRawMap(raw, 'loadExtensionsFromDir');
  }

  Future<Map<String, dynamic>> loadExtensionFromPath(String filePath) async {
    final raw = await _call('loadExtensionFromPath', {'file_path': filePath});
    return _decodeRawMap(raw, 'loadExtensionFromPath');
  }

  Future<void> unloadExtension(String extensionId) =>
      _call('unloadExtension', {'extension_id': extensionId});

  Future<void> removeExtension(String extensionId) =>
      _call('removeExtension', {'extension_id': extensionId});

  Future<List<Map<String, dynamic>>> getInstalledExtensions() async {
    final raw = await _call('getInstalledExtensions');
    return _decodeRawList(raw, 'getInstalledExtensions');
  }

  Future<void> setExtensionEnabled(String extensionId, bool enabled) {
    return _call('setExtensionEnabled', {
      'extension_id': extensionId,
      'enabled': enabled,
    });
  }

  /// Pending signed-session verification for [extensionId] (auth_url +
  /// callback_url), or null when the provider did not request one.
  Future<Map<String, dynamic>?> getExtensionPendingAuth(
    String extensionId,
  ) async {
    try {
      final raw = await _call('getExtensionPendingAuth', {
        'extension_id': extensionId,
      });
      return _decodeRawMap(raw, 'getExtensionPendingAuth');
    } on GoBackendCallException {
      return null;
    }
  }

  /// Feeds a grant produced by the verification page into the Go system.
  Future<void> setExtensionSessionGrantByID(
    String extensionId,
    String grant,
  ) {
    return _call('setExtensionSessionGrantByID', {
      'extension_id': extensionId,
      'grant': grant,
    });
  }

  /// Runs a named action on an extension (e.g. "completeGrant").
  Future<Map<String, dynamic>> invokeExtensionAction(
    String extensionId,
    String action,
  ) async {
    final raw = await _call('invokeExtensionAction', {
      'extension_id': extensionId,
      'action': action,
    });
    return _decodeRawMap(raw, 'invokeExtensionAction');
  }

  Future<void> setProviderPriority(List<String> providerIds) {
    return _call('setProviderPriority', {'priority': providerIds});
  }

  Future<List<String>> getProviderPriority() async {
    final raw = await _call('getProviderPriority');
    return _decodeRawStringList(raw, 'getProviderPriority');
  }

  Future<void> setMetadataProviderPriority(List<String> providerIds) {
    return _call('setMetadataProviderPriority', {'priority': providerIds});
  }

  Future<List<String>> getMetadataProviderPriority() async {
    final raw = await _call('getMetadataProviderPriority');
    return _decodeRawStringList(raw, 'getMetadataProviderPriority');
  }

  Future<void> setFallbackProviders(List<String> providerIds) {
    return _call('setFallbackProviders', {'provider_ids': providerIds});
  }

  Future<void> cleanupExtensions() => _call('cleanupExtensions');

  // ─── Extension store (registry.json repos) ──────────────────────────────

  Future<void> setRepoRegistryUrl(String registryUrl) {
    return _call('setRepoRegistryUrl', {'registry_url': registryUrl});
  }

  Future<String> getRepoRegistryUrl() async {
    final raw = await _call('getRepoRegistryUrl');
    return raw?.toString() ?? '';
  }

  Future<void> clearRepoRegistryUrl() => _call('clearRepoRegistryUrl');

  Future<List<Map<String, dynamic>>> getRepoExtensions({
    bool forceRefresh = true,
  }) async {
    final raw = await _call('getRepoExtensions', {'force_refresh': forceRefresh});
    return _decodeRawList(raw, 'getRepoExtensions');
  }

  Future<List<Map<String, dynamic>>> getRepoCategories() async {
    final raw = await _call('getRepoCategories');
    return _decodeRawList(raw, 'getRepoCategories');
  }

  /// Downloads the package for [extensionId] into [destDir]; returns the
  /// local path to the .sflx/.spotiflac-ext file.
  Future<String> downloadRepoExtension(String extensionId, String destDir) async {
    final raw = await _call('downloadRepoExtension', {
      'extension_id': extensionId,
      'dest_dir': destDir,
    });
    return raw?.toString() ?? '';
  }

  // ─── Internals ──────────────────────────────────────────────────────────

  Future<Object?> _call(String method, [Map<Object?, Object?>? args]) async {
    if (!await _probe()) {
      throw const GoBackendUnavailableException();
    }
    _ensureGrantListener();
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on MissingPluginException catch (e) {
      // Either the channel is genuinely unregistered (transient — e.g. engine
      // restart) or Kotlin returned notImplemented() for an unknown method.
      // Don't latch off permanently: reset the probe so the next call retries.
      debugPrint('[GoBackendBridge] MissingPluginException on "$method": $e');
      lastError = 'bridge missing for "$method"';
      _available = false;
      _probed = false;
      _probeFuture = null;
      throw const GoBackendUnavailableException();
    } on PlatformException catch (e) {
      throw GoBackendCallException(e.code, e.message ?? '');
    }
  }

  Future<Map<String, dynamic>> _callMap(
    String method, [
    Map<Object?, Object?>? args,
  ]) async {
    final raw = await _call(method, args);
    return _decodeRawMap(raw, method);
  }

  Map<String, dynamic> _decodeRawMap(Object? raw, String method) {
    try {
      final decoded = jsonDecode(raw?.toString() ?? '');
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      throw const GoBackendCallException('bad_json', 'Expected JSON object');
    } on FormatException {
      throw GoBackendCallException('bad_json', '$method returned invalid JSON');
    }
  }

  List<Map<String, dynamic>> _decodeRawList(Object? raw, String method) {
    try {
      final decoded = jsonDecode(raw?.toString() ?? '[]');
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList(growable: false);
      }
      throw const GoBackendCallException('bad_json', 'Expected JSON array');
    } on FormatException {
      throw GoBackendCallException('bad_json', '$method returned invalid JSON');
    }
  }

  List<String> _decodeRawStringList(Object? raw, String method) {
    try {
      final decoded = jsonDecode(raw?.toString() ?? '[]');
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList(growable: false);
      }
      throw const GoBackendCallException('bad_json', 'Expected JSON array');
    } on FormatException {
      throw GoBackendCallException('bad_json', '$method returned invalid JSON');
    }
  }
}

/// One session-grant event from native (deep link callback).
class GoSessionGrantEvent {
  final String extensionId;
  final bool success;
  const GoSessionGrantEvent(this.extensionId, this.success);
}

/// Snapshot of one Go download item's progress.
class GoDownloadProgress {
  final String itemId;
  final String status;
  final String stage;
  final double progress;
  final int bytesReceived;
  final int bytesTotal;
  final double speedMbps;
  final bool isDownloading;

  const GoDownloadProgress({
    required this.itemId,
    required this.status,
    required this.stage,
    required this.progress,
    required this.bytesReceived,
    required this.bytesTotal,
    required this.speedMbps,
    required this.isDownloading,
  });

  static GoDownloadProgress? fromJson(dynamic json) {
    if (json is! Map) return null;
    return GoDownloadProgress(
      itemId: json['item_id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      stage: json['stage']?.toString() ?? '',
      progress: ((json['progress'] as num?) ?? 0).toDouble(),
      bytesReceived: ((json['bytes_received'] as num?) ?? 0).toInt(),
      bytesTotal: ((json['bytes_total'] as num?) ?? 0).toInt(),
      speedMbps: ((json['speed_mbps'] as num?) ?? 0).toDouble(),
      isDownloading: json['is_downloading'] == true,
    );
  }
}