import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:u_player/core/navigation/app_keys.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/modules/player/pages/player_screen.dart';
import 'package:u_player/platform/audio_query_compat.dart';
import 'package:u_player/platform/platform_env.dart';

/// Dart side of the desktop mini player.
///
/// The window belongs to the GTK runner (see
/// `linux/runner/mini_player_window.cc`): it hosts a second Flutter engine
/// running this same bundle with [kMiniPlayerEntrypoint] as its entrypoint
/// argument, which makes `main()` boot the small panel instead of the whole
/// application. The two isolates share nothing else, so everything the panel
/// shows or asks for travels over the `uplayer/mini_window` channel that the
/// runner brokers between them:
///
/// * this side pushes snapshots of [PlaybackController]'s state,
/// * the panel sends commands back (`playPause`, `next`, `hide`, ...),
/// * the runner reports `closed` when the window is taken away.
///
/// The user's choice is remembered across launches. The panel's engine is
/// built the first time the mini player opens and then lives until the app
/// quits; turning the mini player off only unmaps its window, because tearing
/// a second engine down mid-session is not stable on GTK.
class MiniPlayerWindowService {
  MiniPlayerWindowService._();

  static final MiniPlayerWindowService instance = MiniPlayerWindowService._();

  /// The method channel the runner brokers between the two engines.
  static const MethodChannel _channel = MethodChannel('uplayer/mini_window');

  /// Entrypoint argument that turns a launch of this bundle into the mini
  /// panel. Must match `kMiniWindowEntrypoint` in `mini_player_window.cc`.
  static const String kMiniPlayerEntrypoint = 'uplayer-mini';

  /// The window's title, used to find it again through `hyprctl`. Must match
  /// `kMiniWindowTitle` in `mini_player_window.cc`.
  static const String kMiniWindowTitle = 'uPlayer Mini Player';

  /// The panel's size, matching the native window's default size.
  static const double panelWidth = 380;
  static const double panelHeight = 128;

  /// The gap between the panel and the screen edges.
  static const int _panelMargin = 16;

  /// Preference key remembering whether the user wants the mini player.
  static const String _preferenceKey = 'desktop_mini_player_enabled';

  /// Whether the user wants the mini player open (the shell bar button's
  /// state). It stays true while the panel is hidden behind the full player.
  final ValueNotifier<bool> isEnabled = ValueNotifier<bool>(false);

  bool _initialized = false;
  bool _windowShown = false;
  bool _layerShell = true;
  String _layerShellReason = 'ok';
  bool _hintedAboutLayerShell = false;
  bool _arrangingWindow = false;
  Timer? _ticker;
  int? _artworkSongId;
  Uint8List? _artworkBytes;

