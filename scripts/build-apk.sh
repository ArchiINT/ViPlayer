#!/usr/bin/env bash
#
# Builds a signed release APK.
#
# Refuses to build without the permanent release key (android/key.properties):
# a debug-signed APK on the phone would force an uninstall (= data loss) the
# first time a properly signed build is installed. Use --allow-debug-key only
# for throwaway test builds.
#
# Usage:
#   scripts/build-apk.sh                    # universal APK
#   scripts/build-apk.sh --split            # smaller per-ABI APKs
#   scripts/build-apk.sh --allow-debug-key  # test build, never install over a real one

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_flutter

split=false allow_debug=false skip_codegen=false
for arg in "$@"; do
  case "$arg" in
    --split) split=true ;;
    --allow-debug-key) allow_debug=true ;;
    --skip-codegen) skip_codegen=true ;; # used by deploy-all.sh
    *) die "Unknown option: $arg" ;;
  esac
done

if [ ! -f "$PROJECT_DIR/android/key.properties" ]; then
  $allow_debug || die "No release key (android/key.properties). Run scripts/create-keystore.sh first."
  warn "Building with the DEBUG key — do not install over a release build."
fi

$skip_codegen || codegen

step "Building release APK"
cd "$PROJECT_DIR"
# The build talks to adb and may restart its server, which drops a phone
# connected over USB. Give the build its own adb server on another port.
export ANDROID_ADB_SERVER_PORT=5039
if $split; then
  "$FLUTTER" build apk --release --split-per-abi
else
  "$FLUTTER" build apk --release
fi

command -v adb >/dev/null && adb kill-server >/dev/null 2>&1 || true
unset ANDROID_ADB_SERVER_PORT

echo
ls -1 "$PROJECT_DIR"/build/app/outputs/flutter-apk/*.apk
