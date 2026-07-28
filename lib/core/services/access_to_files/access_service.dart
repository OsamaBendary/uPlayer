import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:u_player/core/services/favorites_service/favorites_service.dart';
import 'package:u_player/core/services/folder_filter/folder_filter_service.dart';

class LocalAudioRepository {
  final FavoritesService _favoritesService = FavoritesService();
  final FolderFilterService _folderFilterService = FolderFilterService();
  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<bool> requestPermission() async {
    var status = await Permission.audio.request();

    if (!status.isGranted) {
      status = await Permission.storage.request();
    }

    return status.isGranted;
  }

  /// Returns every song on the device, filtered down to the user's chosen
  /// folders if they've selected any. An empty selection (the default,
  /// nobody has opened the folder picker yet) means no filter — every song
  /// is included, same as before this feature existed.
  Future<List<SongModel>> fetchLocalSongs() async {
    bool granted = await requestPermission();

    if (!granted) {
      return [];
    }

    final allSongs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final selectedFolders = await _folderFilterService.getSelectedFolders();
    if (selectedFolders.isEmpty) {
      return allSongs;
    }

    return allSongs.where((song) {
      final path = song.data;
      return selectedFolders.any((folder) => path.startsWith(folder));
    }).toList();
  }

  Future<List<SongModel>> fetchFavoriteSongs() async {
    final List<SongModel> allSongs = await fetchLocalSongs();

    final List<String> favIds = await _favoritesService.getFavoriteSongIds();

    final List<SongModel> favoriteSongs = allSongs.where((song) {
      return favIds.contains(song.id.toString());
    }).toList();

    return favoriteSongs;
  }

  /// Distinct parent-folder paths across every audio file on the device
  /// (unfiltered — this is what feeds the folder picker, so it has to show
  /// real folders regardless of any filter already applied). Derived from
  /// song paths directly rather than a separate directory-picker package,
  /// since the device's music is already scanned here.
  Future<List<String>> fetchAvailableFolders() async {
    bool granted = await requestPermission();
    if (!granted) return [];

    final songs = await _audioQuery.querySongs(uriType: UriType.EXTERNAL);
    final folders = <String>{};
    for (final song in songs) {
      final path = song.data;
      final lastSlash = path.lastIndexOf('/');
      if (lastSlash > 0) {
        folders.add(path.substring(0, lastSlash));
      }
    }
    final list = folders.toList()..sort();
    return list;
  }
}
