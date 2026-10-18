import 'package:flutter/material.dart';
import 'package:u_player/platform/audio_query_compat.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';
import 'package:u_player/modules/library/widgets/smart_artwork_widget.dart';
import 'package:u_player/modules/library/widgets/song_options_dialog.dart';
import 'package:u_player/modules/player/pages/lyrics_screen.dart';
import 'package:u_player/modules/player/widgets/desktop_controls.dart';

/// The Linux desktop player: artwork on the left half, the list that is
/// playing (album, playlist or queue) on the right half, and its own
/// transport bar — including lyrics and volume controls — under the list.
///
/// The phone player stays single-column and gesture-driven; this layout is
/// used only when `isLinuxDesktop` is true.
class DesktopPlayerLayout extends StatelessWidget {
  const DesktopPlayerLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final song = controller.currentSong;
        if (song == null) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text(
                'Nothing is playing yet.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: DynamicGradientBackground(
            songId: song.id,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Half and half while there is room for it; stacked
                  // artwork-over-list when the window is squeezed narrow.
                  final isWide = constraints.maxWidth >= 880;
                  final artworkPane = _ArtworkPane(song: song);
                  final listPane = _PlayingListPane(song: song);

                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(child: artworkPane),
                        Expanded(child: listPane),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(flex: 5, child: artworkPane),
                      Expanded(flex: 6, child: listPane),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Large square artwork, centred in its half of the window.
class _ArtworkPane extends StatelessWidget {
  final SongModel song;

  const _ArtworkPane({required this.song});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.biggest.shortestSide * 0.82).clamp(120.0, 640.0);
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 40,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: SmartArtworkWidget(
                    song: song,
                    width: side,
                    height: side,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 22),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: side),
                  child: Column(
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist ?? 'Unknown Artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Album header + the tracks that are playing + the transport bar.
class _PlayingListPane extends StatelessWidget {
  final SongModel song;

  const _PlayingListPane({required this.song});

  void _openLyrics(BuildContext context, SongModel song) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LyricsScreen(
          song: song,
          heroTag: 'desktop-lyrics-${song.id}',
          positionStream: PlaybackController.instance.audioPlayer.positionStream,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;
    final queue = controller.queue;
    final totalDuration = queue.fold<Duration>(
      Duration.zero,
      (sum, s) => sum + Duration(milliseconds: s.duration ?? 0),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (Navigator.of(context).canPop())
                IconButton(
                  tooltip: 'Close player',
                  color: Colors.white70,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 26),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.album ?? song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${song.artist ?? 'Unknown Artist'} • '
                      '${queue.length} ${queue.length == 1 ? 'track' : 'tracks'} • '
                      '${formatDuration(totalDuration)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: _QueueList(queue: queue)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SeekBarRow(),
                Row(
                  children: [
                    const TransportButtons(),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Lyrics',
                      color: Colors.white70,
                      icon: const Icon(Icons.lyrics_rounded),
                      onPressed: () => _openLyrics(context, song),
                    ),
                    const VolumeControl(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The playing list with a header row (#, title, duration) like a desktop
/// music player's track table.
class _QueueList extends StatelessWidget {
  final List<SongModel> queue;

  const _QueueList({required this.queue});

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    if (queue.isEmpty) {
      return const Center(
        child: Text('Queue is empty.', style: TextStyle(color: Colors.white54)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: [
              const SizedBox(
                width: 30,
                child: Text('#', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
              const Expanded(
                child: Text('Title', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
              const SizedBox(
                width: 56,
                child: Text(
                  'Time',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: queue.length,
            itemBuilder: (context, index) => _QueueRow(
              song: queue[index],
              index: index,
              isCurrent: index == controller.currentIndex,
            ),
          ),
        ),
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  final SongModel song;
  final int index;
  final bool isCurrent;

  const _QueueRow({
    required this.song,
    required this.index,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => controller.jumpToQueueIndex(index),
          onSecondaryTap: () => SongOptionsDialog.show(context, song),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isCurrent ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isCurrent
                  ? Border.all(color: Colors.white.withValues(alpha: 0.16))
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: isCurrent
                      ? const Icon(Icons.graphic_eq_rounded, size: 15, color: Colors.greenAccent)
                      : Text(
                          '${index + 1}',
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                ),
                Expanded(
                  child: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? Colors.greenAccent : Colors.white,
                      fontSize: 13.5,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  formatPlaybackTime(Duration(milliseconds: song.duration ?? 0)),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
