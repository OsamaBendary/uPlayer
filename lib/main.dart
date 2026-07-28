import 'package:flutter/material.dart';
import 'package:u_player/modules/splash/splash_screen.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:u_player/modules/player/pages/widgets/mini_player_bar.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.u_player.channel.audio',
    androidNotificationChannelName: 'Audio Playback',
    androidNotificationOngoing: true,
  );

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: const SplashScreen(),
    // Applied above every route in the app, so the floating mini-player
    // shows up regardless of which screen is on top — it's not a nav
    // bar, so it doesn't need to be added per-screen. It hides itself
    // automatically (see MiniPlayerBar) while the full PlayerScreen is
    // already open.
    builder: (context, child) {
      return Stack(
        children: [
          if (child != null) child,
          const MiniPlayerBar(),
        ],
      );
    },
  ));
}
