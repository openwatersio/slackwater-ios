#!/bin/zsh
set -euo pipefail

root=${0:A:h:h}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/repo/scripts" "$scratch/repo/Slackwater" "$scratch/repo/SlackwaterTests" "$scratch/repo/SlackwaterUITests" "$scratch/bin"
touch "$scratch/repo/project.yml"  # the source-changed sweep at the end walks these
cp "$root/scripts/test.sh" "$scratch/repo/scripts/test.sh"
cp "$root/scripts/first-run.sh" "$scratch/repo/scripts/first-run.sh"
touch "$scratch/repo/scripts/iwls-fixtures.mjs"
log="$scratch/calls"

for tool in node open xcodegen xcodebuild sysctl; do
  cat > "$scratch/bin/$tool" <<'STUB'
#!/bin/zsh
[[ ${0:t} == sysctl ]] && { print 34359738368; exit 0; }
print -r -- "${0:t} $* | live=${TEST_RUNNER_SLACKWATER_LIVE:-} full=${TEST_RUNNER_SLACKWATER_FULL:-} perf=${TEST_RUNNER_SLACKWATER_PERF_SCALE:-}" >> "$CALL_LOG"
[[ ${0:t} == open && $* == '-a DeviceHub' && ${NO_DEVICE_HUB:-0} == 1 ]] && exit 1
[[ ${0:t} == node && ${FAIL_PREPARE:-0} == 1 ]] && {
  print -u2 -- "IWLS recording missing; run: node scripts/iwls-fixtures.mjs refresh"
  exit 1
}
# The idle-timeout text lives in the result bundle's store, so a run that
# spent its time there leaves it where the runner looks.
if [[ ${0:t} == xcodebuild && ${IDLE_TIMEOUTS:-0} -gt 0 ]]; then
  prev=""
  for a in "$@"; do
    [[ $prev == -resultBundlePath ]] && bundle=$a
    prev=$a
  done
  if [[ -n ${bundle:-} ]]; then
    mkdir -p "$bundle"
    repeat $IDLE_TIMEOUTS \
      print -n -- "animations complete notification not received" >> "$bundle/database.sqlite3"
  fi
fi
if [[ ${0:t} == xcodebuild ]]; then
  repeat 45 print "raw test output"
  print -u2 "raw stderr evidence"
  [[ ${FAIL_XCODEBUILD:-0} == 1 ]] && exit 65
fi
exit 0
STUB
  chmod +x "$scratch/bin/$tool"
done

# `xcrun simctl` is the script's own erased device (created fresh here, so the
# udid is whatever `create` prints); `xcrun xcresulttool` is what the ran-nothing
# guard reads. RAN_TESTS=0 simulates a shard whose selection matched no tests.
cat > "$scratch/bin/xcrun" <<'STUB'
#!/bin/zsh
print -r -- "xcrun $*" >> "$CALL_LOG"
case "$1 $2" in
  "simctl create") print "SIM-${3// /_}" ;;
  "xcresulttool get") [[ ${UNAVAILABLE_RESULTS:-0} == 1 ]] && exit 1; [[ ${UNAVAILABLE_RESULTS:-0} == 2 ]] && { print "partial JSON"; exit 0; }; print "{\"passedTests\": ${RAN_TESTS:-1}, \"failedTests\": 0}" ;;
esac
exit 0
STUB
chmod +x "$scratch/bin/xcrun"

cat > "$scratch/bin/lockf" <<'STUB'
#!/bin/zsh
print -r -- "lockf $*" >> "$CALL_LOG"
if [[ $1 == -t ]]; then exit 0; fi
shift
exec "$@"
STUB
chmod +x "$scratch/bin/lockf"

run_mode() {
  : > "$log"
  PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 \
    zsh "$scratch/repo/scripts/test.sh" "$@" >/dev/null
}

assert_has() { grep -Fq -- "$1" "$log" || { print -u2 -- "missing: $1"; cat "$log"; exit 1; }; }
assert_lacks() { ! grep -Fq -- "$1" "$log" || { print -u2 -- "unexpected: $1"; cat "$log"; exit 1; }; }
assert_count() { [[ $(grep -c -- "$1" "$log") == "$2" ]] || { print -u2 -- "wrong count: $1"; cat "$log"; exit 1; }; }

run_mode
assert_has "node scripts/iwls-fixtures.mjs prepare"
assert_has "xcrun simctl create Slackwater iPhone 17 · repo iPhone 17"
assert_has "xcrun simctl erase SIM-Slackwater_iPhone_17_·_repo"
assert_has "id=SIM-Slackwater_iPhone_17_·_repo"
assert_has "-skip-testing:SlackwaterUITests/LiveFetchTests"
assert_has "-skip-testing:SlackwaterTests/NationalScaleTests/testHybridDirectionHasFullCoverageAndMatchesBaseline"
assert_has "-collect-test-diagnostics never"
assert_has "-test-timeouts-enabled YES -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 600"
assert_has "-derivedDataPath build/DerivedData"
assert_lacks "live=1"
[[ $(sed -n '/^node /=' "$log") -lt $(sed -n '/^xcodegen /=' "$log") ]] || {
  print -u2 -- "fixture preparation did not precede XcodeGen"
  exit 1
}

