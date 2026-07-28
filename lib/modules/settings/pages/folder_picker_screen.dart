import 'package:flutter/material.dart';
import 'package:u_player/core/services/access_to_files/access_service.dart';
import 'package:u_player/core/services/folder_filter/folder_filter_service.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Choose Folders', style: TextStyle(color: Colors.white)),
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
              padding: const EdgeInsets.all(16),
              child: Text(
                _selected.isEmpty
                    ? 'No folders selected — all music on the device is included.'
                    : '${_selected.length} folder${_selected.length == 1 ? '' : 's'} selected',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _availableFolders.length,
                itemBuilder: (context, index) {
                  final folder = _availableFolders[index];
                  final isSelected = _selected.contains(folder);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _toggle(folder),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.15)
                                : Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.folder_rounded,
                                color: isSelected ? Colors.white : Colors.white38,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  folder,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
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
    );
  }
}
