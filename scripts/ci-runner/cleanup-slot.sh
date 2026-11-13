#!/bin/zsh
# Clean one CI slot: delete the clones of its two fixed simulators, erase the
# fixed ones, and kill processes still holding them. Touches only devices named
# SlackwaterCI-<slot>-*, never another slot or a developer's own simulators.
# SIMCTL_DEVICES_JSON=<path> reads the device list from a file instead of
# simctl; CLEANUP_DRY_RUN=1 prints the commands instead of running them.
set -eu
slot=${1:?usage: cleanup-slot.sh <slot>}
phone=SlackwaterCI-$slot-iPhone
pad=SlackwaterCI-$slot-iPad
failed=0
empty='{"devices":{}}'

# Prints the device list of one set: the file named by $1 when it is set,
# otherwise simctl's listing of set $2 (the default set when empty). A list
# that cannot be read or is not a device list is a failure, never an empty
# set: the caller marks the cleanup failed and skips that set.
list_set() {
    local out
    if [[ -n $1 ]]; then
        out=$(cat -- "$1" 2>/dev/null) || return 1
    elif [[ -n $2 ]]; then
        out=$(xcrun simctl --set "$2" list devices -j 2>/dev/null) || return 1
    else
        out=$(xcrun simctl list devices -j 2>/dev/null) || return 1
    fi
    print -r -- "$out" | jq -e '.devices | type == "object"' >/dev/null 2>&1 || return 1
    print -r -- "$out"
}

devices=$(list_set "${SIMCTL_DEVICES_JSON:-}" '') || {
    print -u2 -r -- "cleanup-slot: could not list the default simulator set; skipping it"
    devices=$empty
    failed=1
}

# Prints the command in dry-run mode. Otherwise runs simctl, tolerating the
# failure of a shutdown on a device that is already down.
simctl() {
    local -a set_args=()
    local label=
    if [[ -n ${simset:-} ]]; then set_args=(--set "$simset"); label="--set XCTestDevices "; fi
    if [[ -n ${CLEANUP_DRY_RUN:-} ]]; then
        print -r -- "simctl $label$*"
    elif [[ $1 == shutdown ]]; then
        xcrun simctl $set_args "$@" 2>/dev/null || true
    else
        # Best-effort: one stuck device must not stop the rest of the cleanup.
        xcrun simctl $set_args "$@" || { print -u2 -r -- "cleanup-slot: simctl $label$* failed"; failed=1; }
    fi
}

clones=(${(f)"$(print -r -- "$devices" | jq -r --arg p "SlackwaterCI-$slot-" --arg a "$phone" --arg b "$pad" \
    '.devices[][] | select((.name | startswith($p)) and .name != $a and .name != $b) | .udid')"})
# Only available fixed devices: one whose runtime an Xcode update dropped is
# still listed, and erasing it fails with nothing but xcrun's message.
fixed=(${(f)"$(print -r -- "$devices" | jq -r --arg a "$phone" --arg b "$pad" \
    '.devices[][] | select((.name == $a or .name == $b) and .isAvailable == true) | .udid')"})
# The slot's names that exist only as unavailable devices.
unavailable=(${(f)"$(print -r -- "$devices" | jq -r --arg a "$phone" --arg b "$pad" \
    '[.devices[][] | select(.name == $a or .name == $b)] | group_by(.name)[]
     | select(all(.isAvailable != true)) | .[0].name')"})

# xcodebuild keeps its parallel-test clones in a separate device set that a
# plain `simctl list` never shows; a cancelled run leaves them booted there.
# Their names contain the slot's name ("Clone 1 of SlackwaterCI-1-iPhone").
# SIMCTL_XCTEST_DEVICES_JSON=<path> overrides the listing. A missing set
# directory is an empty set; a set that is there and cannot be listed fails.
xctest_set=$HOME/Library/Developer/XCTestDevices
xctest_devices=$empty
if [[ -n ${SIMCTL_XCTEST_DEVICES_JSON:-} || -d $xctest_set ]]; then
    xctest_devices=$(list_set "${SIMCTL_XCTEST_DEVICES_JSON:-}" "$xctest_set") || {
        print -u2 -r -- "cleanup-slot: could not list $xctest_set; skipping it"
        xctest_devices=$empty
        failed=1
    }
fi
xctest_clones=(${(f)"$(print -r -- "$xctest_devices" | jq -r --arg p "SlackwaterCI-$slot-" \
    '.devices[][] | select(.name | contains($p)) | .udid')"})

# Kill what still holds the slot's devices so nothing can hold one while it is
# erased. The name pattern is the one that matters: scripts/test.sh passes
# `-destination 'platform=iOS Simulator,name=SlackwaterCI-<slot>-iPhone'`, with
# no UDID, and its workers run on clones with UDIDs of their own. The UDIDs
# catch anything started against a device directly.
pids=()
for pattern in "SlackwaterCI-$slot-" $fixed $clones $xctest_clones; do
    pids+=($(pgrep -f "$pattern" || true))
done
# A process can exit between pgrep and kill, and kill then fails. That is
# the outcome the kill wanted, so a failed kill counts only while the
# process is still there afterwards; otherwise a job that ended on its own
# would turn the cleanup, and the job, red.
killed=()
for pid in ${(u)pids}; do
    name=$(ps -p $pid -o comm= 2>/dev/null || true)
    case ${name:t} in
        xcodebuild|Simulator|xctest)
            killed+=($pid)
            if [[ -n ${CLEANUP_DRY_RUN:-} ]]; then
                print -r -- "kill $pid"
            else
                kill $pid 2>/dev/null || ! kill -0 $pid 2>/dev/null || failed=1
            fi
            ;;
    esac
done
# A killed xcodebuild can take a few seconds to let go of its devices, and a
# shutdown or delete before then fails. Wait up to 10 s, then kill -9.
if [[ -n ${CLEANUP_DRY_RUN:-} ]]; then
    for pid in $killed; do print -r -- "wait $pid"; done
else
    for _ in {1..10}; do
        alive=()
        for pid in $killed; do kill -0 $pid 2>/dev/null && alive+=($pid); done
        killed=($alive)
        (( $#killed )) || break
        sleep 1
    done
    # The same race: one that exits after the last check is gone, not stuck.
    for pid in $killed; do kill -9 $pid 2>/dev/null || ! kill -0 $pid 2>/dev/null || failed=1; done
fi

for udid in $clones; do
    simctl shutdown $udid
    simctl delete $udid
done
simset=$xctest_set
for udid in $xctest_clones; do
    simctl shutdown $udid
    simctl delete $udid
done
simset=

# Erase refuses a booted device, so shut down any fixed device not already down.
up=(${(f)"$(print -r -- "$devices" | jq -r --arg a "$phone" --arg b "$pad" \
    '.devices[][] | select((.name == $a or .name == $b) and .state != "Shutdown") | .udid')"})
for udid in $up; do
    simctl shutdown $udid
done
for udid in $fixed; do
    simctl erase $udid
done
for name in $unavailable; do
    print -u2 -r -- "fixed device $name is not available on any runtime; rerun scripts/ci-runner/install.sh"
    failed=1
done

exit $failed
