#!/bin/sh
# Drives reregister.sh and install.sh in dry-run mode against a fake HOME.
# Nothing here registers a runner, loads a launchd job, or touches a simulator.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
dir=$root/scripts/ci-runner
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fail() { printf '%s\n' "$*" >&2; exit 1; }
same() {
    [ "$2" = "$3" ] || fail "$1 mismatch:
--- expected
$2
--- actual
$3"
}

# reregister.sh
home=$scratch/home
runner=$home/actions-runner/studio-2
mkdir -p "$runner"
rereg() {
    (cd "$runner" && env HOME="$home" RUNNER_DRY_RUN=1 RUNNER_TOKEN_CMD='echo tok' "$@" sh "$dir/reregister.sh")
}

if (cd "$runner" && env -u SLOT HOME="$home" RUNNER_DRY_RUN=1 RUNNER_TOKEN_CMD='echo tok' sh "$dir/reregister.sh") >"$scratch/out" 2>&1; then
    fail 'reregister.sh ran without SLOT'
fi
grep -q SLOT "$scratch/out" || fail "reregister.sh without SLOT said: $(cat "$scratch/out")"
if rereg SLOT=4 >/dev/null 2>&1; then fail 'reregister.sh accepted slot 4'; fi

config="./config.sh --unattended --ephemeral --replace --url https://github.com/openwatersio/slackwater-ios --token tok --name studio-2 --labels studio --work _work"
out=$(rereg SLOT=2 2>"$scratch/err")
same 'reregister sequence' "$(printf '%s\n' 'zsh ./cleanup-slot.sh 2' "$config" './run.sh')" "$out"
same 'reregister .env' "$(printf '%s\n' \
    "would write $runner/.env:" \
    'SLACKWATER_CI_SLOT=2' \
    "ACTIONS_RUNNER_HOOK_JOB_STARTED=$runner/hook-job-started.sh" \
    "PATH=$home/.local/share/mise/shims:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")" "$(cat "$scratch/err")"

# A runner killed mid-job leaves its local registration behind, which
# config.sh refuses to overwrite; it is removed first, with a removal token.
: >"$runner/.runner"
out=$(rereg SLOT=2 RUNNER_TOKEN_CMD='[ "$1" = remove-token ] && echo rm || echo tok' 2>/dev/null)
same 'reregister with a stale registration' "$(printf '%s\n' 'zsh ./cleanup-slot.sh 2' './config.sh remove --token rm' "$config" './run.sh')" "$out"
rm "$runner/.runner"

out=$(rereg SLOT=2 SLACKWATER_CI_SCRIPTS=/checkout/scripts/ci-runner 2>/dev/null)
same 'reregister with a scripts refresh' "$(printf '%s\n' \
    "cp /checkout/scripts/ci-runner/hook-job-started.sh /checkout/scripts/ci-runner/cleanup-slot.sh $runner/" \
    'zsh ./cleanup-slot.sh 2' "$config" './run.sh')" "$out"

# The plist template renders to a valid property list.
sed -e 's|@SLOT@|1|g' -e "s|@RUNNER_DIR@|$home/actions-runner/studio-1|g" -e "s|@HOME@|$home|g" \
    "$dir/launchd.plist.template" >"$scratch/rendered.plist"
plutil -lint -s "$scratch/rendered.plist" || fail 'rendered plist does not lint'
[ "$(plutil -extract Label raw "$scratch/rendered.plist")" = io.openwaters.slackwater.ci-runner.1 ] || fail 'plist label'
[ "$(plutil -extract ProgramArguments.1 raw "$scratch/rendered.plist")" = "$home/actions-runner/studio-1/reregister.sh" ] || fail 'plist program'
[ "$(plutil -extract EnvironmentVariables.SLOT raw "$scratch/rendered.plist")" = 1 ] || fail 'plist slot'
[ "$(plutil -extract KeepAlive raw "$scratch/rendered.plist")" = true ] || fail 'plist KeepAlive'
# mise's shims come first, so node is mise.toml's and not Homebrew's.
[ "$(plutil -extract EnvironmentVariables.PATH raw "$scratch/rendered.plist")" = "$home/.local/share/mise/shims:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" ] || fail 'plist PATH'

