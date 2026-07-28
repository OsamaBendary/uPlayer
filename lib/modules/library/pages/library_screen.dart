import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/core/services/access_to_files/access_service.dart';
import 'package:u_player/modules/library/pages/album_song_list_screen.dart';
import 'package:u_player/modules/library/pages/artist_screen.dart';
import 'package:u_player/modules/library/widgets/album_card.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/artist_card.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';
import 'package:u_player/modules/settings/pages/folder_picker_screen.dart';

enum LibrarySortMode { artist, album }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final LocalAudioRepository _audioRepository = LocalAudioRepository();

  bool _isLoading = true;
  List<SongModel> _songs = [];
  LibrarySortMode _sortMode = LibrarySortMode.artist;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    setState(() => _isLoading = true);
    final songs = await _audioRepository.fetchLocalSongs();
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _isLoading = false;
    });
  }

  Future<void> _openFolderPicker() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
    );
    // The selected folders may have changed while that screen was open —
    // reload so the library reflects it right away.
    _loadSongs();
  }

  Future<void> _openFavorites() async {
    final favorites = await _audioRepository.fetchFavoriteSongs();
    if (!mounted) return;

    if (favorites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No favorites yet — tap the heart on a song to add one.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF2A2A2A),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumSongListScreen.fromSongs(
          title: 'Favorites',
          subtitle: '${favorites.length} song${favorites.length == 1 ? '' : 's'}',
          songs: favorites,
          artworkSongId: favorites.first.id,
          heroArtTag: 'favorites-art',
          heroTitleTag: 'favorites-title',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AppGradientBackground(
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _songs.isEmpty
              ? const Center(
            child: Text('No songs found on device', style: TextStyle(color: Colors.white)),
          )
              : Column(
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: LabelChip(
                          'Library',
                          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    _HeaderIconButton(
                      icon: Icons.favorite_rounded,
                      onTap: _openFavorites,
                    ),
                    const SizedBox(width: 8),
                    _HeaderIconButton(
                      icon: Icons.folder_rounded,
                      onTap: _openFolderPicker,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SortToggle(
                mode: _sortMode,
                onChanged: (mode) => setState(() => _sortMode = mode),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_sortMode == LibrarySortMode.artist) {
      final artists = groupSongsByArtist(_songs);
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: artists.length,
        itemBuilder: (context, index) {
          final artist = artists[index];
          return ArtistCard(
            artist: artist,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ArtistScreen(artist: artist)),
              );
            },
          );
        },
      );
    }

    final albums = groupSongsByAlbum(_songs);
    const crossAxisCount = 2;
    const spacing = 16.0;
    const horizontalPadding = 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            (constraints.maxWidth - horizontalPadding * 2 - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final itemHeight = AlbumCard.estimatedHeightForWidth(itemWidth);

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: itemHeight,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return AlbumCard(
              album: album,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => AlbumSongListScreen(album: album)),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white70, size: 20),
        ),
      ),
    );
  }
}

class _SortToggle extends StatelessWidget {
  final LibrarySortMode mode;
  final ValueChanged<LibrarySortMode> onChanged;

  const _SortToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _button(context, 'Artists', LibrarySortMode.artist),
            _button(context, 'Albums', LibrarySortMode.album),
          ],
        ),
      ),
    );
  }

  Widget _button(BuildContext context, String label, LibrarySortMode target) {
    final bool selected = mode == target;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(target),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
