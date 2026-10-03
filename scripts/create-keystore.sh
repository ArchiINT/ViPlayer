#!/usr/bin/env bash
#
# One-time: creates the permanent Android release signing key and
# android/key.properties.
#
# Every APK must be signed with THE SAME key, otherwise Android refuses to
# update the installed app without uninstalling it (= losing its data).
# Back up the .jks file and the password somewhere safe.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

KEYSTORE="${KEYSTORE:-$HOME/viplayer-release.jks}"
PROPS="$PROJECT_DIR/android/key.properties"
ALIAS="viplayer"

[ -f "$PROPS" ] && die "$PROPS already exists — the key is set up. Not overwriting."
[ -f "$KEYSTORE" ] && die "$KEYSTORE already exists. Write android/key.properties by hand (see docs/RELEASE.md)."
command -v keytool >/dev/null || die "keytool not found (install jdk17-openjdk)"

read -rsp "Choose a keystore password (min 6 chars): " PASS; echo
read -rsp "Repeat password: " PASS2; echo
[ "$PASS" = "$PASS2" ] || die "Passwords do not match"
[ ${#PASS} -ge 6 ] || die "Password too short"

keytool -genkeypair -v -keystore "$KEYSTORE" -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 36500 -alias "$ALIAS" \
  -storepass "$PASS" -keypass "$PASS" -dname "CN=ViPlayer"

umask 077
cat > "$PROPS" <<PROPS_EOF
storePassword=$PASS
keyPassword=$PASS
keyAlias=$ALIAS
storeFile=$KEYSTORE
PROPS_EOF

step "Done"
echo "Keystore: $KEYSTORE"
echo "Config:   $PROPS (git-ignored)"
warn "BACK UP $KEYSTORE AND THE PASSWORD. Losing them means future updates"
warn "cannot be installed over the current app without wiping its data."
