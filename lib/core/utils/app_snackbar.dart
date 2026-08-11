import 'package:flutter/material.dart';
import 'package:u_player/core/navigation/app_keys.dart';

/// Shows a floating snackbar above the bottom nav bar + mini-player area.
class AppSnackBar {
  /// Extra clearance above the system nav inset for the floating tab bar (56px)
  /// and MiniPlayerBar (64px + 80px offset). 160px places it cleanly above both.
  static const double _navBarClearance = 160.0;

  static void show(
    String message, {
    BuildContext? context,
    Color? backgroundColor,
    Duration? duration,
  }) {
    final bottomMargin = _bottomMargin(context);

    final snackBar = SnackBar(
      content: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: backgroundColor ?? const Color(0xFF2C2C2E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      margin: EdgeInsets.fromLTRB(20, 0, 20, bottomMargin),
      duration: duration ?? const Duration(seconds: 3),
    );

    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(snackBar);
      return;
    }

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(snackBar);
    }
  }

  static double _bottomMargin(BuildContext? context) {
    // Prefer the root messenger's context (safe even after a route pop) so
    // the system inset is accounted for; fall back to the caller's context.
    final effectiveContext =
        rootScaffoldMessengerKey.currentContext ?? context;
    if (effectiveContext != null && effectiveContext.mounted) {
      return MediaQuery.of(effectiveContext).padding.bottom + _navBarClearance;
    }
    return _navBarClearance;
  }
}
