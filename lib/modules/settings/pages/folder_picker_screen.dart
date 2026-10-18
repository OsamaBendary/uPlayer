import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:u_player/core/services/access_to_files/access_service.dart';
import 'package:u_player/core/services/folder_filter/folder_filter_service.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';
import 'package:u_player/platform/linux/linux_paths.dart';
import 'package:u_player/platform/platform_env.dart';

class FolderPickerScreen extends StatefulWidget {
  const FolderPickerScreen({super.key});

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  final LocalAudioRepository _repository = LocalAudioRepository();
  final FolderFilterService _folderFilterService = FolderFilterService();

  bool _isLoading = true;
  List<String> _availableFolders = [];
  Set<String> _selected = {};
  String _searchQuery = '';

  /// Linux-only: the directories the scanner walks (vs. the sub-folder
  /// checkbox filter above).
  List<String> _scanRoots = [];
  String _defaultScanRootHint = '';
  bool _isPickingDirectory = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folders = await _repository.fetchAvailableFolders();
    final selected = await _folderFilterService.getSelectedFolders();
    final roots =
        isLinuxDesktop ? await _folderFilterService.getScanRoots() : <String>[];
    final defaultRoot = isLinuxDesktop && roots.isEmpty
        ? (await _repository.getScanRoots()).firstOrNull ?? LinuxPaths.homeDir
        : '';
    if (!mounted) return;
    setState(() {
      _availableFolders = folders;
      _selected = selected.toSet();
      _scanRoots = roots;
      _defaultScanRootHint = defaultRoot;
      _isLoading = false;
    });
  }

  /// Re-reads the folder lists (after a scan root change) and kicks off a
  /// library refresh so the new folders show up in the library immediately.
  Future<void> _reloadAfterRootChange() async {
    await _load();
    unawaited(PlaybackController.instance.refreshLibrary());
  }

  Future<void> _addScanRoot() async {
    if (_isPickingDirectory) return;
    setState(() => _isPickingDirectory = true);
    String? picked;
    try {
      picked = await getDirectoryPath(
        initialDirectory: _scanRoots.isNotEmpty ? _scanRoots.last : null,
        confirmButtonText: 'Scan this folder',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open folder dialog: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingDirectory = false);
    }
    if (picked == null || picked.isEmpty) return;
    await _folderFilterService.addScanRoot(picked);
    await _reloadAfterRootChange();
  }

  Future<void> _removeScanRoot(String path) async {
    await _folderFilterService.removeScanRoot(path);
    await _reloadAfterRootChange();
  }

  Future<void> _toggle(String folder) async {
    setState(() {
      if (_selected.contains(folder)) {
        _selected.remove(folder);
      } else {
        _selected.add(folder);
      }
    });
    await _folderFilterService.setSelectedFolders(_selected.toList());
  }

  Future<void> _selectAll() async {
    setState(() {
      _selected = _availableFolders.toSet();
    });
    await _folderFilterService.setSelectedFolders(_selected.toList());
  }

  Future<void> _clearAll() async {
    setState(() {
      _selected.clear();
    });
    await _folderFilterService.setSelectedFolders([]);
  }

  String _getShortLabel(String path) {
    final parts = path.split(RegExp(r'[/\\]')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return path;
    if (parts.length == 1) return parts.last;
    return '${parts[parts.length - 2]}/${parts.last}';
  }

  List<String> get _filteredAndSortedFolders {
    final filtered = _searchQuery.isEmpty
        ? List<String>.from(_availableFolders)
        : _availableFolders
            .where((f) => f.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    filtered.sort((a, b) =>
        _getShortLabel(a).toLowerCase().compareTo(_getShortLabel(b).toLowerCase()));
    return filtered;
  }

  /// Linux-only section: the directories scanned for music, editable with a
  /// native (GTK) folder dialog. The checkbox list underneath only filters
  /// sub-folders *inside* these roots.
  Widget _buildScanRootsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Music folders to scan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _isPickingDirectory ? null : _addScanRoot,
                icon: _isPickingDirectory
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.create_new_folder_rounded, size: 18),
                label: const Text('Add folder'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_scanRoots.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                _defaultScanRootHint.isEmpty
                    ? 'No folders picked yet.'
                    : 'No folders picked yet — scanning $_defaultScanRootHint by default.',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            )
          else
            for (final root in _scanRoots)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.only(left: 14, right: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.library_music_rounded,
                      color: Colors.amberAccent,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        root,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove folder',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white54,
                        size: 20,
                      ),
                      onPressed: () => _removeScanRoot(root),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 14),
          const Text(
            'Sub-folder filter',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredFolders = _filteredAndSortedFolders;

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const LabelChip('Choose Folders'),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        if (isLinuxDesktop) _buildScanRootsSection(),
                        if (_availableFolders.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 24,
                            ),
                            child: Text(
                              'No music folders found yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        else ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: TextField(
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Search sub-folders...',
                                hintStyle: const TextStyle(color: Colors.white54),
                                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.1),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val;
                                });
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _selected.isEmpty
                                        ? 'All music included (no filter)'
                                        : '${_selected.length} of ${_availableFolders.length} folder${_availableFolders.length == 1 ? '' : 's'} selected',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: _selectAll,
                                      child: const Text('Select All',
                                          style: TextStyle(color: Colors.white)),
                                    ),
                                    TextButton(
                                      onPressed: _clearAll,
                                      child: const Text('Clear',
                                          style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.only(
                                  left: 16, right: 16, bottom: 160),
                              itemCount: filteredFolders.length,
                              itemBuilder: (context, index) {
                                final folder = filteredFolders[index];
                                final isSelected = _selected.contains(folder);
                                final shortLabel = _getShortLabel(folder);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () => _toggle(folder),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 250),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.white
                                                  .withValues(alpha: 0.15)
                                              : Colors.black
                                                  .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color: isSelected
                                                ? Colors.white38
                                                : Colors.transparent,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isSelected
                                                  ? Icons.check_circle_rounded
                                                  : Icons.folder_rounded,
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.white38,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    shortLabel,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w500),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    folder,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 12),
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
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
        ),
      ),
    );
  }
}
