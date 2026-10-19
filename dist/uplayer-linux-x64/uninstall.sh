#!/usr/bin/env bash
rm -rf "$HOME/.local/opt/uplayer"
rm -f "$HOME/.local/share/applications/com.uplayer.u_player.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Removed. Your settings in ~/.local/share/com.uplayer.u_player were kept."
