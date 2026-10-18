import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:u_player/platform/audio_query_compat.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/song_options_dialog.dart';
import 'package:u_player/modules/library/widgets/smart_artwork_widget.dart';
import 'package:u_player/modules/player/widgets/desktop_controls.dart';

/// Tile metrics of the album grid. The grid is laid out by hand instead of
/// with a [GridView] so that one album can expand into a run of cells with
/// the remaining tiles packing around it.
const double _tileHeight = 196;
const double _tileSpacing = 12;
const double _tileMaxWidth = 160;
const double _gridHorizontalPadding = 16;

/// Columns an expanded album spans (clamped when the window is too narrow).
const int _blockColumns = 3;

/// The Linux desktop library: a group list on the left (genres or artists),
/// an album grid in the middle. Clicking an album expands it in place into a
/// 3x1 run of grid cells — artwork filling the left side, its tracklist on
/// the right — while the surrounding tiles reflow around it like a masonry
/// layout. Clicking the artwork (or the card's close button) collapses it
/// back into a tile.
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

String _albumKey(AlbumGroup album) => '${album.name}\u0000${album.artist}';

class _DesktopLibraryLayoutState extends State<DesktopLibraryLayout> {
  final PlaybackController _controller = PlaybackController.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  _GroupMode _groupMode = _GroupMode.genres;

  /// Selected sidebar entry; null = "All songs".
  String? _selectedGroup;

  /// 'album\u0000artist' of the album expanded into a grid block.
  /// null = nothing is expanded.
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

  Future<void> _play(AlbumGroup album, int index) async {
    // Queue the whole album (like the phone's album screen does) starting at
    // the tapped track, so "next" walks the album instead of the library.
    await _controller.playQueue(album.songs, startIndex: index);
  }

  /// Expands the album's block in the grid; tapping the expanded album again
  /// collapses it back into its tile.
  void _selectAlbum(AlbumGroup album) {
    final key = _albumKey(album);
    setState(() => _selectedAlbumKey = _selectedAlbumKey == key ? null : key);
  }

