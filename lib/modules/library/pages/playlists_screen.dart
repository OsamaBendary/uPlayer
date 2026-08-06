import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart' hide PlaylistModel;
import 'package:u_player/core/models/playlist_model.dart';
import 'package:u_player/core/services/access_to_files/access_service.dart';
import 'package:u_player/core/services/playlist/playlist_service.dart';
import 'package:u_player/modules/library/pages/album_song_list_screen.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';
import 'package:u_player/modules/library/pages/playlist_detail_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  List<PlaylistModel> _playlists = [];
  bool _isLoading = true;
  int _likedCount = 0;
  final LocalAudioRepository _audioRepository = LocalAudioRepository();

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
    _loadLikedCount();
  }

  Future<void> _loadLikedCount() async {
    final favorites = await _audioRepository.fetchFavoriteSongs();
    if (mounted) setState(() => _likedCount = favorites.length);
  }

  Future<void> _openLikedSongs() async {
    final favorites = await _audioRepository.fetchFavoriteSongs();
    if (!mounted) return;
    if (favorites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No liked songs yet — tap the heart on a song to add one.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF2A2A2A),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumSongListScreen.fromSongs(
          title: 'Liked Songs',
          subtitle: '${favorites.length} song${favorites.length == 1 ? '' : 's'}',
          songs: favorites,
          artworkSongId: favorites.first.id,
          heroArtTag: 'liked-songs-art',
          heroTitleTag: 'liked-songs-title',
        ),
      ),
    );
    _loadLikedCount();
  }

  Future<void> _loadPlaylists() async {
    final playlists = await PlaylistService().getAll();
    setState(() {
      _playlists = playlists;
      _isLoading = false;
    });
  }

  Future<void> _createPlaylist() async {
    String name = '';
    String? imagePath;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF222222),
              title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final image = await picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        setDialogState(() => imagePath = image.path);
                      }
                    },
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                        image: imagePath != null
                            ? DecorationImage(
                                image: FileImage(File(imagePath!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: imagePath == null
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_rounded, color: Colors.white38, size: 32),
                                SizedBox(height: 4),
                                Text('Add Cover', style: TextStyle(color: Colors.white38, fontSize: 12)),
                              ],
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Playlist name',
                      hintStyle: TextStyle(color: Colors.white38),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                    ),
                    onChanged: (val) => name = val,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Create', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && name.trim().isNotEmpty) {
      final playlist = await PlaylistService().createPlaylist(name.trim());
      if (imagePath != null) {
        await PlaylistService().setCoverImage(playlist.id, imagePath);
      }
      _loadPlaylists();
    }
  }

  Future<void> _showPlaylistOptions(PlaylistModel playlist) async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(playlist.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white),
              title: const Text('Rename', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(dialogContext);
                _renamePlaylist(playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(dialogContext);
                await PlaylistService().deletePlaylist(playlist.id);
                _loadPlaylists();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Future<void> _renamePlaylist(PlaylistModel playlist) async {
    String name = playlist.name;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Rename Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          autofocus: true,
          controller: TextEditingController(text: name),
          style: const TextStyle(color: Colors.white),
          onChanged: (val) => name = val,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true && name.trim().isNotEmpty) {
      await PlaylistService().renamePlaylist(playlist.id, name.trim());
      _loadPlaylists();
    }
  }

  Widget _buildPlaylistCard(PlaylistModel playlist) {
    Widget cover;
    if (playlist.coverImagePath != null && playlist.coverImagePath!.isNotEmpty) {
      cover = Image.file(File(playlist.coverImagePath!), fit: BoxFit.cover);
    } else if (playlist.songIds.isNotEmpty) {
      cover = QueryArtworkWidget(
        id: playlist.songIds.first,
        type: ArtworkType.AUDIO,
        artworkFit: BoxFit.cover,
        nullArtworkWidget: Container(
          color: Colors.white12,
          child: const Icon(Icons.music_note, color: Colors.white38, size: 40),
        ),
      );
    } else {
      cover = Container(
        color: Colors.white12,
        child: const Icon(Icons.queue_music, color: Colors.white38, size: 40),
      );
    }

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: playlist)),
        );
        _loadPlaylists();
      },
      onLongPress: () => _showPlaylistOptions(playlist),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: cover),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${playlist.songIds.length} songs',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLikedSongsCard() {
    return GestureDetector(
      onTap: _openLikedSongs,
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF9C27B0), Color(0xFFE91E63)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE91E63).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Liked Songs',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_likedCount song${_likedCount == 1 ? '' : 's'}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.7), size: 28),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48), // Balance
                  const LabelChip(
                    'Playlists',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: _createPlaylist,
                  ),
                ],
              ),
            ),
            // Pinned liked songs card
            _buildLikedSongsCard(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _playlists.isEmpty
                      ? const Center(
                          child: Text(
                            'No playlists yet — tap + to create one',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 160),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: _playlists.length,
                          itemBuilder: (context, index) {
                            return _buildPlaylistCard(_playlists[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
