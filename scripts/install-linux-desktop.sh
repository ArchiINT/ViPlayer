#!/usr/bin/env bash
#
# Builds ViPlayer (release) and installs it as a regular desktop app under
# $HOME (no sudo): application menu entry + `viplayer` terminal command.
#
# Data safety: the app's database lives in ~/.local/share/com.viplayer.app and
# music in ~/Music/ViPlayer — this script never touches either. It backs up the
# database first and swaps the app bundle atomically, so a failed build leaves
# the installed version working.
#
# Usage: scripts/install-linux-desktop.sh [--skip-codegen]

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_flutter

INSTALL_DIR="$HOME/.local/lib/viplayer"
BIN_LINK="$HOME/.local/bin/viplayer"
DESKTOP_FILE="$HOME/.local/share/applications/viplayer.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
ICON_SRC="$PROJECT_DIR/assets/icon/icon.png"
[ -f "$ICON_SRC" ] || ICON_SRC="$PROJECT_DIR/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

[ "${1:-}" = "--skip-codegen" ] || codegen

step "Building Linux release bundle"
cd "$PROJECT_DIR"
"$FLUTTER" build linux --release
BUNDLE="$PROJECT_DIR/build/linux/x64/release/bundle"
[ -x "$BUNDLE/viplayer" ] || die "Build failed: $BUNDLE/viplayer missing"

"$PROJECT_DIR/scripts/backup-data.sh" --linux

step "Installing to $INSTALL_DIR"
mkdir -p "$(dirname "$INSTALL_DIR")"
rm -rf "$INSTALL_DIR.new"
cp -r "$BUNDLE" "$INSTALL_DIR.new"
rm -rf "$INSTALL_DIR.old"
[ -d "$INSTALL_DIR" ] && mv "$INSTALL_DIR" "$INSTALL_DIR.old"
mv "$INSTALL_DIR.new" "$INSTALL_DIR"
rm -rf "$INSTALL_DIR.old"

mkdir -p "$(dirname "$BIN_LINK")" "$ICON_DIR" "$(dirname "$DESKTOP_FILE")"
ln -sf "$INSTALL_DIR/viplayer" "$BIN_LINK"
cp -f "$ICON_SRC" "$ICON_DIR/viplayer.png"

cat > "$DESKTOP_FILE" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=ViPlayer
Comment=Music player with downloads and LAN sync
Exec=$INSTALL_DIR/viplayer %U
Icon=viplayer
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupWMClass=$APP_ID
DESKTOP_EOF

command -v update-desktop-database >/dev/null && \
  update-desktop-database "$(dirname "$DESKTOP_FILE")" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && \
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

step "Done — launch \"ViPlayer\" from the menu or run: viplayer"
