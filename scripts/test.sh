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

# One xcodebuild at a time per WORKTREE. build/xcodebuild.lock covers this
# worktree's DerivedData: a bare `xcodebuild build` or `build-for-testing` here
# writes the same DerivedData, so running one while tests are in flight swaps
# Slackwater.app out from under the live run. Every remaining UI test then fails
# with "Cannot launch simulated executable: no file found at .../Slackwater.app"
# — zero assertion failures, which reads as a real regression and isn't one.
# Same shape if you kill a run and then clean its DerivedData. Builds take this
# lock too (CONTRIBUTING.md, "Local test runs", has the recipe).
#
# Other worktrees' runs are not waited for. Runs on separate devices with
# separate DerivedData do not disturb each other: measured 2026-10-01, two runs
# overlapped for eight minutes with four clones each, no "Test crashed with
# signal kill" in either (the signature that justified a machine-wide lock on
# 2026-08-02, when DerivedData was still shared — docs/testflight.md). What
# overlap does cost is speed, ~2× on UI waits, which the PERF_SCALE default
# below absorbs.
#
# lockf(1) holds the lock in the kernel for the lifetime of the process, so a
# killed or cancelled run releases it — a lock file with a PID in it would wedge
# the next run instead. Re-exec before the cd below, while $0 still resolves
# against the caller's directory.
if [[ -z "${SLACKWATER_TEST_LOCK:-}" ]]; then
  export SLACKWATER_TEST_LOCK=1
  wtlock="$(dirname "$0")/../build/xcodebuild.lock"
  mkdir -p "${wtlock:h}"
  lockf -t 0 "$wtlock" true 2>/dev/null \
    || echo "an xcodebuild holds $wtlock — waiting for it"
  exec lockf "$wtlock" "$0" "$@"
fi

cd "$(dirname "$0")/.."

# TEST_RUNNER_ prefix: xcodebuild strips it and sets the rest on the UI-test
# RUNNER process, which is where ScreenshotTestCase reads M1_SHOT_DIR. A bare
# M1_SHOT_DIR in this shell never reaches it (the tests fall back to /tmp).
export TEST_RUNNER_M1_SHOT_DIR="${SHOT_DIR:-/tmp/slackwater-shots}"
mkdir -p "$TEST_RUNNER_M1_SHOT_DIR"

# Every wait in the UI target and the unit tests' wall-clock budgets were
# calibrated on this Mac running one suite alone. Several worktrees now run at
# once, and under overlap the same tests ran ~2× slower (31/42/45 s alone,
# 50/91/71 s overlapped) and three of twelve tripped their waits. CI sets 4 for
# its runners (.github/workflows/ci.yml) and that is taken as given.
export TEST_RUNNER_SLACKWATER_PERF_SCALE="${TEST_RUNNER_SLACKWATER_PERF_SCALE:-2}"

# SLACKWATER_XCTESTRUN names a .xctestrun from an earlier build-for-testing
# (CI builds once and shards the tests across jobs). The fixture is compiled
# into the unit-test bundle, so that build already staged it.
if [[ -z "${SLACKWATER_XCTESTRUN:-}" ]]; then
  [[ $MODE == live ]] || node scripts/iwls-fixtures.mjs prepare
  xcodegen generate
fi

