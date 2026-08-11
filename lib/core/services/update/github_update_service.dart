import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:u_player/core/utils/app_snackbar.dart';

class GitHubUpdateService {
  static const String repoOwner = "OsamaBendary";
  static const String repoName = "uPlayer";

  /// Checks GitHub Releases API for new updates.
  /// If [silentIfLatest] is true, no dialog is shown if the user is already on the latest version.
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool silentIfLatest = true,
  }) async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      final url = Uri.parse(
        "https://api.github.com/repos/$repoOwner/$repoName/releases/latest",
      );

      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
      });

      if (response.statusCode != 200) {
        if (!silentIfLatest && context.mounted) {
          _showSnackBar(context, 'Unable to check for updates right now.');
        }
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final String tagName = (data['tag_name'] as String? ?? '').replaceAll('v', '');
      final String releaseUrl = data['html_url'] as String? ?? "https://github.com/$repoOwner/$repoName/releases";
      final String releaseNotes = data['body'] as String? ?? "A new version of uPlayer is available!";

      if (_isVersionNewer(currentVersion, tagName)) {
        if (!context.mounted) return;
        _showUpdateDialog(context, tagName, releaseNotes, releaseUrl);
      } else if (!silentIfLatest) {
        if (!context.mounted) return;
        _showSnackBar(context, 'You are using the latest version (v$currentVersion).');
      }
    } catch (e) {
      if (!silentIfLatest && context.mounted) {
        _showSnackBar(context, 'Failed to check for updates.');
      }
    }
  }

  static bool _isVersionNewer(String current, String latest) {
    if (latest.isEmpty) return false;
    List<int> currParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < latestParts.length; i++) {
      int curr = i < currParts.length ? currParts[i] : 0;
      if (latestParts[i] > curr) return true;
      if (latestParts[i] < curr) return false;
    }
    return false;
  }

  static void _showUpdateDialog(
    BuildContext context,
    String newVersion,
    String releaseNotes,
    String releaseUrl,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'New Version Available (v$newVersion)',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A new release of uPlayer is available on GitHub!',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            if (releaseNotes.isNotEmpty) ...[
              const Text(
                'Release Notes:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(
                    releaseNotes,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final Uri uri = Uri.parse(releaseUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Update Now', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static void _showSnackBar(BuildContext context, String message) {
    AppSnackBar.show(message, context: context);
  }
}
