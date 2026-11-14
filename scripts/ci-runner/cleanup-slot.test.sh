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

# A fixed device left only on a dropped runtime (isAvailable false) is not
# erased, says to rerun install.sh, and fails the cleanup; the slot's other
# device is still erased. Slot 1 above also has an unavailable iPhone, on
# iOS 25, beside its available one: that one is skipped without a failure.
if out=$(CLEANUP_DRY_RUN=1 SIMCTL_DEVICES_JSON=$fixture SIMCTL_XCTEST_DEVICES_JSON=$xctest_fixture \
    zsh "$root/scripts/ci-runner/cleanup-slot.sh" 4 2>"${TMPDIR:-/tmp}/cleanup-slot-test-err.$$"); then
    rm -f "${TMPDIR:-/tmp}/cleanup-slot-test-err.$$"
    printf 'cleanup-slot.sh exited 0 with an unavailable fixed device\n' >&2; exit 1
fi
err=$(<"${TMPDIR:-/tmp}/cleanup-slot-test-err.$$")
rm -f "${TMPDIR:-/tmp}/cleanup-slot-test-err.$$"
actual=$(print -r -- "$out" | grep '^simctl' | sort || true)
[[ "$actual" == 'simctl erase 44444444-0000-0000-0000-000000000002' ]] || { printf 'unavailable fixed device mismatch:\n%s\n' "$actual" >&2; exit 1; }
[[ "$err" == 'fixed device SlackwaterCI-4-iPhone is not available on any runtime; rerun scripts/ci-runner/install.sh' ]] || {
    printf 'unexpected stderr for an unavailable fixed device:\n%s\n' "$err" >&2; exit 1
}

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

# A clone that xcodebuild's own teardown deleted between the listing and the
# delete is done, not stuck: the stand-in xcrun refuses the delete with
# "Invalid device" and then lists the set without it, and the cleanup exits 0.
# Shutdowns and erases succeed; the default-set listing comes from the fixture.
mkdir -p "$scratch/bin"
cat > "$scratch/bin/xcrun" <<'STUB'
#!/bin/sh
shift                                   # simctl
[ "$1" = --set ] && shift 2
case "$1" in
    list) printf '{"devices":{}}\n' ;;
    delete) printf 'Invalid device: %s\n' "$2" >&2; exit 149 ;;
    *) exit 0 ;;
esac
STUB
chmod +x "$scratch/bin/xcrun"
if ! out=$(HOME=$scratch/home PATH="$scratch/bin:$PATH" SIMCTL_DEVICES_JSON=$fixture SIMCTL_XCTEST_DEVICES_JSON=$xctest_fixture \
    zsh "$root/scripts/ci-runner/cleanup-slot.sh" 1 2>"$scratch/err"); then
    printf 'cleanup-slot.sh failed on clones that were already gone:\n%s\n' "$(<"$scratch/err")" >&2; exit 1
fi
[[ $(grep -c 'was already gone' "$scratch/err") -eq 4 ]] || { printf 'expected four already-gone lines:\n%s\n' "$(<"$scratch/err")" >&2; exit 1; }
grep -q 'failed' "$scratch/err" && { printf 'a vanished clone was counted as a failure:\n%s\n' "$(<"$scratch/err")" >&2; exit 1; }

# A delete that fails while the device is still listed is still a failure.
cat > "$scratch/bin/xcrun" <<STUB
#!/bin/sh
shift
[ "\$1" = --set ] && shift 2
case "\$1" in
    list) cat "$fixture" ;;
    delete) printf 'Unable to delete: %s\n' "\$2" >&2; exit 1 ;;
    *) exit 0 ;;
esac
STUB
if HOME=$scratch/home PATH="$scratch/bin:$PATH" SIMCTL_DEVICES_JSON=$fixture SIMCTL_XCTEST_DEVICES_JSON=$xctest_fixture \
    zsh "$root/scripts/ci-runner/cleanup-slot.sh" 1 >/dev/null 2>"$scratch/err"; then
    printf 'cleanup-slot.sh exited 0 with a clone that would not delete\n' >&2; exit 1
fi
grep -q 'simctl delete .* failed' "$scratch/err" || { printf 'no failed line for a stuck clone:\n%s\n' "$(<"$scratch/err")" >&2; exit 1; }
