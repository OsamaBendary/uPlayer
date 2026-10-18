#!/usr/bin/env bash
# Installs the uPlayer Linux desktop build for the current user and registers
# it as the handler for `uplayer://` / `spotiflac://` links (provider
# verification redirects).
#
#   scripts/install_linux_desktop.sh [--build] [debug|release]
#
# Layout:
#   ~/.local/opt/uplayer/            app bundle (exe + libs + Go sidecar)
#   ~/.local/bin/uPlayer             launcher symlink
#   ~/.local/share/applications/com.uplayer.u_player.desktop
#   ~/.local/share/icons/hicolor/192x192/apps/u_player.png
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_MODE="release"
DO_BUILD="false"
for arg in "$@"; do
  case "$arg" in
    --build) DO_BUILD="true" ;;
    debug|release|profile) BUILD_MODE="$arg" ;;
    *) echo "usage: $0 [--build] [debug|release|profile]" >&2; exit 2 ;;
  esac
done

case "$(uname -m)" in
  x86_64|amd64) ARCH_DIR="x64" ;;
  aarch64|arm64) ARCH_DIR="arm64" ;;
  armv7l|arm) ARCH_DIR="arm" ;;
  *) ARCH_DIR="$(uname -m)" ;;
esac

if [ "$DO_BUILD" = "true" ]; then
  "$ROOT/scripts/build_linux.sh" "$BUILD_MODE"
fi

BUNDLE_DIR="$ROOT/build/linux/$ARCH_DIR/$BUILD_MODE/bundle"
if [ ! -x "$BUNDLE_DIR/u_player" ]; then
  echo "No bundle at $BUNDLE_DIR — run scripts/build_linux.sh $BUILD_MODE first (or pass --build)." >&2
  exit 1
fi
if [ ! -x "$BUNDLE_DIR/uplayer_go_sidecar" ]; then
  echo "Warning: Go sidecar missing from the bundle; downloads/library scanning will be unavailable." >&2
fi

INSTALL_DIR="$HOME/.local/opt/uplayer"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/192x192/apps"

echo "==> Installing to $INSTALL_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
cp -r "$BUNDLE_DIR/." "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/u_player" "$INSTALL_DIR/uplayer_go_sidecar"

ln -sfn "$INSTALL_DIR/u_player" "$BIN_DIR/uPlayer"

ICON_SRC="$ROOT/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$ICON_DIR/u_player.png"
fi

echo "==> Registering desktop entry + URI handlers"
cat > "$APP_DIR/com.uplayer.u_player.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=uPlayer
GenericName=Music Player
Comment=Local and extension-powered music player
Exec=$INSTALL_DIR/u_player %u
Icon=u_player
Terminal=false
Categories=AudioVideo;Audio;Player;
Keywords=music;player;audio;
MimeType=x-scheme-handler/uplayer;x-scheme-handler/spotiflac;
StartupWMClass=com.uplayer.u_player
EOF

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
fi
if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default com.uplayer.u_player.desktop x-scheme-handler/uplayer || true
  xdg-mime default com.uplayer.u_player.desktop x-scheme-handler/spotiflac || true
fi

echo
echo "==> Installed"
echo "    app:      $INSTALL_DIR/u_player"
echo "    launcher: $BIN_DIR/uPlayer  (add ~/.local/bin to PATH if it isn't)"
echo "    menu:     uPlayer (Audio/Video → Player)"
echo "    links:    uplayer:// and spotiflac:// now open in uPlayer"
