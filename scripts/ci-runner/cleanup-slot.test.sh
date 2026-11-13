#!/bin/zsh
set -eu
root=${0:A:h:h:h}
fixture=$root/scripts/ci-runner/fixtures/simctl-devices.json
xctest_fixture=$root/scripts/ci-runner/fixtures/simctl-xctest-devices.json

# kill lines come from scanning real processes, so only simctl lines are compared.
run() {
    local out
    out=$(CLEANUP_DRY_RUN=1 SIMCTL_DEVICES_JSON=$fixture SIMCTL_XCTEST_DEVICES_JSON=$xctest_fixture zsh "$root/scripts/ci-runner/cleanup-slot.sh" "$1") || {
        printf 'cleanup-slot.sh %s exited non-zero\n' "$1" >&2; exit 1
    }
    print -r -- "$out" | grep '^simctl' | sort || true
}

expected=$(printf '%s\n' \
    'simctl delete 11111111-0000-0000-0000-000000000003' \
    'simctl delete 11111111-0000-0000-0000-000000000004' \
    'simctl erase 11111111-0000-0000-0000-000000000001' \
    'simctl erase 11111111-0000-0000-0000-000000000002' \
    'simctl shutdown 11111111-0000-0000-0000-000000000003' \
    'simctl shutdown 11111111-0000-0000-0000-000000000004' \
    'simctl --set XCTestDevices delete 33333333-0000-0000-0000-000000000001' \
    'simctl --set XCTestDevices delete 33333333-0000-0000-0000-000000000002' \
    'simctl --set XCTestDevices shutdown 33333333-0000-0000-0000-000000000001' \
    'simctl --set XCTestDevices shutdown 33333333-0000-0000-0000-000000000002' | sort)
actual=$(run 1)
[[ "$actual" == "$expected" ]] || { printf 'slot 1 mismatch:\n%s\n' "$actual" >&2; exit 1; }

actual=$(run 3)
[[ -z "$actual" ]] || { printf 'slot 3 should be empty:\n%s\n' "$actual" >&2; exit 1; }

# An XCTestDevices set that is there but cannot be listed fails the cleanup
# and is skipped, while the default set is still cleaned.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/home/Library/Developer/XCTestDevices"
if out=$(HOME=$scratch/home CLEANUP_DRY_RUN=1 SIMCTL_DEVICES_JSON=$fixture SIMCTL_XCTEST_DEVICES_JSON=$scratch/missing.json \
    zsh "$root/scripts/ci-runner/cleanup-slot.sh" 1 2>"$scratch/err"); then
    printf 'cleanup-slot.sh exited 0 with an unlistable XCTestDevices set\n' >&2; exit 1
fi
actual=$(print -r -- "$out" | grep '^simctl' | sort || true)
expected_default=$(print -r -- "$expected" | grep -v -- '--set XCTestDevices')
[[ "$actual" == "$expected_default" ]] || { printf 'unlistable XCTestDevices mismatch:\n%s\n' "$actual" >&2; exit 1; }
grep -q 'could not list' "$scratch/err" || { printf 'no line said the set could not be listed:\n%s\n' "$(<"$scratch/err")" >&2; exit 1; }

# A default set that cannot be listed fails too, and skips that whole pass.
if out=$(HOME=$scratch/home CLEANUP_DRY_RUN=1 SIMCTL_DEVICES_JSON=$scratch/missing.json SIMCTL_XCTEST_DEVICES_JSON=$xctest_fixture \
    zsh "$root/scripts/ci-runner/cleanup-slot.sh" 1 2>/dev/null); then
    printf 'cleanup-slot.sh exited 0 with an unlistable default set\n' >&2; exit 1
fi
actual=$(print -r -- "$out" | grep '^simctl' | sort || true)
expected_xctest=$(print -r -- "$expected" | grep -- '--set XCTestDevices')
[[ "$actual" == "$expected_xctest" ]] || { printf 'unlistable default set mismatch:\n%s\n' "$actual" >&2; exit 1; }
