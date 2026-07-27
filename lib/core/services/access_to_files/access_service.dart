import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:u_player/core/services/favorites_service/favorites_service.dart';

class LocalAudioRepository {
  final FavoritesService _favoritesService = FavoritesService();
  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<bool> requestPermission() async {
    var status = await Permission.audio.request();

    if (!status.isGranted) {
      status = await Permission.storage.request();
    }

    return status.isGranted;
  }

  Future<List<SongModel>> fetchLocalSongs() async {
    bool granted = await requestPermission();

    if (!granted) {
      return [];
    }

    return await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
  }

  Future<List<SongModel>> fetchFavoriteSongs() async {
    final List<SongModel> allSongs = await fetchLocalSongs();

    final List<String> favIds = await _favoritesService.getFavoriteSongIds();

    final List<SongModel> favoriteSongs = allSongs.where((song) {
      return favIds.contains(song.id.toString());
    }).toList();

    return favoriteSongs;
  }
}