run_mode --full
assert_count '^xcodebuild ' 2
assert_has "xcrun simctl create Slackwater iPad Pro 11-inch (M5) · repo iPad Pro 11-inch (M5)"
assert_has "id=SIM-Slackwater_iPad_Pro_11-inch_(M5)_·_repo"
assert_has "-skip-testing:SlackwaterUITests/LiveFetchTests"
assert_has "-collect-test-diagnostics never"
assert_lacks "NationalScaleTests"
assert_lacks "live=1"

run_mode --unit
assert_count '^xcodebuild ' 1
assert_has "-only-testing:SlackwaterTests"
assert_has "-collect-test-diagnostics never"
assert_lacks "NationalScaleTests"

run_mode --live
assert_count '^xcodebuild ' 1
assert_lacks "iwls-fixtures.mjs prepare"
assert_has "-only-testing:SlackwaterUITests/LiveFetchTests"
assert_has "-collect-test-diagnostics never"
assert_has "live=1 full="

TEST_RUNNER_SLACKWATER_LIVE=1 TEST_RUNNER_SLACKWATER_FULL=1 run_mode
assert_lacks "live=1"
assert_lacks "full=1"

# An explicit device is taken as given: addressed by name, never erased.
SLACKWATER_SIMS='Mine' run_mode
assert_has "name=Mine"
assert_lacks "simctl erase"
assert_lacks "simctl create"

# A prebuilt run tests the given products and never rebuilds or regenerates.
SLACKWATER_XCTESTRUN='products/Plan.xctestrun' run_mode
assert_has "xcodebuild test-without-building -xctestrun products/Plan.xctestrun"
assert_has "-test-timeouts-enabled YES -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 600"
assert_lacks "xcodegen"
assert_lacks "iwls-fixtures.mjs prepare"
assert_lacks "-derivedDataPath"

# CI's shard variables reach xcodebuild; a shard that ran nothing fails.
SLACKWATER_ONLY='A/B,C/D' SLACKWATER_SKIP='E/F' run_mode
assert_has "-only-testing:A/B -only-testing:C/D -skip-testing:E/F"
: > "$log"
if PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 RAN_TESTS=0 \
    zsh "$scratch/repo/scripts/test.sh" >/dev/null 2>&1; then
  print -u2 -- "runner reported green after running no tests"
  exit 1
fi
assert_has "xcodebuild test"

for args in '--wat' '--full --live'; do
  : > "$log"
  if PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 zsh -c "'$scratch/repo/scripts/test.sh' $args" >/dev/null 2>&1; then
    print -u2 -- "accepted invalid arguments: $args"
    exit 1
  fi
  [[ ! -s "$log" ]] || { print -u2 -- "invalid arguments ran tools"; exit 1; }
done

for mode in --unit --live; do
  : > "$log"
  if PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 SLACKWATER_SIMS='One,Two' \
      zsh "$scratch/repo/scripts/test.sh" "$mode" >/dev/null 2>&1; then
    print -u2 -- "$mode accepted multiple simulators"
    exit 1
  fi
  [[ ! -s "$log" ]] || { print -u2 -- "bad simulator override ran tools"; exit 1; }
done

: > "$log"
if PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 SLACKWATER_SIMS='' \
    zsh "$scratch/repo/scripts/test.sh" >/dev/null 2>&1; then
  print -u2 -- "runner accepted an empty simulator override"
  exit 1
fi
[[ ! -s "$log" ]] || { print -u2 -- "empty simulator override ran tools"; exit 1; }

: > "$log"
if PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 FAIL_PREPARE=1 \
    zsh "$scratch/repo/scripts/test.sh" >/dev/null 2>&1; then
  print -u2 -- "runner ignored fixture preparation failure"
  exit 1
fi
assert_has "node scripts/iwls-fixtures.mjs prepare"
assert_lacks "xcodegen"
assert_lacks "xcodebuild"

# The CI budget reaches xcodebuild as given; the default is clamped to 2–4.
SLACKWATER_WORKERS=1 run_mode --unit
assert_has "-parallel-testing-worker-count 1 "
run_mode --unit
grep -Eq -- '-parallel-testing-worker-count [234] ' "$log" || { print -u2 -- "default workers outside 2–4"; cat "$log"; exit 1; }
assert_lacks "-parallel-testing-enabled NO"

