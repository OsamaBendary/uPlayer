import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Pure-Dart FLAC metadata + cover art writer.
///
/// Reads an existing FLAC file, replaces/adds VORBIS_COMMENT and PICTURE
/// metadata blocks, and writes the result back.  Does NOT re-encode audio.
class FlacTagWriter {
  // ─── Public API ───────────────────────────────────────────────────────────

  /// Writes [tags] and optional [artworkBytes] into the FLAC file at
  /// [filePath].  Returns true on success.
  static Future<bool> writeTagsAndArtwork({
    required String filePath,
    required String title,
    required String artist,
    required String album,
    required String year,
    required String genre,
    required String trackNumber,
    Uint8List? artworkBytes,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[FlacTagWriter] File not found: $filePath');
        return false;
      }

      final bytes = await file.readAsBytes();
      final result = _rewriteFlac(
        bytes: bytes,
        title: title,
        artist: artist,
        album: album,
        year: year,
        genre: genre,
        trackNumber: trackNumber,
        artworkBytes: artworkBytes,
      );

      if (result == null) {
        debugPrint('[FlacTagWriter] Not a valid FLAC file or rewrite failed');
        return false;
      }

      await file.writeAsBytes(result, flush: true);
      debugPrint('[FlacTagWriter] Tags written to $filePath');
      return true;
    } catch (e) {
      debugPrint('[FlacTagWriter] Error: $e');
      return false;
    }
  }

  // ─── FLAC block parsing ──────────────────────────────────────────────────

  static const _flacMarker = [0x66, 0x4C, 0x61, 0x43]; // "fLaC"
  static const _blockTypeStreamInfo = 0;
  static const _blockTypeVorbisComment = 4;
  static const _blockTypePicture = 6;

  /// Rewrites FLAC bytes, replacing VORBIS_COMMENT and PICTURE blocks.
  static Uint8List? _rewriteFlac({
    required Uint8List bytes,
    required String title,
    required String artist,
    required String album,
    required String year,
    required String genre,
    required String trackNumber,
    Uint8List? artworkBytes,
  }) {
    // Validate fLaC marker
    if (bytes.length < 4) return null;
    for (int i = 0; i < 4; i++) {
      if (bytes[i] != _flacMarker[i]) return null;
    }

    // Parse existing metadata blocks, keeping everything except
    // VORBIS_COMMENT and PICTURE (we'll replace them)
    int pos = 4;
    bool isLast = false;
    Uint8List? streamInfoBlock;
    final List<Uint8List> keepBlocks = []; // other blocks to preserve

    while (!isLast && pos + 4 <= bytes.length) {
      final header = bytes[pos];
      isLast = (header & 0x80) != 0;
      final blockType = header & 0x7F;
      final blockLen =
          (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3];
      pos += 4;

      if (pos + blockLen > bytes.length) break;

      final blockData = bytes.sublist(pos, pos + blockLen);
      pos += blockLen;

      if (blockType == _blockTypeStreamInfo) {
        streamInfoBlock = blockData;
      } else if (blockType != _blockTypeVorbisComment &&
          blockType != _blockTypePicture) {
        // Preserve padding and other block types (SEEKTABLE, CUESHEET, etc.)
        keepBlocks.add(_encodeBlock(blockType, blockData, isLast: false));
      }
      // Skip old VORBIS_COMMENT and PICTURE blocks — we rebuild them below
    }

    if (streamInfoBlock == null) return null;

    // Build new VORBIS_COMMENT block
    final vcBlock = _buildVorbisCommentBlock(
      title: title,
      artist: artist,
      album: album,
      year: year,
      genre: genre,
      trackNumber: trackNumber,
    );

    // Build PICTURE block if artwork provided
    Uint8List? picBlock;
    if (artworkBytes != null && artworkBytes.isNotEmpty) {
      picBlock = _buildPictureBlock(artworkBytes);
    }

    // Assemble: fLaC + STREAMINFO + kept blocks + VORBIS_COMMENT + PICTURE
    // + audio stream
    final builder = BytesBuilder();
    builder.add(_flacMarker);
    builder.add(_encodeBlock(_blockTypeStreamInfo, streamInfoBlock,
        isLast: false));
    for (final b in keepBlocks) {
      builder.add(b);
    }

    final bool hasPicture = picBlock != null;
    // VORBIS_COMMENT is last only if no picture follows
    builder.add(_encodeBlock(
      _blockTypeVorbisComment,
      vcBlock,
      isLast: !hasPicture,
    ));
    if (picBlock != null) {
      builder.add(_encodeBlock(_blockTypePicture, picBlock, isLast: true));
    }

    // Audio frames start after the last metadata block
    builder.add(bytes.sublist(pos));

    return builder.toBytes();
  }

  // ─── Block builders ───────────────────────────────────────────────────────

  static Uint8List _encodeBlock(int type, Uint8List data,
      {required bool isLast}) {
    final header = BytesBuilder();
    final headerByte = (isLast ? 0x80 : 0x00) | (type & 0x7F);
    header.addByte(headerByte);
    final len = data.length;
    header.addByte((len >> 16) & 0xFF);
    header.addByte((len >> 8) & 0xFF);
    header.addByte(len & 0xFF);
    header.add(data);
    return header.toBytes();
  }

  /// Builds a VORBIS_COMMENT block (RFC 7845 / Ogg Vorbis comment spec).
  /// Format: little-endian uint32 vendor-len + vendor + uint32 count +
  ///         [uint32 comment-len + UTF-8 "KEY=value"]*
  static Uint8List _buildVorbisCommentBlock({
    required String title,
    required String artist,
    required String album,
    required String year,
    required String genre,
    required String trackNumber,
  }) {
    const vendor = 'uPlayer';
    final comments = <String>[];
    if (title.isNotEmpty) comments.add('TITLE=$title');
    if (artist.isNotEmpty) comments.add('ARTIST=$artist');
    if (album.isNotEmpty) comments.add('ALBUM=$album');
    if (year.isNotEmpty) comments.add('DATE=$year');
    if (genre.isNotEmpty) comments.add('GENRE=$genre');
    if (trackNumber.isNotEmpty) comments.add('TRACKNUMBER=$trackNumber');

    final bb = BytesBuilder();

    // Vendor string
    final vendorBytes = utf8.encode(vendor);
    _addLeUint32(bb, vendorBytes.length);
    bb.add(vendorBytes);

    // Comment count
    _addLeUint32(bb, comments.length);

    // Comments
    for (final c in comments) {
      final cb = utf8.encode(c);
      _addLeUint32(bb, cb.length);
      bb.add(cb);
    }

    return bb.toBytes();
  }

  /// Builds a PICTURE metadata block (FLAC spec, type 3 = Front Cover).
  /// Format: all big-endian uint32 fields.
  static Uint8List _buildPictureBlock(Uint8List imageBytes) {
    // Detect MIME type from magic bytes
    String mime = 'image/jpeg';
    if (imageBytes.length >= 8 &&
        imageBytes[0] == 0x89 &&
        imageBytes[1] == 0x50 &&
        imageBytes[2] == 0x4E &&
        imageBytes[3] == 0x47) {
      mime = 'image/png';
    }
    final mimeBytes = ascii.encode(mime);
    final descBytes = Uint8List(0); // empty description

    final bb = BytesBuilder();
    _addBEUint32(bb, 3); // picture type: front cover
    _addBEUint32(bb, mimeBytes.length);
    bb.add(mimeBytes);
    _addBEUint32(bb, descBytes.length);
    bb.add(descBytes);
    _addBEUint32(bb, 0); // width (0 = unknown)
    _addBEUint32(bb, 0); // height
    _addBEUint32(bb, 0); // color depth
    _addBEUint32(bb, 0); // indexed-color count
    _addBEUint32(bb, imageBytes.length);
    bb.add(imageBytes);
    return bb.toBytes();
  }

  // ─── Byte helpers ─────────────────────────────────────────────────────────

  static void _addLeUint32(BytesBuilder b, int value) {
    b.addByte(value & 0xFF);
    b.addByte((value >> 8) & 0xFF);
    b.addByte((value >> 16) & 0xFF);
    b.addByte((value >> 24) & 0xFF);
  }

  static void _addBEUint32(BytesBuilder b, int value) {
    b.addByte((value >> 24) & 0xFF);
    b.addByte((value >> 16) & 0xFF);
    b.addByte((value >> 8) & 0xFF);
    b.addByte(value & 0xFF);
  }
}
