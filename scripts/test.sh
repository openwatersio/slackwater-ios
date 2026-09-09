#!/bin/zsh
# Run the test suite.
#
#   ./scripts/test.sh              fast run   — iPhone only; iterate with this
#   ./scripts/test.sh --full       full run   — both simulators + live IWLS and
#                                               on-device fits; before an upload
#   SHOT_DIR=/tmp/shots ./scripts/test.sh     where the UI tests save their screenshots
#   SLACKWATER_SIMS='A,B' ./scripts/test.sh   run on other devices (CI sets this)
#
# One plan (TestPlans/Slackwater.xctestplan). The live-IWLS UI tests skip
# themselves unless SLACKWATER_FULL reaches the runner; see docs/testflight.md.
set -euo pipefail

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

MODE=fast
if [[ "${1:-}" == "--full" ]]; then
  MODE=full
  # TEST_RUNNER_ prefix (same mechanism as M1_SHOT_DIR below): reaches
  # ScreenshotTestCase.skipUnlessFull, which otherwise skips the live-IWLS
  # tests — all of them in LiveFetchTests.
  export TEST_RUNNER_SLACKWATER_FULL=1
fi

# TEST_RUNNER_ prefix: xcodebuild strips it and sets the rest on the UI-test
# RUNNER process, which is where ScreenshotTestCase reads M1_SHOT_DIR. A bare
# M1_SHOT_DIR in this shell never reaches it (the tests fall back to /tmp).
export TEST_RUNNER_M1_SHOT_DIR="${SHOT_DIR:-/tmp/slackwater-shots}"
mkdir -p "$TEST_RUNNER_M1_SHOT_DIR"

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
types=("iPhone 17")
[[ $MODE == full ]] && types+=("iPad Pro 11-inch (M5)")

# The script drives its OWN devices, erased before every run.
#
# A simulator anyone has used accumulates state that survives app uninstalls —
# a location permission grant, a simulated fix, an App Group plist — and
# `xcodebuild test` clones inherit all of it. That costs correctness in both
# directions (tests that fail only here, tests that pass only here, both
# documented in CLAUDE.md), and it costs TIME. Measured 2026-09-09, same two
# tests, same commit:
#
#   testReturnToNowFromHistory        264 s used device   24 s erased   25 s CI
#   testFastTideCommentaryNamesTheRate 141 s used device   22 s erased   28 s CI
#
# The app stays busy behind an inherited fix, and XCUITest waits for the app to
# go quiet before every query — so a dirty device does not fail, it crawls.
# Erased, this Mac matches the hosted runner test for test, which is the point:
# CI gets a fresh runner image every run, so an erased device is the only local
# configuration that runs the same experiment CI does.
#
# Its own devices, never yours. `Slackwater <type>` is created on first run;
# your `iPhone 17` keeps the favourites you put there. An explicit
# SLACKWATER_SIMS is taken as given and NOT erased for the same reason — it may
# be the device you use by hand.
own_sim() {
  local type=$1 name="Slackwater $1" found count udid
  found=$(xcrun simctl list devices available | grep -F "$name (") || true
  count=$(printf '%s' "$found" | grep -c . || true)
  # Two devices with one name is not hypothetical — it has happened here, and
  # `-destination name=` then fails with "multiple devices matched". Refuse
  # rather than guess which one; the run below addresses the device by id.
  if [[ $count -gt 1 ]]; then
    echo "error: $count simulators are named '$name'. Delete the extras:" >&2
    printf '%s\n' "$found" >&2
    exit 1
  fi
  if [[ $count -eq 0 ]]; then
    udid=$(xcrun simctl create "$name" "$type")
  else
    udid=$(printf '%s' "$found" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  fi
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl erase "$udid"
  printf '%s' "$udid"
}

sims=(); dests=()
if [[ -n "${SLACKWATER_SIMS:-}" ]]; then
  for name in "${(@s/,/)SLACKWATER_SIMS}"; do
    sims+=("$name"); dests+=("platform=iOS Simulator,name=$name")
  done
else
  for type in "${types[@]}"; do
    udid=$(own_sim "$type")
    sims+=("$type"); dests+=("platform=iOS Simulator,id=$udid")
  done
fi

# testHybridDirectionHasFullCoverageAndMatchesBaseline sweeps all 2,776 bundled
# stations x 20 times, each a 30-hour extremes search: 18 s, which is 86% of the
# whole unit target's 21 s. It validates stations.json — it can only change when
# the BUNDLE changes, never when app code does — so it rides the full plan with
# the other data-shaped checks. -skip-testing rather than an env gate: the
# TEST_RUNNER_ route below reaches the UI-test runner process only, never the
# app process that hosts the unit bundle.
skip=()
[[ $MODE == fast ]] && skip=(-skip-testing:SlackwaterTests/NationalScaleTests/testHybridDirectionHasFullCoverageAndMatchesBaseline)

# One shard's share of the suite, comma-separated. CI's matrix sets exactly one
# of these per shard (.github/workflows/ci.yml); a local run sets neither and
# gets the lot.
#
# SLACKWATER_SKIP is what makes the split safe to leave alone: the last shard
# names no tests of its own, it skips the other three, so a class added later
# runs there rather than running nowhere and reporting green.
[[ -n "${SLACKWATER_ONLY:-}" ]] && for t in "${(@s/,/)SLACKWATER_ONLY}"; do skip+=("-only-testing:$t"); done
[[ -n "${SLACKWATER_SKIP:-}" ]] && for t in "${(@s/,/)SLACKWATER_SKIP}"; do skip+=("-skip-testing:$t"); done

# A run is only evidence if the source held still for it. This Mac carries a
# dozen worktrees and several agent sessions, and a second session editing a
# test mid-suite produces a failure that belongs to code you never ran — which
# has already cost one wrong diagnosis, twice: an in-progress assertion read as
# a stale-simulator problem, and a passing suite credited to the wrong commit.
# The lock stops two xcodebuild runs colliding; nothing stopped this.
srcmark=$(mktemp)
trap 'rm -f "$srcmark"' EXIT

for i in {1..$#sims}; do
  sim=$sims[$i]
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
    -testPlan Slackwater -destination "$dests[$i]" \
    -parallel-testing-worker-count "${SLACKWATER_WORKERS:-2}" \
    "${skip[@]}" \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -resultBundlePath "$bundle" \
    | tail -40
  echo "=== $MODE · $sim: $((SECONDS - start))s ==="
done

# Not fatal: the run may well be clean, and the person editing is entitled to.
# But the result stops being evidence, and that has to be said out loud rather
# than discovered later from a confusing failure.
changed=$(find Slackwater SlackwaterTests SlackwaterUITests project.yml \
  -newer "$srcmark" \( -name '*.swift' -o -name 'project.yml' \) 2>/dev/null)
if [[ -n "$changed" ]]; then
  echo "warning: source changed while the suite ran — this result is not evidence for any commit:"
  printf '  %s\n' ${(f)changed}
fi
