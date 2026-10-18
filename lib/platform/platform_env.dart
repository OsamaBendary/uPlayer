import 'dart:io' show Platform;

/// True when running on a Linux desktop (uPlayer's desktop port target).
///
/// The app is built for Android phones and Linux desktops. Everything that
/// differs between the two — media library source, artwork, permissions,
/// folder picking, the native Go bridge transport — branches on this flag.
bool get isLinuxDesktop => Platform.isLinux;

/// True on Android (the original phone target, MediaStore-based).
bool get isAndroidMobile => Platform.isAndroid;

/// True on iOS (not a supported build target today, but kept compiling).
bool get isAppleMobile => Platform.isIOS;
