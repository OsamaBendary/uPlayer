import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:u_player/core/models/playlist_model.dart';

class PlaylistService {
  static const String _key = 'user_playlists';

  Future<List<PlaylistModel>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_key);
    if (data == null) return [];
    
    final List<dynamic> jsonList = jsonDecode(data);
    return jsonList.map((e) => PlaylistModel.fromJson(e)).toList();
  }

  Future<void> _save(List<PlaylistModel> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(playlists.map((e) => e.toJson()).toList());
    await prefs.setString(_key, data);
  }

  Future<PlaylistModel> createPlaylist(String name) async {
    final playlists = await getAll();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final newPlaylist = PlaylistModel(id: id, name: name);
    playlists.add(newPlaylist);
    await _save(playlists);
    return newPlaylist;
  }

  Future<void> deletePlaylist(String id) async {
    final playlists = await getAll();
    playlists.removeWhere((p) => p.id == id);
    await _save(playlists);
  }

  Future<void> renamePlaylist(String id, String name) async {
    final playlists = await getAll();
    final index = playlists.indexWhere((p) => p.id == id);
    if (index != -1) {
      playlists[index].name = name;
      await _save(playlists);
    }
  }

  Future<void> addSong(String playlistId, int songId) async {
    final playlists = await getAll();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      if (!playlists[index].songIds.contains(songId)) {
        playlists[index].songIds.add(songId);
        await _save(playlists);
      }
    }
  }

  Future<void> removeSong(String playlistId, int songId) async {
    final playlists = await getAll();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      playlists[index].songIds.remove(songId);
      await _save(playlists);
    }
  }

  Future<void> setCoverImage(String playlistId, String? imagePath) async {
    final playlists = await getAll();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      playlists[index].coverImagePath = imagePath;
      await _save(playlists);
    }
  }

  Future<void> reorderSongs(String playlistId, List<int> newOrder) async {
    final playlists = await getAll();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      playlists[index].songIds = List.from(newOrder);
      await _save(playlists);
    }
  }
}
