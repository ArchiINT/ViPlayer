# Shared helpers for ViPlayer scripts. Sourced, not executed.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER="${FLUTTER:-$HOME/flutter/bin/flutter}"
DART="${DART:-$HOME/flutter/bin/dart}"

APP_ID="com.viplayer.app"
APK="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"
# Where the app keeps its database on Linux (getApplicationSupportDirectory).
LINUX_DATA_DIR="$HOME/.local/share/$APP_ID"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mxx %s\033[0m\n' "$*" >&2; exit 1; }

require_flutter() {
  [ -x "$FLUTTER" ] || die "Flutter not found at $FLUTTER (set FLUTTER=/path/to/flutter)"
}

# Regenerates Drift code and localizations. Safe to run any time.
codegen() {
  step "Code generation (pub get, build_runner, gen-l10n)"
  cd "$PROJECT_DIR"
  "$FLUTTER" pub get
  "$DART" run build_runner build --delete-conflicting-outputs
  "$FLUTTER" gen-l10n
}

# Analyzer + tests (incl. database migration tests). Aborts the deploy on
# failure, so a broken build never reaches the phone.
verify() {
  step "Checks (flutter analyze + flutter test)"
  cd "$PROJECT_DIR"
  "$FLUTTER" analyze
  "$FLUTTER" test
}