# install.sh, on a machine that still has the old organisation runner, its
# launchd agent, the old simulators, and one of the new ones already.
home=$scratch/install-home
mkdir -p "$home/actions-runner/slackwater-ios" "$home/Library/LaunchAgents"
: >"$home/actions-runner/slackwater-ios/.runner"
: >"$home/Library/LaunchAgents/actions.runner.openwatersio.studio.plist"
printf '%s\n' actions.runner.openwatersio.studio com.apple.other >"$scratch/loaded"
cat >"$scratch/devices.json" <<'JSON'
{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
  {"name": "SlackwaterCI-iPhone", "udid": "AAAAAAAA-0000-0000-0000-000000000001", "state": "Shutdown", "isAvailable": true},
  {"name": "SlackwaterCI-iPad", "udid": "AAAAAAAA-0000-0000-0000-000000000002", "state": "Shutdown", "isAvailable": true},
  {"name": "Clone 1 of SlackwaterCI-iPhone", "udid": "AAAAAAAA-0000-0000-0000-000000000003", "state": "Booted", "isAvailable": true},
  {"name": "SlackwaterCI-1-iPhone", "udid": "BBBBBBBB-0000-0000-0000-000000000001", "state": "Shutdown", "isAvailable": true},
  {"name": "iPhone 17", "udid": "CCCCCCCC-0000-0000-0000-000000000001", "state": "Shutdown", "isAvailable": true}
]}}
JSON
# xcodebuild's clone set: an old clone, and a slot's clone that stays.
cat >"$scratch/xctest.json" <<'JSON'
{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
  {"name": "Clone 2 of SlackwaterCI-iPad", "udid": "DDDDDDDD-0000-0000-0000-000000000001", "state": "Booted", "isAvailable": true},
  {"name": "Clone 1 of SlackwaterCI-1-iPhone", "udid": "DDDDDDDD-0000-0000-0000-000000000002", "state": "Shutdown", "isAvailable": true}
]}}
JSON
install() {
    env HOME="$home" RUNNER_DRY_RUN=1 RUNNER_VERSION=v2.330.0 \
        RUNNER_LOADED_LABELS="$scratch/loaded" SIMCTL_DEVICES_JSON="$scratch/devices.json" \
        SIMCTL_XCTEST_DEVICES_JSON="$scratch/xctest.json" \
        sh "$dir/install.sh"
}
uid=$(id -u)
url=https://github.com/actions/runner/releases/download/v2.330.0/actions-runner-osx-arm64-2.330.0.tar.gz
iphone=com.apple.CoreSimulator.SimDeviceType.iPhone-17
ipad=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB
runtime=com.apple.CoreSimulator.SimRuntime.iOS-27-0
expected=$(
    printf '%s\n' \
        "launchctl bootout gui/$uid/actions.runner.openwatersio.studio" \
        "rm -f $home/Library/LaunchAgents/actions.runner.openwatersio.studio.plist" \
        'operator: the old runner is registered with the organisation; with an org-admin token, run:' \
        "operator:   cd $home/actions-runner/slackwater-ios && ./config.sh remove --token \"\$(gh api -X POST orgs/openwatersio/actions/runners/remove-token --jq .token)\" && cd && rm -rf $home/actions-runner/slackwater-ios" \
        "operator:   gh api -X DELETE \"orgs/openwatersio/actions/runner-groups/\$(gh api orgs/openwatersio/actions/runner-groups --jq '.runner_groups[] | select(.name == \"slackwater-nightly\") | .id')\"" \
        'xcrun simctl shutdown AAAAAAAA-0000-0000-0000-000000000001' \
        'xcrun simctl delete AAAAAAAA-0000-0000-0000-000000000001' \
        'xcrun simctl shutdown AAAAAAAA-0000-0000-0000-000000000002' \
        'xcrun simctl delete AAAAAAAA-0000-0000-0000-000000000002' \
        'xcrun simctl shutdown AAAAAAAA-0000-0000-0000-000000000003' \
        'xcrun simctl delete AAAAAAAA-0000-0000-0000-000000000003' \
        "xcrun simctl --set $home/Library/Developer/XCTestDevices shutdown DDDDDDDD-0000-0000-0000-000000000001" \
        "xcrun simctl --set $home/Library/Developer/XCTestDevices delete DDDDDDDD-0000-0000-0000-000000000001" \
        "mkdir -p $home/Library/LaunchAgents $home/Library/Logs"
    for n in 1 2 3; do
        r=$home/actions-runner/studio-$n
        plist=$home/Library/LaunchAgents/io.openwaters.slackwater.ci-runner.$n.plist
        printf '%s\n' \
            "mkdir -p $r" \
            "curl -fsSL -o $r/runner.tar.gz $url" \
            "tar -xzf $r/runner.tar.gz -C $r" \
            "rm $r/runner.tar.gz" \
            "cp $dir/hook-job-started.sh $r/.hook-job-started.sh.new" "mv -f $r/.hook-job-started.sh.new $r/hook-job-started.sh" \
            "cp $dir/cleanup-slot.sh $r/.cleanup-slot.sh.new" "mv -f $r/.cleanup-slot.sh.new $r/cleanup-slot.sh" \
            "cp $dir/reregister.sh $r/.reregister.sh.new" "mv -f $r/.reregister.sh.new $r/reregister.sh"
        [ "$n" = 1 ] || printf '%s\n' "xcrun simctl create SlackwaterCI-$n-iPhone $iphone $runtime"
        printf '%s\n' \
            "xcrun simctl create SlackwaterCI-$n-iPad $ipad $runtime" \
            "write $plist" \
            "launchctl bootstrap gui/$uid $plist"
    done
)
out=$(install)
same 'install, first run' "$expected" "$out"
# Dry-run changes nothing, so a second run must decide the same way.
out=$(install)
same 'install, second run' "$expected" "$out"

