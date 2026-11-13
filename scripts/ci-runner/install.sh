#!/bin/sh
# Install the Studio's three ephemeral CI runner slots, and retire the old
# organisation runner and its simulators. See README.md in this directory.
#
# Each step checks before it acts, so running this again changes nothing that
# is already in place; a plist that no longer matches the template is
# rewritten and its job reloaded.
#
# RUNNER_DRY_RUN=1 prints the commands instead of running them. For tests,
# RUNNER_VERSION=<tag> skips the release lookup, RUNNER_LAUNCHCTL_LIST=<file>
# and SIMCTL_DEVICES_JSON=<file> stand in for `launchctl list` and
# `xcrun simctl list devices -j`.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
uid=$(id -u)
agents=$HOME/Library/LaunchAgents
old_label=actions.runner.openwatersio.studio
old_dir=$HOME/actions-runner/slackwater-ios
# The devices and runtime the hosted app job names (SLACKWATER_SIM_OS there).
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

if [ -n "${RUNNER_LAUNCHCTL_LIST:-}" ]; then
    loaded=$(cat "$RUNNER_LAUNCHCTL_LIST")
else
    loaded=$(launchctl list)
fi
is_loaded() {
    printf '%s\n' "$loaded" | awk -v label="$1" '$3 == label { found = 1 } END { exit !found }'
}
if [ -n "${SIMCTL_DEVICES_JSON:-}" ]; then
    devices=$(cat "$SIMCTL_DEVICES_JSON")
else
    devices=$(xcrun simctl list devices -j)
fi
has_device() {
    printf '%s\n' "$devices" | jq -e --arg n "$1" 'any(.devices[][]; .name == $n)' >/dev/null
}

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

    # reregister.sh runs these copies; between jobs there is no checkout.
    stale=
    for script in hook-job-started.sh cleanup-slot.sh reregister.sh; do
        cmp -s "$here/$script" "$dir/$script" || stale=1
    done
    if [ -n "$stale" ]; then
        run cp "$here/hook-job-started.sh" "$here/cleanup-slot.sh" "$here/reregister.sh" "$dir/"
    fi

    for device in iPhone iPad; do
        name=SlackwaterCI-$slot-$device
        if [ "$device" = iPhone ]; then type=$iphone_type; else type=$ipad_type; fi
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
