import 'package:flutter/material.dart';
import 'package:u_player/core/utils/app_snackbar.dart';
import 'package:u_player/core/services/discord/discord_config.dart';
import 'package:u_player/core/services/discord/discord_rich_presence_service.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/services/update/github_update_service.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';
import 'package:u_player/modules/settings/pages/customization_screen.dart';
import 'package:u_player/modules/settings/pages/download_folder_picker_screen.dart';
import 'package:u_player/modules/settings/pages/extension_management_screen.dart';
import 'package:u_player/modules/settings/pages/folder_picker_screen.dart';
import 'package:u_player/core/services/folder_filter/folder_filter_service.dart';
import 'package:u_player/platform/platform_env.dart';

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
        AppSnackBar.show('Play counts cleared', context: context);
      }
    }
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF222222),
        title: Text('About uPlayer', style: TextStyle(color: Colors.white)),
        content: Text('Version 2.0.0\nA beautiful music player for your local audio files.', style: TextStyle(color: Colors.white70)),
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

  Widget _buildSwitchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF5865F2),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientBackground(
      child: SafeArea(
        child: SingleChildScrollView(
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
                icon: Icons.extension_outlined,
                title: 'Extension Store & Providers',
                subtitle: 'Manage repositories & download providers',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExtensionManagementScreen()),
                  );
                },
              ),
              _buildSettingRow(
                icon: Icons.folder_special_outlined,
                title: 'Download Destination Folder',
                subtitle: 'Assign target folder for downloaded music',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DownloadFolderPickerScreen()),
                  );
                },
              ),
              _buildSettingRow(
                icon: Icons.folder_outlined,
                title: 'Choose Scanned Folders',
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
                icon: Icons.tune,
                title: 'Customization',
                subtitle: 'Song tap behavior & seek bar style',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CustomizationScreen()),
                  );
                },
              ),
              if (isLinuxDesktop && kDiscordApplicationId.isNotEmpty)
                ValueListenableBuilder<bool>(
                  valueListenable: DiscordRichPresenceService.instance.enabledNotifier,
                  builder: (context, discordEnabled, _) {
                    return _buildSwitchRow(
                      icon: Icons.forum_outlined,
                      title: 'Discord Rich Presence',
                      subtitle: discordEnabled
                          ? 'Show what you are listening to on Discord'
                          : 'Hidden from your Discord profile',
                      value: discordEnabled,
                      onChanged: (value) => DiscordRichPresenceService.instance.setEnabled(value),
                    );
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
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}