  /// The playing track may sit in a queue that is not the album expanded in
  /// the grid, so every row compares against the live queue position.
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
                                : _AlbumGridView(
                                    albums: albums,
                                    selectedKey: _selectedAlbumKey,
                                    playingAlbumName: _controller.currentSong?.album,
                                    onSelect: _selectAlbum,
                                    onPlay: _play,
                                    isRowPlaying: _isRowPlaying,
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

/// One positioned piece of a grid band: either an album tile or the expanded
/// album's card (which spans [_blockColumns] columns of one row).
class _BandItem {
  final AlbumGroup album;
  final int col;
  final int colSpan;
  final bool isBlock;

  const _BandItem({
    required this.album,
    required this.col,
    this.colSpan = 1,
    this.isBlock = false,
  });
}

/// One row of the album grid. Rows are the unit of lazy building — everything
/// outside the visible rows is never laid out.
class _GridBand {
  final List<_BandItem> items;
  final AlbumGroup? blockAlbum;

  const _GridBand({required this.items, this.blockAlbum});
}

/// Lays [albums] out row by row. When [selectedKey] names one of them, that
/// album expands into a [_blockColumns]-wide card in its own grid row and the
/// other albums are re-packed row-major into the cells left free around it —
/// so the neighbourhood reflows instead of leaving a wide hole.
List<_GridBand> _buildBands(
  List<AlbumGroup> albums,
  int columns,
  String? selectedKey,
) {
  final bands = <_GridBand>[];
  if (albums.isEmpty || columns <= 0) return bands;

  var blockIndex = -1;
  if (selectedKey != null) {
    for (var i = 0; i < albums.length; i++) {
      if (_albumKey(albums[i]) == selectedKey) {
        blockIndex = i;
        break;
      }
    }
  }

  final blockCols = math.min(_blockColumns, columns);
  final blockRow = blockIndex >= 0 ? blockIndex ~/ columns : -1;
  // The card keeps its own column when the row has room for it, and slides
  // left when it does not (albums clicked in the last columns of a row).
  final blockCol = blockIndex >= 0
      ? math.min(blockIndex % columns, columns - blockCols)
      : -1;

  var next = 0;
  AlbumGroup? takeAlbum() {
    while (next < albums.length && next == blockIndex) {
      next++;
    }
    if (next >= albums.length) return null;
    return albums[next++];
  }

  for (var row = 0;; row++) {
    if (row == blockRow) {
      final items = <_BandItem>[];

      // Fill the cells the card leaves free in its own row.
      for (var col = 0; col < columns; col++) {
        if (col >= blockCol && col < blockCol + blockCols) continue;
        final album = takeAlbum();
        if (album == null) break;
        items.add(_BandItem(album: album, col: col));
      }
      final blockAlbum = albums[blockIndex];
      items.add(_BandItem(
        album: blockAlbum,
        col: blockCol,
        colSpan: blockCols,
        isBlock: true,
      ));

      bands.add(_GridBand(items: items, blockAlbum: blockAlbum));
      continue;
    }

    final items = <_BandItem>[];
    for (var col = 0; col < columns; col++) {
      final album = takeAlbum();
      if (album == null) break;
      items.add(_BandItem(album: album, col: col));
    }
    if (items.isEmpty) break;
    bands.add(_GridBand(items: items));
  }

  return bands;
}

/// The album grid. Tiles are laid out band by band inside a lazy
/// [SliverList], so a big library stays cheap to scroll — only the bands on
/// screen are built, even while an album is expanded.
class _AlbumGridView extends StatefulWidget {
  final List<AlbumGroup> albums;
  final String? selectedKey;
  final String? playingAlbumName;
  final ValueChanged<AlbumGroup> onSelect;
  final void Function(AlbumGroup album, int index) onPlay;
  final bool Function(SongModel song) isRowPlaying;

  const _AlbumGridView({
    required this.albums,
    required this.selectedKey,
    required this.playingAlbumName,
    required this.onSelect,
    required this.onPlay,
    required this.isRowPlaying,
  });

  @override
  State<_AlbumGridView> createState() => _AlbumGridViewState();
}

class _AlbumGridViewState extends State<_AlbumGridView> {
  final ScrollController _scrollController = ScrollController();

  int _columns = 1;
  int? _pendingScrollRow;

  @override
  void didUpdateWidget(covariant _AlbumGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A freshly expanded album is brought into view after it has been laid
    // out; collapsing (key -> null) never moves the scroll position.
    if (widget.selectedKey != null && widget.selectedKey != oldWidget.selectedKey) {
      _pendingScrollRow = _rowForSelection();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPending());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int? _rowForSelection() {
    final key = widget.selectedKey;
    if (key == null || _columns <= 0) return null;
    final index = widget.albums.indexWhere((album) => _albumKey(album) == key);
    if (index < 0) return null;
    return index ~/ _columns;
  }

  void _scrollToPending() {
    final row = _pendingScrollRow;
    _pendingScrollRow = null;
    if (row == null || !_scrollController.hasClients) return;

    final blockTop = row * (_tileHeight + _tileSpacing);
    final blockHeight = _tileHeight;
    final position = _scrollController.position;
    final viewport = position.viewportDimension;

    // Tapping a tile that is already on screen should not move the grid.
    if (blockTop >= position.pixels &&
        blockTop + blockHeight <= position.pixels + viewport) {
      return;
    }

    final target = (blockTop - (viewport - blockHeight) / 2)
        .clamp(0.0, position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The same column math the old SliverGridDelegateWithMaxCrossAxisExtent
        // performed, kept explicit because the expanded album needs to know
        // exactly which cells it covers.
        final available =
            math.max(0.0, constraints.maxWidth - _gridHorizontalPadding * 2);
        _columns = math.max(1, (available / (_tileMaxWidth + _tileSpacing)).ceil());
        final tileWidth = available <= 0
            ? _tileMaxWidth
            : (available - (_columns - 1) * _tileSpacing) / _columns;

        final bands = _buildBands(widget.albums, _columns, widget.selectedKey);

        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                _gridHorizontalPadding,
                0,
                _gridHorizontalPadding,
                14,
              ),
              sliver: SliverList.builder(
                itemCount: bands.length,
                itemBuilder: (context, index) {
                  final band = bands[index];
                  final blockAlbum = band.blockAlbum;
                  return _AlbumBand(
                    band: band,
                    tileWidth: tileWidth,
                    playingAlbumName: widget.playingAlbumName,
                    onSelect: widget.onSelect,
                    onPlay: widget.onPlay,
                    isRowPlaying: widget.isRowPlaying,
                    onCollapse: blockAlbum == null
                        ? null
                        : () => widget.onSelect(blockAlbum),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One row of the grid, rendered as an explicitly positioned stack so the
/// expanded card can span several cells of a single row.
class _AlbumBand extends StatelessWidget {
  final _GridBand band;
  final double tileWidth;
  final String? playingAlbumName;
  final ValueChanged<AlbumGroup> onSelect;
  final void Function(AlbumGroup album, int index) onPlay;
  final bool Function(SongModel song) isRowPlaying;
  final VoidCallback? onCollapse;

  const _AlbumBand({
    required this.band,
    required this.tileWidth,
    required this.playingAlbumName,
    required this.onSelect,
    required this.onPlay,
    required this.isRowPlaying,
    required this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // The row is one tile tall plus the spacing that separates it from the
      // next one; the tiles inside sit at its top.
      height: _tileHeight + _tileSpacing,
      child: Stack(
        children: [
          for (final item in band.items)
            Positioned(
              // Stable per-album keys so the tiles that merely reflow around
              // an expanding card keep their element (and artwork) instead
              // of being matched by position.
              key: ValueKey(_albumKey(item.album)),
              left: item.col * (tileWidth + _tileSpacing),
              width: item.colSpan * tileWidth + (item.colSpan - 1) * _tileSpacing,
              height: _tileHeight,
              child: item.isBlock
                  ? _AlbumBlock(
                      album: item.album,
                      isRowPlaying: isRowPlaying,
                      onPlay: onPlay,
                      onCollapse: onCollapse,
                    )
                  : _AlbumTile(
                      album: item.album,
                      isPlaying: item.album.name == playingAlbumName,
                      onTap: () => onSelect(item.album),
                      onDoubleTap: () => onPlay(item.album, 0),
                    ),
            ),
        ],
      ),
    );
  }
}

/// The expanded album: the artwork fills the whole left side of the card and
/// the album's details sit beside it on the right — the desktop player's
/// shape, inline in the grid where the album's tile used to be. Clicking the
/// artwork (or the ✕) collapses the card back into its tile.
class _AlbumBlock extends StatelessWidget {
  final AlbumGroup album;
  final bool Function(SongModel song) isRowPlaying;
  final void Function(AlbumGroup album, int index) onPlay;
  final VoidCallback? onCollapse;

  const _AlbumBlock({
    required this.album,
    required this.isRowPlaying,
    required this.onPlay,
    required this.onCollapse,
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

  String _meta() {
    final year = _year();
    return [
      album.artist,
      ?year,
      '${album.songCount} ${album.songCount == 1 ? 'track' : 'tracks'}',
      formatDuration(album.totalDuration),
    ].join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Very narrow windows leave no room for the artwork beside the
          // tracklist; the list then uses the whole card.
          final showPhoto = constraints.maxWidth >= 320;
          final photoSide = showPhoto
              ? math.min(constraints.maxHeight, constraints.maxWidth * 0.42)
              : 0.0;

          return Row(
            children: [
              if (showPhoto) ...[
                _photo(photoSide),
                const SizedBox(width: 12),
              ],
              Expanded(child: _list()),
            ],
          );
        },
      ),
    );
  }

  /// The album artwork, filling the card's full height. Clicking it collapses
  /// the card: the card *is* the album's grid cell, so the photo doubles as
  /// the way back to the tile it replaced.
  Widget _photo(double side) {
    return Tooltip(
      message: 'Collapse album',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onCollapse,
          child: SizedBox(
            width: side,
            height: side,
            child: SmartArtworkWidget(
              song: album.representativeSong,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _meta(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => onPlay(album, 0),
              icon: const Icon(Icons.play_arrow_rounded, size: 17),
              label: const Text('Play'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Collapse album',
              iconSize: 18,
              color: Colors.white54,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded),
              onPressed: onCollapse,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(child: _trackList()),
      ],
    );
  }

  Widget _trackList() {
    return ListView.builder(
      padding: const EdgeInsets.only(right: 2, bottom: 2),
      itemCount: album.songs.length,
      itemBuilder: (context, index) {
        final song = album.songs[index];
        final isPlaying = isRowPlaying(song);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onPlay(album, index),
            onSecondaryTap: () => SongOptionsDialog.show(context, song),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isPlaying ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: isPlaying
                        ? const Icon(
                            Icons.graphic_eq_rounded,
                            size: 13,
                            color: Colors.greenAccent,
                          )
                        : Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                          ),
                  ),
                  Expanded(
                    child: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isPlaying ? Colors.greenAccent : Colors.white,
                        fontSize: 12.5,
                        fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatPlaybackTime(Duration(milliseconds: song.duration ?? 0)),
                    style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

class _AlbumTile extends StatelessWidget {
  final AlbumGroup album;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _AlbumTile({
    required this.album,
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
            borderRadius: BorderRadius.circular(12),
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



