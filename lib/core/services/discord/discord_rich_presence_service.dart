import 'dart:async';

import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:u_player/core/services/discord/discord_artwork_resolver.dart';
import 'package:u_player/core/services/discord/discord_config.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/platform/audio_query_compat.dart';
import 'package:u_player/platform/platform_env.dart';

/// Immutable "what is playing right now" view used to build an activity.
@immutable
class DiscordPresenceSnapshot {
  const DiscordPresenceSnapshot({
    required this.hasTrack,
    this.songId,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.position = Duration.zero,
    this.duration,
    this.isPlaying = false,
  });

  const DiscordPresenceSnapshot.idle()
    : hasTrack = false,
      songId = null,
      title = '',
      artist = '',
      album = '',
      position = Duration.zero,
      duration = null,
      isPlaying = false;

  final bool hasTrack;
  final int? songId;
  final String title;
  final String artist;
  final String album;
  final Duration position;
  final Duration? duration;
  final bool isPlaying;
}

/// Builds the Discord activity for [snapshot].
///
/// Layout on Discord:
///   Listening to uPlayer          ← application name (Developer Portal)
///   `song title`                  ← details
///   `artist • album`              ← state (prefixed with "Paused" when paused)
///   [━━━━━━━──────]               ← start/end timestamps (Listening time bar)
///
/// Extracted as a pure function so the layout is unit-testable without a
/// running Discord client.
DiscordPresence buildDiscordPresence(
  DiscordPresenceSnapshot snapshot, {
  String? artworkUrl,
  DateTime? now,
}) {
  if (!snapshot.hasTrack) {
    return const DiscordPresence(
      type: DiscordActivityType.listening,
      statusDisplayType: DiscordStatusDisplayType.name,
      details: 'Browsing library',
      state: 'No track playing',
    );
  }

  final title = _clampText(snapshot.title, kDiscordMaxDetailsLength);
  final state = _stateLine(snapshot);
  final album = _displayField(snapshot.album);
  final artist = _displayField(snapshot.artist);

  DiscordTimestamps? timestamps;
  if (snapshot.isPlaying) {
    final start = (now ?? DateTime.now()).subtract(snapshot.position);
    final startSeconds = start.millisecondsSinceEpoch ~/ 1000;
    int? endSeconds;
    final duration = snapshot.duration;
    if (duration != null && duration.inMilliseconds > 0) {
      endSeconds = start.add(duration).millisecondsSinceEpoch ~/ 1000;
    }
    timestamps = DiscordTimestamps(start: startSeconds, end: endSeconds);
  }

  DiscordAsset? largeAsset;
  final coverUrl = artworkUrl?.trim() ?? '';
  if (coverUrl.isNotEmpty) {
    final tooltip = _clampText(
      [if (album.isNotEmpty) album, if (artist.isNotEmpty) artist].join(' • '),
      128,
    );
    largeAsset = DiscordAsset.fromUrl(
      coverUrl,
      text: tooltip.isEmpty ? null : tooltip,
    );
  } else if (kDiscordFallbackArtworkKey.isNotEmpty) {
    largeAsset = DiscordAsset.fromKey(
      kDiscordFallbackArtworkKey,
      text: 'uPlayer',
    );
  }

  return DiscordPresence(
    type: DiscordActivityType.listening,
    statusDisplayType: DiscordStatusDisplayType.details,
    details: title.isEmpty ? 'Unknown track' : title,
    state: state.isEmpty ? null : state,
    timestamps: timestamps,
    largeAsset: largeAsset,
  );
}

String _stateLine(DiscordPresenceSnapshot snapshot) {
  final artist = _displayField(snapshot.artist);
  final album = _displayField(snapshot.album);

  var line = [
    if (!snapshot.isPlaying) 'Paused',
    if (artist.isNotEmpty) artist,
    if (album.isNotEmpty) album,
  ].join(' • ');

  // Keep the line on a single row in the small profile card: drop the album
  // (still visible in the artwork tooltip) before ever truncating mid-word.
  if (line.runes.length > kDiscordSoftStateLength && album.isNotEmpty) {
    final withoutAlbum = [
      if (!snapshot.isPlaying) 'Paused',
      if (artist.isNotEmpty) artist,
    ].join(' • ');
    if (withoutAlbum.isNotEmpty) line = withoutAlbum;
  }

  return _clampText(line, kDiscordMaxStateLength);
}

String _displayField(String value) {
  final cleaned = _cleanField(value);
  final lower = cleaned.toLowerCase();
  if (lower == '<unknown>' ||
      lower == 'unknown' ||
      lower == 'unknown artist' ||
      lower == 'unknown album') {
    return '';
  }
  return cleaned;
}

