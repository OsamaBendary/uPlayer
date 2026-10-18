import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:u_player/core/navigation/app_keys.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/platform/audio_query_compat.dart';
import 'package:u_player/modules/library/pages/library_nav_screen.dart';
import 'package:u_player/modules/library/widgets/smart_artwork_widget.dart';
import 'package:u_player/modules/player/pages/lyrics_screen.dart';
import 'package:u_player/modules/player/pages/player_screen.dart';
import 'package:u_player/modules/player/widgets/desktop_controls.dart';

/// The Linux desktop shell's bottom bar: tab navigation on the left, the
/// current song in the middle, and playback controls (transport, seek,
/// lyrics, volume) on the right.
///
/// It replaces the phone's floating nav pill + mini player bar, which are
/// sized for a thumb and look out of place in a wide window.
class DesktopShellBar extends StatelessWidget {
  const DesktopShellBar({super.key});

  static const double height = 76;

  static const _navIcons = [
    Icons.library_music_rounded,
    Icons.queue_music_rounded,
    Icons.bar_chart_rounded,
    Icons.file_download_rounded,
    Icons.settings_rounded,
  ];

  static const _navLabels = [
    'Library',
    'Playlists',
    'Stats',
    'Downloads',
    'Settings',
  ];

  void _openPlayerScreen() {
    if (PlaybackController.instance.isPlayerScreenVisible.value) return;
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: PlayerScreen.routeName),
        builder: (_) => const PlayerScreen(),
      ),
    );
  }

  void _openLyrics(BuildContext context) {
    final song = PlaybackController.instance.currentSong;
    if (song == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LyricsScreen(
          song: song,
          heroTag: 'shell-lyrics-${song.id}',
          positionStream: PlaybackController.instance.audioPlayer.positionStream,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final song = controller.currentSong;
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF141414).withValues(alpha: 0.97),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: Row(
            children: [
              const _NavSection(icons: _navIcons, labels: _navLabels),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 16),
                color: Colors.white.withValues(alpha: 0.08),
              ),
              _NowPlayingSection(
                song: song,
                onTap: song == null ? null : _openPlayerScreen,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SeekBarRow(horizontalPadding: 0),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [TransportButtons()],
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Lyrics',
                color: Colors.white70,
                icon: const Icon(Icons.lyrics_rounded, size: 22),
                onPressed: song == null ? null : () => _openLyrics(context),
              ),
              const VolumeControl(sliderWidth: 96, iconSize: 20),
              const SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }
}

class _NavSection extends StatelessWidget {
  final List<IconData> icons;
  final List<String> labels;

  const _NavSection({required this.icons, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: ValueListenableBuilder<int>(
        valueListenable: currentTabNotifier,
        builder: (context, currentIndex, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(icons.length, (i) {
              final selected = currentIndex == i;
              return Tooltip(
                message: labels[i],
                child: IconButton(
                  iconSize: 22,
                  color: selected ? Colors.white : Colors.white38,
                  icon: Icon(icons[i]),
                  onPressed: () {
                    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
                    currentTabNotifier.value = i;
                  },
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _NowPlayingSection extends StatelessWidget {
  final SongModel? song;
  final VoidCallback? onTap;

  const _NowPlayingSection({required this.song, this.onTap});

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return SizedBox(
      width: 230,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (song == null)
                  const Icon(Icons.music_note_rounded, color: Colors.white24, size: 22)
                else
                  SmartArtworkWidget(
                    song: song!,
                    width: 42,
                    height: 42,
                    borderRadius: BorderRadius.circular(12),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song?.title ?? 'Nothing playing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      StreamBuilder<PlayerState>(
                        stream: controller.audioPlayer.playerStateStream,
                        builder: (context, snapshot) {
                          final playing = snapshot.data?.playing ?? false;
                          return Text(
                            playing
                                ? (song?.artist ?? 'Unknown Artist')
                                : 'Paused · ${song?.artist ?? 'Unknown Artist'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                          );
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
