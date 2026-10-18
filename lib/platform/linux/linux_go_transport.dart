import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:u_player/platform/linux/linux_paths.dart';

/// Talks to the Go backend sidecar process on Linux.
///
/// On Android the download/extension engine is linked in as a gomobile AAR
/// behind a MethodChannel (Kotlin `GoBackendBridge`). Linux has no gomobile
/// support, so the same Go package is compiled as a small native binary
/// (`go_backend/cmd/uplayer_sidecar`) and spoken to over line-delimited JSON
/// on its stdin/stdout. Method names, argument keys, result payloads and
/// error codes deliberately mirror the Kotlin bridge so Dart-side code
/// (`GoBackendBridge`) behaves identically on both platforms.
///
/// Protocol
///   ->  {"id":1,"method":"downloadByStrategy","args":{...}}
///   <-  {"id":1,"result":"..."} | {"id":1,"error":{"code":"...","message":"..."}}
///   <-  {"event":"...","data":{...}}          (unsolicited, e.g. session grants)
///
/// Blocking Go calls (downloads) run on the sidecar's own goroutines; the
/// Dart event loop only ever waits on the pipe.
class LinuxGoTransport {
  LinuxGoTransport._();

  static final LinuxGoTransport instance = LinuxGoTransport._();

  Process? _process;
  final Map<int, Completer<Object?>> _pending = {};
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  int _nextId = 1;
  bool _startFailed = false;

  /// Unsolicited events from the sidecar (currently session-grant results).
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Human-readable reason the transport is unavailable ('' when healthy).
  String lastError = '';

  bool get isRunning => _process != null;

