#!/bin/sh
# Start one ephemeral CI runner slot: clean the slot's simulators, register a
# fresh runner with a new token, and become the runner. launchd runs this from
# ~/actions-runner/studio-<slot>/ and starts it again each time the runner
# exits after its one job.
#
# SLOT=<1-3> is required. SLACKWATER_CI_SCRIPTS=<dir> refreshes the hook and
# cleanup scripts from a checkout first; without it the copies already in the
# runner directory run. RUNNER_TOKEN_CMD=<command> replaces the token minting,
# which otherwise reads a fine-grained token from the login Keychain.
# RUNNER_DRY_RUN=1 prints the commands instead of running them, and the .env
# it would write on stderr.
set -eu
case "${SLOT:-}" in
    1|2|3) ;;
    *) printf 'reregister.sh: SLOT must be 1, 2 or 3, got "%s"\n' "${SLOT:-}" >&2; exit 64 ;;
esac
repo=openwatersio/slackwater-ios
runner_dir=$HOME/actions-runner/studio-$SLOT
cd "$runner_dir"

run() {
    if [ -n "${RUNNER_DRY_RUN:-}" ]; then printf '%s\n' "$*"; else "$@"; fi
}

# Prints a short-lived registration or removal token for this repository.
mint() {
    if [ -n "${RUNNER_TOKEN_CMD:-}" ]; then
        sh -c "$RUNNER_TOKEN_CMD"
    elif [ -n "${RUNNER_DRY_RUN:-}" ]; then
        printf 'DRY_RUN_TOKEN\n'
    else
        # Separate, so a missing Keychain item fails here instead of letting
        # gh fall back to whatever account it is logged in as.
        gh_token=$(security find-generic-password -s slackwater-ci-runner -w) || return 1
        GH_TOKEN=$gh_token gh api -X POST "repos/$repo/actions/runners/$1" --jq .token
    fi
}

if [ -n "${SLACKWATER_CI_SCRIPTS:-}" ]; then
    run cp "$SLACKWATER_CI_SCRIPTS/hook-job-started.sh" "$SLACKWATER_CI_SCRIPTS/cleanup-slot.sh" \
        "$SLACKWATER_CI_SCRIPTS/reregister.sh" "$runner_dir/"
fi

# The runner loads .env into every job's environment. The workflow reads the
# slot from it, and launchd's PATH does not reach the job otherwise.
env_file=$(printf '%s\n' \
    "SLACKWATER_CI_SLOT=$SLOT" \
    "ACTIONS_RUNNER_HOOK_JOB_STARTED=$runner_dir/hook-job-started.sh" \
    "PATH=/opt/homebrew/bin:$HOME/.local/share/mise/shims:/usr/bin:/bin:/usr/sbin:/sbin")
if [ -n "${RUNNER_DRY_RUN:-}" ]; then
    printf 'would write %s/.env:\n%s\n' "$runner_dir" "$env_file" >&2
else
    printf '%s\n' "$env_file" >"$runner_dir/.env"
fi

run zsh ./cleanup-slot.sh "$SLOT"

# An ephemeral runner removes its local registration when its job ends. One
# killed mid-job (a reboot, a crash) leaves it, and config.sh refuses to
# configure over it.
# Tokens are assigned before use so a failed mint stops the script here.
if [ -e .runner ]; then
    token=$(mint remove-token)
    run ./config.sh remove --token "$token"
fi

token=$(mint registration-token)
run ./config.sh --unattended --ephemeral --replace --url "https://github.com/$repo" \
    --token "$token" --name "studio-$SLOT" --labels studio --work _work

if [ -n "${RUNNER_DRY_RUN:-}" ]; then
    printf '%s\n' './run.sh'
else
    exec ./run.sh
fi
