import 'package:flutter/material.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/modules/library/pages/library_nav_screen.dart';
import 'package:u_player/modules/player/pages/player_screen.dart';
import 'package:u_player/modules/splash/splash_screen.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:u_player/modules/player/pages/widgets/mini_player_bar.dart';

/// MiniPlayerBar is placed via MaterialApp's `builder`, which puts it
/// *outside* the Navigator's subtree (the `context` the builder callback
/// gets is the app-level context above the Navigator, not inside it) — so
/// `Navigator.of(context)` from within MiniPlayerBar can never find a
/// Navigator, no matter what's currently on screen. This key gives any
/// widget in the app a reliable way to push routes regardless of where it
/// lives in the tree.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Drives PlaybackController.isPlayerScreenVisible directly from the
/// Navigator's own push/pop/replace/remove events, by keeping a shadow
/// stack and checking whether PlayerScreen's route is on top after every
/// change.
///
/// This replaces the old approach of manually flipping a bool in
/// PlayerScreen's initState/dispose. That worked most of the time, but a
/// manually-maintained flag can silently desync from reality (hot reload,
/// an unusual pop path, any future refactor that adds another way to leave
/// the screen) and once it does, the mini-player just never comes back —
/// which is exactly the symptom that kept recurring. Reading the actual
/// navigation stack instead of a separate flag can't drift out of sync
/// with itself, because there's only one source of truth.
class _PlayerVisibilityObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  void _recompute() {
    final isPlayerOnTop = _stack.isNotEmpty && _stack.last.settings.name == PlayerScreen.routeName;
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

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: rootNavigatorKey,
    navigatorObservers: [_PlayerVisibilityObserver()],
    home: const SplashScreen(),
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