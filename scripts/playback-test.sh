#!/usr/bin/env bash
#
# End-to-end playback check on the Linux desktop: real engine (libmpv),
# muted. Your library and settings are not touched (temporary XDG dirs).
#
# Usage: scripts/playback-test.sh <music-dir>
#   <music-dir> must contain a "ViPlayer" folder with a few audio files.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_flutter

MUSIC="${1:?usage: scripts/playback-test.sh <music-dir>}"
DATA="$(mktemp -d)"
trap 'rm -rf "$DATA"' EXIT

cd "$PROJECT_DIR"
step "Playback test (real engine, muted)"
XDG_DATA_HOME="$DATA" XDG_MUSIC_DIR="$MUSIC" \
  "$FLUTTER" test integration_test/playback_test.dart -d linux
