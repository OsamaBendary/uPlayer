import 'dart:io';
import 'package:flutter/material.dart';
import 'package:u_player/core/services/download/download_service.dart';
import 'package:u_player/core/utils/app_snackbar.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

class DownloadFolderPickerScreen extends StatefulWidget {
  const DownloadFolderPickerScreen({super.key});

  @override
  State<DownloadFolderPickerScreen> createState() => _DownloadFolderPickerScreenState();
}

class _DownloadFolderPickerScreenState extends State<DownloadFolderPickerScreen> {
  late TextEditingController _pathController;
  String _currentPath = '';

  final List<String> _quickPresets = const [
    '/storage/emulated/0/Music/uPlayer',
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Download',
  ];

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController();
    _loadCurrentPath();
  }

  Future<void> _loadCurrentPath() async {
    final path = await DownloadService().getDownloadDirectoryPath();
    if (mounted) {
      setState(() {
        _currentPath = path;
        _pathController.text = path;
      });
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _savePath(String newPath) async {
    // Public storage paths need "All files access" on Android 10+ — request it
    // before attempting to create/use the folder.
    if (newPath.startsWith('/storage/emulated/0/')) {
      final granted = await DownloadService.ensureAllFilesAccess();
      if (!granted) {
        if (!mounted) return;
        AppSnackBar.show(
          'All files access is required for the public Music folder. '
          'Enable it in Settings → Apps → uPlayer.',
          context: context,
        );
        return;
      }
    }
    final targetDir = Directory(newPath);
    if (!await targetDir.exists()) {
      try {
        await targetDir.create(recursive: true);
      } catch (e) {
        if (!mounted) return;
        AppSnackBar.show('Could not create directory: $e', context: context);
        return;
      }
    }

    await DownloadService().setDownloadDirectoryPath(newPath);
    await _loadCurrentPath();
    if (mounted) {
      AppSnackBar.show('Download folder updated!', context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const LabelChip('Download Destination Folder'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Download Location',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_special_rounded, color: Colors.amberAccent, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _currentPath,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Custom Directory Path',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pathController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '/storage/emulated/0/Music/uPlayer',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _savePath(_pathController.text.trim()),
                      child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),

                const SizedBox(height: 28),
                const Text(
                  'Quick Presets',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                for (final preset in _quickPresets)
                  GestureDetector(
                    onTap: () {
                      _pathController.text = preset;
                      _savePath(preset);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _currentPath == preset ? Colors.amberAccent.withValues(alpha: 0.5) : Colors.white10,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            color: _currentPath == preset ? Colors.amberAccent : Colors.white70,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              preset,
                              style: TextStyle(
                                color: _currentPath == preset ? Colors.amberAccent : Colors.white,
                                fontSize: 13,
                                fontWeight: _currentPath == preset ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (_currentPath == preset)
                            const Icon(Icons.check_circle_rounded, color: Colors.amberAccent, size: 20),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
