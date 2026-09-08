#!/bin/zsh
# Run the test suite.
#
#   ./scripts/test.sh              fast run   — iPhone only; iterate with this
#   ./scripts/test.sh --full       full run   — offline, both simulators + data sweep
#   ./scripts/test.sh --unit       unit target only, one simulator
#   ./scripts/test.sh --live       live IWLS smoke only, one simulator
#   SHOT_DIR=/tmp/shots ./scripts/test.sh     where the UI tests save their screenshots
#   SLACKWATER_SIMS='A,B' ./scripts/test.sh   run on other devices (CI sets this)
#
# One plan (TestPlans/Slackwater.xctestplan), selected by mode below.
set -euo pipefail

MODE=fast
case $#:${1:-} in
  0:) ;;
  1:--full) MODE=full ;;
  1:--unit) MODE=unit ;;
  1:--live) MODE=live ;;
  *) print -u2 "usage: $0 [--full|--unit|--live]"; exit 2 ;;
esac

# Live access is opt-in per invocation. Do not let a parent shell turn an
# offline run live, including through the retired full-mode switch.
unset TEST_RUNNER_SLACKWATER_LIVE SLACKWATER_LIVE
unset TEST_RUNNER_SLACKWATER_FULL SLACKWATER_FULL
[[ $MODE == live ]] && export TEST_RUNNER_SLACKWATER_LIVE=1

sims=("iPhone 17")
[[ $MODE == full ]] && sims+=("iPad Pro 11-inch (M5)")
if (( ${+SLACKWATER_SIMS} )); then
  [[ -n $SLACKWATER_SIMS ]] || { print -u2 "SLACKWATER_SIMS must name a device"; exit 2; }
  sims=("${(@s/,/)SLACKWATER_SIMS}")
  for sim in "${sims[@]}"; do
    [[ -n $sim ]] || { print -u2 "SLACKWATER_SIMS contains an empty device"; exit 2; }
  done
