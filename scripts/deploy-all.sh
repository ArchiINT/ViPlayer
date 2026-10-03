#!/usr/bin/env bash
#
# One command to update ViPlayer everywhere after code changes.
#
#   1. code generation
#   2. analyzer + tests — a failing check stops everything
#   3. desktop: DB backup, build, atomic install
#   4. phone:   versionCode bump, signed APK, `adb install -r` (keeps data)
#
# The phone is reached over USB or Wi-Fi (`adb connect <phone-ip>:<port>`,
# see docs/RELEASE.md).
#
# Usage:
#   scripts/deploy-all.sh              # PC + phone
#   scripts/deploy-all.sh --linux      # desktop only
#   scripts/deploy-all.sh --phone      # phone only
#   scripts/deploy-all.sh --no-checks  # skip analyze/tests (not recommended)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_flutter

do_linux=true do_phone=true checks=true
for arg in "$@"; do
  case "$arg" in
    --linux) do_phone=false ;;
    --phone) do_linux=false ;;
    --no-checks) checks=false ;;
    *) die "Unknown option: $arg (use --linux, --phone, --no-checks)" ;;
  esac
done

if $do_phone && [ ! -f "$PROJECT_DIR/android/key.properties" ]; then
  die "No release key (android/key.properties). Run scripts/create-keystore.sh once."
fi

codegen
$checks && verify

if $do_linux; then
  "$PROJECT_DIR/scripts/install-linux-desktop.sh" --skip-codegen
  warn "Restart ViPlayer on the PC to use the new version."
fi

if $do_phone; then
  step "Phone: bumping versionCode"
  "$PROJECT_DIR/scripts/bump-version.sh"
  # Always per-ABI APKs: a third of the universal size (the audio engine is
  # bundled per CPU type). Flutter offsets versionCode per ABI, so deploys
  # must stay per-ABI from now on — see docs/RELEASE.md.
  "$PROJECT_DIR/scripts/build-apk.sh" --skip-codegen --split
  OUT="$PROJECT_DIR/build/app/outputs/flutter-apk"

  ADB="$(command -v adb || true)"
  if [ -z "$ADB" ]; then
    warn "adb not found — copy the APK for your phone (usually arm64-v8a) from: $OUT"
  elif [ "$("$ADB" get-state 2>/dev/null || true)" != "device" ]; then
    warn "Phone not connected. Connect via USB or 'adb connect <ip>:<port>', then:"
    echo "   adb install -r $OUT/app-arm64-v8a-release.apk"
  else
    ABI="$("$ADB" shell getprop ro.product.cpu.abi | tr -d '\r')"
    APK="$OUT/app-$ABI-release.apk"
    [ -f "$APK" ] || die "No APK for the phone's CPU ($ABI) in $OUT"
    step "Installing on phone ($ABI, data is kept)"
    # Never uninstall automatically. If the signature differs, stop and
    # explain instead of wiping the user's data.
    if ! out="$("$ADB" install -r "$APK" 2>&1)"; then
      echo "$out"
      if grep -q 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' <<<"$out"; then
        die "The installed app is signed with a different key. Nothing was changed. See docs/RELEASE.md → 'Signature mismatch'."
      fi
      if grep -q 'INSTALL_FAILED_VERSION_DOWNGRADE' <<<"$out"; then
        die "The phone has a newer versionCode. Nothing was changed. See docs/RELEASE.md → 'Versions'."
      fi
      die "adb install failed — the installed app was left untouched."
    fi
    echo "$out" | tail -1
  fi
fi

step "All done"
