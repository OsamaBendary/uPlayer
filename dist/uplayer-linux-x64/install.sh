#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/opt/uplayer"

rm -rf "$DEST"
mkdir -p "$DEST" "$HOME/.local/share/applications"
cp -r "$HERE/app/." "$DEST/"
cp "$HERE/icon.png" "$DEST/icon.png"

cat > "$HOME/.local/share/applications/com.uplayer.u_player.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=uPlayer
Exec=$DEST/u_player %u
Path=$DEST
Icon=$DEST/icon.png
Terminal=false
Categories=AudioVideo;Audio;Player;
MimeType=x-scheme-handler/uplayer;x-scheme-handler/spotiflac;
DESK

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Installed. Open uPlayer from your app launcher."
