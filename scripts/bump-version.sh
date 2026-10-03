#!/usr/bin/env bash
#
# Bumps the version in pubspec.yaml.
#
# The build number (after "+") becomes Android's versionCode and must only
# ever grow: Android refuses to install a lower versionCode over a higher one
# without wiping data.
#
# Usage:
#   scripts/bump-version.sh           # 1.2.3+7 -> 1.2.3+8   (build only)
#   scripts/bump-version.sh patch     # 1.2.3+7 -> 1.2.4+8
#   scripts/bump-version.sh minor     # 1.2.3+7 -> 1.3.0+8
#   scripts/bump-version.sh major     # 1.2.3+7 -> 2.0.0+8

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

PUBSPEC="$PROJECT_DIR/pubspec.yaml"
current="$(grep -E '^version: ' "$PUBSPEC" | sed -E 's/^version: //')"
[[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]] \
  || die "Unexpected version format in pubspec.yaml: '$current'"

major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}
build=$(( BASH_REMATCH[4] + 1 ))

case "${1:-build}" in
  build) ;;
  patch) patch=$((patch + 1)) ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  major) major=$((major + 1)); minor=0; patch=0 ;;
  *) die "Unknown part '$1' (use: build | patch | minor | major)" ;;
esac

next="$major.$minor.$patch+$build"
sed -i -E "s/^version: .*/version: $next/" "$PUBSPEC"
echo "version: $current -> $next"
