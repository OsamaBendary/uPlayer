import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_audio_tagger/flutter_audio_tagger.dart';
import 'package:flutter_audio_tagger/tag.dart';

class TagInfo {
  final String title;
  final String artist;
  final String album;
  final String year;
  final String genre;
  final Uint8List? artwork;

  TagInfo({
    required this.title,
    required this.artist,
    required this.album,
    required this.year,
    required this.genre,
    this.artwork,
  });
}

class TagEditorService {
  final FlutterAudioTagger _tagger = FlutterAudioTagger();

  Future<TagInfo?> readTags(String filePath) async {
    try {
      final tag = await _tagger.getAllTags(filePath);
      if (tag == null) return null;
      return TagInfo(
        title: tag.title ?? '',
        artist: tag.artist ?? '',
        album: tag.album ?? '',
        year: tag.year ?? '',
        genre: tag.genre ?? '',
        artwork: tag.artwork,
      );
    } catch (e) {
      debugPrint('TagEditorService readTags error: $e');
      return null;
    }
  }

  Future<bool> writeTagsAndArtwork({
    required String filePath,
    required String title,
    required String artist,
    required String album,
    required String year,
    required String genre,
    String trackNumber = '',
    Uint8List? artworkBytes,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('TagEditorService error: File does not exist at $filePath');
      return false;
    }

    await Future.delayed(const Duration(milliseconds: 100));

    // 1. Try native FlutterAudioTagger plugin write
    try {
      if (artworkBytes != null && artworkBytes.isNotEmpty) {
        try {
          final tag = Tag(
            title: title,
            artist: artist,
            album: album,
            year: year,
            genre: genre,
            artwork: artworkBytes,
          );
          final audioData = await _tagger.editTagsAndArtwork(tag, filePath);
          if (audioData.musicData.isNotEmpty) {
            await file.writeAsBytes(audioData.musicData, flush: true);
            return true;
          }
        } catch (artworkErr) {
          debugPrint(
              'TagEditorService editTagsAndArtwork plugin fallback: $artworkErr');
        }
      }

      final fallbackTag = Tag(
        title: title,
        artist: artist,
        album: album,
        year: year,
        genre: genre,
      );
      final audioData = await _tagger.editTags(fallbackTag, filePath);
      if (audioData.musicData.isNotEmpty) {
        await file.writeAsBytes(audioData.musicData, flush: true);
        return true;
      }
    } catch (e) {
      debugPrint('TagEditorService plugin write error: $e');
    }

    // 2. Pure Dart ID3v2.3 fallback (MP3 only)
    try {
      final rawAudioBytes = await file.readAsBytes();
      final taggedBytes = embedID3v23(
        audioBytes: rawAudioBytes,
        title: title,
        artist: artist,
        album: album,
        year: year,
        genre: genre,
        trackNumber: trackNumber,
        artworkBytes: artworkBytes,
      );
      await file.writeAsBytes(taggedBytes, flush: true);
      return true;
    } catch (dartErr) {
      debugPrint('TagEditorService pure Dart encoder error: $dartErr');
      return false;
    }
  }

