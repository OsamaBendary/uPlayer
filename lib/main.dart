import 'package:flutter/material.dart';
import 'package:u_player/modules/splash/splash_screen.dart';
import 'package:just_audio_background/just_audio_background.dart';


  void main() async {
    WidgetsFlutterBinding.ensureInitialized();

    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.u_player.channel.audio',
      androidNotificationChannelName: 'Audio Playback',
      androidNotificationOngoing: true,
    );

    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    ));
  }