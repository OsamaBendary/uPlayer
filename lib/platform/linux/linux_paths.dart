import 'dart:io';

/// XDG-conformant paths for the Linux desktop build.
///
/// Android gets its directories from the Kotlin bridge (`filesDir`,
/// `cacheDir`, external `Music/`); on Linux we follow the XDG base directory
/// spec instead:
///   * support/data -> `~/.local/share/uplayer`   ($XDG_DATA_HOME)
///   * cache        -> `~/.cache/uplayer`         ($XDG_CACHE_HOME)
///   * music        -> `xdg-user-dir MUSIC` (~/Music)
class LinuxPaths {
  LinuxPaths._();

  static String get _home => Platform.environment['HOME'] ?? '/tmp';

  /// The user's home directory (`$HOME`).
  static String get homeDir => _home;

  static String get supportDir {
    final xdg = Platform.environment['XDG_DATA_HOME'];
    final base = (xdg == null || xdg.isEmpty) ? '$_home/.local/share' : xdg;
    return '$base/uplayer';
  }

  static String get cacheDir {
    final xdg = Platform.environment['XDG_CACHE_HOME'];
    final base = (xdg == null || xdg.isEmpty) ? '$_home/.cache' : xdg;
    return '$base/uplayer';
  }

  static String get coverCacheDir => '$cacheDir/covers';

  static String get librarySnapshotPath => '$supportDir/library_snapshot.json';

  static String get extensionsDir => '$supportDir/extensions';

  static String get extensionsDataDir => '$supportDir/data';

  /// The user's Music folder, honoring `xdg-user-dirs` when available.
  static Future<String> musicDir() async {
    try {
      final result = await Process.run('xdg-user-dir', ['MUSIC']);
      if (result.exitCode == 0) {
        final dir = result.stdout.toString().trim();
        if (dir.isNotEmpty && dir != _home) return dir;
      }
    } catch (_) {
      // xdg-user-dir not installed — fall through to ~/Music.
    }
    return '$_home/Music';
  }

  /// Where downloads land by default.
  static Future<String> defaultDownloadDir() async {
    return '${await musicDir()}/uPlayer';
  }
}
