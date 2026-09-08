#!/bin/zsh
set -euo pipefail

root=${0:A:h:h}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/repo/scripts" "$scratch/bin"
cp "$root/scripts/test.sh" "$scratch/repo/scripts/test.sh"
touch "$scratch/repo/scripts/iwls-fixtures.mjs"
log="$scratch/calls"

for tool in node xcodegen xcodebuild; do
  cat > "$scratch/bin/$tool" <<'STUB'
#!/bin/zsh
print -r -- "${0:t} $* | live=${TEST_RUNNER_SLACKWATER_LIVE:-} full=${TEST_RUNNER_SLACKWATER_FULL:-}" >> "$CALL_LOG"
[[ ${0:t} == node && ${FAIL_PREPARE:-0} == 1 ]] && {
  print -u2 -- "IWLS recording missing; run: node scripts/iwls-fixtures.mjs refresh"
  exit 1
}
exit 0
STUB
  chmod +x "$scratch/bin/$tool"
done

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
assert_has "name=iPhone 17"
assert_has "-skip-testing:SlackwaterUITests/LiveFetchTests"
assert_has "-skip-testing:SlackwaterTests/NationalScaleTests/testHybridDirectionHasFullCoverageAndMatchesBaseline"
assert_lacks "live=1"
[[ $(sed -n '/^node /=' "$log") -lt $(sed -n '/^xcodegen /=' "$log") ]] || {
  print -u2 -- "fixture preparation did not precede XcodeGen"
  exit 1
}

run_mode --full
assert_count '^xcodebuild ' 2
assert_has "name=iPad Pro 11-inch (M5)"
assert_has "-skip-testing:SlackwaterUITests/LiveFetchTests"
assert_lacks "NationalScaleTests"
assert_lacks "live=1"

run_mode --unit
assert_count '^xcodebuild ' 1
assert_has "-only-testing:SlackwaterTests"
assert_lacks "NationalScaleTests"

run_mode --live
assert_count '^xcodebuild ' 1
assert_lacks "iwls-fixtures.mjs prepare"
assert_has "-only-testing:SlackwaterUITests/LiveFetchTests"
assert_has "live=1 full="

TEST_RUNNER_SLACKWATER_LIVE=1 TEST_RUNNER_SLACKWATER_FULL=1 run_mode
assert_lacks "live=1"
assert_lacks "full=1"

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

# Exercise the normal machine-lock probe and re-exec once; the table above
# bypasses it so each assertion can focus on a single mode decision.
: > "$log"
PATH="$scratch/bin:$PATH" CALL_LOG="$log" zsh "$scratch/repo/scripts/test.sh" --live >/dev/null
assert_count '^lockf ' 2
assert_has "xcodebuild test"

print "runner mode checks passed"
