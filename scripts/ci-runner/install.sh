#!/bin/sh
# Install the Studio's three ephemeral CI runner slots, and retire the old
# organisation runner and its simulators. See README.md in this directory.
#
# Each step checks before it acts, so running this again changes nothing that
# is already in place; a plist that no longer matches the template is
# rewritten and its job reloaded.
#
# RUNNER_DRY_RUN=1 prints the commands instead of running them. For tests,
# RUNNER_VERSION=<tag> skips the release lookup, RUNNER_LOADED_LABELS=<file>
# (one label per line) stands in for asking launchd which jobs are loaded, and
# SIMCTL_DEVICES_JSON=<file> for `xcrun simctl list devices -j`, and
# SIMCTL_XCTEST_DEVICES_JSON=<file> for the same listing of XCTestDevices.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
uid=$(id -u)
agents=$HOME/Library/LaunchAgents
old_label=actions.runner.openwatersio.studio
old_dir=$HOME/actions-runner/slackwater-ios
# The devices the hosted app job names, and the runtime CI_SIM_OS in ci.yml names.
iphone_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17
ipad_type=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB
runtime=com.apple.CoreSimulator.SimRuntime.iOS-27-0

run() {
    if [ -n "${RUNNER_DRY_RUN:-}" ]; then printf '%s\n' "$*"; else "$@"; fi
}

tools=jq
if [ -z "${RUNNER_DRY_RUN:-}" ]; then
    tools="jq gh xcrun curl"
    # Attributes only, never the secret: reregister.sh needs the item present.
    security find-generic-password -s slackwater-ci-runner >/dev/null 2>&1 || {
        printf 'install.sh: no slackwater-ci-runner item in the login Keychain; see README.md\n' >&2
        exit 1
    }
fi
for tool in $tools; do
    command -v "$tool" >/dev/null || { printf 'install.sh: %s is not on PATH\n' "$tool" >&2; exit 1; }
done

# Asks the GUI domain by name: `launchctl list` reads the caller's domain,
# which over ssh is not gui/<uid>.
is_loaded() {
    if [ -n "${RUNNER_LOADED_LABELS:-}" ]; then
        grep -qxF "$1" "$RUNNER_LOADED_LABELS"
    else
        launchctl print "gui/$uid/$1" >/dev/null 2>&1
    fi
}
if [ -n "${SIMCTL_DEVICES_JSON:-}" ]; then
    devices=$(cat "$SIMCTL_DEVICES_JSON")
else
    devices=$(xcrun simctl list devices -j)
fi
# Anything but a device list would read as no devices at all: has_device
# would find none and simctl create would run beside the existing ones.
is_device_list() {
    printf '%s\n' "$1" | jq -e '.devices | type == "object"' >/dev/null 2>&1
}
is_device_list "$devices" || {
    printf 'install.sh: xcrun simctl list devices -j did not print a device list\n' >&2
    exit 1
}
# A device counts only on the pinned runtime and while it is available: one
# left on an older or deleted runtime is not one the jobs can boot.
has_device() {
    printf '%s\n' "$devices" | jq -e --arg n "$1" --arg r "${runtime##*.}" \
        'any(.devices | to_entries[] | select(.key | endswith($r)) | .value[]; .name == $n and .isAvailable == true)' >/dev/null
}

# Two available devices of one slot name on the pinned runtime are both the
# slot's as far as cleanup-slot.sh and the jobs can tell. Which one to keep is
# the operator's call, so stop before changing anything.
duplicates=0
for slot in 1 2 3; do
    for device in iPhone iPad; do
        name=SlackwaterCI-$slot-$device
        udids=$(printf '%s\n' "$devices" | jq -r --arg n "$name" --arg r "${runtime##*.}" \
            '[.devices | to_entries[] | select(.key | endswith($r)) | .value[]
              | select(.name == $n and .isAvailable == true) | .udid] | select(length > 1) | join(" ")')
        if [ -n "$udids" ]; then
            printf 'install.sh: more than one available %s on %s: %s\n' "$name" "${runtime##*.}" "$udids" >&2
            printf 'install.sh:   keep one, delete each of the others with: xcrun simctl delete <udid>\n' >&2
            duplicates=1
        fi
    done
done
[ "$duplicates" = 0 ] || exit 1

# The old runner: one organisation-level runner named studio in the
# slackwater-nightly group, served by its own launchd agent.
if is_loaded "$old_label"; then
    run launchctl bootout "gui/$uid/$old_label"
fi
if [ -e "$agents/$old_label.plist" ]; then
    run rm -f "$agents/$old_label.plist"
fi
# Its removal token is minted from the organisation, which the repository
# token cannot do, so the operator runs these.
if [ -e "$old_dir/.runner" ]; then
    printf '%s\n' \
        'operator: the old runner is registered with the organisation; with an org-admin token, run:' \
        "operator:   cd $old_dir && ./config.sh remove --token \"\$(gh api -X POST orgs/openwatersio/actions/runners/remove-token --jq .token)\" && cd && rm -rf $old_dir" \
        "operator:   gh api -X DELETE \"orgs/openwatersio/actions/runner-groups/\$(gh api orgs/openwatersio/actions/runner-groups --jq '.runner_groups[] | select(.name == \"slackwater-nightly\") | .id')\""
fi

