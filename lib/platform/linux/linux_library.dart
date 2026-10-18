import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:u_player/core/services/go/go_backend_bridge.dart';
import 'package:u_player/platform/audio_query_compat.dart';
import 'package:u_player/platform/artwork/artwork_registry.dart';
import 'package:u_player/platform/linux/linux_paths.dart';

/// Filesystem-backed music library for the Linux desktop build.
///
/// Replaces Android's MediaStore scan. Uses the Go backend's native library
/// scanner (the same tag readers used when downloading), incrementally:
/// a snapshot of `path -> mtime` is persisted so refreshes only re-read
/// files that changed on disk.
class LinuxLibraryService {
  LinuxLibraryService._();

  static final LinuxLibraryService instance = LinuxLibraryService._();

  final GoBackendBridge _bridge = GoBackendBridge.instance;

  bool _coverDirConfigured = false;

  /// Snapshot of the last successful scan: path -> mtime (ms).
  final Map<String, int> _files = {};

  /// path -> raw LibraryScanResult JSON entry.
  final Map<String, Map<String, dynamic>> _meta = {};

  bool _stateLoaded = false;

  /// Guard so overlapping refreshes (e.g. app start + pull-to-refresh) don't
  /// run the scanner concurrently.
  Future<List<SongModel>>? _inFlight;

  /// Scans [roots] (incrementally when possible) and returns every song,
  /// sorted by title like Android's `SongSortType.TITLE` scan.
  Future<List<SongModel>> fetchSongs({required List<String> roots}) {
    final pending = _inFlight;
    if (pending != null) return pending;
    final future = _fetchSongs(roots);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<List<SongModel>> _fetchSongs(List<String> roots) async {
    if (!_bridge.isAvailable) {
      throw const GoBackendUnavailableException(
        'Go sidecar backend is not running',
      );
    }

    await _ensureCoverDir();
    await _loadState();

    var scannedSomething = false;
    for (final root in roots) {
      if (!Directory(root).existsSync()) {
        debugPrint('[LinuxLibrary] scan root missing, skipping: $root');
        continue;
      }
      try {
        final existing = _existingFilesUnder(root);
        final raw = await _bridge.scanLibraryFolderIncremental(
          root,
          jsonEncode(existing),
        );
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        _mergeIncremental(decoded);
        scannedSomething = true;
      } catch (e) {
        debugPrint('[LinuxLibrary] scan failed for "$root": $e');
      }
    }

    if (scannedSomething) {
      // Roots that were removed in the picker stop being scanned, so their
      // tracks have to be dropped from the snapshot here.
      _pruneOutsideRoots(roots);
      await _saveState();
    }

    final songs = <SongModel>[];
    ArtworkRegistry.instance.clearLibrary();
    for (final entry in _meta.values) {
      try {
        final song = SongModel.fromLinuxScan(entry);
        final cover = (entry['coverPath'] ?? '').toString();
        ArtworkRegistry.instance.registerSong(
          id: song.id,
          audioPath: song.data,
          coverPath: cover.isEmpty ? null : cover,
        );
        songs.add(song);
      } catch (e) {
        debugPrint('[LinuxLibrary] bad scan entry skipped: $e');
      }
    }

    songs.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return songs;
  }

  /// Distinct parent folders across every scanned song (unfiltered), used to
  /// feed the folder filter UI — mirrors the Android implementation.
  Future<List<String>> availableFolders() async {
    await _loadState();
    final folders = <String>{};
    for (final entry in _meta.values) {
      final path = _baseAudioPath((entry['filePath'] ?? '').toString());
      final slash = path.lastIndexOf('/');
      if (slash > 0) folders.add(path.substring(0, slash));
    }
    final list = folders.toList()..sort();
    return list;
  }

  /// Real on-disk path behind a snapshot key (CUE virtual tracks are stored
  /// as `archive.flac#track03`).
  static String _baseAudioPath(String path) {
    final idx = path.lastIndexOf('#track');
    return idx > 0 ? path.substring(0, idx) : path;
  }

  /// Normalized `root/` prefix used for containment checks.
  static String _rootPrefix(String root) {
    var normalized = root;
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return '$normalized/';
  }

  /// Snapshot entries that belong to [root] only. The Go scanner reports
  /// every key it wasn't passed as a deletion candidate, so entries from
  /// other scan roots must be filtered out.
  Map<String, int> _existingFilesUnder(String root) {
    final prefix = _rootPrefix(root);
    final existing = <String, int>{};
    _files.forEach((path, modTime) {
      if (_baseAudioPath(path).startsWith(prefix)) existing[path] = modTime;
    });
    return existing;
  }

  /// Drops snapshot entries that no longer fall under any scan root (the
  /// user removed a folder in the picker, so it is never scanned again).
  void _pruneOutsideRoots(List<String> roots) {
    final prefixes = roots.map(_rootPrefix).toList();
    final removed = <String>[];
    _meta.removeWhere((path, _) {
      final keep = prefixes.any(_baseAudioPath(path).startsWith);
      if (!keep) removed.add(path);
      return !keep;
    });
    for (final path in removed) {
      _files.remove(path);
    }
    if (removed.isNotEmpty) {
      debugPrint(
        '[LinuxLibrary] pruned ${removed.length} tracks outside scan roots',
      );
    }
  }

  void _mergeIncremental(Map<dynamic, dynamic> decoded) {
    final scanned = decoded['scanned'];
    if (scanned is List) {
      for (final item in scanned) {
        if (item is! Map) continue;
        final entry = item.cast<String, dynamic>();
        final path = entry['filePath']?.toString() ?? '';
        if (path.isEmpty) continue;
        _meta[path] = entry;
        _files[path] = (entry['fileModTime'] as num?)?.toInt() ?? 0;
      }
    }
    final deleted = decoded['deletedPaths'];
    if (deleted is List) {
      for (final item in deleted) {
        final path = item.toString();
        _meta.remove(path);
        _files.remove(path);
      }
    }
  }

  Future<void> _ensureCoverDir() async {
    if (_coverDirConfigured) return;
    try {
      await Directory(LinuxPaths.coverCacheDir).create(recursive: true);
      await _bridge.setLibraryCoverCacheDir(LinuxPaths.coverCacheDir);
      _coverDirConfigured = true;
    } catch (e) {
      debugPrint('[LinuxLibrary] cover cache dir setup failed: $e');
    }
  }

  Future<void> _loadState() async {
    if (_stateLoaded) return;
    _stateLoaded = true;
    try {
      final file = File(LinuxPaths.librarySnapshotPath);
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final files = decoded['files'];
      if (files is Map) {
        files.forEach((k, v) {
          if (v is num) _files[k.toString()] = v.toInt();
        });
      }
      final meta = decoded['meta'];
      if (meta is Map) {
        meta.forEach((k, v) {
          if (v is Map) _meta[k.toString()] = v.cast<String, dynamic>();
        });
      }
      debugPrint('[LinuxLibrary] snapshot loaded: ${_meta.length} tracks');
    } catch (e) {
      debugPrint('[LinuxLibrary] snapshot load failed: $e');
    }
  }

  Future<void> _saveState() async {
    try {
      final file = File(LinuxPaths.librarySnapshotPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'v': 1, 'files': _files, 'meta': _meta}),
        flush: true,
      );
    } catch (e) {
      debugPrint('[LinuxLibrary] snapshot save failed: $e');
    }
  }
}
