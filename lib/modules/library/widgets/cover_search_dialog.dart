import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/cover/cover_search_service.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/services/tag_editor/tag_editor_service.dart';
import 'package:u_player/core/utils/app_snackbar.dart';

/// Searches the iTunes catalog for a song's cover art, lets the user pick a
/// match, and embeds the artwork into the audio file's tags.
class CoverSearchDialog extends StatefulWidget {
  final SongModel song;

  const CoverSearchDialog({super.key, required this.song});

  static Future<void> show(BuildContext context, SongModel song) async {
    await showDialog(
      context: context,
      builder: (_) => CoverSearchDialog(song: song),
    );
  }

  @override
  State<CoverSearchDialog> createState() => _CoverSearchDialogState();
}

class _CoverSearchDialogState extends State<CoverSearchDialog> {
  final CoverSearchService _service = CoverSearchService();

  List<CoverCandidate> _candidates = [];
  bool _isSearching = false;
  bool _isEmbedding = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _isSearching = true;
      _searched = false;
      _candidates = [];
    });
    final results = await _service.search(
      title: widget.song.title,
      artist: widget.song.artist ?? '',
    );
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _searched = true;
      _candidates = results;
    });
  }

  Future<void> _embed(CoverCandidate candidate) async {
    setState(() => _isEmbedding = true);
    final bytes = await _service.fetchArtwork(candidate.artworkUrl);
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        setState(() => _isEmbedding = false);
        AppSnackBar.show('Failed to download cover art.', context: context);
      }
      return;
    }

    final tagInfo = await TagEditorService().readTags(widget.song.data);
    final success = await TagEditorService().writeTagsAndArtwork(
      filePath: widget.song.data,
      title: tagInfo?.title.isNotEmpty == true
          ? tagInfo!.title
          : widget.song.title,
      artist: tagInfo?.artist.isNotEmpty == true
          ? tagInfo!.artist
          : (widget.song.artist ?? ''),
      album: tagInfo?.album.isNotEmpty == true
          ? tagInfo!.album
          : (widget.song.album ?? ''),
      year: tagInfo?.year ?? '',
      genre: tagInfo?.genre ?? '',
      artworkBytes: bytes,
    );

    if (!mounted) return;
    if (success) {
      await PlaybackController.instance.invalidateArtworkCache(widget.song);
      await PlaybackController.instance.refreshLibrary();
      if (!mounted) return;
      Navigator.pop(context);
      AppSnackBar.show('Cover art embedded into "${widget.song.title}"!', context: context);
    } else {
      setState(() => _isEmbedding = false);
      AppSnackBar.show('Failed to embed cover art.', context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF222222),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.image_search_rounded, color: Colors.white),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Search Cover Art',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        height: 380,
        child: _buildContent(),
      ),
      actions: [
        TextButton(
          onPressed: _isEmbedding ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_isEmbedding) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 14),
            Text('Embedding artwork...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (!_searched || _candidates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported_outlined, color: Colors.white38, size: 40),
            const SizedBox(height: 10),
            const Text(
              'No covers found for this song.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _search,
              child: const Text('Try Again', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Searching for "${widget.song.title}" by ${widget.song.artist ?? 'Unknown'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _candidates.length,
            itemBuilder: (context, index) {
              final candidate = _candidates[index];
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _embed(candidate),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          candidate.artworkUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: Colors.white10,
                            child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      candidate.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}