import 'package:flutter/material.dart';
import 'package:u_player/core/services/player/artwork_style_preference.dart';
import 'package:u_player/core/services/player/seekbar_preference.dart';
import 'package:u_player/core/services/player/tap_preference.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

class CustomizationScreen extends StatelessWidget {
  const CustomizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 24, bottom: 24),
                  child: LabelChip(
                    'Customization',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: songTapOpensPlayer,
                  builder: (context, opensPlayer, _) {
                    return _buildSection(
                      title: 'Song tap behavior',
                      subtitle: 'What happens when you tap a song',
                      child: SwitchListTile(
                        value: opensPlayer,
                        onChanged: (value) => setSongTapOpensPlayer(value),
                        activeThumbColor: Colors.white,
                        activeTrackColor: const Color(0xFF3D5AFE),
                        title: const Text(
                          'Open player screen on tap',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          opensPlayer
                              ? 'Tapping a song plays it and opens the full player.'
                              : 'Tapping a song plays it in the mini player; tap the mini player to open the full player.',
                          style: const TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildSection(
                  title: 'Seek bar style',
                  subtitle: 'Shown on the player screen',
                  child: Column(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: useWaveformSeekbar,
                        builder: (context, isWaveform, _) {
                          return Column(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.linear_scale_rounded, color: Colors.white70),
                                title: const Text('Normal seek bar', style: TextStyle(color: Colors.white)),
                                trailing: !isWaveform ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                                onTap: () => setUseWaveformSeekbar(false),
                              ),
                              ListTile(
                                leading: const Icon(Icons.show_chart_rounded, color: Colors.white70),
                                title: const Text('Waveform seek bar', style: TextStyle(color: Colors.white)),
                                trailing: isWaveform ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                                onTap: () => setUseWaveformSeekbar(true),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  title: 'Artwork style',
                  subtitle: 'Shown on the player screen',
                  child: Column(
                    children: [
                      ValueListenableBuilder<PlayerArtworkStyle>(
                        valueListenable: playerArtworkStyle,
                        builder: (context, style, _) {
                          return Column(
                            children: [
                              for (final option in PlayerArtworkStyle.values)
                                ListTile(
                                  leading: Icon(
                                    _iconFor(option),
                                    color: Colors.white70,
                                  ),
                                  title: Text(
                                    option.label,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  trailing: style == option
                                      ? const Icon(Icons.check_rounded, color: Colors.white)
                                      : null,
                                  onTap: () => setPlayerArtworkStyle(option),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(PlayerArtworkStyle style) {
    switch (style) {
      case PlayerArtworkStyle.normal:
        return Icons.image_rounded;
      case PlayerArtworkStyle.pictureDisc:
        return Icons.album_rounded;
      case PlayerArtworkStyle.silver:
        return Icons.circle_rounded;
      case PlayerArtworkStyle.jewelCase:
        return Icons.album_outlined;
      case PlayerArtworkStyle.minimal:
        return Icons.brightness_2_rounded;
    }
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
