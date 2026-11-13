#!/bin/sh
# Refuse any job that is not a push to main or a same-repository pull request
# from a human. Runs on the runner before every job, where a pull request
# cannot edit it.
#
# A failing hook alone is not enough: the runner marks the job failed but its
# steps runner still starts, and a step under `if: always()` runs. So a
# refusal kills this job's Runner.Worker before any step can start. The
# ephemeral runner then exits and launchd brings up a fresh one.
#
# Only when this file is the hook the runner's .env names: the CI jobs run
# this script's test inside a real job, under a Runner.Worker of their own,
# from the checkout's copy. A workflow cannot change which file the runner
# calls. Run by hand or from the test, it only exits 1.
set -eu
trusted=0
case "$GITHUB_EVENT_NAME" in
    push)
        [ "$GITHUB_REF" = refs/heads/main ] && trusted=1
        ;;
    pull_request)
        head=$(jq -r '.pull_request.head.repo.full_name // empty' "$GITHUB_EVENT_PATH")
        if [ "$head" = "$GITHUB_REPOSITORY" ] && [ "$GITHUB_ACTOR" != 'dependabot[bot]' ]; then trusted=1; fi
        ;;
esac
[ "$trusted" = 1 ] && exit 0

printf 'refusing %s from %s: not a trusted run for this runner\n' "$GITHUB_EVENT_NAME" "$GITHUB_ACTOR" >&2
[ -n "${ACTIONS_RUNNER_HOOK_JOB_STARTED:-}" ] && [ "$0" -ef "$ACTIONS_RUNNER_HOOK_JOB_STARTED" ] || exit 1
pid=$$
while [ "$pid" -gt 1 ]; do
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') || break
    [ -n "$pid" ] || break
    if [ "$(ps -o comm= -p "$pid" 2>/dev/null | sed 's|.*/||')" = Runner.Worker ]; then
        kill -9 "$pid"
        break
    fi
done
exit 1
