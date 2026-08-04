import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/services/playlist/playlist_service.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

class PlaylistSongPickerScreen extends StatefulWidget {
  final String playlistId;
  final List<int> existingSongIds;

  const PlaylistSongPickerScreen({
    super.key,
    required this.playlistId,
    required this.existingSongIds,
  });

  @override
  State<PlaylistSongPickerScreen> createState() => _PlaylistSongPickerScreenState();
}

class _PlaylistSongPickerScreenState extends State<PlaylistSongPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<SongModel> _allSongs = [];
  List<SongModel> _filteredSongs = [];
  final Set<int> _selectedIds = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _allSongs = PlaybackController.instance.songs;
    _filteredSongs = _allSongs;
    
    // We only track newly selected items, not existing ones
    // Or we could track all and handle additions
  }

  void _filterSongs(String query) {
    if (query.isEmpty) {
      setState(() => _filteredSongs = _allSongs);
      return;
    }
    
    final lower = query.toLowerCase();
    setState(() {
      _filteredSongs = _allSongs.where((s) {
        return (s.title.toLowerCase().contains(lower)) ||
               (s.artist?.toLowerCase().contains(lower) ?? false) ||
               (s.album?.toLowerCase().contains(lower) ?? false);
      }).toList();
    });
  }

  Future<void> _saveSelection() async {
    setState(() => _isSaving = true);
    
    final playlistService = PlaylistService();
    for (final id in _selectedIds) {
      await playlistService.addSong(widget.playlistId, id);
    }
    
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Center(
                        child: LabelChip(
                          'Add Songs',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isSaving || _selectedIds.isEmpty ? null : _saveSelection,
                      child: _isSaving 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Done', style: TextStyle(
                              color: _selectedIds.isEmpty ? Colors.white38 : Colors.white, 
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            )),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterSongs,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search songs...',
                      hintStyle: TextStyle(color: Colors.white54),
                      prefixIcon: Icon(Icons.search, color: Colors.white54),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _filteredSongs.length,
                  itemBuilder: (context, index) {
                    final song = _filteredSongs[index];
                    final isExisting = widget.existingSongIds.contains(song.id);
                    final isSelected = _selectedIds.contains(song.id);
                    
                    return ListTile(
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
                        style: TextStyle(
                          color: isExisting ? Colors.white54 : Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        song.artist ?? 'Unknown',
                        style: TextStyle(color: isExisting ? Colors.white38 : Colors.white60),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isExisting
                          ? const Icon(Icons.check, color: Colors.white38)
                          : Checkbox(
                              value: isSelected,
                              activeColor: Colors.white,
                              checkColor: Colors.black,
                              side: const BorderSide(color: Colors.white54),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedIds.add(song.id);
                                  } else {
                                    _selectedIds.remove(song.id);
                                  }
                                });
                              },
                            ),
                      onTap: isExisting ? null : () {
                        setState(() {
                          if (isSelected) {
                            _selectedIds.remove(song.id);
                          } else {
                            _selectedIds.add(song.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
