import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/modules/library/pages/album_song_list_screen.dart';
import 'package:u_player/modules/library/pages/artist_screen.dart';
import 'package:u_player/modules/library/widgets/album_card.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/artist_card.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

/// Pre-calculated positions for zero-lag scrub performance.
class PrecomputedAlphabetData {
  final Map<String, double> offsets;
  final Set<String> activeLetters;
  static const List<String> alphabet = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
  ];

  PrecomputedAlphabetData({required this.offsets, required this.activeLetters});

  factory PrecomputedAlphabetData.fromArtists(List<ArtistGroup> artists) {
    final Map<String, double> offsets = {};
    final Set<String> activeLetters = {};
    double currentOffset = 68.0;

    for (int i = 0; i < artists.length; i++) {
      final name = artists[i].name.trim();
      final firstChar = name.isNotEmpty ? name[0].toUpperCase() : '#';
      final letter = (firstChar.codeUnitAt(0) >= 65 && firstChar.codeUnitAt(0) <= 90) ? firstChar : '#';

      activeLetters.add(letter);
      offsets.putIfAbsent(letter, () => currentOffset);
      currentOffset += 72.0;
    }

    return PrecomputedAlphabetData(offsets: offsets, activeLetters: activeLetters);
  }

  factory PrecomputedAlphabetData.fromAlbums(
      List<AlbumGroup> albums,
      int crossAxisCount,
      double itemHeight,
      double spacing,
      ) {
    final Map<String, double> offsets = {};
    final Set<String> activeLetters = {};
    double currentOffset = 68.0;

    for (int i = 0; i < albums.length; i += crossAxisCount) {
      final name = albums[i].name.trim();
      final firstChar = name.isNotEmpty ? name[0].toUpperCase() : '#';
      final letter = (firstChar.codeUnitAt(0) >= 65 && firstChar.codeUnitAt(0) <= 90) ? firstChar : '#';

      activeLetters.add(letter);
      offsets.putIfAbsent(letter, () => currentOffset);
      currentOffset += itemHeight + spacing;
    }

    return PrecomputedAlphabetData(offsets: offsets, activeLetters: activeLetters);
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final PlaybackController _controller = PlaybackController.instance;
  final PageController _pageController = PageController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  int _currentIndex = 0;
  String _searchQuery = '';

  // Grouping the whole library into artists/albums is only needed while
  // searching, and only needs to happen again when the song list itself
  // changes — not on every keystroke.
  List<SongModel>? _groupCacheSongs;
  List<ArtistGroup> _cachedArtists = [];
  List<AlbumGroup> _cachedAlbums = [];

  @override
  void initState() {
    super.initState();
    _controller.ensureInitialized();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final next = _searchController.text.trim();
    if (next != _searchQuery) {
      setState(() => _searchQuery = next);
    }
  }

  void _ensureSearchGroups(List<SongModel> songs) {
    if (identical(_groupCacheSongs, songs)) return;
    _groupCacheSongs = songs;
    _cachedArtists = groupSongsByArtist(songs);
    _cachedAlbums = groupSongsByAlbum(songs);
  }


  void _onTabChanged(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final isLoading = _controller.isLoading;
        final songs = _controller.songs;

        final query = _searchQuery.toLowerCase();
        final isSearching = query.isNotEmpty;

        List<SongModel> matchedSongs = const [];
        List<AlbumGroup> matchedAlbums = const [];
        List<ArtistGroup> matchedArtists = const [];

        if (isSearching) {
          _ensureSearchGroups(songs);

          matchedSongs = songs.where((s) {
            final title = s.title.toLowerCase();
            final artist = (s.artist ?? '').toLowerCase();
            final album = (s.album ?? '').toLowerCase();
            return title.contains(query) || artist.contains(query) || album.contains(query);
          }).toList();

          matchedAlbums = _cachedAlbums.where((a) => a.name.toLowerCase().contains(query)).toList();
          matchedArtists = _cachedArtists.where((a) => a.name.toLowerCase().contains(query)).toList();
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: AppGradientBackground(
            child: SafeArea(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : songs.isEmpty
                  ? const Center(
                child: Text('No songs found on device', style: TextStyle(color: Colors.white)),
              )
                  : Column(
                children: [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: LabelChip(
                        'Library',
                        style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _LibrarySearchBar(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onClear: () => _searchController.clear(),
                  ),
                  const SizedBox(height: 12),
                  if (!isSearching) ...[
                    _SortToggle(
                      currentIndex: _currentIndex,
                      onChanged: _onTabChanged,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: isSearching
                        ? _SearchResultsView(
                      query: _searchQuery,
                      songs: matchedSongs,
                      albums: matchedAlbums,
                      artists: matchedArtists,
                    )
                        : PageView(
                      controller: _pageController,
                      onPageChanged: (index) => setState(() => _currentIndex = index),
                      children: [
                        _ArtistsTabView(songs: songs),
                        _AlbumsTabView(songs: songs),
                      ],
                    ),
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

class _ArtistsTabView extends StatefulWidget {
  final List<SongModel> songs;
  const _ArtistsTabView({required this.songs});

  @override
  State<_ArtistsTabView> createState() => _ArtistsTabViewState();
}

class _ArtistsTabViewState extends State<_ArtistsTabView> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  List<ArtistGroup> _artists = [];
  PrecomputedAlphabetData? _alphabetData;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _processData();
  }

  @override
  void didUpdateWidget(covariant _ArtistsTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songs != widget.songs) {
      _processData();
    }
  }

  void _processData() {
    final grouped = groupSongsByArtist(widget.songs);
    setState(() {
      _artists = grouped;
      _alphabetData = PrecomputedAlphabetData.fromArtists(grouped);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLetter(String letter) {
    if (_alphabetData == null) return;
    final targetOffset = _alphabetData!.offsets[letter];
    if (targetOffset != null && _scrollController.hasClients) {
      _scrollController.jumpTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_artists.isEmpty || _alphabetData == null) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(left: 16, right: 36, top: 8),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AllSongsBar(
                    label: 'All Songs (${widget.songs.length})',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AlbumSongListScreen.fromSongs(
                            title: 'All Songs',
                            subtitle: '${widget.songs.length} songs',
                            songs: widget.songs,
                            artworkSongId: widget.songs.first.id,
                            heroArtTag: 'all-songs-art',
                            heroTitleTag: 'all-songs-title',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(left: 16, right: 36, bottom: 160),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final artist = _artists[index];

                    return AnimatedBuilder(
                      animation: PlaybackController.instance,
                      builder: (context, _) {
                        final currentPlayingSong = PlaybackController.instance.currentSong;
                        final isPlaying = currentPlayingSong != null &&
                            artist.songs.any((s) => s.id == currentPlayingSong.id);

                        return ArtistCard(
                          artist: artist,
                          isPlaying: isPlaying,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ArtistScreen(artist: artist)),
                            );
                          },
                        );
                      },
                    );
                  },
                  childCount: _artists.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 4,
          top: 0,
          bottom: 0,
          child: AlphabetScrubber(
            activeLetters: _alphabetData!.activeLetters,
            onLetterSelect: _scrollToLetter,
          ),
        ),
      ],
    );
  }
}

class _AlbumsTabView extends StatefulWidget {
  final List<SongModel> songs;
  const _AlbumsTabView({required this.songs});

  @override
  State<_AlbumsTabView> createState() => _AlbumsTabViewState();
}

class _AlbumsTabViewState extends State<_AlbumsTabView> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  List<AlbumGroup> _albums = [];
  PrecomputedAlphabetData? _alphabetData;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _albums = groupSongsByAlbum(widget.songs);
  }

  @override
  void didUpdateWidget(covariant _AlbumsTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songs != widget.songs) {
      _albums = groupSongsByAlbum(widget.songs);
      _alphabetData = null;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLetter(String letter) {
    if (_alphabetData == null) return;
    final targetOffset = _alphabetData!.offsets[letter];
    if (targetOffset != null && _scrollController.hasClients) {
      _scrollController.jumpTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_albums.isEmpty) {
      return const SizedBox.shrink();
    }

    const crossAxisCount = 2;
    const spacing = 16.0;
    const horizontalPadding = 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - horizontalPadding * 2 - spacing * (crossAxisCount - 1) - 20) / crossAxisCount;
        final itemHeight = AlbumCard.estimatedHeightForWidth(itemWidth);

        _alphabetData ??= PrecomputedAlphabetData.fromAlbums(
          _albums,
          crossAxisCount,
          itemHeight,
          spacing,
        );

        return Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.only(left: horizontalPadding, right: 36, top: 8),
                  sliver: SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AllSongsBar(
                        label: 'All Songs (${widget.songs.length})',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AlbumSongListScreen.fromSongs(
                                title: 'All Songs',
                                subtitle: '${widget.songs.length} songs',
                                songs: widget.songs,
                                artworkSongId: widget.songs.first.id,
                                heroArtTag: 'all-songs-art',
                                heroTitleTag: 'all-songs-title',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(left: horizontalPadding, right: 36, bottom: 160),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      mainAxisExtent: itemHeight,
                    ),
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        final album = _albums[index];

                        return AnimatedBuilder(
                          animation: PlaybackController.instance,
                          builder: (context, _) {
                            final currentPlayingSong = PlaybackController.instance.currentSong;
                            final isPlaying = currentPlayingSong != null &&
                                album.songs.any((s) => s.id == currentPlayingSong.id);

                            return AlbumCard(
                              album: album,
                              isPlaying: isPlaying,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => AlbumSongListScreen(album: album)),
                                );
                              },
                            );
                          },
                        );
                      },
                      childCount: _albums.length,
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: AlphabetScrubber(
                activeLetters: _alphabetData!.activeLetters,
                onLetterSelect: _scrollToLetter,
              ),
            ),
          ],
        );
      },
    );
  }
}