  /// Starts the sidecar process if it isn't running yet. Returns false when
  /// the binary can't be found or fails to spawn.
  Future<bool> ensureStarted() async {
    if (_process != null) return true;
    if (_startFailed) return false;

    final binary = _resolveBinary();
    if (binary == null) {
      _startFailed = true;
      lastError = 'uplayer Go sidecar binary not found';
      debugPrint('[LinuxGoTransport] $lastError');
      return false;
    }

    try {
      final process = await Process.start(
        binary,
        const [],
        workingDirectory: File(binary).parent.path,
      );
      _process = process;

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine, onError: (Object e) {
        debugPrint('[LinuxGoTransport] stdout error: $e');
      }, onDone: () {
        debugPrint('[LinuxGoTransport] sidecar exited');
        _process = null;
        _failAllPending('sidecar exited');
      });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          debugPrint('[go] $line');
        }
      });

      // Give it a beat to crash fatally at startup, so callers get a clean
      // "unavailable" instead of a hang on the first request.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (_process == null) {
        _startFailed = true;
        lastError = 'Go sidecar exited immediately after start';
        return false;
      }
      debugPrint('[LinuxGoTransport] sidecar started: $binary');
      return true;
    } catch (e) {
      _startFailed = true;
      lastError = 'failed to start Go sidecar: $e';
      debugPrint('[LinuxGoTransport] $lastError');
      return false;
    }
  }

  /// Mirrors the Kotlin bridge's `invokeMethod` semantics.
  Future<Object?> invoke(String method, Map<Object?, Object?>? args) async {
    // getAppDirs is answered by the host on Android too (pure Kotlin); the
    // sidecar never sees it.
    if (method == 'getAppDirs') {
      return _appDirs();
    }

    if (!await ensureStarted()) {
      throw PlatformException(
        code: 'missing_go_backend',
        message: lastError,
      );
    }

    final process = _process;
    if (process == null) {
      throw PlatformException(
        code: 'missing_go_backend',
        message: lastError,
      );
    }

    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;

    final normalizedArgs = <String, Object?>{};
    args?.forEach((k, v) {
      if (k == null) return;
      // JSON-encode list arguments the way Kotlin's jsonArray() does — the
      // Go side expects a JSON string for *_priority / fallback providers.
      normalizedArgs[k.toString()] =
          (v is List || v is Map) ? jsonEncode(v) : v;
    });

    final request = jsonEncode({
      'id': id,
      'method': method,
      'args': normalizedArgs,
    });

    try {
      process.stdin.writeln(request);
      await process.stdin.flush();
    } catch (e) {
      _pending.remove(id);
      throw PlatformException(
        code: 'missing_go_backend',
        message: 'sidecar stdin closed: $e',
      );
    }

    return completer.future;
  }

  /// Native deep-link channel exposed by the GTK runner
  /// (`linux/runner/my_application.cc`).
  static const MethodChannel _deepLinkChannel =
      MethodChannel('com.uplayer.u_player/deep_links');

  bool _deepLinksAttached = false;

  /// Listens for `uplayer://` / `spotiflac://` deep links forwarded by the
  /// GTK runner, and drains any that arrived before Dart was listening
  /// (cold start / app launched from the browser).
  Future<void> attachDeepLinkChannel() async {
    if (_deepLinksAttached) return;
    _deepLinksAttached = true;

    _deepLinkChannel.setMethodCallHandler((call) async {
      if (call.method == 'sessionGrantUri' && call.arguments is String) {
        await handleSessionGrantUri(call.arguments as String);
      }
    });

    try {
      // Calling this also tells the runner that the handler is attached, so
      // later links are pushed directly.
      final pending =
          await _deepLinkChannel.invokeListMethod<String>('takePendingUris');
      for (final uri in pending ?? const <String>[]) {
        unawaited(handleSessionGrantUri(uri));
      }
    } catch (e) {
      debugPrint('[LinuxGoTransport] deep link drain failed: $e');
    }
  }

  /// Feeds a `uplayer://session-grant?...` / `spotiflac://session-grant?...`
  /// URI into the extension session exchange, then emits the same
  /// `extensionSessionGrantCompleted` event the Android deep-link handler
  /// produces.
  Future<void> handleSessionGrantUri(String uri) async {
    Uri parsed;
    try {
      parsed = Uri.parse(uri);
    } catch (_) {
      return;
    }
    if (parsed.host != 'session-grant') return;

    final grant = parsed.queryParameters['grant'] ??
        parsed.queryParameters['code'] ??
        '';
    final extensionId = parsed.queryParameters['state'] ?? '';
    if (grant.isEmpty || extensionId.isEmpty) {
      debugPrint('[LinuxGoTransport] session grant URI missing grant/state');
      return;
    }

    var success = false;
    try {
      await invoke('setExtensionSessionGrantByID', {
        'extension_id': extensionId,
        'grant': grant,
      });
      final raw = await invoke('invokeExtensionAction', {
        'extension_id': extensionId,
        'action': 'completeGrant',
      });
      success = (raw?.toString() ?? '').contains('"success":true');
    } catch (e) {
      debugPrint('[LinuxGoTransport] session grant failed: $e');
    }

    _events.add({
      'event': 'extensionSessionGrantCompleted',
      'data': {'extension_id': extensionId, 'success': success},
    });
  }

  // ─── Internals ───────────────────────────────────────────────────────────

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      debugPrint('[LinuxGoTransport] non-JSON sidecar line: $line');
      return;
    }
    if (decoded is! Map) return;

    if (decoded.containsKey('event')) {
      _events.add(decoded.cast<String, dynamic>());
      return;
    }

    final id = (decoded['id'] as num?)?.toInt();
    if (id == null) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;

    final error = decoded['error'];
    if (error is Map) {
      completer.completeError(PlatformException(
        code: error['code']?.toString() ?? 'go_backend_error',
        message: error['message']?.toString() ?? '',
      ));
      return;
    }

    var result = decoded['result'];
    // Mirror the Kotlin bridge quirks:
    //  * downloadCoverToFile returns null on success (Go returns Unit).
    //  * getAllDownloadProgressDelta returns "" when nothing changed and
    //    Kotlin maps that to null.
    if (decoded['method'] == 'downloadCoverToFile') {
      result = null;
    } else if (result == '') {
      result = null;
    }
    completer.complete(result);
  }

  void _failAllPending(String reason) {
    final pending = Map.of(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(PlatformException(
          code: 'missing_go_backend',
          message: reason,
        ));
      }
    }
  }

  Future<Map<String, String>> _appDirs() async {
    return {
      'support_dir': LinuxPaths.supportDir,
      'cache_dir': LinuxPaths.cacheDir,
      'default_download_dir': '${await LinuxPaths.musicDir()}/uPlayer',
    };
  }

  /// Locates the sidecar binary:
  ///  1. `UPLAYER_GO_SIDECAR` env override (development),
  ///  2. next to the app executable inside the bundle (release installs),
  ///  3. `build/go_sidecar/` in the project (flutter run / flutter build).
  String? _resolveBinary() {
    const name = 'uplayer_go_sidecar';

    final override = Platform.environment['UPLAYER_GO_SIDECAR'];
    if (override != null && override.isNotEmpty) {
      if (File(override).existsSync()) return override;
      debugPrint('[LinuxGoTransport] UPLAYER_GO_SIDECAR not found: $override');
    }

    String? check(String path) {
      final f = File(path);
      return f.existsSync() ? f.path : null;
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final bundled = check('$exeDir/$name') ?? check('$exeDir/lib/$name');
    if (bundled != null) return bundled;

    final cwd = Directory.current.path;
    final dev = check('$cwd/build/go_sidecar/$name') ??
        check('$cwd/go_backend/build/$name');
    if (dev != null) return dev;

    return null;
  }
}