String _cleanField(String value) {
  return value
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _clampText(String value, int maxLength) {
  final cleaned = _cleanField(value);
  if (cleaned.runes.length <= maxLength) return cleaned;
  return String.fromCharCodes(cleaned.runes.take(maxLength));
}

/// Publishes uPlayer playback to Discord Rich Presence over the local IPC
/// socket.
///
/// Linux desktop only: Discord's IPC transport does not exist on Android.
/// The service owns the connection lifecycle (connect, retry, reconnect),
/// coalesces updates to stay comfortably below Discord's rate limit, and
/// keeps the progress bar accurate by refreshing the start/end timestamps
/// from the live playback position.
class DiscordRichPresenceService {
  DiscordRichPresenceService._internal();

  static final DiscordRichPresenceService instance =
      DiscordRichPresenceService._internal();

  static const String _enabledPrefsKey = 'discord_presence_enabled';
  static const Duration _reconnectInterval = Duration(seconds: 20);
  static const Duration _progressInterval = Duration(seconds: 20);
  static const Duration _minSendInterval = Duration(seconds: 3);

  final DiscordArtworkResolver _artworkResolver = DiscordArtworkResolver();

  /// Exposed to Settings so the switch reflects (and drives) the service.
  final ValueNotifier<bool> enabledNotifier = ValueNotifier<bool>(false);

  PlaybackController? _controller;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  DiscordRPC? _rpc;
  Timer? _reconnectTimer;
  Timer? _progressTimer;
  Timer? _sendTimer;

  bool _started = false;
  bool _enabled = false;
  bool _connecting = false;
  bool _disposed = false;
  bool _hasResolvedArtwork = false;
  int? _artworkSongId;
  String? _artworkUrl;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastFingerprint = '';

  bool get isEnabled => _enabled;

  /// Attaches to playback and starts publishing presence. Safe to call more
  /// than once; subsequent calls are ignored.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    if (!isLinuxDesktop || kDiscordApplicationId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledPrefsKey) ?? true;
    } catch (e) {
      debugPrint('[DiscordPresence] preference load failed: $e');
      _enabled = true;
    }
    enabledNotifier.value = _enabled;

    _controller = PlaybackController.instance;
    _controller!.addListener(_onControllerChanged);
    _playerStateSubscription = _controller!.audioPlayer.playerStateStream
        .listen((_) {
          _scheduleSend();
        });

    // The controller may already be initialized (restored session) before the
    // service attaches; prime the current track so artwork resolves even when
    // no further notification arrives until playback changes.
    _onControllerChanged();

    if (_enabled) {
      unawaited(_connect());
      _startProgressTimer();
    }
  }

  /// Turns presence on/off from Settings. Turning it off clears the activity
  /// on Discord and disconnects.
  Future<void> setEnabled(bool value) async {
    if (_disposed) return;
    _enabled = value && isLinuxDesktop && kDiscordApplicationId.isNotEmpty;
    enabledNotifier.value = _enabled;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledPrefsKey, value);
    } catch (e) {
      debugPrint('[DiscordPresence] preference save failed: $e');
    }

    if (!_enabled) {
      _sendTimer?.cancel();
      _progressTimer?.cancel();
      _reconnectTimer?.cancel();
      _lastFingerprint = '';
      _artworkSongId = null;
      _artworkUrl = null;
      _hasResolvedArtwork = false;
      final rpc = _rpc;
      _rpc = null;
      if (rpc != null) {
        try {
          await rpc.clearPresence();
        } catch (_) {}
        await rpc.dispose();
      }
      return;
    }

    _startProgressTimer();
    _onControllerChanged();
    if (_rpc == null) {
      unawaited(_connect());
    } else {
      _sendTimer?.cancel();
      await _sendPresence();
    }
  }

  // ─── Playback tracking ───────────────────────────────────────────────────

  void _onControllerChanged() {
    final song = _controller?.currentSong;
    if (song != null && song.id != _artworkSongId) {
      _artworkSongId = song.id;
      _artworkUrl = null;
      _hasResolvedArtwork = false;
      if (_enabled) {
        unawaited(_resolveArtwork(song));
      }
    }
    _scheduleSend();
  }

  Future<void> _resolveArtwork(SongModel song) async {
    if (!_enabled || _disposed) return;
    final url = await _artworkResolver.resolve(song);
    if (_disposed || _controller?.currentSong?.id != song.id) return;
    _hasResolvedArtwork = true;
    if (_artworkUrl != url) {
      _artworkUrl = url;
      _scheduleSend();
    }
  }

  DiscordPresenceSnapshot _snapshot() {
    final controller = _controller;
    final song = controller?.currentSong;
    if (controller == null || song == null) {
      return const DiscordPresenceSnapshot.idle();
    }

    final player = controller.audioPlayer;
    final trackDuration = song.duration;
    final duration =
        player.duration ??
        (trackDuration != null && trackDuration > 0
            ? Duration(milliseconds: trackDuration)
            : null);

    return DiscordPresenceSnapshot(
      hasTrack: true,
      songId: song.id,
      title: song.title,
      artist: song.artist ?? '',
      album: song.album ?? '',
      position: player.position,
      duration: duration,
      isPlaying: player.playing,
    );
  }

  // ─── Update scheduling ───────────────────────────────────────────────────

  void _scheduleSend() {
    if (!_enabled || _disposed || _rpc == null) return;
    _sendTimer?.cancel();
    var delay = _minSendInterval - DateTime.now().difference(_lastSentAt);
    if (delay.isNegative) delay = Duration.zero;
    _sendTimer = Timer(delay, () => unawaited(_sendPresence()));
  }

  Future<void> _sendPresence() async {
    final rpc = _rpc;
    if (!_enabled || _disposed || rpc == null || !rpc.isConnected) return;

    final snapshot = _snapshot();
    if (snapshot.hasTrack && snapshot.songId != _artworkSongId) {
      // Defensive: never show the previous track's cover on a new track.
      _artworkSongId = snapshot.songId;
      _artworkUrl = null;
      _hasResolvedArtwork = false;
    }
    final presence = buildDiscordPresence(
      snapshot,
      artworkUrl: _hasResolvedArtwork ? _artworkUrl : null,
    );

    // Periodic refreshes recompute the start/end timestamps from the live
    // position, so a seek or repeat-one restart changes the fingerprint and
    // triggers an update; steady playback produces an identical payload and
    // is skipped entirely.
    final fingerprint = _fingerprint(snapshot, presence);
    if (fingerprint == _lastFingerprint) return;
    _lastFingerprint = fingerprint;
    _lastSentAt = DateTime.now();

    try {
      await rpc.setPresence(presence);
    } catch (e) {
      debugPrint('[DiscordPresence] update failed: $e');
      _handleDisconnected();
    }
  }

  String _fingerprint(
    DiscordPresenceSnapshot snapshot,
    DiscordPresence presence,
  ) {
    final timestamps = presence.timestamps;
    return [
      snapshot.songId,
      presence.type.value,
      presence.details ?? '',
      presence.state ?? '',
      presence.largeAsset?.effectiveKey ?? '',
      presence.largeAsset?.text ?? '',
      presence.statusDisplayType?.value ?? '',
      timestamps?.start ?? '',
      timestamps?.end ?? '',
    ].join('|');
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(_progressInterval, (_) => _scheduleSend());
  }

  // ─── Connection lifecycle ────────────────────────────────────────────────

  Future<void> _connect() async {
    if (!_enabled || _disposed || _connecting || _rpc != null) return;
    _connecting = true;
    final rpc = DiscordRPC();
    try {
      await rpc.initialize(kDiscordApplicationId);
      if (!_enabled || _disposed) {
        await rpc.dispose();
        return;
      }
      _rpc = rpc;
      _lastFingerprint = '';
      rpc.onDisconnected.listen((event) {
        if (_rpc != rpc) return;
        debugPrint('[DiscordPresence] disconnected: ${event.message}');
        _handleDisconnected();
      });
      rpc.onError.listen((event) {
        debugPrint(
          '[DiscordPresence] error ${event.errorCode}: ${event.message}',
        );
      });
      debugPrint('[DiscordPresence] connected');
      _scheduleSend();
    } catch (e) {
      debugPrint('[DiscordPresence] connect failed: $e');
      await rpc.dispose();
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleDisconnected() {
    if (_disposed) return;
    final rpc = _rpc;
    if (rpc == null) return;
    _rpc = null;
    _lastFingerprint = '';
    unawaited(rpc.dispose());
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_enabled || _disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectInterval, () => unawaited(_connect()));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sendTimer?.cancel();
    _progressTimer?.cancel();
    _reconnectTimer?.cancel();
    _controller?.removeListener(_onControllerChanged);
    await _playerStateSubscription?.cancel();
    final rpc = _rpc;
    _rpc = null;
    await rpc?.dispose();
    enabledNotifier.dispose();
  }
}