  /// Embeds ID3v2.3 tags into raw MP3 bytes.
  ///
  /// Frame layout (ID3v2.3 spec §3.3):
  ///   [4 bytes] Frame ID (ASCII)
  ///   [4 bytes] Frame size (big-endian, NOT synchsafe in v2.3)
  ///   [2 bytes] Frame flags
  ///   [n bytes] Frame content
  ///
  /// Text frames prepend a 1-byte encoding indicator before the text.
  /// APIC frame:  encoding(1) + mime + 0x00 + pic_type(1) + description + 0x00 + imageData
  static Uint8List embedID3v23({
    required Uint8List audioBytes,
    required String title,
    required String artist,
    required String album,
    required String year,
    required String genre,
    String trackNumber = '',
    Uint8List? artworkBytes,
  }) {
    // ── Frame builders ──────────────────────────────────────────────────────

    /// Builds a text frame.  Content = 0x03 (UTF-8 encoding byte) + UTF-8 text.
    Uint8List makeTextFrame(String frameId, String value) {
      if (value.isEmpty) return Uint8List(0);
      final valueBytes = utf8.encode(value);
      // Content: encoding byte + text
      final contentSize = 1 + valueBytes.length;
      final fb = BytesBuilder();
      fb.add(ascii.encode(frameId));          // 4-byte frame ID
      // Frame size: big-endian uint32 (ID3v2.3 uses plain int, NOT synchsafe)
      fb.addByte((contentSize >> 24) & 0xFF);
      fb.addByte((contentSize >> 16) & 0xFF);
      fb.addByte((contentSize >> 8) & 0xFF);
      fb.addByte(contentSize & 0xFF);
      fb.addByte(0x00); // flags byte 1
      fb.addByte(0x00); // flags byte 2
      fb.addByte(0x03); // encoding: UTF-8
      fb.add(valueBytes);
      return fb.toBytes();
    }

    /// Builds an APIC (Attached Picture) frame.
    ///
    /// Content layout:
    ///   encoding(1) | mime | 0x00 | picture_type(1) | description | 0x00 | imageData
    Uint8List? makeApicFrame(Uint8List imgBytes) {
      if (imgBytes.isEmpty) return null;

      // Detect image format
      bool isPng = imgBytes.length >= 4 &&
          imgBytes[0] == 0x89 &&
          imgBytes[1] == 0x50 &&
          imgBytes[2] == 0x4E &&
          imgBytes[3] == 0x47;
      final mimeStr = isPng ? 'image/png' : 'image/jpeg';
      final mimeBytes = ascii.encode(mimeStr);

      // Build content:
      // 1 (encoding) + mimeLen + 1 (null) + 1 (pic type) + 1 (empty desc null) + imageLen
      final contentSize =
          1 + mimeBytes.length + 1 + 1 + 1 + imgBytes.length;

      final fb = BytesBuilder();
      fb.add(ascii.encode('APIC'));            // frame ID
      fb.addByte((contentSize >> 24) & 0xFF);  // frame size (big-endian)
      fb.addByte((contentSize >> 16) & 0xFF);
      fb.addByte((contentSize >> 8) & 0xFF);
      fb.addByte(contentSize & 0xFF);
      fb.addByte(0x00); // flag byte 1
      fb.addByte(0x00); // flag byte 2
      // Content:
      fb.addByte(0x00); // encoding: ISO-8859-1 (safest for APIC mime/desc)
      fb.add(mimeBytes);
      fb.addByte(0x00); // null terminator after MIME
      fb.addByte(0x03); // picture type: Front Cover
      fb.addByte(0x00); // empty description (null-terminated)
      fb.add(imgBytes);
      return fb.toBytes();
    }

    // ── Build all frames ─────────────────────────────────────────────────────
    final framesBuilder = BytesBuilder();
    framesBuilder.add(makeTextFrame('TIT2', title));
    framesBuilder.add(makeTextFrame('TPE1', artist));
    framesBuilder.add(makeTextFrame('TALB', album));
    framesBuilder.add(makeTextFrame('TYER', year));
    framesBuilder.add(makeTextFrame('TCON', genre));
    if (trackNumber.isNotEmpty) {
      framesBuilder.add(makeTextFrame('TRCK', trackNumber));
    }
    if (artworkBytes != null && artworkBytes.isNotEmpty) {
      final apic = makeApicFrame(artworkBytes);
      if (apic != null) framesBuilder.add(apic);
    }

    final allFrames = framesBuilder.toBytes();
    final tagSize = allFrames.length;

    // ── Build ID3v2.3 header ─────────────────────────────────────────────────
    // Tag size field uses synchsafe integers (each byte's MSB is 0).
    final builder = BytesBuilder();
    builder.add(ascii.encode('ID3'));
    builder.addByte(0x03); // version 2.3
    builder.addByte(0x00); // revision 0
    builder.addByte(0x00); // flags

    // Synchsafe integer encoding for tag size
    builder.addByte((tagSize >> 21) & 0x7F);
    builder.addByte((tagSize >> 14) & 0x7F);
    builder.addByte((tagSize >> 7) & 0x7F);
    builder.addByte(tagSize & 0x7F);

    builder.add(allFrames);

    // ── Strip any existing ID3 header from audioBytes ────────────────────────
    int audioStartOffset = 0;
    if (audioBytes.length >= 10 &&
        audioBytes[0] == 0x49 && // 'I'
        audioBytes[1] == 0x44 && // 'D'
        audioBytes[2] == 0x33)   // '3'
    {
      final existingSize = ((audioBytes[6] & 0x7F) << 21) |
          ((audioBytes[7] & 0x7F) << 14) |
          ((audioBytes[8] & 0x7F) << 7) |
          (audioBytes[9] & 0x7F);
      audioStartOffset = 10 + existingSize;
    }

    if (audioStartOffset < audioBytes.length) {
      builder.add(audioBytes.sublist(audioStartOffset));
    } else {
      builder.add(audioBytes);
    }

    return builder.toBytes();
  }
}
