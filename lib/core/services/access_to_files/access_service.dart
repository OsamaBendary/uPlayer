import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:u_player/core/services/favorites_service/favorites_service.dart';
import 'package:u_player/core/services/folder_filter/folder_filter_service.dart';
import 'package:u_player/core/services/go/go_backend_bridge.dart';

class LocalAudioRepository {
  final FavoritesService _favoritesService = FavoritesService();
  final FolderFilterService _folderFilterService = FolderFilterService();
  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Tag metadata (track/disc numbers) read from audio files, keyed by file
  /// path, so repeated library refreshes never re-read the same file. Small
  /// bounded cache — album ordering enrichment only reads a handful of files
  /// per refresh anyway.
  static final Map<String, Map<String, dynamic>> _tagMetaCache = {};
  static const int _tagCacheMax = 600;

  /// Hard cap on tag reads per refresh, so a library with hundreds of
  /// untagged albums can never stall startup.
  static const int _maxTagReadsPerRefresh = 48;

  /// Bounded concurrency for tag reads.
  static const int _tagReadConcurrency = 4;

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
    final songs = selectedFolders.isEmpty
        ? allSongs
        : allSongs.where((song) {
            final path = song.data;
            return selectedFolders.any((folder) => path.startsWith(folder));
          }).toList();

    return _enrichAmbiguousAlbumOrdering(songs);
  }

  /// The MediaStore only exposes a plain track number — no disc number, and
  /// no track at all when a file's tags weren't scanned (track comes back
  /// as 0). Sorting an album by that alone misplaces songs on multi-disc
  /// releases (disc 2 restarts at track 1, so discs interleave) and dumps
  /// untagged tracks at the front.
  ///
  /// This recovers the real disc/track numbers from the files' tags for the
  /// albums that need them: albums with duplicate track numbers (likely
  /// multi-disc) and albums where every track number is missing. Reads are
  /// cached per path, bounded in total and concurrency, and failures just
  /// leave the song untouched (the old ordering applies).
  Future<List<SongModel>> _enrichAmbiguousAlbumOrdering(
    List<SongModel> songs,
  ) async {
    if (songs.isEmpty) return songs;

    final byAlbum = <String, List<SongModel>>{};
    for (final song in songs) {
      final key = song.albumId?.toString() ??
          '${song.album ?? ''}|${song.artist ?? ''}';
      byAlbum.putIfAbsent(key, () => []).add(song);
    }

    final toEnrich = <SongModel>[];
    for (final group in byAlbum.values) {
      final nonzeroTracks = group
          .map((s) => s.track ?? 0)
          .where((t) => t > 0)
          .toList();
      final hasDuplicateTracks =
          nonzeroTracks.toSet().length < nonzeroTracks.length;
      final allMissing = nonzeroTracks.isEmpty;
      if (hasDuplicateTracks || allMissing) {
        toEnrich.addAll(group);
      }
    }
    if (toEnrich.isEmpty) return songs;

    // De-duplicate by path, cap total reads per refresh.
    final seen = <String>{};
    final targets = <SongModel>[];
    for (final song in toEnrich) {
      if (seen.add(song.data)) {
        targets.add(song);
        if (targets.length >= _maxTagReadsPerRefresh) break;
      }
    }
    if (targets.isEmpty) return songs;

    final bridge = GoBackendBridge.instance;
    final reads = <Future<void>>[];
    var cursor = 0;

    void pump() {
      while (reads.length < _tagReadConcurrency && cursor < targets.length) {
        final song = targets[cursor];
        cursor++;
        reads.add(() async {
          Map<String, dynamic>? meta = _tagMetaCache[song.data];
          if (meta == null) {
            try {
              meta = await bridge.readFileMetadata(song.data);
            } catch (_) {
              meta = null;
            }
            meta ??= const {};
            _tagMetaCache[song.data] = meta;
            while (_tagMetaCache.length > _tagCacheMax) {
              _tagMetaCache.remove(_tagMetaCache.keys.first);
            }
          }
          final disc = (meta['disc_number'] as num?)?.toInt() ?? 0;
          final track = (meta['track_number'] as num?)?.toInt() ?? 0;
          if (disc > 0 || track > 0) {
            final map = song.getMap;
            if (disc > 0) map['disc_number'] = disc;
            if (track > 0) map['tag_track_number'] = track;
          }
        }());
      }
    }

    pump();
    while (reads.isNotEmpty) {
      await Future.wait(reads);
      reads.clear();
      pump();
    }

    return songs;
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