class AlphabetScrubber extends StatefulWidget {
  final Set<String> activeLetters;
  final ValueChanged<String> onLetterSelect;

  const AlphabetScrubber({
    super.key,
    required this.activeLetters,
    required this.onLetterSelect,
  });

  @override
  State<AlphabetScrubber> createState() => _AlphabetScrubberState();
}

class _AlphabetScrubberState extends State<AlphabetScrubber> {
  double? _dragY;
  int _lastSelectedIndex = -1;

  void _updateDrag(Offset localPosition, double height) {
    final clampedY = localPosition.dy.clamp(0.0, height);
    final itemHeight = height / PrecomputedAlphabetData.alphabet.length;
    final index = (clampedY / itemHeight).floor().clamp(0, PrecomputedAlphabetData.alphabet.length - 1);

    if (index != _lastSelectedIndex) {
      _lastSelectedIndex = index;
      widget.onLetterSelect(PrecomputedAlphabetData.alphabet[index]);
    }

    if (_dragY != clampedY) {
      setState(() => _dragY = clampedY);
    }
  }

  void _resetDrag() {
    if (_dragY != null) {
      setState(() {
        _dragY = null;
        _lastSelectedIndex = -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final alphabet = PrecomputedAlphabetData.alphabet;
        final itemHeight = totalHeight / alphabet.length;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (details) => _updateDrag(details.localPosition, totalHeight),
          onVerticalDragUpdate: (details) => _updateDrag(details.localPosition, totalHeight),
          onVerticalDragEnd: (_) => _resetDrag(),
          onVerticalDragCancel: _resetDrag,
          child: RepaintBoundary(
            child: Container(
              width: 32,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(alphabet.length, (index) {
                  final letter = alphabet[index];
                  final isAvailable = widget.activeLetters.contains(letter);

                  double scale = 1.0;
                  double opacity = isAvailable ? 0.6 : 0.2;
                  Color color = isAvailable ? Colors.white : Colors.white30;

                  if (_dragY != null) {
                    final itemCenterY = (index * itemHeight) + (itemHeight / 2);
                    final distance = (_dragY! - itemCenterY).abs() / itemHeight;

                    if (distance < 3.0) {
                      final double factor = math.max(0.0, 1.0 - (distance / 3.0));
                      scale = 1.0 + (factor * 0.8);
                      opacity = isAvailable ? (0.6 + (factor * 0.4)) : opacity;
                      color = isAvailable ? Colors.white : Colors.white54;
                    }
                  }

                  return SizedBox(
                    height: itemHeight,
                    child: Center(
                      child: Transform.scale(
                        scale: scale,
                        child: Text(
                          letter,
                          style: TextStyle(
                            color: color.withOpacity(opacity),
                            fontSize: 10,
                            fontWeight: scale > 1.2 ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AllSongsBar extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AllSongsBar({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.queue_music_rounded, color: Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}


class _SortToggle extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  const _SortToggle({required this.currentIndex, required this.onChanged});

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
            _button(context, 'Artists', 0),
            _button(context, 'Albums', 1),
          ],
        ),
      ),
    );
  }

  Widget _button(BuildContext context, String label, int targetIndex) {
    final bool selected = currentIndex == targetIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(targetIndex),
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

/// Search field for songs/albums/artists, shown pinned above the tab
/// toggle. Purely presentational — filtering happens in the parent.
class _LibrarySearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;

  const _LibrarySearchBar({
    required this.controller,
    required this.focusNode,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                cursorColor: Colors.white,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search songs, albums, artists',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
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
                    child: Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Combined search results: matching artists, albums, and songs, each in
/// their own section. Sections with no matches are omitted entirely.
class _SearchResultsView extends StatelessWidget {
  final String query;
  final List<SongModel> songs;
  final List<AlbumGroup> albums;
  final List<ArtistGroup> artists;

  const _SearchResultsView({
    required this.query,
    required this.songs,
    required this.albums,
    required this.artists,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty && albums.isEmpty && artists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No results for "$query"',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 15),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
      children: [
        if (artists.isNotEmpty) ...[
          const _SearchSectionLabel('Artists'),
          const SizedBox(height: 8),
          ...artists.map(
                (artist) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AnimatedBuilder(
                animation: PlaybackController.instance,
                builder: (context, _) {
                  final currentPlayingSong = PlaybackController.instance.currentSong;
                  final isPlaying = currentPlayingSong != null &&
                      artist.songs.any((s) => s.id == currentPlayingSong.id);
                  return ArtistCard(
                    artist: artist,
                    isPlaying: isPlaying,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ArtistScreen(artist: artist)),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (albums.isNotEmpty) ...[
          const _SearchSectionLabel('Albums'),
          const SizedBox(height: 8),
          SizedBox(
            height: AlbumCard.estimatedHeightForWidth(140),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: albums.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final album = albums[index];
                return SizedBox(
                  width: 140,
                  child: AnimatedBuilder(
                    animation: PlaybackController.instance,
                    builder: (context, _) {
                      final currentPlayingSong = PlaybackController.instance.currentSong;
                      final isPlaying = currentPlayingSong != null &&
                          album.songs.any((s) => s.id == currentPlayingSong.id);
                      return AlbumCard(
                        album: album,
                        isPlaying: isPlaying,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => AlbumSongListScreen(album: album)),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (songs.isNotEmpty) ...[
          const _SearchSectionLabel('Songs'),
          const SizedBox(height: 8),
          ...songs.map(
                (song) => _SearchSongTile(
              song: song,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlbumSongListScreen.fromSongs(
                    title: 'Search Results',
                    subtitle: '${songs.length} song${songs.length == 1 ? '' : 's'}',
                    songs: songs,
                    artworkSongId: song.id,
                    heroArtTag: 'search-art-${song.id}',
                    heroTitleTag: 'search-title-${song.id}',
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SearchSectionLabel extends StatelessWidget {
  final String label;
  const _SearchSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Lightweight row for a single song match. Tapping opens a list screen
/// scoped to the current search results, consistent with how "All Songs"
/// and "Favorites" are opened elsewhere in the library.
class _SearchSongTile extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;

  const _SearchSongTile({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PlaybackController.instance,
      builder: (context, _) {
        final isPlaying = PlaybackController.instance.currentSong?.id == song.id;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: QueryArtworkWidget(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      artworkWidth: 40,
                      artworkHeight: 40,
                      artworkFit: BoxFit.cover,
                      nullArtworkWidget: Container(
                        width: 40,
                        height: 40,
                        color: Colors.white10,
                        child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPlaying ? Colors.greenAccent : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
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