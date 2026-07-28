import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';


Future<ConcatenatingAudioSource> createPlaylist(List<SongModel> songs) async {
  return ConcatenatingAudioSource(
    children: songs.map((song) {
      return AudioSource.uri(
        Uri.parse(song.data),
        tag: MediaItem(
          id: song.id.toString(),
          title: song.title,
          artist: song.artist ?? "Unknown Artist",
          album: song.album ?? "Unknown Album",
        ),
      );
    }).toList(),
  );
}