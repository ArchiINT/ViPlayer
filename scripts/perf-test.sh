#!/usr/bin/env bash
#
# Measures UI smoothness on the Linux desktop build (profile mode) against a
# throwaway library, and prints frame timings. Your real library and settings
# are not touched: the app runs with temporary XDG directories.
#
# Usage: scripts/perf-test.sh <music-dir>
#   <music-dir> must contain a "ViPlayer" folder with audio files; it is used
#   as the download folder, which the app always scans.
#
# Targets: 99th percentile frame build and raster time under 16 ms (60 fps).

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_flutter

MUSIC="${1:?usage: scripts/perf-test.sh <music-dir>}"
DATA="$(mktemp -d)"
trap 'rm -rf "$DATA"' EXIT

cd "$PROJECT_DIR"
step "Running perf test (profile build)"
XDG_DATA_HOME="$DATA" XDG_MUSIC_DIR="$MUSIC" \
  "$FLUTTER" drive -d linux --profile \
  --driver=test_driver/perf_driver.dart \
  --target=integration_test/perf_test.dart

step "Frame timings (ms)"
python3 - <<'PY'
import json
s = json.load(open('build/perf/library.timeline_summary.json'))
keys = [
    ('frame_count', 'frames'),
    ('average_frame_build_time_millis', 'build avg'),
    ('90th_percentile_frame_build_time_millis', 'build p90'),
    ('99th_percentile_frame_build_time_millis', 'build p99'),
    ('worst_frame_build_time_millis', 'build worst'),
    ('average_frame_rasterizer_time_millis', 'raster avg'),
    ('90th_percentile_frame_rasterizer_time_millis', 'raster p90'),
    ('99th_percentile_frame_rasterizer_time_millis', 'raster p99'),
    ('worst_frame_rasterizer_time_millis', 'raster worst'),
    ('missed_frame_build_budget_count', 'missed build budget'),
    ('missed_frame_rasterizer_budget_count', 'missed raster budget'),
]
for k, label in keys:
    v = s.get(k)
    if v is not None:
        print(f'  {label:22} {v:.2f}' if isinstance(v, float) else f'  {label:22} {v}')
PY
