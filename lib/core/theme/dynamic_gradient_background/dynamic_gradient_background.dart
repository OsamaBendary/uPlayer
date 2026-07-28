import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:palette_generator_master/palette_generator_master.dart';
import 'package:animate_gradient/animate_gradient.dart';


class DynamicGradientBackground extends StatefulWidget {
  final int songId;
  final Widget child;

  const DynamicGradientBackground({
    super.key,
    required this.songId,
    required this.child,
  });

  @override
  State<DynamicGradientBackground> createState() => _DynamicGradientBackgroundState();
}

class _DynamicGradientBackgroundState extends State<DynamicGradientBackground> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  List<Color> _gradientColors = [
    const Color(0xFF1E1E2C),
    const Color(0xFF0D0D0D),
  ];

  @override
  void initState() {
    super.initState();
    _extractColors(widget.songId);
  }

  @override
  void didUpdateWidget(covariant DynamicGradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _extractColors(widget.songId);
    }
  }

  Future<void> _extractColors(int songId) async {
    try {
      final Uint8List? bytes = await _audioQuery.queryArtwork(
        songId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 300,
      );

      if (bytes != null && bytes.isNotEmpty) {
        final imageProvider = MemoryImage(bytes);

        final PaletteGeneratorMaster palette = await PaletteGeneratorMaster.fromImageProvider(
          imageProvider,
          maximumColorCount: 16,
        );

        final Color primaryColor = palette.darkMutedColor?.color ??
            palette.darkVibrantColor?.color ??
            palette.dominantColor?.color ??
            const Color(0xFF1E1E2C);

        final Color secondaryColor = palette.dominantColor?.color != primaryColor
            ? (palette.dominantColor?.color ?? const Color(0xFF0D0D0D))
            : const Color(0xFF0D0D0D);

        if (mounted) {
          setState(() {
            _gradientColors = [
              primaryColor.withValues(alpha: 0.8),
              secondaryColor.withValues(alpha: 0.2),
              const Color(0xFF0D0D0D),
            ];
          });
        }
      } else {
        _resetToDefault();
      }
    } catch (_) {
      _resetToDefault();
    }
  }

  void _resetToDefault() {
    if (mounted) {
      setState(() {
        _gradientColors = [
          const Color(0xFF1E1E2C),
          const Color(0xFF0D0D0D),
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimateGradient(
      animateAlignments: true,
      primaryBegin: Alignment.topCenter,
      secondaryEnd: Alignment.bottomCenter,
      repeat: true,
      primaryColors: _gradientColors,
      secondaryColors: _gradientColors,
     // child: AnimatedContainer(
        //duration: const Duration(milliseconds: 600),
        //curve: Curves.easeOut,
        //decoration: BoxDecoration(
          //gradient: LinearGradient(
          //  begin: Alignment.topCenter,
          //  end: Alignment.bottomCenter,
          //  colors: _gradientColors,
           // stops: const [0.0, 0.65, 1.0],
        //  ),
       // ),
        child: widget.child,
    );
  }
}