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

if [[ -n ${SIMCTL_DEVICES_JSON:-} ]]; then
    devices=$(<"$SIMCTL_DEVICES_JSON")
else
    devices=$(xcrun simctl list devices -j)
fi

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
fixed=(${(f)"$(print -r -- "$devices" | jq -r --arg a "$phone" --arg b "$pad" \
    '.devices[][] | select(.name == $a or .name == $b) | .udid')"})

for udid in $clones; do
    simctl shutdown $udid
    simctl delete $udid
done

# xcodebuild keeps its parallel-test clones in a separate device set that a
# plain `simctl list` never shows; a cancelled run leaves them booted there.
# Their names contain the slot's name ("Clone 1 of SlackwaterCI-1-iPhone").
# SIMCTL_XCTEST_DEVICES_JSON=<path> overrides the listing. A missing set is fine.
xctest_set=$HOME/Library/Developer/XCTestDevices
xctest_devices='{"devices":{}}'
if [[ -n ${SIMCTL_XCTEST_DEVICES_JSON:-} ]]; then
    xctest_devices=$(<"$SIMCTL_XCTEST_DEVICES_JSON")
elif [[ -d $xctest_set ]]; then
    xctest_devices=$(xcrun simctl --set "$xctest_set" list devices -j 2>/dev/null || print -r -- '{"devices":{}}')
fi
xctest_clones=(${(f)"$(print -r -- "$xctest_devices" | jq -r --arg p "SlackwaterCI-$slot-" \
    '.devices[][] | select(.name | contains($p)) | .udid')"})
simset=$xctest_set
for udid in $xctest_clones; do
    simctl shutdown $udid
    simctl delete $udid
done
simset=

for udid in $fixed; do
    # Kill first so a lingering process cannot hold the device while it erases.
    for pid in $(pgrep -f "$udid" || true); do
        name=$(ps -p $pid -o comm= 2>/dev/null || true)
        case ${name:t} in
            xcodebuild|Simulator|xctest)
                if [[ -n ${CLEANUP_DRY_RUN:-} ]]; then print -r -- "kill $pid"; else kill $pid || failed=1; fi
                ;;
        esac
    done
done

# Erase refuses a booted device, so shut down any fixed device not already down.
up=(${(f)"$(print -r -- "$devices" | jq -r --arg a "$phone" --arg b "$pad" \
    '.devices[][] | select((.name == $a or .name == $b) and .state != "Shutdown") | .udid')"})
for udid in $up; do
    simctl shutdown $udid
done
for udid in $fixed; do
    simctl erase $udid
done

exit $failed
