import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static const String _favKey = 'favorite_songs_ids';

  Future<List<String>> getFavoriteSongIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favKey) ?? [];
  }

  Future<bool> isFavorite(int songId) async {
    final favorites = await getFavoriteSongIds();
    return favorites.contains(songId.toString());
  }

  Future<bool> toggleFavorite(int songId) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await getFavoriteSongIds();
    final String idStr = songId.toString();

    if (favorites.contains(idStr)) {
      favorites.remove(idStr);
    } else {
      favorites.add(idStr);
    }

    await prefs.setStringList(_favKey, favorites);
    return favorites.contains(idStr);
  }
}