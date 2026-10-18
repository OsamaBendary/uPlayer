import 'package:flutter/material.dart';
import 'package:u_player/platform/audio_query_compat.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/theme/dynamic_gradient_background/dynamic_gradient_background.dart';
import 'package:u_player/modules/library/widgets/smart_artwork_widget.dart';
import 'package:u_player/modules/library/widgets/song_options_dialog.dart';
import 'package:u_player/modules/player/pages/widgets/lyrics_pane.dart';
import 'package:u_player/modules/player/widgets/desktop_controls.dart';

/// The Linux desktop player: artwork on the left, the queue or the current
/// track's lyrics on the right, and a full-width transport bar underneath.
///
/// The right pane carries a `Queue | Lyrics` switch and opens on the lyrics,
/// so the words are on screen as soon as the player does while the artwork
/// keeps the whole left half of the window. A mid-sized window still fits
/// both panes; below [_splitWidth] they stack the way the phone layout does.
///
/// The phone player stays single-column and gesture-driven; this layout is
/// used only when `isLinuxDesktop` is true.
class DesktopPlayerLayout extends StatelessWidget {
  const DesktopPlayerLayout({super.key});

  /// Below this width artwork and the right pane stop sitting side by side.
  static const double _splitWidth = 880;

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
                  return Column(
                    children: [
                      Expanded(
                        child: _panes(constraints.maxWidth, song),
                      ),
                      const _PlayerTransportBar(),
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

  Widget _panes(double width, SongModel song) {
    final artworkPane = _ArtworkPane(song: song);
    final rightPane = _RightPane(song: song);

    if (width >= _splitWidth) {
      return Row(
        children: [
          Expanded(child: artworkPane),
          Expanded(child: rightPane),
        ],
      );
    }

    return Column(
      children: [
        Expanded(flex: 5, child: artworkPane),
        Expanded(flex: 6, child: rightPane),
      ],
    );
  }
}

/// Large square artwork, centred in its pane, with the playing track's
/// title and artist underneath when there is room for them.
class _ArtworkPane extends StatelessWidget {
  final SongModel song;

  const _ArtworkPane({required this.song});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Size the artwork from the pane's width and let FittedBox shrink the
        // whole block when the pane is too short for it — a pane that is
        // squeezed in either direction loses size instead of overflowing.
        final side = (constraints.maxWidth * 0.82).clamp(64.0, 640.0);
        final showText = constraints.maxHeight >= 200;

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
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
                  if (showText) ...[
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What the right-hand pane shows. The choice is session-only: opening the
/// player always starts on the lyrics.
enum _PaneTab { queue, lyrics }

/// The player's right-hand pane: the queue or the current track's lyrics,
/// behind a small Queue | Lyrics switch. The header follows the selection —
/// the album with its totals for the queue, the track for the lyrics — and
/// the transport lives in the bar under the panes, so the pane gets the
/// window's full height.
class _RightPane extends StatefulWidget {
  final SongModel song;

  const _RightPane({required this.song});

  @override
  State<_RightPane> createState() => _RightPaneState();
}

class _RightPaneState extends State<_RightPane> {
  _PaneTab _tab = _PaneTab.lyrics;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final queue = PlaybackController.instance.queue;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 18, 8),
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
              Expanded(child: _header(song, queue)),
              const SizedBox(width: 8),
              _switch(),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _tab == _PaneTab.queue
                ? _QueueView(queue: queue)
                : LyricsPane(song: song),
          ),
        ],
      ),
    );
  }

  Widget _header(SongModel song, List<SongModel> queue) {
    final isQueue = _tab == _PaneTab.queue;
    final totalDuration = queue.fold<Duration>(
      Duration.zero,
      (sum, s) => sum + Duration(milliseconds: s.duration ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isQueue ? (song.album ?? song.title) : song.title,
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
          isQueue
              ? '${song.artist ?? 'Unknown Artist'} • '
                    '${queue.length} ${queue.length == 1 ? 'track' : 'tracks'} • '
                    '${formatDuration(totalDuration)}'
              : '${song.artist ?? 'Unknown Artist'} • '
                    '${song.album ?? 'Unknown Album'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
      ],
    );
  }

  /// The two-slot pill that swaps the pane's contents.
  Widget _switch() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _switchTab('Queue', _PaneTab.queue),
          _switchTab('Lyrics', _PaneTab.lyrics),
        ],
      ),
    );
  }

  Widget _switchTab(String label, _PaneTab tab) {
    final isSelected = tab == _tab;

    return Material(
      color: isSelected ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _tab = tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// The player's own transport bar, spanning the full window under the panes:
/// seek, transport, repeat and volume.
class _PlayerTransportBar extends StatelessWidget {
  const _PlayerTransportBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SeekBarRow(),
            const Row(
              children: [
                TransportButtons(),
                Spacer(),
                VolumeControl(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The playing list with a header row (#, title, duration) like a desktop
/// music player's track table.
class _QueueView extends StatelessWidget {
  final List<SongModel> queue;

  const _QueueView({required this.queue});

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

