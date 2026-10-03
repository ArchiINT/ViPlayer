#!/usr/bin/env bash
#
# Run after changing lib/core/database/tables.dart (and bumping schemaVersion
# in app_database.dart). Regenerates Drift code, saves a snapshot of the new
# schema in drift_schemas/ and generates migration tests in test/drift/.
# Commit the generated files — the tests guarantee that upgrading from every
# previous version keeps the user's data.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_flutter

codegen
step "Schema snapshot + migration tests"
cd "$PROJECT_DIR"
"$DART" run drift_dev make-migrations
"$FLUTTER" test test/drift