# SLACKWATER_SIMS overrides the fast/full device list outright — CI sets it to
# ONE device so the fast lane stays iPhone-only (see .github/workflows/ci.yml).
# Separate devices still share this worktree's DerivedData, so its lock also
# covers runs with different device selections (see the lock comment above).
#
# Fast is iPhone-only. Measured on build 27: the iPad leg costs 1169 s and is
# the ONLY place three tests run (testM44IPadSplit,
# testM50DetailSwapsBetweenSameKindStations, testM52IPadAutoSelectsTheFirstStation
# — 100 s between them). The other 34 UI tests it runs are a second rendering of
# what the iPhone leg just proved. Nineteen minutes for 100 s of unique coverage
# is a pre-release check, not an every-commit one, so --full keeps both.
# The script drives its OWN devices, erased before every run.
#
# A simulator anyone has used accumulates state that survives app uninstalls —
# a location permission grant, a simulated fix, an App Group plist — and
# `xcodebuild test` clones inherit all of it. That costs correctness in both
# directions (tests that fail only here, tests that pass only here, both
# documented in CONTRIBUTING.md, "UI test state"), and it costs TIME.
# Measured 2026-09-09, same two tests, same commit:
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
# Its own devices, never yours, and one per WORKTREE: `Slackwater <type> ·
# <worktree>` is created on first run. Your `iPhone 17` keeps the favourites
# you put there, and another worktree's run must never erase or clone the base
# device this one is cloning — two runs booting one device was the first
# documented way to get "Test crashed with signal kill" (docs/testflight.md).
# An explicit SLACKWATER_SIMS is taken as given and NOT erased for the same
# reason — it may be the device you use by hand.
own_sim() {
  local type=$1 name="Slackwater $1 · ${PWD:t}" found count udid
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

dests=()
for sim in "${sims[@]}"; do
  if (( ${+SLACKWATER_SIMS} )); then
    dests+=("platform=iOS Simulator,name=$sim")
  else
    dests+=("platform=iOS Simulator,id=$(own_sim "$sim")")
  fi
done

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
# Never, because "on-failure" is not what it says. xcodebuild runs
# `simctl diagnose` on EVERY run and discards the result on success, and on
# this Mac the `log collect` inside the clone hangs until diagnose's own
# 600 s timeout: three UI tests (118 s) took 764 s, a 243 s unit run took 819 s,
# seven runs in three days, on iOS 27.0 and 27.2 devices, with one worker and
# four. The clone's logd then dies of XPC_EXIT_REASON_SIGTERM_TIMEOUT at
# teardown. Measured 2026-10-01 with `sample` on the hung simctl.
#
# The evidence #474 wanted survives: the screen recording and the UI
# hierarchy are XCTest attachments, not simctl diagnostics. A failing test
# under `never` left an .mp4 and the hierarchy .txt in an 11 MB bundle, 60 s
# end to end. Only the sysdiagnose-style simctl_diagnostics directory is gone.
diagnostics=never

# One shard's share of the suite, comma-separated. CI's matrix sets exactly one
# of these per shard (.github/workflows/ci.yml); a local run sets neither and
# gets the lot.
#
# SLACKWATER_SKIP is what makes the split safe to leave alone: the last shard
# names no tests of its own, it skips the other three, so a class added later
# runs there rather than running nowhere and reporting green.
[[ -n "${SLACKWATER_ONLY:-}" ]] && for t in "${(@s/,/)SLACKWATER_ONLY}"; do selection+=("-only-testing:$t"); done
[[ -n "${SLACKWATER_SKIP:-}" ]] && for t in "${(@s/,/)SLACKWATER_SKIP}"; do selection+=("-skip-testing:$t"); done

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
  # on 16 GB, so the default is one per 8 GB. It stops at four: the fast plan
  # has seven UI classes and xcodebuild distributes whole classes, so the
  # longest (DetailAndScrub) bounds the run past that, and every erased clone's
  # first boot spends ~10 cores on iOS widget rendering for a minute. CI sets
  # SLACKWATER_WORKERS=1 — a hosted arm runner has ~7 GB.
  workers=$(( $(sysctl -n hw.memsize) / 8589934592 ))
  (( workers < 2 )) && workers=2
  (( workers > 4 )) && workers=4
  workers=${SLACKWATER_WORKERS:-$workers}
  if [[ -n "${SLACKWATER_XCTESTRUN:-}" ]]; then
    action=(test-without-building -xctestrun "$SLACKWATER_XCTESTRUN")
  else
    action=(test -project Slackwater.xcodeproj -scheme Slackwater -testPlan Slackwater
            -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages)
  fi
  mkdir -p build
  rawlog="${bundle%.xcresult}.log"
  # XCTest must bound a blocked launch, including in downloaded test products (#580).
  set +e
  xcodebuild "${action[@]}" -destination "$dests[$i]" \
    -parallel-testing-worker-count "$workers" \
    -collect-test-diagnostics "$diagnostics" \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 600 \
    "${selection[@]}" \
    -resultBundlePath "$bundle" \
    2>&1 | tee "$rawlog" | tail -40
  command_status=$pipestatus[1]
  set -e
  # A shard that runs NOTHING exits 0 and reports green — which is the failure
  # mode sharding introduces, and the one nobody would notice. A typo in
  # SLACKWATER_ONLY, a class renamed out from under the matrix, and the lane
  # goes green faster than ever while testing nothing. So count what ran.
  ran=$(xcrun xcresulttool get test-results summary --path "$bundle" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    ran=d["passedTests"]+d["failedTests"]
    summary={k:d[k] for k in ("title","result","startTime","finishTime","passedTests","failedTests","skippedTests","totalTestCount") if k in d}
    summary["status"]="available"
except (ValueError,KeyError,TypeError):
    ran="unavailable"
    summary={"status":"unavailable"}
with open(sys.argv[1],"w") as f: json.dump(summary,f); f.write("\n")
if ran=="unavailable": sys.exit(1)
print(ran)' "${bundle%.xcresult}.summary.json" 2>/dev/null || echo unavailable)
  if [[ "$ran" == unavailable ]]; then
    echo "warning: test results unavailable on $sim — see $rawlog" >&2
  fi
  # XCUITest waits for the app to report its animations complete before every
  # synthesized event and every query, and spends 60 s on the wait when that
  # report never comes. A shard doing it repeatedly is measuring the timeout
  # and not the app (#556) — and it reads as nothing but a slow runner, since
  # the run still passes. Say it out loud.
  #
  # Out of the bundle's store, not the output above: xcodebuild prints the
  # activity text only when it runs the tests serially, and this script always
  # runs clones. `grep -o`, because the store is one long line.
  # `|| true` inside the pipe: grep exits 1 on no match, which under
  # `set -o pipefail` would fail the assignment and abort the run.
  idle=$({ grep -ao "animations complete notification not received" \
    "$bundle/database.sqlite3" 2>/dev/null || true; } | wc -l | tr -d ' ')
  if (( idle )); then
    echo "warning: $idle XCUITest idle timeouts on $sim, 60 s each (#556)"
  fi
  echo "=== $MODE · $sim: $((SECONDS - start))s · $ran tests ==="
  (( command_status == 0 )) || exit "$command_status"
  if [[ "$ran" == "0" ]]; then
    echo "error: no tests ran on $sim — check SLACKWATER_ONLY/SLACKWATER_SKIP" >&2
    exit 1
  fi
  [[ "$ran" != unavailable ]] || exit 1
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
