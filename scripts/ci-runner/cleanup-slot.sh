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
    if [[ -n ${CLEANUP_DRY_RUN:-} ]]; then
        print -r -- "simctl $*"
    elif [[ $1 == shutdown ]]; then
        xcrun simctl "$@" 2>/dev/null || true
    else
        # Best-effort: one stuck device must not stop the rest of the cleanup.
        xcrun simctl "$@" || { print -u2 -r -- "cleanup-slot: simctl $* failed"; failed=1; }
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
