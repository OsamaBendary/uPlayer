import 'package:flutter/material.dart';

/// Root navigator — usable from overlays (mini player, nav bar) that sit
/// outside the Navigator subtree in MaterialApp's builder.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Root ScaffoldMessenger — shows snackbars above the floating nav bar.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
