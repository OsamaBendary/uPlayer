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

/// Bottom padding scrollable lists leave so their last row stays clear of the
/// shell chrome.
///
/// On Android the mini player and floating nav bar hover over the content, so
/// lists reserve room for both. On the Linux desktop the `DesktopShellBar` is
/// a normal layout sibling — the content area already ends above it — so lists
/// only need a small breathing gap.
double get listBottomInset => isLinuxDesktop ? 24 : 160;