# Once everything is in place, a run does nothing.
for n in 1 2 3; do
    r=$home/actions-runner/studio-$n
    mkdir -p "$r"
    : >"$r/config.sh"
    cp "$dir/hook-job-started.sh" "$dir/cleanup-slot.sh" "$dir/reregister.sh" "$r/"
    sed -e "s|@SLOT@|$n|g" -e "s|@RUNNER_DIR@|$r|g" -e "s|@HOME@|$home|g" "$dir/launchd.plist.template" \
        >"$home/Library/LaunchAgents/io.openwaters.slackwater.ci-runner.$n.plist"
    printf '%s\n' "io.openwaters.slackwater.ci-runner.$n" >>"$scratch/loaded"
done
mkdir -p "$home/Library/Logs"
rm -rf "$home/actions-runner/slackwater-ios" "$home/Library/LaunchAgents/actions.runner.openwatersio.studio.plist"
grep ci-runner "$scratch/loaded" >"$scratch/loaded.new"
mv "$scratch/loaded.new" "$scratch/loaded"
cat >"$scratch/devices.json" <<'JSON'
{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
  {"name": "SlackwaterCI-1-iPhone", "udid": "1", "isAvailable": true}, {"name": "SlackwaterCI-1-iPad", "udid": "2", "isAvailable": true},
  {"name": "SlackwaterCI-2-iPhone", "udid": "3", "isAvailable": true}, {"name": "SlackwaterCI-2-iPad", "udid": "4", "isAvailable": true},
  {"name": "SlackwaterCI-3-iPhone", "udid": "5", "isAvailable": true}, {"name": "SlackwaterCI-3-iPad", "udid": "6", "isAvailable": true}
]}}
JSON
printf '%s\n' '{"devices": {}}' >"$scratch/xctest.json"
out=$(install)
same 'install when installed' '' "$out"

# A device left on another runtime, or one whose runtime is gone, is not
# there: install.sh deletes it, then creates the slot's on the pinned one.
cp "$scratch/devices.json" "$scratch/installed.json"
cat >"$scratch/devices.json" <<'JSON'
{"devices": {
  "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
    {"name": "SlackwaterCI-1-iPhone", "udid": "1", "isAvailable": true}, {"name": "SlackwaterCI-1-iPad", "udid": "2", "isAvailable": true},
    {"name": "SlackwaterCI-2-iPhone", "udid": "3", "isAvailable": false}, {"name": "SlackwaterCI-2-iPad", "udid": "4", "isAvailable": true},
    {"name": "SlackwaterCI-3-iPhone", "udid": "5", "isAvailable": true}
  ],
  "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
    {"name": "SlackwaterCI-3-iPad", "udid": "6", "isAvailable": true}
  ]
}}
JSON
out=$(install)
same 'install with devices off the pinned runtime' "$(printf '%s\n' \
    'xcrun simctl shutdown 3' \
    'xcrun simctl delete 3' \
    "xcrun simctl create SlackwaterCI-2-iPhone $iphone $runtime" \
    'xcrun simctl shutdown 6' \
    'xcrun simctl delete 6' \
    "xcrun simctl create SlackwaterCI-3-iPad $ipad $runtime")" "$out"
mv "$scratch/installed.json" "$scratch/devices.json"

# A listing that is not a device list stops the install before any simulator
# is created: read as empty, it would put new devices beside the old ones.
cp "$scratch/devices.json" "$scratch/installed.json"
printf '%s\n' '{"error": "CoreSimulatorService connection became invalid"}' >"$scratch/devices.json"
if install >"$scratch/out" 2>"$scratch/err"; then fail 'install.sh accepted a malformed device listing'; fi
grep -q 'create' "$scratch/out" && fail "install.sh created a device from a malformed listing: $(cat "$scratch/out")"
grep -q 'did not print a device list' "$scratch/err" || fail "install.sh on a malformed listing said: $(cat "$scratch/err")"
mv "$scratch/installed.json" "$scratch/devices.json"
printf '%s\n' 'not json' >"$scratch/xctest.json"
if install >"$scratch/out" 2>"$scratch/err"; then fail 'install.sh accepted a malformed XCTestDevices listing'; fi
grep -q 'create' "$scratch/out" && fail "install.sh created a device beside a malformed XCTestDevices listing: $(cat "$scratch/out")"
grep -q 'is not a device list' "$scratch/err" || fail "install.sh on a malformed XCTestDevices listing said: $(cat "$scratch/err")"
printf '%s\n' '{"devices": {}}' >"$scratch/xctest.json"

# A changed plist reloads its job.
printf '<!-- old -->\n' >>"$home/Library/LaunchAgents/io.openwaters.slackwater.ci-runner.2.plist"
plist=$home/Library/LaunchAgents/io.openwaters.slackwater.ci-runner.2.plist
out=$(install)
same 'install with a changed plist' "$(printf '%s\n' \
    "launchctl bootout gui/$uid/io.openwaters.slackwater.ci-runner.2" \
    "write $plist" \
    "launchctl bootstrap gui/$uid $plist")" "$out"

printf 'runner install checks passed\n'
