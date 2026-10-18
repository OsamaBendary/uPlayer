import 'package:flutter/material.dart';
import 'package:u_player/platform/audio_query_compat.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/song_options_dialog.dart';
import 'package:u_player/modules/library/widgets/smart_artwork_widget.dart';
import 'package:u_player/modules/player/widgets/desktop_controls.dart';

/// The Linux desktop library: a group list on the left (genres or artists),
/// an album grid in the middle, and the selected album's tracks in a panel
/// along the bottom — the shape a wide window wants, instead of the phone's
/// two-column grid + full-screen drill-down.
class DesktopLibraryLayout extends StatefulWidget {
  final List<SongModel> songs;
  final bool isLoading;

  const DesktopLibraryLayout({
    super.key,
    required this.songs,
    this.isLoading = false,
  });

  @override
  State<DesktopLibraryLayout> createState() => _DesktopLibraryLayoutState();
}

enum _GroupMode { genres, artists }

class _DesktopLibraryLayoutState extends State<DesktopLibraryLayout> {
  final PlaybackController _controller = PlaybackController.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  _GroupMode _groupMode = _GroupMode.genres;

  /// Selected sidebar entry; null = "All songs".
  String? _selectedGroup;

  /// 'album\u0000artist' of the album whose tracks are shown in the bottom
  /// panel. null = follow whatever is playing.
  String? _selectedAlbumKey;

  String _query = '';

