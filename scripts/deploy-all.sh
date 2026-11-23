#!/usr/bin/env bash
#
# One command to update ViPlayer everywhere after code changes.
#
#   1. code generation
#   2. analyzer + tests — a failing check stops everything
#   3. desktop: DB backup, build, atomic install
#   4. phone:   versionCode bump, signed APK, published for LAN updates;
#               `adb install -r` too if the phone is connected (keeps data)
#
# Without adb the phone updates itself: after its next sync with this PC it
# downloads the APK and offers "Install" (docs/RELEASE.md → "Updates over
# the network"). The PC app must be running then — it serves the file.
#
# Usage:
#   scripts/deploy-all.sh              # PC + phone
#   scripts/deploy-all.sh --linux      # desktop only
#   scripts/deploy-all.sh --phone      # phone only
#   scripts/deploy-all.sh --lan        # phone over the network only, no adb
#   scripts/deploy-all.sh --no-checks  # skip analyze/tests (not recommended)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_flutter

do_linux=true do_phone=true checks=true use_adb=true
for arg in "$@"; do
  case "$arg" in
    --linux) do_phone=false ;;
    --phone) do_linux=false ;;
    --lan) use_adb=false ;;
    --no-checks) checks=false ;;
    *) die "Unknown option: $arg (use --linux, --phone, --lan, --no-checks)" ;;
  esac
done

# Offers an APK to paired phones: the PC app serves update.json + the APK
# from its data folder (SyncService), phones download and verify it.
publish_update() {
  local apk="$1" aapt2 code name sha dir
  [ -f "$apk" ] || die "No APK to publish: $apk"
  aapt2="$(ls "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"
  [ -x "$aapt2" ] || die "aapt2 not found (Android SDK build-tools) — needed to read the APK's versionCode"
  # The APK's own versionCode: per-ABI builds add an offset (arm64: 2000+).
  code="$("$aapt2" dump badging "$apk" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -1)"
  name="$("$aapt2" dump badging "$apk" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p" | head -1)"
  [ -n "$code" ] || die "Could not read the versionCode of $apk"
  sha="$(sha256sum "$apk" | cut -d' ' -f1)"
  dir="$LINUX_DATA_DIR/update"
  mkdir -p "$dir"
  # APK first, then the info that points at it: a phone never sees an
  # update.json whose file is not there yet.
  cp "$apk" "$dir/viplayer.apk.tmp" && mv "$dir/viplayer.apk.tmp" "$dir/viplayer.apk"
  printf '{"versionCode": %s, "versionName": "%s", "sha256": "%s", "size": %s}\n' \
    "$code" "$name" "$sha" "$(stat -c %s "$apk")" > "$dir/update.json.tmp"
  mv "$dir/update.json.tmp" "$dir/update.json"
  step "Offered to phones over the network: $name (versionCode $code)"
}

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

  publish_update "$OUT/app-arm64-v8a-release.apk"

  ADB="$(command -v adb || true)"
  if ! $use_adb; then
    echo "   The phone picks it up at its next sync with this PC."
  elif [ -z "$ADB" ]; then
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