  /// Hooks the service up to the shell. Safe to call on platforms without the
  /// desktop mini player: it does nothing there.
  Future<void> init() async {
    if (!isLinuxDesktop || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_onPanelMessage);

    final controller = PlaybackController.instance;
    controller.addListener(_onPlaybackChanged);
    controller.audioPlayer.playerStateStream.listen((_) => _pushState());
    controller.isPlayerScreenVisible.addListener(_onPlayerScreenChanged);

    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_preferenceKey) ?? false) {
      isEnabled.value = true;
      await _open();
    }
  }

  /// Opens the mini player (or closes it when it is already open).
  Future<void> toggle() => isEnabled.value ? disable() : enable();

  Future<void> enable() async {
    if (!isLinuxDesktop || isEnabled.value) return;
    isEnabled.value = true;
    await _persist(true);
    await _open();
  }

  Future<void> disable() async {
    if (!isLinuxDesktop) return;
    isEnabled.value = false;
    _windowShown = false;
    _stopTicker();
    await _persist(false);
    try {
      // The runner only unmaps the panel: destroying the second engine while
      // the shell keeps rendering is unstable, so the window stays ready for
      // the next time the mini player is switched on.
      await _channel.invokeMethod<void>('close');
    } catch (_) {
      // The window was never created, or is already gone.
    }
  }

  // -------------------------------------------------------------------------
  // Window
  // -------------------------------------------------------------------------

  Future<void> _open() async {
    Map<Object?, Object?>? result;
    try {
      result = await _channel.invokeMethod<Map<Object?, Object?>>('show');
    } catch (_) {
      // No runner behind the channel (or the window could not be created).
      _windowShown = false;
      return;
    }

    _windowShown = true;
    _layerShell = result?['layerShell'] == true;
    _layerShellReason = result?['layerShellReason'] as String? ?? 'ok';
    _startTicker();

    if (!_layerShell) {
      unawaited(_arrangeFloatingWindow());
      if (_layerShellReason == 'lib-missing') _hintAboutLayerShell();
    }

    final song = PlaybackController.instance.currentSong;
    if (song != null) {
      unawaited(_sendArtwork(song.id));
    } else {
      unawaited(_pushState());
    }
  }

  /// The full player already shows everything the panel does, so the panel
  /// steps aside while it is on screen and comes back when it closes.
  void _onPlayerScreenChanged() {
    if (!isEnabled.value) return;
    final playerVisible =
        PlaybackController.instance.isPlayerScreenVisible.value;

    if (playerVisible && _windowShown) {
      _windowShown = false;
      _stopTicker();
      unawaited(_hideWindow());
    } else if (!playerVisible && !_windowShown) {
      unawaited(_open());
    }
  }

  Future<void> _hideWindow() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {
      // The window is already gone.
    }
  }

  /// The window was taken away (compositor close on the fallback path, or the
  /// runner shutting down): remember that the mini player is off and forget
  /// the engine it belonged to.
  void _onWindowClosed() {
    _windowShown = false;
    _stopTicker();
    if (!isEnabled.value) return;
    isEnabled.value = false;
    unawaited(_persist(false));
  }

  Future<void> _persist(bool enabled) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_preferenceKey, enabled);
    } catch (_) {
      // Preferences are best-effort: the panel still works for this session.
    }
  }

  // -------------------------------------------------------------------------
  // Playback snapshots
  // -------------------------------------------------------------------------

  void _onPlaybackChanged() {
    unawaited(_pushState());
  }

  void _startTicker() {
    // The position is the only thing that keeps moving on its own: one update
    // a second keeps the progress line honest without chattering at the
    // channel (the panel interpolates between updates).
    _ticker ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_pushState()),
    );
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Sends the panel everything it needs to draw the current track. Artwork
  /// bytes are only attached when explicitly asked for: they are the one part
  /// of the snapshot that is not cheap to copy. [artworkFor] names the song the
  /// answer is about, so the panel can tell "no cover" from "not asked yet".
  Future<void> _pushState({int? artworkFor}) async {
    if (!_windowShown) return;
    try {
      await _channel.invokeMethod<void>(
        'message',
        _snapshot(artworkFor: artworkFor),
      );
    } catch (_) {
      // The panel is on its way out; the next update will find it gone.
    }
  }

  Map<String, Object?> _snapshot({int? artworkFor}) {
    final controller = PlaybackController.instance;
    final player = controller.audioPlayer;
    final song = controller.currentSong;

    if (song == null) {
      return {'type': 'state', 'songId': null, 'playing': false};
    }

    final snapshot = <String, Object?>{
      'type': 'state',
      'songId': song.id,
      'title': song.title,
      'artist': song.artist ?? 'Unknown Artist',
      'album': song.album ?? '',
      'playing': player.playing,
      'positionMs': player.position.inMilliseconds,
      'durationMs':
          (player.duration ?? Duration(milliseconds: song.duration ?? 0))
              .inMilliseconds,
    };

    if (artworkFor != null) {
      snapshot['artworkSongId'] = artworkFor;
      if (_artworkSongId == artworkFor && _artworkBytes != null) {
        snapshot['artwork'] = _artworkBytes;
      }
    }
    return snapshot;
  }

  Future<void> _sendArtwork(int songId) async {
    if (_artworkSongId != songId) {
      final song = _songById(songId);
      final bytes = song == null ? null : await _readArtworkBytes(song);
      final prepared = bytes == null ? null : await _downscaleArtwork(bytes);

      _artworkSongId = prepared == null ? null : songId;
      _artworkBytes = prepared;
      if (!_windowShown) return;
    }
    await _pushState(artworkFor: songId);
  }

  SongModel? _songById(int id) {
    final controller = PlaybackController.instance;
    final current = controller.currentSong;
    if (current != null && current.id == id) return current;
    for (final song in controller.queue) {
      if (song.id == id) return song;
    }
    return null;
  }

  /// The same artwork the shell's own widgets show for [song]: a companion
  /// file next to the track, the folder's cover, or whatever the scan cached.
  static Future<Uint8List?> _readArtworkBytes(SongModel song) async {
    final path = song.data;
    if (path.isNotEmpty) {
      try {
        final dot = path.lastIndexOf('.');
        if (dot != -1) {
          final base = path.substring(0, dot);
          for (final candidate in ['$base.jpg', '$base.png']) {
            final file = File(candidate);
            if (file.existsSync()) {
              final bytes = await file.readAsBytes();
              if (bytes.isNotEmpty) return bytes;
            }
          }
        }
        final cover = File('${File(path).parent.path}/cover.jpg');
        if (cover.existsSync()) {
          final bytes = await cover.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {
        // Fall through to the scan cache below.
      }
    }
    return ArtworkRegistry.instance.readArtworkBytes(song.id);
  }

  /// The panel draws the artwork at 96 logical pixels; re-encoding it at
  /// 256 px keeps the channel message small (full-size covers can be tens of
  /// megabytes) without a visible difference.
  static Future<Uint8List> _downscaleArtwork(Uint8List bytes) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 256,
        allowUpscaling: false,
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return bytes;
      return data.buffer.asUint8List();
    } catch (_) {
      // Whatever the file is, the panel can still try to decode it as-is.
      return bytes;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  // -------------------------------------------------------------------------
  // Panel commands
  // -------------------------------------------------------------------------

  Future<void> _onPanelMessage(MethodCall call) async {
    if (call.method != 'message') return;
    final message = call.arguments;
    if (message is! Map) return;

    switch (message['type']) {
      case 'ready':
        // The panel is listening now: give it the full picture, artwork
        // included.
        final song = PlaybackController.instance.currentSong;
        if (song != null) {
          await _sendArtwork(song.id);
        } else {
          await _pushState();
        }
      case 'requestArtwork':
        final songId = message['songId'];
        if (songId is int) await _sendArtwork(songId);
      case 'playPause':
        await _togglePlayback();
      case 'next':
        await PlaybackController.instance.audioPlayer.seekToNext();
      case 'previous':
        await PlaybackController.instance.audioPlayer.seekToPrevious();
      case 'openFullPlayer':
        _openFullPlayer();
      case 'hide':
        await disable();
      case 'closed':
        _onWindowClosed();
    }
  }

  Future<void> _togglePlayback() async {
    final player = PlaybackController.instance.audioPlayer;
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  void _openFullPlayer() {
    final controller = PlaybackController.instance;
    final navigator = rootNavigatorKey.currentState;
    if (navigator != null && !controller.isPlayerScreenVisible.value) {
      navigator.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: PlayerScreen.routeName),
          builder: (_) => const PlayerScreen(),
        ),
      );
    }
    // The window the user just clicked is a small overlay; bring the shell
    // itself to the front so the player screen is actually visible.
    unawaited(_raiseMainWindow());
  }

  Future<void> _raiseMainWindow() async {
    try {
      await _channel.invokeMethod<void>('raise');
    } catch (_) {
      // Nothing to raise.
    }
  }

  // -------------------------------------------------------------------------
  // Fallback placement
  // -------------------------------------------------------------------------

  /// Without gtk-layer-shell the panel is an ordinary window, and a tiling
  /// compositor is free to slot it into the layout. Hyprland can be asked to
  /// float, pin and park it in the top-right corner over its own IPC; other
  /// sessions keep the window hints and whatever the user's rules do.
  Future<void> _arrangeFloatingWindow() async {
    if (_arrangingWindow) return;
    if (Platform.environment['HYPRLAND_INSTANCE_SIGNATURE'] == null) return;

    _arrangingWindow = true;
    try {
      final client = await _findFloatingWindow();
      if (client == null) return;
      final address = client.address;

      // Both dispatchers toggle the state, so only reach for them when the
      // window is not already where it should be.
      if (!client.floating) {
        await _hyprctlDispatch("hl.dsp.window.float('address:$address')", [
          'setfloating',
          'address:$address',
        ]);
      }
      if (!client.pinned) {
        await _hyprctlDispatch("hl.dsp.window.pin('address:$address')", [
          'pin',
          'address:$address',
        ]);
      }

      final monitor = await _focusedMonitor();
      if (monitor != null) {
        final x = monitor.x + monitor.width - panelWidth.round() - _panelMargin;
        final y = monitor.y + _panelMargin;
        await _hyprctlDispatch(
          "hl.dsp.window.move({ x = $x, y = $y, window = 'address:$address' })",
          ['movewindowpixel', 'exact $x $y,address:$address'],
        );
      }
    } catch (_) {
      // Purely cosmetic: the window is usable wherever it lands.
    } finally {
      _arrangingWindow = false;
    }
  }

  /// Finds the mini window in Hyprland's client list, retrying briefly: it
  /// only shows up there once the compositor has mapped it.
  Future<({String address, bool floating, bool pinned})?>
  _findFloatingWindow() async {
    for (var attempt = 0; attempt < 12; attempt++) {
      final clients = await _hyprctlJson(['clients']);
      for (final client in clients ?? const []) {
        if (client is! Map || client['title'] != kMiniWindowTitle) continue;
        final address = client['address'];
        if (address is String && address.isNotEmpty) {
          return (
            address: address,
            floating: client['floating'] == true,
            pinned: client['pinned'] == true,
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  Future<({int x, int y, int width})?> _focusedMonitor() async {
    final monitors = await _hyprctlJson(['monitors']);
    if (monitors == null || monitors.isEmpty) return null;

    Map<Object?, Object?>? chosen;
    for (final monitor in monitors) {
      if (monitor is! Map) continue;
      chosen ??= monitor;
      if (monitor['focused'] == true) {
        chosen = monitor;
        break;
      }
    }
    if (chosen == null) return null;

    final x = chosen['x'];
    final y = chosen['y'];
    final width = chosen['width'];
    if (x is! int || y is! int || width is! int) return null;
    return (x: x, y: y, width: width);
  }

  /// Runs a dispatcher through `hyprctl`. Hyprland 0.5x turns `dispatch`
  /// arguments into Lua (`hl.dsp.*`); older releases take the plain
  /// dispatcher name and its arguments. Try the current form first and fall
  /// back to the legacy call when the compositor rejects it.
  Future<void> _hyprctlDispatch(
    String luaExpression,
    List<String> legacyArguments,
  ) async {
    if (await _hyprctlSucceeds(['dispatch', luaExpression])) return;
    await _hyprctlSucceeds(['dispatch', ...legacyArguments]);
  }

  Future<bool> _hyprctlSucceeds(List<String> arguments) async {
    try {
      final result = await Process.run('hyprctl', arguments);
      return result.exitCode == 0 &&
          !(result.stdout as String).trimLeft().startsWith('error');
    } catch (_) {
      // hyprctl is missing or the instance is gone; nothing to arrange.
      return false;
    }
  }

  Future<List<Object?>?> _hyprctlJson(List<String> arguments) async {
    try {
      final result = await Process.run('hyprctl', [...arguments, '-j']);
      if (result.exitCode != 0) return null;
      final decoded = jsonDecode(result.stdout as String);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void _hintAboutLayerShell() {
    if (_hintedAboutLayerShell) return;
    _hintedAboutLayerShell = true;
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text(
          'The mini player floats without gtk-layer-shell: install it for an '
          'always-on-top overlay that no window can cover.',
        ),
      ),
    );
  }
}