  // Grouping every song on each rebuild is wasteful — cache the derived
  // lists until the inputs actually change.
  List<SongModel>? _cacheSongs;
  _GroupMode? _cacheMode;
  String? _cacheGroup;
  String _cacheQuery = '';
  List<_GroupEntry> _cachedGroups = [];
  List<AlbumGroup> _cachedAlbums = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final next = _searchController.text.trim();
    if (next != _query) setState(() => _query = next);
  }

  void _recompute() {
    final songs = widget.songs;
    final query = _query.toLowerCase();

    // Search narrows the whole library first, then the sidebar selection
    // narrows it further — so a search never silently ignores the group the
    // user picked.
    List<SongModel> matched = songs;
    if (query.isNotEmpty) {
      matched = songs.where((s) {
        return s.title.toLowerCase().contains(query) ||
            (s.artist ?? '').toLowerCase().contains(query) ||
            (s.album ?? '').toLowerCase().contains(query);
      }).toList();
    }

    _cachedGroups = _buildGroups(matched);
    _cachedAlbums = groupSongsByAlbum(_songsInSelectedGroup(songs));
    _cacheSongs = songs;
    _cacheMode = _groupMode;
    _cacheGroup = _selectedGroup;
    _cacheQuery = _query;
  }

  List<SongModel> _songsInSelectedGroup(List<SongModel> songs) {
    final group = _selectedGroup;
    if (group == null) return songs;

    final query = _query.toLowerCase();
    return songs.where((s) {
      if (query.isNotEmpty &&
          !s.title.toLowerCase().contains(query) &&
          !(s.artist ?? '').toLowerCase().contains(query) &&
          !(s.album ?? '').toLowerCase().contains(query)) {
        return false;
      }
      if (_groupMode == _GroupMode.artists) {
        return (s.artist ?? 'Unknown Artist') == group;
      }
      return splitGenres(s.genre).contains(group);
    }).toList();
  }

  /// Sidebar entries for the current mode, counted over the searched subset.
  List<_GroupEntry> _buildGroups(List<SongModel> songs) {
    final counts = <String, int>{};

    if (_groupMode == _GroupMode.genres) {
      for (final song in songs) {
        for (final genre in splitGenres(song.genre)) {
          counts[genre] = (counts[genre] ?? 0) + 1;
        }
      }
    } else {
      for (final group in groupSongsByArtist(songs)) {
        counts[group.name] = group.songCount;
      }
    }

    final entries = counts.entries
        .map((e) => _GroupEntry(label: e.key, count: e.value))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return entries;
  }

  AlbumGroup? _resolveSelectedAlbum(List<AlbumGroup> albums) {
    if (albums.isEmpty) return null;

    final key = _selectedAlbumKey;
    if (key != null) {
      for (final album in albums) {
        if ('${album.name}\u0000${album.artist}' == key) return album;
      }
    }

    // Nothing picked (or the pick scrolled out of the current filter): show
    // what is playing, so the bottom panel is useful the moment music
    // starts — which is what the panel is for.
    final playing = _controller.currentSong;
    if (playing != null) {
      for (final album in albums) {
        if (album.name == (playing.album ?? '') && album.artist == (playing.artist ?? '')) {
          return album;
        }
      }
    }
    return albums.first;
  }

  Future<void> _play(AlbumGroup album, int index) async {
    // Queue the whole album (like the phone's album screen does) starting at
    // the tapped track, so "next" walks the album instead of the library.
    await _controller.playQueue(album.songs, startIndex: index);
  }

  void _selectAlbum(AlbumGroup album) {
    setState(() => _selectedAlbumKey = '${album.name}\u0000${album.artist}');
  }

  /// The playing track may sit in a queue that is not the album shown in the
  /// panel, so every row compares against the live queue position.
  bool _isRowPlaying(SongModel song) {
    final current = _controller.currentSong;
    return current != null && current.id == song.id;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.songs.isEmpty) {
      return const Center(
        child: Text('No songs found on device', style: TextStyle(color: Colors.white)),
      );
    }

    if (!identical(_cacheSongs, widget.songs) ||
        _cacheMode != _groupMode ||
        _cacheGroup != _selectedGroup ||
        _cacheQuery != _query) {
      _recompute();
    }

    final albums = _cachedAlbums;
    final selectedAlbum = _resolveSelectedAlbum(albums);

    return Scaffold(
      backgroundColor: Colors.black,
      body: AppGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 210,
                      child: _GroupSidebar(
                        mode: _groupMode,
                        groups: _cachedGroups,
                        totalSongs: widget.songs.length,
                        selected: _selectedGroup,
                        onModeChanged: (mode) => setState(() {
                          _groupMode = mode;
                          _selectedGroup = null;
                        }),
                        onSelected: (value) => setState(() => _selectedGroup = value),
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _SearchRow(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            onClear: () => _searchController.clear(),
                            albumCount: albums.length,
                          ),
                          Expanded(
                            child: albums.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No albums match this selection.',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  )
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      // The track panel keeps a fixed share of
                                      // the height so the grid stays the
                                      // focus on tall windows but still
                                      // leaves the panel usable on short
                                      // ones.
                                      return _LibraryBody(
                                        albums: albums,
                                        panelHeight: (constraints.maxHeight * 0.40)
                                            .clamp(190.0, 280.0),
                                        selectedAlbum: selectedAlbum,
                                        playingAlbumName: _controller.currentSong?.album,
                                        onSelect: _selectAlbum,
                                        onPlay: _play,
                                        isRowPlaying: _isRowPlaying,
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Album grid on top, the selected album's tracks underneath — the middle
/// column of the desktop library.
class _LibraryBody extends StatelessWidget {
  final List<AlbumGroup> albums;
  final double panelHeight;
  final AlbumGroup? selectedAlbum;
  final String? playingAlbumName;
  final ValueChanged<AlbumGroup> onSelect;
  final void Function(AlbumGroup album, int index) onPlay;
  final bool Function(SongModel song) isRowPlaying;

  const _LibraryBody({
    required this.albums,
    required this.panelHeight,
    required this.selectedAlbum,
    required this.playingAlbumName,
    required this.onSelect,
    required this.onPlay,
    required this.isRowPlaying,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _AlbumGrid(
            albums: albums,
            selectedKey: selectedAlbum == null
                ? null
                : '${selectedAlbum!.name}\u0000${selectedAlbum!.artist}',
            playingAlbumName: playingAlbumName,
            onSelect: onSelect,
            onPlay: (album) => onPlay(album, 0),
          ),
        ),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
        SizedBox(
          height: panelHeight,
          child: selectedAlbum == null
              ? const SizedBox.shrink()
              : _AlbumTrackPanel(
                  album: selectedAlbum!,
                  isRowPlaying: isRowPlaying,
                  onPlay: (index) => onPlay(selectedAlbum!, index),
                ),
        ),
      ],
    );
  }
}

/// Splits a metadata genre string into individual genres: files in the wild
/// use ';', ',', '/' or '|' as separators, sometimes several at once.
List<String> splitGenres(String? raw) {
  if (raw == null) return const [];
  return raw
      .split(RegExp(r'[;|/]|,\s*'))
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toSet()
      .toList();
}

class _GroupEntry {
  final String label;
  final int count;

  const _GroupEntry({required this.label, required this.count});
}

class _GroupSidebar extends StatelessWidget {
  final _GroupMode mode;
  final List<_GroupEntry> groups;
  final int totalSongs;
  final String? selected;
  final ValueChanged<_GroupMode> onModeChanged;
  final ValueChanged<String?> onSelected;

  const _GroupSidebar({
    required this.mode,
    required this.groups,
    required this.totalSongs,
    required this.selected,
    required this.onModeChanged,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final label = mode == _GroupMode.genres ? 'Genres' : 'Artists';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: PopupMenuButton<_GroupMode>(
            tooltip: 'Group by',
            position: PopupMenuPosition.under,
            onSelected: onModeChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: _GroupMode.genres, child: Text('Genres')),
              PopupMenuItem(value: _GroupMode.artists, child: Text('Artists')),
            ],
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(Icons.expand_more_rounded, color: Colors.white54, size: 18),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            itemCount: groups.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _SidebarTile(
                  label: 'All songs',
                  trailing: '$totalSongs',
                  isSelected: selected == null,
                  onTap: () => onSelected(null),
                );
              }
              final entry = groups[index - 1];
              return _SidebarTile(
                label: entry.label,
                trailing: '${entry.count}',
                isSelected: selected == entry.label,
                onTap: () => onSelected(entry.label),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final String label;
  final String trailing;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.label,
    required this.trailing,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  trailing,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;
  final int albumCount;

  const _SearchRow({
    required this.controller,
    required this.focusNode,
    required this.onClear,
    required this.albumCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.search,
                      cursorColor: Colors.white,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search songs, albums, artists',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: onClear,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$albumCount ${albumCount == 1 ? 'album' : 'albums'}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  final List<AlbumGroup> albums;
  final String? selectedKey;
  final String? playingAlbumName;
  final ValueChanged<AlbumGroup> onSelect;
  final ValueChanged<AlbumGroup> onPlay;

  const _AlbumGrid({
    required this.albums,
    required this.selectedKey,
    required this.playingAlbumName,
    required this.onSelect,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 196,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final key = '${album.name}\u0000${album.artist}';
        return _AlbumTile(
          album: album,
          isSelected: key == selectedKey,
          isPlaying: album.name == playingAlbumName,
          onTap: () => onSelect(album),
          onDoubleTap: () => onPlay(album),
        );
      },
    );
  }
}

class _AlbumTile extends StatelessWidget {
  final AlbumGroup album;
  final bool isSelected;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _AlbumTile({
    required this.album,
    required this.isSelected,
    required this.isPlaying,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: Colors.white.withValues(alpha: 0.18))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SmartArtworkWidget(
                          song: album.representativeSong,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      if (isPlaying)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.graphic_eq_rounded,
                              color: Colors.greenAccent,
                              size: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumTrackPanel extends StatelessWidget {
  final AlbumGroup album;
  final bool Function(SongModel song) isRowPlaying;
  final ValueChanged<int> onPlay;

  const _AlbumTrackPanel({
    required this.album,
    required this.isRowPlaying,
    required this.onPlay,
  });

  /// Release year as printed on the first track that carries one.
  String? _year() {
    for (final song in album.songs) {
      final releaseDate = (song.linuxScan?['releaseDate'] ?? '').toString();
      if (releaseDate.length >= 4) {
        final year = releaseDate.substring(0, 4);
        if (int.tryParse(year) != null) return year;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final year = _year();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              SmartArtworkWidget(
                song: album.representativeSong,
                width: 52,
                height: 52,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        album.artist,
                        ?year,
                        '${album.songCount} ${album.songCount == 1 ? 'track' : 'tracks'}',
                        formatDuration(album.totalDuration),
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => onPlay(0),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Play'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 10),
            itemCount: album.songs.length,
            itemBuilder: (context, index) {
              final song = album.songs[index];
              final isPlaying = isRowPlaying(song);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onPlay(index),
                    onSecondaryTap: () => SongOptionsDialog.show(context, song),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isPlaying
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: isPlaying
                                ? const Icon(Icons.graphic_eq_rounded,
                                    size: 14, color: Colors.greenAccent)
                                : Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                          Expanded(
                            child: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isPlaying ? Colors.greenAccent : Colors.white,
                                fontSize: 13,
                                fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            formatPlaybackTime(Duration(milliseconds: song.duration ?? 0)),
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
