import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:on_audio_query/on_audio_query.dart' hide PlaylistModel;
import 'package:u_player/core/models/playlist_model.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/services/playlist/playlist_service.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/swipe_back_detector.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/modules/library/pages/playlist_song_picker_screen.dart';
import 'package:u_player/main.dart'; // for rootNavigatorKey if needed
import 'package:u_player/modules/player/pages/player_screen.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final PlaylistModel playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late PlaylistModel _playlist;
  List<SongModel> _songs = [];

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    // Reload playlist from service in case it changed
    final allPlaylists = await PlaylistService().getAll();
    final updatedPlaylist = allPlaylists.firstWhere(
      (p) => p.id == _playlist.id,
      orElse: () => _playlist,
    );

    final allSongs = PlaybackController.instance.songs;
    final playlistSongs = <SongModel>[];
    
    for (final id in updatedPlaylist.songIds) {
      final song = allSongs.cast<SongModel?>().firstWhere((s) => s?.id == id, orElse: () => null);
      if (song != null) {
        playlistSongs.add(song);
      }
    }

    setState(() {
      _playlist = updatedPlaylist;
      _songs = playlistSongs;
    });
  }

  Future<void> _pickCoverImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await PlaylistService().setCoverImage(_playlist.id, image.path);
      await _loadSongs();
    }
  }

  Future<void> _addSongs() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistSongPickerScreen(
          playlistId: _playlist.id,
          existingSongIds: _playlist.songIds,
        ),
      ),
    );
    _loadSongs();
  }

  void _playAll({bool shuffle = false}) {
    if (_songs.isEmpty) return;
    if (PlaybackController.instance.isPlayerScreenVisible.value) return;
    
    final songsToPlay = List<SongModel>.from(_songs);
    if (shuffle) {
      songsToPlay.shuffle();
    }
    
    PlaybackController.instance.playQueue(songsToPlay, startIndex: 0);
    
    if (rootNavigatorKey.currentContext != null) {
      Navigator.push(
        rootNavigatorKey.currentContext!,
        MaterialPageRoute(
          settings: const RouteSettings(name: PlayerScreen.routeName),
          builder: (_) => const PlayerScreen(),
        ),
      );
    }
  }

  Widget _buildHeader() {
    Widget cover;
    if (_playlist.coverImagePath != null && _playlist.coverImagePath!.isNotEmpty) {
      cover = Image.file(File(_playlist.coverImagePath!), fit: BoxFit.cover);
    } else if (_songs.isNotEmpty) {
      cover = QueryArtworkWidget(
        id: _songs.first.id,
        type: ArtworkType.AUDIO,
        artworkFit: BoxFit.cover,
        nullArtworkWidget: Container(
          color: Colors.white12,
          child: const Icon(Icons.music_note, color: Colors.white38, size: 60),
        ),
      );
    } else {
      cover = Container(
        color: Colors.white12,
        child: const Icon(Icons.queue_music, color: Colors.white38, size: 60),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _pickCoverImage,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                cover,
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _playlist.name,
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '${_songs.length} songs',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildActionButton(Icons.play_arrow, 'Play', () => _playAll(shuffle: false)),
            const SizedBox(width: 16),
            _buildActionButton(Icons.shuffle, 'Shuffle', () => _playAll(shuffle: true)),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = _songs.isNotEmpty
        ? DynamicGradientBackground(
            songId: _songs.first.id,
            child: _buildBody(),
          )
        : AppGradientBackground(child: _buildBody());

    return SwipeBackDetector(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: _addSongs,
            ),
          ],
        ),
        body: background,
      ),
    );
  }

  Widget _buildBody() {
    return SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 160),
        itemCount: _songs.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _buildHeader();
          
          final song = _songs[index - 1];
          return Dismissible(
            key: ValueKey(song.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              color: Colors.redAccent,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) async {
              await PlaylistService().removeSong(_playlist.id, song.id);
              _loadSongs();
            },
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: QueryArtworkWidget(
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    nullArtworkWidget: Container(
                      color: Colors.white12,
                      child: const Icon(Icons.music_note, color: Colors.white38),
                    ),
                  ),
                ),
              ),
              title: Text(
                song.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                song.artist ?? 'Unknown Artist',
                style: const TextStyle(color: Colors.white60),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                formatDuration(Duration(milliseconds: song.duration ?? 0)),
                style: const TextStyle(color: Colors.white38),
              ),
              onTap: () {
                if (PlaybackController.instance.isPlayerScreenVisible.value) return;
                PlaybackController.instance.playQueue(_songs, startIndex: index - 1);
                if (rootNavigatorKey.currentContext != null) {
                  Navigator.push(
                    rootNavigatorKey.currentContext!,
                    MaterialPageRoute(
                      settings: const RouteSettings(name: PlayerScreen.routeName),
                      builder: (_) => const PlayerScreen(),
                    ),
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }
}
