import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_audio_tagger/flutter_audio_tagger.dart';
import 'package:on_audio_query/on_audio_query.dart';

class SmartArtworkWidget extends StatefulWidget {
  final SongModel song;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final BoxFit fit;

  const SmartArtworkWidget({
    super.key,
    required this.song,
    this.width = 56,
    this.height = 56,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.fit = BoxFit.cover,
  });

  @override
  State<SmartArtworkWidget> createState() => _SmartArtworkWidgetState();
}

class _SmartArtworkWidgetState extends State<SmartArtworkWidget> {
  late Future<Widget?> _artworkFuture;

  @override
  void initState() {
    super.initState();
    _artworkFuture = _loadArtworkWidget();
  }

  @override
  void didUpdateWidget(covariant SmartArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id || oldWidget.song.data != widget.song.data) {
      _artworkFuture = _loadArtworkWidget();
    }
  }

  Future<Widget?> _loadArtworkWidget() async {
    final songPath = widget.song.data;
    if (songPath.isNotEmpty) {
      try {
        // 1. Companion .jpg file saved next to audio file
        final dotIdx = songPath.lastIndexOf('.');
        if (dotIdx != -1) {
          final basePath = songPath.substring(0, dotIdx);
          final jpgFile = File('$basePath.jpg');
          final pngFile = File('$basePath.png');

          if (await jpgFile.exists()) {
            return Image.file(jpgFile, width: widget.width, height: widget.height, fit: widget.fit);
          }
          if (await pngFile.exists()) {
            return Image.file(pngFile, width: widget.width, height: widget.height, fit: widget.fit);
          }
        }

        // 2. Cover.jpg in parent folder
        final parentDir = File(songPath).parent;
        final coverJpg = File('${parentDir.path}/cover.jpg');
        if (await coverJpg.exists()) {
          return Image.file(coverJpg, width: widget.width, height: widget.height, fit: widget.fit);
        }

        // 3. Embedded ID3/FLAC tag artwork bytes
        final bytes = await FlutterAudioTagger().getArtWork(songPath);
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(bytes, width: widget.width, height: widget.height, fit: widget.fit);
        }
      } catch (e) {
        debugPrint('SmartArtworkWidget error: $e');
      }
    }
    return null;
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF1A1A1A),
      child: const Icon(Icons.music_note_rounded, color: Colors.white38),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: FutureBuilder<Widget?>(
          future: _artworkFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
              return snapshot.data!;
            }

            return QueryArtworkWidget(
              id: widget.song.id,
              type: ArtworkType.AUDIO,
              artworkWidth: widget.width,
              artworkHeight: widget.height,
              artworkFit: widget.fit,
              quality: 100,
              format: ArtworkFormat.JPEG,
              size: 500,
              nullArtworkWidget: _buildPlaceholder(),
            );
          },
        ),
      ),
    );
  }
}