# The old simulators carry no slot number: SlackwaterCI-iPhone, SlackwaterCI-iPad
# and clones named after them. A new name has a digit after the first hyphen.
for udid in $(printf '%s\n' "$devices" | jq -r '.devices[][] | select(.name | test("SlackwaterCI-[A-Za-z]")) | .udid'); do
    if [ -n "${RUNNER_DRY_RUN:-}" ]; then
        run xcrun simctl shutdown "$udid"
    else
        xcrun simctl shutdown "$udid" 2>/dev/null || true
    fi
    run xcrun simctl delete "$udid"
done
# xcodebuild's parallel-test clones of them live in a set of their own, which
# a plain `simctl list` never shows ("Clone 1 of SlackwaterCI-iPhone").
# SIMCTL_XCTEST_DEVICES_JSON=<file> stands in for its listing.
xctest_set=$HOME/Library/Developer/XCTestDevices
xctest_devices=
if [ -n "${SIMCTL_XCTEST_DEVICES_JSON:-}" ]; then
    xctest_devices=$(cat "$SIMCTL_XCTEST_DEVICES_JSON")
elif [ -d "$xctest_set" ]; then
    xctest_devices=$(xcrun simctl --set "$xctest_set" list devices -j) || {
        printf 'install.sh: could not list %s; its old clones stay\n' "$xctest_set" >&2
        xctest_devices=
    }
fi
if [ -n "$xctest_devices" ] && ! is_device_list "$xctest_devices"; then
    printf 'install.sh: the listing of %s is not a device list\n' "$xctest_set" >&2
    exit 1
fi
if [ -n "$xctest_devices" ]; then
    for udid in $(printf '%s\n' "$xctest_devices" | jq -r '.devices[][] | select(.name | test("SlackwaterCI-[A-Za-z]")) | .udid'); do
        if [ -n "${RUNNER_DRY_RUN:-}" ]; then
            run xcrun simctl --set "$xctest_set" shutdown "$udid"
        else
            xcrun simctl --set "$xctest_set" shutdown "$udid" 2>/dev/null || true
        fi
        run xcrun simctl --set "$xctest_set" delete "$udid"
    done
fi

if [ ! -d "$agents" ] || [ ! -d "$HOME/Library/Logs" ]; then
    run mkdir -p "$agents" "$HOME/Library/Logs"
fi

version=${RUNNER_VERSION:-}
rendered=$(mktemp)
trap 'rm -f "$rendered"' EXIT

for slot in 1 2 3; do
    dir=$HOME/actions-runner/studio-$slot
    label=io.openwaters.slackwater.ci-runner.$slot
    plist=$agents/$label.plist

    if [ ! -e "$dir/config.sh" ]; then
        [ -n "$version" ] || version=$(gh release view --repo actions/runner --json tagName -q .tagName)
        number=${version#v}
        run mkdir -p "$dir"
        run curl -fsSL -o "$dir/runner.tar.gz" \
            "https://github.com/actions/runner/releases/download/v$number/actions-runner-osx-arm64-$number.tar.gz"
        run tar -xzf "$dir/runner.tar.gz" -C "$dir"
        run rm "$dir/runner.tar.gz"
    fi

    # reregister.sh runs these copies; between jobs there is no checkout. A
    # copy lands beside the old file and is moved over it, so a running
    # reregister.sh keeps reading the old file instead of rewritten text.
    for script in hook-job-started.sh cleanup-slot.sh reregister.sh; do
        if ! cmp -s "$here/$script" "$dir/$script"; then
            run cp "$here/$script" "$dir/.$script.new"
            run mv -f "$dir/.$script.new" "$dir/$script"
        fi
    done

    for device in iPhone iPad; do
        name=SlackwaterCI-$slot-$device
        if [ "$device" = iPhone ]; then type=$iphone_type; else type=$ipad_type; fi
        # A device of this name off the pinned runtime, or unavailable, is
        # not the slot's, but cleanup-slot.sh picks devices by name and
        # would erase it too. Delete it before creating the real one.
        for udid in $(printf '%s\n' "$devices" | jq -r --arg n "$name" --arg r "${runtime##*.}" \
            '.devices | to_entries[] | .key as $k | .value[]
             | select(.name == $n and (($k | endswith($r) | not) or .isAvailable != true)) | .udid'); do
            if [ -n "${RUNNER_DRY_RUN:-}" ]; then
                run xcrun simctl shutdown "$udid"
            else
                xcrun simctl shutdown "$udid" 2>/dev/null || true
            fi
            run xcrun simctl delete "$udid"
        done
        has_device "$name" || run xcrun simctl create "$name" "$type" "$runtime"
    done

    sed -e "s|@SLOT@|$slot|g" -e "s|@RUNNER_DIR@|$dir|g" -e "s|@HOME@|$HOME|g" \
        "$here/launchd.plist.template" >"$rendered"
    if ! cmp -s "$rendered" "$plist"; then
        # Reloading stops a runner mid-job; only a changed plist does it.
        if is_loaded "$label"; then run launchctl bootout "gui/$uid/$label"; fi
        if [ -n "${RUNNER_DRY_RUN:-}" ]; then
            printf 'write %s\n' "$plist"
        else
            cp "$rendered" "$plist"
        fi
        run launchctl bootstrap "gui/$uid" "$plist"
    elif ! is_loaded "$label"; then
        run launchctl bootstrap "gui/$uid" "$plist"
    fi
done
