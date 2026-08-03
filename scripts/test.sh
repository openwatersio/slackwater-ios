#!/bin/zsh
# Run the test suite on both reference simulators.
#
#   ./scripts/test.sh              fast plan  — iterate with this
#   ./scripts/test.sh --full       full plan  — live IWLS + on-device fits; before an upload
#   SHOT_DIR=/tmp/shots ./scripts/test.sh     where the UI tests save their screenshots
#   SLACKWATER_SIMS='A,B' ./scripts/test.sh   run on other devices (CI sets this)
#
# The two plans live in TestPlans/ and are checked in; see docs/testflight.md.
set -euo pipefail
cd "$(dirname "$0")/.."

PLAN=Slackwater
[[ "${1:-}" == "--full" ]] && PLAN=Slackwater-Full

# TEST_RUNNER_ prefix: xcodebuild strips it and sets the rest on the UI-test
# RUNNER process, which is where ScreenshotTests reads M1_SHOT_DIR. A bare
# M1_SHOT_DIR in this shell never reaches it (the tests fall back to /tmp).
export TEST_RUNNER_M1_SHOT_DIR="${SHOT_DIR:-/tmp/slackwater-shots}"
mkdir -p "$TEST_RUNNER_M1_SHOT_DIR"

xcodegen generate

# The self-hosted runner is the same Mac we develop on, and two xcodebuild runs
# booting the same simulator device SIGKILL each other's test runner — the
# failures read as "Test crashed with signal kill" and results even bleed across
# the two sessions. CI passes its own device names here so it can never share a
# device with a local run (see .github/workflows/ci.yml).
sims=("iPhone 17" "iPad Pro 11-inch (M5)")
[[ -n "${SLACKWATER_SIMS:-}" ]] && sims=("${(@s/,/)SLACKWATER_SIMS}")

for sim in "${sims[@]}"; do
  echo "=== $PLAN · $sim ==="
  start=$SECONDS
  bundle="build/results-$PLAN-${sim// /_}.xcresult"
  rm -rf "$bundle"   # xcodebuild refuses to overwrite one
  # -clonedSourcePackagesDirPath: repo-local SPM cache, never the Xcode GUI's
  # (docs/testflight.md — two resolvers on the MapLibre artifact corrupt it).
  xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
    -testPlan "$PLAN" -destination "platform=iOS Simulator,name=$sim" \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -resultBundlePath "$bundle" \
    | tail -40
  echo "=== $PLAN · $sim: $((SECONDS - start))s ==="
done
