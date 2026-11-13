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
