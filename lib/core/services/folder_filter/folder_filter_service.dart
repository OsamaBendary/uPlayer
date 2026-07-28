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
}
