import 'package:flutter/material.dart';
import 'package:u_player/core/services/access_to_files/access_service.dart';
import 'package:u_player/core/services/folder_filter/folder_filter_service.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folders = await _repository.fetchAvailableFolders();
    final selected = await _folderFilterService.getSelectedFolders();
    if (!mounted) return;
    setState(() {
      _availableFolders = folders;
      _selected = selected.toSet();
      _isLoading = false;
    });
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
              : _availableFolders.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'No music folders found on this device yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: TextField(
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Search folders...',
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
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 160),
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
                                      duration: const Duration(milliseconds: 250),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white.withValues(alpha: 0.15)
                                            : Colors.black.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(14),
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
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  shortLabel,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w500),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  folder,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
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
                    ),
        ),
      ),
    );
  }
}
