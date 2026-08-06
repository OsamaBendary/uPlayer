import 'package:flutter/material.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/services/update/github_update_service.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';
import 'package:u_player/modules/settings/pages/folder_picker_screen.dart';
import 'package:u_player/core/services/folder_filter/folder_filter_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _folderCount = 0;

  @override
  void initState() {
    super.initState();
    _loadFolderCount();
  }

  Future<void> _loadFolderCount() async {
    final folders = await FolderFilterService().getSelectedFolders();
    setState(() {
      _folderCount = folders.length;
    });
  }

  Future<void> _clearPlayCounts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Clear Play Counts', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to clear all play statistics?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await PlaybackController.instance.clearPlayCounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Play counts cleared')),
        );
      }
    }
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF222222),
        title: Text('About uPlayer', style: TextStyle(color: Colors.white)),
        content: Text('Version 1.0.0\nA beautiful music player for your local audio files.', style: TextStyle(color: Colors.white70)),
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 24, bottom: 24),
              child: LabelChip(
                'Settings',
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
              ),
            ),
            _buildSettingRow(
              icon: Icons.folder_outlined,
              title: 'Choose Folders',
              subtitle: _folderCount > 0 ? '$_folderCount selected' : 'All folders',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
                );
                _loadFolderCount();
                PlaybackController.instance.refreshLibrary();
              },
            ),
            _buildSettingRow(
              icon: Icons.system_update_outlined,
              title: 'Check for Updates',
              subtitle: 'Check GitHub for latest release',
              onTap: () => GitHubUpdateService.checkForUpdates(context, silentIfLatest: false),
            ),
            _buildSettingRow(
              icon: Icons.delete_outline,
              title: 'Clear Play Counts',
              subtitle: 'Reset all stats to zero',
              onTap: _clearPlayCounts,
            ),
            _buildSettingRow(
              icon: Icons.info_outline,
              title: 'About',
              onTap: _showAbout,
            ),
          ],
        ),
      ),
    );
  }
}
