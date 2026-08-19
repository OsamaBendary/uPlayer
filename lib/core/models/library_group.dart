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

/// Disc number for ordering an album's songs. The MediaStore never exposes
/// it, so it comes from the tag metadata read during the library scan
/// (stored on the song's map by `LocalAudioRepository`); single-disc albums
/// simply default to disc 1.
int _discNumber(SongModel song) {
  final disc = song.getMap['disc_number'];
  if (disc is num && disc > 0) return disc.toInt();
  return 1;
}

/// on_audio_query's `track` is the raw MediaStore TRACK column — it does NOT
/// combine disc and track numbers. Missing numbers come back as 0 rather
/// than null, so 0 must be treated as "unknown" here, otherwise untagged
/// tracks would sort first. When the scan recovered a real tag track number
/// (`tag_track_number`), it wins over a 0 from the MediaStore. Unknown
/// positions sink to the bottom rather than the top, since "unknown
/// position" shouldn't imply "plays first".
int _trackNumber(SongModel song) {
  final raw = song.track ?? 0;
  if (raw > 0) return raw;
  final tagTrack = song.getMap['tag_track_number'];
  if (tagTrack is num && tagTrack > 0) return tagTrack.toInt();
  return 1 << 30;
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
  /// Now that `songs` is track-ordered, this is genuinely track 1 rather
  /// than whichever track happened to sort first alphabetically.
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

  final groups = map.entries.map((e) {
    // This is the actual fix: previously `e.value` was left in whatever
    // order it arrived in from the flat song list (alphabetical by title),
    // so an album's tracklist had nothing to do with the artist's intended
    // running order. Sort by disc then track; fall back to title for ties
    // or missing track metadata so the order is still deterministic.
    final orderedSongs = List<SongModel>.from(e.value)
      ..sort((a, b) {
        final discCompare = _discNumber(a).compareTo(_discNumber(b));
        if (discCompare != 0) return discCompare;
        final trackCompare = _trackNumber(a).compareTo(_trackNumber(b));
        if (trackCompare != 0) return trackCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return AlbumGroup(name: e.key.$1, artist: e.key.$2, songs: orderedSongs);
  }).toList();

  groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return groups;
}