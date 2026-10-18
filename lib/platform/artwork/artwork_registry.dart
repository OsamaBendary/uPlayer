import 'dart:io';
import 'dart:typed_data';

/// Maps song IDs to artwork on platforms without MediaStore (Linux desktop).
///
/// On Android, `on_audio_query` answers artwork queries straight from the
/// system media database. On Linux there is no such database: the Go library
/// scan extracts each file's embedded cover into a cache directory and
/// returns that path with every scanned track. This registry keeps the
/// `songId -> cached cover / audio path` mapping so widgets and services that
/// only carry the integer ID (QueryArtworkWidget, DynamicGradientBackground,
/// the notification-art cache) can still resolve the right image.
///
/// When the scan found no embedded cover, a sidecar image next to the audio
/// file (`cover.jpg`, `folder.png`, `"Artist - Title".jpg`, ...) is used as a
/// fallback — the same convention the download pipeline uses.
class ArtworkRegistry {
  ArtworkRegistry._internal();

  static final ArtworkRegistry instance = ArtworkRegistry._internal();

  final Map<int, String> _coverPathBySongId = {};
  final Map<int, String> _audioPathBySongId = {};

  /// audio path -> resolved sidecar image path, or '' when none exists.
  final Map<String, String> _sidecarCache = {};

  /// Candidate file names checked next to an audio file, in priority order.
  static const List<String> _sidecarNames = [
    'cover.jpg',
    'cover.jpeg',
    'cover.png',
    'folder.jpg',
    'folder.jpeg',
    'folder.png',
    'front.jpg',
    'front.png',
    'album.jpg',
    'albumart.jpg',
    'albumart.png',
    'artwork.jpg',
    'artwork.png',
    'thumb.jpg',
  ];

  /// Registers a scanned song. [coverPath] is the embedded-cover cache file
  /// returned by the Go scan (may be empty).
  void registerSong({
    required int id,
    required String audioPath,
    String? coverPath,
  }) {
    _audioPathBySongId[id] = audioPath;
    if (coverPath != null && coverPath.isNotEmpty) {
      _coverPathBySongId[id] = coverPath;
    }
  }

  /// Drops everything (called before a fresh library load).
  void clearLibrary() {
    _coverPathBySongId.clear();
    _audioPathBySongId.clear();
    _sidecarCache.clear();
  }

  String? coverPathForSong(int id) => _coverPathBySongId[id];

  String? audioPathForSong(int id) => _audioPathBySongId[id];

  /// Resolves an image file for [id]: embedded cover first (if the cached
  /// file still exists), sidecar images in the song's folder second.
  File? artworkFileForSong(int id) {
    final cover = _coverPathBySongId[id];
    if (cover != null && cover.isNotEmpty) {
      final f = File(cover);
      if (f.existsSync()) return f;
    }
    final audio = _audioPathBySongId[id];
    if (audio == null || audio.isEmpty) return null;
    return artworkFileForAudioPath(audio);
  }

  /// Sidecar image lookup for a known audio file path.
  File? artworkFileForAudioPath(String audioPath) {
    final dir = File(audioPath).parent.path;
    final nameNoExt = _basenameNoExt(audioPath);

    // Same-basename sibling image first ("Artist - Title.jpg" next to the
    // audio file), then the classic folder cover names.
    final candidates = <String>[
      '$dir/$nameNoExt.jpg',
      '$dir/$nameNoExt.jpeg',
      '$dir/$nameNoExt.png',
      for (final n in _sidecarNames) '$dir/$n',
    ];

    for (final path in candidates) {
      final cached = _sidecarCache[path];
      if (cached != null) {
        if (cached.isNotEmpty) return File(cached);
        continue;
      }
      final f = File(path);
      if (f.existsSync()) {
        _sidecarCache[path] = path;
        return f;
      }
      _sidecarCache[path] = '';
    }
    return null;
  }

  /// Raw artwork bytes for [id], or null when no image is available.
  Future<Uint8List?> readArtworkBytes(int id) async {
    final file = artworkFileForSong(id);
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  static String _basenameNoExt(String path) {
    var base = path;
    final slash = base.lastIndexOf(Platform.pathSeparator);
    if (slash >= 0) base = base.substring(slash + 1);
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    return base;
  }
}
