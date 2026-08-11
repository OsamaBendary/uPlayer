import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/services/tag_editor/tag_editor_service.dart';
import 'package:u_player/core/utils/app_snackbar.dart';

class TagEditorDialog extends StatefulWidget {
  final SongModel song;

  const TagEditorDialog({super.key, required this.song});

  @override
  State<TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<TagEditorDialog> {
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  late TextEditingController _yearController;
  late TextEditingController _genreController;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.song.title);
    _artistController = TextEditingController(text: widget.song.artist ?? '');
    _albumController = TextEditingController(text: widget.song.album ?? '');
    _yearController = TextEditingController();
    _genreController = TextEditingController();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tagInfo = await TagEditorService().readTags(widget.song.data);
    if (tagInfo != null && mounted) {
      setState(() {
        if (tagInfo.title.isNotEmpty) _titleController.text = tagInfo.title;
        if (tagInfo.artist.isNotEmpty) _artistController.text = tagInfo.artist;
        if (tagInfo.album.isNotEmpty) _albumController.text = tagInfo.album;
        if (tagInfo.year.isNotEmpty) _yearController.text = tagInfo.year;
        if (tagInfo.genre.isNotEmpty) _genreController.text = tagInfo.genre;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _yearController.dispose();
    _genreController.dispose();
    super.dispose();
  }

  Future<void> _saveTags() async {
    setState(() => _isSaving = true);
    final success = await TagEditorService().writeTagsAndArtwork(
      filePath: widget.song.data,
      title: _titleController.text.trim(),
      artist: _artistController.text.trim(),
      album: _albumController.text.trim(),
      year: _yearController.text.trim(),
      genre: _genreController.text.trim(),
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        await PlaybackController.instance.refreshLibrary();
        if (!mounted) return;
        Navigator.pop(context, true);
        AppSnackBar.show('Audio tags updated successfully!', context: context);
      } else {
        AppSnackBar.show('Failed to update tags.', context: context);
      }
    }
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white38, width: 1),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF222222),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.edit_note_rounded, color: Colors.white),
          SizedBox(width: 8),
          Text('Edit Audio Tags', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField('Song Title', _titleController),
                  _buildTextField('Artist', _artistController),
                  _buildTextField('Album', _albumController),
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Year', _yearController)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTextField('Genre', _genreController)),
                    ],
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _isSaving ? null : _saveTags,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Text('Save Tags', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