# CI tests on the device it booted and warmed, never a cold clone of it.
SLACKWATER_NO_CLONE=1 SLACKWATER_SIMS='Mine' SLACKWATER_WORKERS=1 \
  SLACKWATER_XCTESTRUN='products/Plan.xctestrun' run_mode --full
assert_has "-parallel-testing-enabled NO"
assert_lacks "-parallel-testing-worker-count"

# The wait scale defaults to 2 locally; CI's explicit value is taken as given.
run_mode --unit
assert_has "perf=2"
TEST_RUNNER_SLACKWATER_PERF_SCALE=4 run_mode --unit
assert_has "perf=4"

# Exercise the worktree-lock probe and the re-exec once; the table above
# bypasses them so each assertion can focus on a single mode decision. No
# machine-wide lock: that is what it checks.
: > "$log"
PATH="$scratch/bin:$PATH" CALL_LOG="$log" zsh "$scratch/repo/scripts/test.sh" --live >/dev/null
assert_count '^lockf ' 2
assert_has "lockf $scratch/repo/scripts/../build/xcodebuild.lock $scratch/repo/scripts/test.sh"
assert_lacks "slackwater-test.lock"
assert_has "xcodebuild test"

: > "$log"
PATH="$scratch/bin:$PATH" CALL_LOG="$log" zsh "$scratch/repo/scripts/first-run.sh" >/dev/null
assert_has "open -a DeviceHub"

: > "$log"
PATH="$scratch/bin:$PATH" CALL_LOG="$log" NO_DEVICE_HUB=1 \
  zsh "$scratch/repo/scripts/first-run.sh" >/dev/null 2>&1
assert_has "open -a Simulator"

# A run that spent its time on XCUITest's 60 s idle timeout says so. The line
# is xcodebuild's, `tail -40` drops it, and the result bundle carrying it only
# travels on a failure — so without this the lane is silently slow (#556).
out=$(PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 IDLE_TIMEOUTS=3 \
  zsh "$scratch/repo/scripts/test.sh" --unit)
[[ $out == *"warning: 3 XCUITest idle timeouts"* ]] \
  || { print -u2 -- "idle timeouts went unreported"; print -r -- "$out"; exit 1; }

out=$(PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 \
  zsh "$scratch/repo/scripts/test.sh" --unit)
[[ $out != *"idle timeouts"* ]] \
  || { print -u2 -- "a clean run warned anyway"; print -r -- "$out"; exit 1; }

# Failures still leave elapsed output, a raw log including stderr, and a summary.
set +e
out=$(PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 FAIL_XCODEBUILD=1 UNAVAILABLE_RESULTS=1 \
    zsh "$scratch/repo/scripts/test.sh" --unit 2>&1)
result=$?
set -e
[[ $result == 65 && $out == *"test results unavailable"* && $out == *"s · unavailable tests"* && $out != *"no tests ran"* ]] \
  || { print -u2 -- "failure status or diagnostics lost: $result $out"; exit 1; }
rawlog="$scratch/repo/build/results-unit-iPhone_17.log"
[[ $(grep -c '^raw test output$' "$rawlog") == 45 ]] || { print -u2 "raw output was truncated"; exit 1; }
grep -q '^raw stderr evidence$' "$rawlog"
grep -q '"status": "unavailable"' "${rawlog%.log}.summary.json"

# A successful command with unreadable results is unavailable, never zero.
set +e
out=$(PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 UNAVAILABLE_RESULTS=1 \
    zsh "$scratch/repo/scripts/test.sh" --unit 2>&1)
result=$?
set -e
[[ $result == 1 && $out == *"test results unavailable"* && $out != *"no tests ran"* ]] \
  || { print -u2 -- "unavailable results misreported: $result $out"; exit 1; }
set +e
out=$(PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 UNAVAILABLE_RESULTS=2 \
    zsh "$scratch/repo/scripts/test.sh" --unit 2>&1)
result=$?
set -e
[[ $result == 1 && $out == *"test results unavailable"* && $out != *"no tests ran"* ]] \
  || { print -u2 -- "partial results misreported: $result $out"; exit 1; }
set +e
out=$(PATH="$scratch/bin:$PATH" CALL_LOG="$log" SLACKWATER_TEST_LOCK=1 FAIL_XCODEBUILD=1 IDLE_TIMEOUTS=3 \
    zsh "$scratch/repo/scripts/test.sh" --unit 2>&1)
result=$?
set -e
[[ $result == 65 && $out == *"3 XCUITest idle timeouts"* && $out == *"s · 1 tests"* ]] \
  || { print -u2 -- "failed run skipped diagnostics: $result $out"; exit 1; }
run_mode --unit
grep -q '"passedTests": 1' "${rawlog%.log}.summary.json"

print "runner mode checks passed"
