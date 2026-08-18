import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_gradient/animate_gradient.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:u_player/modules/library/pages/library_nav_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}


class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _requestPlatformPermissions();
    _navigate();
  }

  /// Once per install, asks for the two runtime permissions that keep a music
  /// app alive on aggressive OEM skins (Honor Magic OS, etc.):
  /// - Battery optimization exemption — without it the system kills the
  ///   process in background (media service included) and the app appears to
  ///   "crash". The manifest permission alone does nothing; the exemption
  ///   must be requested.
  /// - POST_NOTIFICATIONS (Android 13+) — without it the media notification
  ///   is blocked and background playback can be torn down.
  /// Never blocks the splash or startup.
  Future<void> _requestPlatformPermissions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('runtime_permissions_requested') == true) return;
      await prefs.setBool('runtime_permissions_requested', true);

      if (Platform.isAndroid) {
        final notification = await Permission.notification.status;
        if (!notification.isGranted) {
          await Permission.notification.request();
        }
        final battery = await Permission.ignoreBatteryOptimizations.status;
        if (!battery.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }
    } catch (e) {
      debugPrint('Platform permission request error: $e');
    }
  }

  void _navigate() async{
    await Future.delayed(Duration(seconds: 3));
    if (!mounted){return;}
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LibraryNavScreen()));
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
    body: Center(
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: AnimateGradient(
          repeat: true,
          primaryColors: [Colors.black, Colors.deepPurple.withValues(alpha: 0.002)],
          secondaryColors: [Colors.black, Color(591678)],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FadeInDownBig(
                  duration: Duration(seconds: 1),
                  child: Image.asset("assets/logo/Foobar2000_logo_white.png", color: Colors.white, width: 250, height: 250, )),
              SizedBox(height: 20,),
              FadeInUpBig(
                  duration: Duration(seconds: 1),
                  child: Text("Uplayer", style: GoogleFonts.pressStart2p(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),)

            ],

          ),
        ),
      ),
    ),
    );
  }
}


