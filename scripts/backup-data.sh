#!/usr/bin/env bash
#
# Backs up the app database before an update. Keeps the last 10 backups in
# ~/.local/share/viplayer-backups/.
#
# Linux: copies the database files directly.
# Phone: app-private data cannot be read over adb on a release build; the
#        phone's safety net is LAN sync (the PC holds a full copy) and the
#        in-app export. See docs/RELEASE.md.
#
# Usage: scripts/backup-data.sh --linux

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

BACKUP_ROOT="$HOME/.local/share/viplayer-backups"
KEEP=10

case "${1:-}" in
  --linux) ;;
  *) die "Usage: scripts/backup-data.sh --linux" ;;
esac

if ! ls "$LINUX_DATA_DIR"/viplayer.sqlite* >/dev/null 2>&1; then
  echo "No database yet in $LINUX_DATA_DIR — nothing to back up."
  exit 0
fi

dest="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
step "Backing up database to $dest"
mkdir -p "$dest"
cp -a "$LINUX_DATA_DIR"/viplayer.sqlite* "$dest/"

# Rotate: keep the newest $KEEP backups.
ls -1dt "$BACKUP_ROOT"/*/ 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -rf
