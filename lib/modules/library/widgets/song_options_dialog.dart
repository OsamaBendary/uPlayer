import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/favorites_service/favorites_service.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/services/playlist/playlist_service.dart';
import 'package:u_player/core/utils/app_snackbar.dart';
import 'package:u_player/modules/library/widgets/cover_search_dialog.dart';
import 'package:u_player/modules/library/widgets/tag_editor_dialog.dart';

class SongOptionsDialog extends StatefulWidget {
  final SongModel song;

  const SongOptionsDialog({super.key, required this.song});

  static Future<void> show(BuildContext context, SongModel song) async {
    await showDialog(
      context: context,
      builder: (_) => SongOptionsDialog(song: song),
    );
  }

  @override
  State<SongOptionsDialog> createState() => _SongOptionsDialogState();
}

class _SongOptionsDialogState extends State<SongOptionsDialog> {
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final fav = await FavoritesService().isFavorite(widget.song.id);
    if (mounted) {
      setState(() => _isFavorite = fav);
    }
  }

  Future<void> _toggleFavorite() async {
    await FavoritesService().toggleFavorite(widget.song.id);
    final fav = await FavoritesService().isFavorite(widget.song.id);
    if (mounted) {
      setState(() => _isFavorite = fav);
      Navigator.pop(context);
      AppSnackBar.show(fav ? 'Added to Liked Songs' : 'Removed from Liked Songs', context: context);
    }
  }

  Future<void> _showAddToPlaylistDialog() async {
    final playlists = await PlaylistService().getAll();
    if (!mounted) return;

    if (playlists.isEmpty) {
      Navigator.pop(context);
      AppSnackBar.show('No playlists created yet. Create one in the Playlists tab!', context: context);
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF222222),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add to Playlist', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                final inPlaylist = playlist.songIds.contains(widget.song.id);
                return ListTile(
                  leading: Icon(
                    Icons.queue_music_rounded,
                    color: inPlaylist ? Colors.white38 : Colors.white,
                  ),
                  title: Text(
                    playlist.name,
                    style: TextStyle(color: inPlaylist ? Colors.white38 : Colors.white),
                  ),
                  subtitle: Text(
                    '${playlist.songIds.length} songs',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  trailing: inPlaylist ? const Icon(Icons.check_rounded, color: Colors.white38) : null,
                  onTap: inPlaylist
                      ? null
                      : () async {
                          await PlaylistService().addSong(playlist.id, widget.song.id);
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          Navigator.pop(context);
                          AppSnackBar.show('Added to ${playlist.name}', context: context);
                        },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
          ],
        );
      },
    );
  }

  void _showInfo() {
    final durationSec = (widget.song.duration ?? 0) ~/ 1000;
    final mins = durationSec ~/ 60;
    final secs = (durationSec % 60).toString().padLeft(2, '0');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Song Info', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Title', widget.song.title),
            _infoRow('Artist', widget.song.artist ?? 'Unknown'),
            _infoRow('Album', widget.song.album ?? 'Unknown'),
            _infoRow('Duration', '$mins:$secs'),
            _infoRow('Path', widget.song.data),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
            TextSpan(text: value, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF222222),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: _isFavorite ? Colors.redAccent : Colors.white70,
            ),
            title: Text(
              _isFavorite ? 'Remove from Liked Songs' : 'Add to Liked Songs',
              style: const TextStyle(color: Colors.white),
            ),
            onTap: _toggleFavorite,
          ),
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded, color: Colors.white70),
            title: const Text('Add to Queue', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              PlaybackController.instance.addToQueue(widget.song);
              AppSnackBar.show('"${widget.song.title}" added to queue', context: context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded, color: Colors.white70),
            title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
            onTap: _showAddToPlaylistDialog,
          ),
          ListTile(
            leading: const Icon(Icons.image_search_rounded, color: Colors.white70),
            title: const Text('Search & Set Cover Art', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              CoverSearchDialog.show(context, widget.song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note_rounded, color: Colors.white70),
            title: const Text('Edit Audio Tags', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              await showDialog(
                context: context,
                builder: (_) => TagEditorDialog(song: widget.song),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded, color: Colors.white70),
            title: const Text('Song Info', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _showInfo();
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }
}
