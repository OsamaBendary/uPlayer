import 'package:flutter/material.dart';
import 'package:u_player/core/navigation/app_keys.dart';
export 'package:u_player/core/navigation/app_keys.dart';
import 'package:u_player/core/services/extension/extension_service.dart';
import 'package:u_player/core/services/go/go_backend_bridge.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/services/player/artwork_style_preference.dart';
import 'package:u_player/core/services/player/seekbar_preference.dart';
import 'package:u_player/core/services/player/tap_preference.dart';
import 'package:u_player/modules/library/pages/library_nav_screen.dart';
import 'package:u_player/modules/player/pages/player_screen.dart';
import 'package:u_player/modules/splash/splash_screen.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:u_player/modules/player/pages/widgets/mini_player_bar.dart';

/// Drives PlaybackController.isPlayerScreenVisible directly from the
/// Navigator's own push/pop/replace/remove events.
class _PlayerVisibilityObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  void _recompute() {
    final isPlayerOnTop =
        _stack.isNotEmpty && _stack.last.settings.name == PlayerScreen.routeName;
    PlaybackController.instance.isPlayerScreenVisible.value = isPlayerOnTop;
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _stack.add(route);
    _recompute();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _stack.remove(route);
    _recompute();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    _stack.remove(route);
    _recompute();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (oldRoute != null) _stack.remove(oldRoute);
    if (newRoute != null) _stack.add(newRoute);
    _recompute();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.u_player.channel.audio',
    androidNotificationChannelName: 'Audio Playback',
    androidNotificationOngoing: true,
  );

  // Initializes the Go download pipeline (gomobile bind). This MUST run before
  // any download: it sets the extension system dirs, loads installed provider
  // extensions (Tidal/Qobuz/...), and makes GoBackendBridge.isAvailable true.
  await GoBackendBridge.instance.init();
  // Syncs the user's extension repos/store + provider priority with Go.
  await ExtensionService().init();
  // Restores persisted player customization preferences (song-tap behavior,
  // seek bar style, artwork style).
  await loadSeekbarPreference();
  await loadSongTapPreference();
  await loadArtworkStylePreference();

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: rootNavigatorKey,
    scaffoldMessengerKey: rootScaffoldMessengerKey,
    navigatorObservers: [_PlayerVisibilityObserver()],
    home: const SplashScreen(),
    theme: ThemeData.dark().copyWith(
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    ),
    builder: (context, child) {
      return Stack(
        children: [
          if (child != null) child,
          const MiniPlayerBar(),
          const FloatingNavBar(),
        ],
      );
    },
  ));
}