fi
if [[ $MODE == unit || $MODE == live ]]; then
  [[ ${#sims} == 1 ]] || { print -u2 "$MODE mode requires exactly one simulator"; exit 2; }
fi

# One test run at a time on this machine. Two concurrent `xcodebuild test` runs
# SIGKILL each other's test runner — every UI test in the losing run reports
# "Test crashed with signal kill" with zero assertion failures, which reads as a
# real failure and isn't one. Separate simulator devices do NOT avoid it: CI died
# this way five times on 2026-08-02, the last with CI and a local run on
# different devices. Whoever gets here second waits.
#
# The lock covers `xcodebuild test` and NOTHING ELSE. A bare `xcodebuild build`
# or `build-for-testing` in this worktree takes no lock and writes the same
# DerivedData, so running one while tests are in flight swaps Slackwater.app out
# from under the live run. Every remaining UI test then fails with "Cannot launch
# simulated executable: no file found at .../Slackwater.app" — zero assertion
# failures, which again reads as a real regression and isn't one. Same shape if
# you kill a run and then clean its DerivedData. Don't run any xcodebuild in a
# worktree that has tests running; wait for the lock like everyone else.
#
# lockf(1) holds the lock in the kernel for the lifetime of the process, so a
# killed or cancelled run releases it — a lock file with a PID in it would wedge
# the next run instead. Re-exec before the cd below, while $0 still resolves
# against the caller's directory.
if [[ -z "${SLACKWATER_TEST_LOCK:-}" ]]; then
  export SLACKWATER_TEST_LOCK=1
  lockf -t 0 /tmp/slackwater-test.lock true 2>/dev/null \
    || echo "another test run holds /tmp/slackwater-test.lock — waiting for it"
  exec lockf /tmp/slackwater-test.lock "$0" "$@"
fi

cd "$(dirname "$0")/.."

# TEST_RUNNER_ prefix: xcodebuild strips it and sets the rest on the UI-test
# RUNNER process, which is where ScreenshotTestCase reads M1_SHOT_DIR. A bare
# M1_SHOT_DIR in this shell never reaches it (the tests fall back to /tmp).
export TEST_RUNNER_M1_SHOT_DIR="${SHOT_DIR:-/tmp/slackwater-shots}"
mkdir -p "$TEST_RUNNER_M1_SHOT_DIR"

[[ $MODE == live ]] || node scripts/iwls-fixtures.mjs prepare
xcodegen generate

# SLACKWATER_SIMS overrides the fast/full device list outright — CI sets it to
# ONE device so the fast lane stays iPhone-only (see .github/workflows/ci.yml).
# It is not concurrency protection: separate devices don't stop concurrent runs
# from killing each other (see the lock comment at the top), the lock does.
#
# Fast is iPhone-only. Measured on build 27: the iPad leg costs 1169 s and is
# the ONLY place three tests run (testM44IPadSplit,
# testM50DetailSwapsBetweenSameKindStations, testM52IPadAutoSelectsTheFirstStation
# — 100 s between them). The other 34 UI tests it runs are a second rendering of
# what the iPhone leg just proved. Nineteen minutes for 100 s of unique coverage
# is a pre-release check, not an every-commit one, so --full keeps both.
# testHybridDirectionHasFullCoverageAndMatchesBaseline sweeps all 2,776 bundled
# stations x 20 times, each a 30-hour extremes search: 18 s, which is 86% of the
# whole unit target's 21 s. It validates stations.json — it can only change when
# the BUNDLE changes, never when app code does — so it rides the full plan with
# the other data-shaped checks. -skip-testing rather than an env gate: the
# TEST_RUNNER_ route below reaches the UI-test runner process only, never the
# app process that hosts the unit bundle.
selection=()
case $MODE in
  fast) selection=(-skip-testing:SlackwaterUITests/LiveFetchTests -skip-testing:SlackwaterTests/NationalScaleTests/testHybridDirectionHasFullCoverageAndMatchesBaseline) ;;
  full) selection=(-skip-testing:SlackwaterUITests/LiveFetchTests) ;;
  unit) selection=(-only-testing:SlackwaterTests) ;;
  live) selection=(-only-testing:SlackwaterUITests/LiveFetchTests) ;;
esac

for sim in "${sims[@]}"; do
  echo "=== $MODE · $sim ==="
  start=$SECONDS
  bundle="build/results-$MODE-${sim// /_}.xcresult"
  rm -rf "$bundle"   # xcodebuild refuses to overwrite one
  # -clonedSourcePackagesDirPath: repo-local SPM cache, never the Xcode GUI's
  # (docs/testflight.md — two resolvers on the MapLibre artifact corrupt it).
  #
  # SlackwaterUITests is parallelizable in the plan, so xcodebuild clones the
  # simulator and distributes the UI-test CLASSES across the clones. All the
  # live-IWLS tests sit in one class (LiveFetchTests) so they stay sequential.
  # The clones live inside this one xcodebuild, so the lock above still covers
  # the whole run. Worker count is a MEMORY budget, not a core count: a booted
  # iOS simulator clone costs ~2.2 GB, and on a 16 GB machine with a normal
  # desktop running, four clones push swap past physical RAM — load average
  # then counts thousands of page-in-blocked threads (430 observed, CPU 89%
  # idle), SpringBoard frames stall for seconds, and taps drop. Two clones fit
  # on 16 GB; set SLACKWATER_WORKERS to the machine's budget (CI sets 1 — a
  # hosted arm runner has ~7 GB).
  xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
    -testPlan Slackwater -destination "platform=iOS Simulator,name=$sim" \
    -parallel-testing-worker-count "${SLACKWATER_WORKERS:-2}" \
    "${selection[@]}" \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -resultBundlePath "$bundle" \
    | tail -40
  echo "=== $MODE · $sim: $((SECONDS - start))s ==="
done
