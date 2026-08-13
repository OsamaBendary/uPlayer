import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:u_player/core/services/extension/extension_service.dart';
import 'package:u_player/core/utils/app_snackbar.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

class ExtensionManagementScreen extends StatefulWidget {
  const ExtensionManagementScreen({super.key});

  @override
  State<ExtensionManagementScreen> createState() => _ExtensionManagementScreenState();
}

class _ExtensionManagementScreenState extends State<ExtensionManagementScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await ExtensionService().init();
    await ExtensionService().refreshStore();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  static const String _officialRepoUrl =
      'https://github.com/spotiflacapp/SpotiFLAC-Extension';

  Future<void> _openOfficialRepo() async {
    final launched = await launchUrl(
      Uri.parse(_officialRepoUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      AppSnackBar.show('Could not open the repository.', context: context);
    }
  }

  Future<void> _addRepoUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isLoading = true);
    await ExtensionService().addRepoUrl(url);
    _urlController.clear();

    if (mounted) {
      setState(() => _isLoading = false);
      AppSnackBar.show('Extension repository added & synced!', context: context);
    }
  }

  void _showAddRepoDialog() {
    if (_urlController.text.isEmpty && ExtensionService().repoUrls.isEmpty) {
      // Seed the official SpotiFLaC extension registry so the store works
      // out of the box (Tidal/Qobuz/... providers).
      _urlController.text = kOfficialExtensionRepo;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Extension Repo URL', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _urlController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'https://raw.githubusercontent.com/.../registry.json',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.3),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _addRepoUrl();
            },
            child: const Text('Add & Sync', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final installed = ExtensionService().installedExtensions;
    final available = ExtensionService().availableRepoExtensions;
    final repoUrls = ExtensionService().repoUrls;

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
          title: const LabelChip('Extension Store & Providers'),
          actions: [
            IconButton(
              icon: const Icon(Icons.link_rounded, color: Colors.white),
              tooltip: 'Official Extension Repo',
              onPressed: _openOfficialRepo,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              tooltip: 'Sync Repositories',
              onPressed: _loadData,
            ),
            IconButton(
              icon: const Icon(Icons.add_link_rounded, color: Colors.white),
              tooltip: 'Add Extension Repo',
              onPressed: _showAddRepoDialog,
            ),
          ],
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Active Installed Providers
                      const Text(
                        'Installed Extensions & Download Providers',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Toggle installed providers on or off to enable search and FLAC downloads.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 14),

                      if (installed.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.extension_off_rounded, color: Colors.white38, size: 36),
                              SizedBox(height: 10),
                              Text(
                                'No Extensions Installed Yet',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Browse available extensions below or add a repository URL.',
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: installed.length,
                          itemBuilder: (context, index) {
                            final ext = installed[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.extension_rounded, color: Colors.white70, size: 26),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ext.name,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        Text(
                                          'v${ext.version} • ${ext.type}',
                                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: ext.isEnabled,
                                    activeColor: Colors.white,
                                    onChanged: (val) async {
                                      await ExtensionService().toggleExtension(ext.id, val);
                                      setState(() {});
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                                    onPressed: () async {
                                      final err = await ExtensionService().deleteExtension(ext.id);
                                      setState(() {});
                                      AppSnackBar.show(
                                        err == null
                                            ? 'Deleted ${ext.name}'
                                            : 'Delete failed: $err',
                                        context: context,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                      const SizedBox(height: 28),

                      // Store / Available Extensions from Repos
                      Row(
                        children: [
                          const Text(
                            'Extension Store',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          if (available.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${available.length} Available',
                                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Extensions discovered from your added repository URLs.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 14),

                      if (available.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 20),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Tap the link icon at top right to add a repository URL.',
                                  style: TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: _showAddRepoDialog,
                                child: const Text('Add Repo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: available.length,
                          itemBuilder: (context, index) {
                            final ext = available[index];
                            final isInstalled = installed.any((i) => i.id == ext.id);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.cloud_download_rounded, color: Colors.white, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ext.name,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        Text(
                                          'v${ext.version} • ${ext.type}',
                                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        ),
                                        if (ext.hasDownloadProvider)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: ExtensionService.requiresLogin(ext.id)
                                                    ? Colors.orange.withValues(alpha: 0.15)
                                                    : Colors.greenAccent.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: ExtensionService.requiresLogin(ext.id)
                                                      ? Colors.orange.withValues(alpha: 0.4)
                                                      : Colors.greenAccent.withValues(alpha: 0.3),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                ExtensionService.requiresLogin(ext.id)
                                                    ? 'Login/verify needed once'
                                                    : 'No login needed',
                                                style: TextStyle(
                                                  color: ExtensionService.requiresLogin(ext.id)
                                                      ? Colors.orangeAccent
                                                      : Colors.greenAccent,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (ext.description.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            ext.description,
                                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isInstalled ? Colors.white12 : Colors.white,
                                      foregroundColor: isInstalled ? Colors.white54 : Colors.black,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: isInstalled
                                        ? null
                                        : () async {
                                            final err = await ExtensionService().installExtension(ext);
                                            await ExtensionService().refreshStore();
                                            if (!mounted) return;
                                            setState(() {});
                                            AppSnackBar.show(
                                              err == null
                                                  ? 'Installed ${ext.name}!'
                                                  : 'Failed: $err',
                                              context: context,
                                            );
                                          },
                                    child: Text(
                                      isInstalled ? 'Installed' : 'Install',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                      const SizedBox(height: 28),

                      // Configured Repositories List
                      const Text(
                        'Added Repository URLs',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),

                      for (final repo in repoUrls)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.link_rounded, color: Colors.white54, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  repo,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                                onPressed: () async {
                                  await ExtensionService().removeRepoUrl(repo);
                                  setState(() {});
                                },
                              ),
                            ],
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
