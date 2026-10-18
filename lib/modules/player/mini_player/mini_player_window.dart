import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:u_player/modules/player/widgets/desktop_controls.dart'
    show formatPlaybackTime;

/// The desktop mini player's window UI.
///
/// This tree runs in its own Flutter engine inside the always-on-top window
/// the GTK runner builds (see `linux/runner/mini_player_window.cc`), not in
/// the shell's engine. It holds no playback state of its own: it draws the
/// last snapshot the shell sent over the brokered `uplayer/mini_window`
/// channel and sends commands back (previous, play/pause, next, open the full
/// player, close the panel).
///
/// See `MiniPlayerWindowService` for the shell side of that conversation.
class MiniPlayerApp extends StatelessWidget {
  const MiniPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const MiniPlayerPanel(),
    );
  }
}

/// Artwork on the left, everything else on the right: the same shape as the
/// phone's mini player bar, sized for a floating panel instead of a strip.
class MiniPlayerPanel extends StatefulWidget {
  const MiniPlayerPanel({super.key});

  @override
  State<MiniPlayerPanel> createState() => _MiniPlayerPanelState();
}

class _MiniPlayerPanelState extends State<MiniPlayerPanel> {
  static const MethodChannel _channel = MethodChannel('uplayer/mini_window');

  static const double _artworkSide = 96;

  bool _hasSong = false;
  String _title = '';
  String _artist = '';
  bool _playing = false;
  Duration _duration = Duration.zero;
  Uint8List? _artwork;

  /// The track the bytes in [_artwork] belong to (null while there is none).
  int? _artworkSongId;

  /// The track currently drawn; used to notice track changes between snapshots.
  int? _currentSongId;

  /// The position the last snapshot carried and when it arrived: between
  /// snapshots the panel advances the progress line itself.
  Duration _reportedPosition = Duration.zero;
  DateTime _reportedAt = DateTime.now();

  /// The song whose artwork has already been asked for, so a track without a
  /// cover does not ask again and again.
  int? _requestedArtworkFor;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMessage);
    // The shell waits for this before sending the first snapshot: a message
    // sent while this isolate is still booting would simply be dropped.
    unawaited(_send({'type': 'ready'}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _send(Map<String, Object?> message) async {
    try {
      await _channel.invokeMethod<void>('message', message);
    } catch (_) {
      // The shell is closing, or did not understand the message.
    }
  }

  Future<void> _handleMessage(MethodCall call) async {
    if (call.method != 'message') return;
    final message = call.arguments;
    if (message is! Map || message['type'] != 'state') return;

    final songId = message['songId'];

    setState(() {
      if (songId is! int) {
        _hasSong = false;
        _title = '';
        _artist = '';
        _playing = false;
        _duration = Duration.zero;
        _reportedPosition = Duration.zero;
        _artwork = null;
        _artworkSongId = null;
        _currentSongId = null;
        _requestedArtworkFor = null;
        return;
      }

      if (_currentSongId != songId) {
        _currentSongId = songId;
        // A different track: ask for its cover again (below). Whatever is on
        // screen stays until the shell answers, so the card does not flash
        // empty between two tracks of the same album.
        _requestedArtworkFor = null;
      }

      _hasSong = true;
      _title = message['title'] as String? ?? _title;
      _artist = message['artist'] as String? ?? _artist;
      _playing = message['playing'] == true;

      final positionMs = message['positionMs'];
      _reportedPosition = Duration(
        milliseconds: positionMs is int ? positionMs : 0,
      );
      _reportedAt = DateTime.now();

      final durationMs = message['durationMs'];
      _duration = Duration(milliseconds: durationMs is int ? durationMs : 0);

      if (message['artworkSongId'] == songId) {
        // A direct answer to an artwork request: either the new cover or the
        // fact that this track has none.
        final artwork = message['artwork'];
        _artwork = artwork is Uint8List ? artwork : null;
        _artworkSongId = songId;
        _requestedArtworkFor = songId;
      }
    });

    if (_hasSong &&
        _artworkSongId != songId &&
        _requestedArtworkFor != songId) {
      _requestedArtworkFor = songId;
      unawaited(_send({'type': 'requestArtwork', 'songId': songId}));
    }
    _syncTicker();
  }

  /// Runs only while something is playing: the progress line moves every
  /// frame, but a paused panel has nothing to do.
  void _syncTicker() {
    if (_hasSong && _playing) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Duration get _position {
    if (!_playing) return _reportedPosition;
    final elapsed = DateTime.now().difference(_reportedAt);
    final position = _reportedPosition + elapsed;
    if (_duration > Duration.zero && position > _duration) return _duration;
    return position;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // A little slack around the card, which has a shadow of its own.
      body: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF141414).withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _artworkTile(),
              const SizedBox(width: 12),
              Expanded(child: _details()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artworkTile() {
    return Tooltip(
      message: 'Open the player',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => unawaited(_send({'type': 'openFullPlayer'})),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: _artworkSide,
              height: _artworkSide,
              child: _artworkImage(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _artworkImage() {
    final artwork = _artwork;
    if (artwork != null && artwork.isNotEmpty) {
      return Image.memory(artwork, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return Container(
      color: Colors.white.withValues(alpha: 0.06),
      alignment: Alignment.center,
      child: Icon(
        _hasSong ? Icons.music_note_rounded : Icons.music_off_rounded,
        color: Colors.white24,
        size: 30,
      ),
    );
  }

  Widget _details() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _hasSong ? _title : 'Nothing playing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _iconButton(
              Icons.open_in_full_rounded,
              'Open the player',
              () => unawaited(_send({'type': 'openFullPlayer'})),
            ),
            _iconButton(
              Icons.close_rounded,
              'Close the mini player',
              () => unawaited(_send({'type': 'hide'})),
            ),
          ],
        ),
        Text(
          _hasSong ? _artist : 'Play something to see it here',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 11.5),
        ),
        const Spacer(),
        _progressLine(),
        const SizedBox(height: 6),
        _transport(),
      ],
    );
  }

  Widget _progressLine() {
    final position = _position;
    final durationMs = _duration.inMilliseconds;
    final fraction = durationMs <= 0
        ? 0.0
        : (position.inMilliseconds / durationMs).clamp(0.0, 1.0);

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white70),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${formatPlaybackTime(position)} / ${formatPlaybackTime(_duration)}',
          style: const TextStyle(color: Colors.white38, fontSize: 10.5),
        ),
      ],
    );
  }

  Widget _transport() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconButton(
          Icons.skip_previous_rounded,
          'Previous',
          _hasSong ? () => unawaited(_send({'type': 'previous'})) : null,
          size: 24,
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: _playing ? 'Pause' : 'Play',
          onPressed: _hasSong
              ? () => unawaited(_send({'type': 'playPause'}))
              : null,
          iconSize: 32,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints.tightFor(width: 40, height: 34),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            disabledBackgroundColor: Colors.white24,
          ),
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const SizedBox(width: 4),
        _iconButton(
          Icons.skip_next_rounded,
          'Next',
          _hasSong ? () => unawaited(_send({'type': 'next'})) : null,
          size: 24,
        ),
      ],
    );
  }

  Widget _iconButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    double size = 16,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: size,
      color: Colors.white60,
      disabledColor: Colors.white24,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
      visualDensity: VisualDensity.compact,
      splashRadius: 16,
      icon: Icon(icon),
    );
  }
}
