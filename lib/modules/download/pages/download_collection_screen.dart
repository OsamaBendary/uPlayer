import 'package:flutter/material.dart';
import 'package:u_player/core/services/download/download_service.dart';
import 'package:u_player/core/services/extension/extension_service.dart';
import 'package:u_player/core/utils/app_snackbar.dart';
import 'package:u_player/modules/download/widgets/download_quality_picker.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';
import 'package:u_player/modules/library/widgets/swipe_back_detector.dart';

class DownloadCollectionScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? coverUrl;
  final String id;
  final bool isArtist;

  const DownloadCollectionScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.coverUrl,
    required this.id,
    required this.isArtist,
  });

  @override
  State<DownloadCollectionScreen> createState() => _DownloadCollectionScreenState();
}

class _DownloadCollectionScreenState extends State<DownloadCollectionScreen> {
  List<SearchResultTrack> _tracks = [];
  List<SearchResultAlbum> _releases = [];
  bool _isLoading = true;
  bool _isBatchDownloading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (widget.isArtist) {
      final releases = await ExtensionService().getArtistReleases(widget.id);
      if (mounted) {
        setState(() {
          _releases = releases;
          _isLoading = false;
        });
      }
    } else {
      final tracks = await ExtensionService().getAlbumTracks(widget.id, albumCoverUrl: widget.coverUrl);
      if (mounted) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadAllAlbumTracks() async {
    if (_tracks.isEmpty) return;
    final qualityChoice = await showDownloadQualityPicker(context);
    if (qualityChoice == null || !mounted) return;
    setState(() => _isBatchDownloading = true);

    await DownloadService().batchDownload(
      _tracks,
      qualityChoice: qualityChoice,
      onProgressUpdate: () {
        if (mounted) setState(() {});
      },
    );

    if (mounted) {
      setState(() => _isBatchDownloading = false);
      AppSnackBar.show('Downloaded ${_tracks.length} tracks to library!', context: context);
    }
  }

  Future<void> _downloadAllArtistReleases() async {
    if (_releases.isEmpty) return;
    final qualityChoice = await showDownloadQualityPicker(context);
    if (qualityChoice == null || !mounted) return;
    setState(() => _isBatchDownloading = true);

    final List<SearchResultTrack> allTracks = [];
    for (final rel in _releases) {
      final tList = await ExtensionService().getAlbumTracks(rel.id, albumCoverUrl: rel.coverUrl);
      allTracks.addAll(tList);
    }

    await DownloadService().batchDownload(
      allTracks,
      qualityChoice: qualityChoice,
      onProgressUpdate: () {
        if (mounted) setState(() {});
      },
    );

    if (mounted) {
      setState(() => _isBatchDownloading = false);
      AppSnackBar.show(
        'Downloaded ${allTracks.length} tracks across ${_releases.length} releases!',
        context: context,
      );
    }
  }

  String _formatDuration(int durationMs) {
    final sec = durationMs ~/ 1000;
    final mins = sec ~/ 60;
    final remainingSecs = (sec % 60).toString().padLeft(2, '0');
    return '$mins:$remainingSecs';
  }

  @override
  Widget build(BuildContext context) {
    return SwipeBackDetector(
      child: AppGradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: LabelChip(widget.isArtist ? 'Artist Releases' : 'Album Tracks'),
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(widget.isArtist ? 40 : 16),
                        child: widget.coverUrl != null
                            ? Image.network(
                                widget.coverUrl!,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, e, s) => Container(
                                  width: 80,
                                  height: 80,
                                  color: Colors.white10,
                                  child: Icon(
                                    widget.isArtist ? Icons.person_rounded : Icons.album_rounded,
                                    color: Colors.white38,
                                    size: 40,
                                  ),
                                ),
                              )
                            : Container(
                                width: 80,
                                height: 80,
                                color: Colors.white10,
                                child: Icon(
                                  widget.isArtist ? Icons.person_rounded : Icons.album_rounded,
                                  color: Colors.white38,
                                  size: 40,
                                ),
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.isArtist ? '${_releases.length} Albums & EPs' : widget.subtitle,
                              style: const TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              icon: _isBatchDownloading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                    )
                                  : const Icon(Icons.download_rounded, size: 18),
                              label: Text(
                                _isBatchDownloading
                                    ? 'Downloading...'
                                    : widget.isArtist
                                        ? 'Download All Releases'
                                        : 'Download Album (${_tracks.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _isBatchDownloading || _isLoading
                                  ? null
                                  : widget.isArtist
                                      ? _downloadAllArtistReleases
                                      : _downloadAllAlbumTracks,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Content Grid/List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : widget.isArtist
                          ? _buildReleasesGrid()
                          : _buildTracksList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReleasesGrid() {
    if (_releases.isEmpty) {
      return const Center(child: Text('No releases found for this artist.', style: TextStyle(color: Colors.white38)));
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.76,
      ),
      itemCount: _releases.length,
      itemBuilder: (context, index) {
        final rel = _releases[index];

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DownloadCollectionScreen(
                  title: rel.name,
                  subtitle: '${rel.artist} • ${rel.trackCount} tracks',
                  coverUrl: rel.coverUrl,
                  id: rel.id,
                  isArtist: false,
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: rel.coverUrl != null
                        ? Image.network(
                            rel.coverUrl!,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, e, s) => Container(
                              color: Colors.white10,
                              child: const Icon(Icons.album_rounded, color: Colors.white38, size: 40),
                            ),
                          )
                        : Container(
                            color: Colors.white10,
                            child: const Icon(Icons.album_rounded, color: Colors.white38, size: 40),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                LabelChip(
                  rel.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        rel.recordType.toUpperCase(),
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${rel.trackCount} tracks',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTracksList() {
    if (_tracks.isEmpty) {
      return const Center(child: Text('No tracks found.', style: TextStyle(color: Colors.white38)));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        final task = DownloadService().activeDownloads[track.id];

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: track.coverUrl != null
                    ? Image.network(
                        track.coverUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, s) => Container(
                          width: 44,
                          height: 44,
                          color: Colors.white10,
                          child: const Icon(Icons.music_note_rounded, color: Colors.white38),
                        ),
                      )
                    : Container(
                        width: 44,
                        height: 44,
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
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${track.artist} • ${_formatDuration(track.durationMs)}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Builder(
                          builder: (context) {
                            final rawQuality = track.qualityLabel as String?;
                            final isUnavailable = rawQuality == null || rawQuality.isEmpty;
                            final badgeText = isUnavailable ? 'Unavailable' : rawQuality;
                            final badgeColor = isUnavailable ? Colors.grey : const Color(0xFFFFD700);

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                    const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 24)
                  else if (task != null && task.hasFailed)
                    IconButton(
                      icon: const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 24),
                      tooltip: 'Download failed. Tap to retry',
                      onPressed: () async {
                        final quality = await showDownloadQualityPicker(
                          context,
                          initial: DownloadQualityChoice.fromTask(task.quality, task.providerQualityId),
                        );
                        if (quality == null) return;
                        DownloadService().activeDownloads.remove(track.id);
                        DownloadService().startDownload(
                          trackId: track.id,
                          title: track.name,
                          artist: track.artist,
                          album: track.album,
                          downloadUrl: track.downloadUrl,
                          deezerTrackId: track.deezerTrackId,
                          coverUrl: track.coverUrl ?? widget.coverUrl,
                          qualityChoice: quality,
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
                      icon: const Icon(Icons.file_download_rounded, color: Colors.white70),
                      onPressed: () async {
                        final quality = await showDownloadQualityPicker(context);
                        if (quality == null) return;
                        DownloadService().startDownload(
                          trackId: track.id,
                          title: track.name,
                          artist: track.artist,
                          album: track.album,
                          downloadUrl: track.downloadUrl,
                          deezerTrackId: track.deezerTrackId,
                          coverUrl: track.coverUrl ?? widget.coverUrl,
                          qualityChoice: quality,
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
}
