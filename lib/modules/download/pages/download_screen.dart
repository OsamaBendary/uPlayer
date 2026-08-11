import 'dart:async';
import 'package:flutter/material.dart';
import 'package:u_player/core/services/download/download_service.dart';
import 'package:u_player/core/services/extension/extension_service.dart';
import 'package:u_player/core/services/go/go_backend_bridge.dart';
import 'package:u_player/modules/download/pages/download_collection_screen.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';
import 'package:u_player/modules/settings/pages/extension_management_screen.dart';

enum SearchCategory { tracks, albums, artists }

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final TextEditingController _searchController = TextEditingController();
  SearchCategory _selectedCategory = SearchCategory.tracks;

  List<SearchResultTrack> _trackResults = [];
  List<SearchResultAlbum> _albumResults = [];
  List<SearchResultArtist> _artistResults = [];

  bool _isSearching = false;

  // FIX: was a single shared `_hasSearched` flag. That meant switching
  // categories without re-typing a query would show "No X found" for a
  // category that was never actually searched. Now tracked per category.
  final Map<SearchCategory, bool> _hasSearchedFor = {
    SearchCategory.tracks: false,
    SearchCategory.albums: false,
    SearchCategory.artists: false,
  };

  // FIX: surfaced so failed searches show a real message instead of
  // silently looking like "no results" or spinning forever.
  String? _searchError;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget — do NOT await this. ExtensionService.init() calls
    // fetchExtensionsFromRepo for each saved repo URL (10 s timeout each),
    // and IndexedStack builds all screens simultaneously at startup, so any
    // awaited call here would block the entire app from showing until every
    // repo fetch resolves or times out.
    unawaited(ExtensionService().init());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _searchError = null;
      _hasSearchedFor[_selectedCategory] = true;
    });

    // FIX: wrap in try/catch/finally. Previously, if the extension threw
    // (network error, timeout, bad extension response) `_isSearching` was
    // never reset — the UI was stuck on the loading spinner permanently.
    try {
      if (_selectedCategory == SearchCategory.tracks) {
        final tracks = await ExtensionService().searchTracks(query);
        if (mounted) setState(() => _trackResults = tracks);
      } else if (_selectedCategory == SearchCategory.albums) {
        final albums = await ExtensionService().searchAlbums(query);
        if (mounted) setState(() => _albumResults = albums);
      } else {
        final artists = await ExtensionService().searchArtists(query);
        if (mounted) setState(() => _artistResults = artists);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _searchError = 'Search failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  String _formatDuration(int durationMs) {
    final sec = durationMs ~/ 1000;
    final mins = sec ~/ 60;
    final remainingSecs = (sec % 60).toString().padLeft(2, '0');
    return '$mins:$remainingSecs';
  }

  void _openExtensionManager() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExtensionManagementScreen()),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _showQualitySelector() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Select Download Quality', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: DownloadQuality.values.map((q) {
            final isSelected = ExtensionService().selectedQuality == q;
            return ListTile(
              title: Text(q.label, style: TextStyle(color: isSelected ? Colors.amberAccent : Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(q.description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Colors.amberAccent) : null,
              onTap: () async {
                await ExtensionService().setQuality(q);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                if (mounted) setState(() {});
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProviderSelector() {
    final providers = ExtensionService().downloadProviders;
    final selected = ExtensionService().selectedProviderId;

    Widget buildChip(String label, {required IconData icon, required bool isSelected, required VoidCallback onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.amber : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? Colors.amberAccent : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? Colors.black : Colors.white70, size: 14),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (providers.isEmpty) {
      return GestureDetector(
        onTap: _openExtensionManager,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.amberAccent, size: 14),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'No download providers — tap to install one',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          buildChip(
            'Auto',
            icon: Icons.auto_awesome_rounded,
            isSelected: selected == null,
            onTap: () async {
              await ExtensionService().setDownloadProvider(null);
              if (mounted) setState(() {});
            },
          ),
          ...providers.map((p) => buildChip(
                p.name,
                icon: Icons.cloud_download_rounded,
                isSelected: selected == p.id,
                onTap: () async {
                  await ExtensionService().setDownloadProvider(p.id);
                  if (mounted) setState(() {});
                },
              )),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, SearchCategory category) {
    final isSelected = _selectedCategory == category;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = category;
          if (_searchController.text.trim().isNotEmpty) {
            _performSearch();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeQuality = ExtensionService().selectedQuality;
    return AppGradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: LabelChip(
                      'Search & Download',
                      style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Quality Selector Badge Chip
                  GestureDetector(
                    onTap: _showQualitySelector,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.high_quality_rounded, color: Colors.amberAccent, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            activeQuality.label,
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.extension_rounded, color: Colors.white, size: 22),
                    tooltip: 'Manage Extensions',
                    onPressed: _openExtensionManager,
                  ),
                ],
              ),
            ),
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _performSearch(),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, or albums...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                            onPressed: _performSearch,
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),
            // Download Provider Selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              child: _buildProviderSelector(),
            ),
            // Go backend state banner
            if (!GoBackendBridge.instance.isAvailable)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Go backend off (legacy mode): '
                          '${GoBackendBridge.instance.lastError.isEmpty ? 'unknown reason' : GoBackendBridge.instance.lastError}',
                          style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Category Segmented Control
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  _buildCategoryChip('Tracks', SearchCategory.tracks),
                  const SizedBox(width: 10),
                  _buildCategoryChip('Albums', SearchCategory.albums),
                  const SizedBox(width: 10),
                  _buildCategoryChip('Artists', SearchCategory.artists),
                ],
              ),
            ),
            // Results View
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _searchError != null
                      ? Center(
                          child: Text(_searchError!, style: const TextStyle(color: Colors.redAccent)),
                        )
                      : _selectedCategory == SearchCategory.tracks
                          ? _buildTracksList()
                          : _selectedCategory == SearchCategory.albums
                              ? _buildAlbumsList()
                              : _buildArtistsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTracksList() {
    if (_trackResults.isEmpty && _hasSearchedFor[SearchCategory.tracks]!) {
      return const Center(child: Text('No tracks found.', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      itemCount: _trackResults.length,
      itemBuilder: (context, index) {
        final track = _trackResults[index];
        final task = DownloadService().activeDownloads[track.id];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: track.coverUrl != null
                    ? Image.network(
                  track.coverUrl!,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, e, s) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.white10,
                    child: const Icon(Icons.music_note_rounded, color: Colors.white38),
                  ),
                )
                    : Container(
                  width: 50,
                  height: 50,
                  color: Colors.white10,
                  child: const Icon(Icons.music_note_rounded, color: Colors.white38),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${track.artist} • ${track.album}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _formatDuration(track.durationMs),
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        const SizedBox(width: 8),
                        Builder(
                          builder: (context) {
                            final rawQuality = track.qualityLabel as String?;
                            final isUnavailable = rawQuality == null || rawQuality.isEmpty;
                            final badgeText = isUnavailable ? 'Unavailable' : rawQuality;
                            final badgeColor = isUnavailable ? Colors.grey : const Color(0xFFFFD700);

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 0.8),
                              ),
                              child: Text(
                                badgeText,
                                style: TextStyle(
                                  color: badgeColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.language_rounded, color: Colors.white54, size: 20),
                    tooltip: 'Open in Web Browser (Cloudflare / Direct Web Download)',
                    onPressed: () {
                      DownloadService.openWebDownloadPage(track.artist, track.name);
                    },
                  ),
                  if (task != null && task.isCompleted)
                    const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 26)
                  else if (task != null && task.hasFailed)
                    IconButton(
                      icon: const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 26),
                      tooltip: 'Download failed. Tap to retry',
                      onPressed: () {
                        DownloadService().activeDownloads.remove(track.id);
                        DownloadService().startDownload(
                          trackId: track.id,
                          title: track.name,
                          artist: track.artist,
                          album: track.album,
                          downloadUrl: track.downloadUrl,
                          deezerTrackId: track.deezerTrackId,
                          coverUrl: track.coverUrl,
                          onProgressUpdate: () => setState(() {}),
                        );
                        setState(() {});
                      },
                    )
                  else if (task != null)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        value: task.progress > 0 ? task.progress : null,
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.file_download_rounded, color: Colors.white),
                      onPressed: () {
                        DownloadService().startDownload(
                          trackId: track.id,
                          title: track.name,
                          artist: track.artist,
                          album: track.album,
                          downloadUrl: track.downloadUrl,
                          deezerTrackId: track.deezerTrackId,
                          coverUrl: track.coverUrl,
                          onProgressUpdate: () => setState(() {}),
                        );
                        setState(() {});
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlbumsList() {
    if (_albumResults.isEmpty && _hasSearchedFor[SearchCategory.albums]!) {
      return const Center(child: Text('No albums found.', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      itemCount: _albumResults.length,
      itemBuilder: (context, index) {
        final album = _albumResults[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DownloadCollectionScreen(
                  title: album.name,
                  subtitle: '${album.artist} • ${album.trackCount} tracks',
                  coverUrl: album.coverUrl,
                  id: album.id,
                  isArtist: false,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: album.coverUrl != null
                      ? Image.network(
                    album.coverUrl!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, s) => Container(
                      width: 60,
                      height: 60,
                      color: Colors.white10,
                      child: const Icon(Icons.album_rounded, color: Colors.white38),
                    ),
                  )
                      : Container(
                    width: 60,
                    height: 60,
                    color: Colors.white10,
                    child: const Icon(Icons.album_rounded, color: Colors.white38),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${album.artist} • ${album.trackCount} tracks',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildArtistsList() {
    if (_artistResults.isEmpty && _hasSearchedFor[SearchCategory.artists]!) {
      return const Center(child: Text('No artists found.', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      itemCount: _artistResults.length,
      itemBuilder: (context, index) {
        final artist = _artistResults[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DownloadCollectionScreen(
                  title: artist.name,
                  subtitle: 'Artist Discography',
                  coverUrl: artist.coverUrl,
                  id: artist.id,
                  isArtist: true,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: artist.coverUrl != null
                      ? Image.network(
                    artist.coverUrl!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, s) => Container(
                      width: 60,
                      height: 60,
                      color: Colors.white10,
                      child: const Icon(Icons.person_rounded, color: Colors.white38),
                    ),
                  )
                      : Container(
                    width: 60,
                    height: 60,
                    color: Colors.white10,
                    child: const Icon(Icons.person_rounded, color: Colors.white38),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap to view discography',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}