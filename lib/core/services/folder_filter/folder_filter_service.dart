import 'package:shared_preferences/shared_preferences.dart';

/// Stores the set of folder paths the user has opted into scanning for
/// music. An empty selection means "no filter" — every audio file on the
/// device is included, which is the existing (pre-feature) behavior, so
/// nothing changes for anyone who never opens the folder picker.
class FolderFilterService {
  static const String _key = 'selected_music_folders';

  Future<List<String>> getSelectedFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  Future<void> setSelectedFolders(List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, folders);
  }

  Future<void> addFolder(String path) async {
    final folders = await getSelectedFolders();
    if (!folders.contains(path)) {
      folders.add(path);
      await setSelectedFolders(folders);
    }
  }

  Future<void> removeFolder(String path) async {
    final folders = await getSelectedFolders();
    folders.remove(path);
    await setSelectedFolders(folders);
  }

  // ─── Linux desktop scan roots ────────────────────────────────────────────
  // On Linux the picker lets the user choose real directories to scan (GTK
  // folder dialog), stored separately from the sub-folder filter above.
  // Empty list = "user never picked anything" -> the repository falls back
  // to ~/Music.

  static const String _scanRootsKey = 'linux_scan_roots';

  Future<List<String>> getScanRoots() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_scanRootsKey) ?? [];
  }

  Future<void> setScanRoots(List<String> roots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_scanRootsKey, roots);
  }

  Future<void> addScanRoot(String path) async {
    final roots = await getScanRoots();
    if (!roots.contains(path)) {
      roots.add(path);
      await setScanRoots(roots);
    }
  }

  Future<void> removeScanRoot(String path) async {
    final roots = await getScanRoots();
    roots.remove(path);
    await setScanRoots(roots);
  }
}
