import 'package:on_audio_query/on_audio_query.dart';

/// Formats a [Duration] as a short human string, e.g. "1 hr 12m" or "3 min 05s".
String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours hr ${minutes}m';
  } else if (minutes > 0) {
    return '$minutes min ${seconds.toString().padLeft(2, '0')}s';
  } else {
    return '$seconds sec';
  }
}

String _cleanArtist(SongModel song) {
  final artist = song.artist;
  if (artist == null || artist == '<unknown>' || artist.trim().isEmpty) {
    return 'Unknown Artist';
  }
  return artist;
}

String _cleanAlbum(SongModel song) {
  final album = song.album;
  if (album == null || album == '<unknown>' || album.trim().isEmpty) {
    return 'Unknown Album';
  }
  return album;
}

class AlbumGroup {
  final String name;
  final String artist;
  final List<SongModel> songs;

  AlbumGroup({required this.name, required this.artist, required this.songs});

  int get songCount => songs.length;

  Duration get totalDuration => songs.fold(
    Duration.zero,
        (sum, s) => sum + Duration(milliseconds: s.duration ?? 0),
  );

  /// Song used as the source for cover art (on_audio_query queries artwork
  /// per-song, there's no direct per-album artwork lookup in this repo).
  SongModel get representativeSong => songs.first;
}

class ArtistGroup {
  final String name;
  final List<SongModel> songs;

  ArtistGroup({required this.name, required this.songs});

  int get songCount => songs.length;

  Duration get totalDuration => songs.fold(
    Duration.zero,
        (sum, s) => sum + Duration(milliseconds: s.duration ?? 0),
  );

  SongModel get representativeSong => songs.first;

  List<AlbumGroup> get albums => groupSongsByAlbum(songs);
}

List<ArtistGroup> groupSongsByArtist(List<SongModel> songs) {
  final Map<String, List<SongModel>> map = {};
  for (final song in songs) {
    map.putIfAbsent(_cleanArtist(song), () => []).add(song);
  }

  final groups = map.entries.map((e) => ArtistGroup(name: e.key, songs: e.value)).toList();
  groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return groups;
}

List<AlbumGroup> groupSongsByAlbum(List<SongModel> songs) {
  final Map<(String, String), List<SongModel>> map = {};
  for (final song in songs) {
    final key = (_cleanAlbum(song), _cleanArtist(song));
    map.putIfAbsent(key, () => []).add(song);
  }

  final groups = map.entries
      .map((e) => AlbumGroup(name: e.key.$1, artist: e.key.$2, songs: e.value))
      .toList();
  groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return groups;
}