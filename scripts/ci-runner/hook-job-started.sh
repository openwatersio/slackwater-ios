#!/bin/sh
# Refuse any job that is not a push to main or a pull request from a person,
# on a branch in this repository other than a dependabot/ one. Runs on the
# runner before every job, where a pull request cannot edit it.
#
# A failing hook alone is not enough: the runner marks the job failed but its
# steps runner still starts, and a step under `if: always()` runs. So a
# refusal kills this job's Runner.Worker before any step can start. The
# ephemeral runner then exits and launchd brings up a fresh one. With no
# Runner.Worker above it, as when run by hand or when ps fails, it prints a
# second line, "no Runner.Worker above the hook; the job was not killed",
# and exits 1.
#
# Every tool is called by absolute path. The PATH reregister.sh writes into
# .env starts with directories the Studio's user can write, so a name looked
# up there could be anything a trusted job left behind. kill stays the shell
# builtin; sleep is not one in macOS's sh, so it is /bin/sleep.
#
# HOOK_PS and HOOK_JQ replace ps and jq for this script's test only. The CI
# jobs run that test inside a real job, under a Runner.Worker of their own,
# so it points HOOK_PS at a stand-in for every case and no refusal there can
# find a real Runner.Worker. They widen nothing: a same-user attacker who can
# set the runner's environment can also rewrite this file.
set -eu
ps=${HOOK_PS:-/bin/ps}
jq=${HOOK_JQ:-/usr/bin/jq}
refused=0

# Says why once, then walks up to this job's Runner.Worker and kills it, or
# says that it found none.
refuse() {
    refused=1
    printf 'refusing %s from %s: not a trusted run for this runner\n' \
        "${GITHUB_EVENT_NAME:-an unnamed event}" "${GITHUB_ACTOR:-an unknown actor}" >&2
    pid=$$
    while [ "$pid" -gt 1 ]; do
        pid=$("$ps" -o ppid= -p "$pid" 2>/dev/null | /usr/bin/tr -d ' ') || break
        [ -n "$pid" ] || break
        if [ "$("$ps" -o comm= -p "$pid" 2>/dev/null | /usr/bin/sed 's|.*/||')" = Runner.Worker ]; then
            # Gives the worker a moment to flush the line above to the job log.
            /bin/sleep 1
            kill -9 "$pid" || true
            return 0
        fi
    done
    printf 'no Runner.Worker above the hook; the job was not killed\n' >&2
}

# Under set -eu, a missing jq, an unreadable event file or an unset variable
# ends the script before it decides. That is a refusal too, and it must kill
# the job like one: exiting non-zero alone lets the job's steps run. Only the
# trusted exit sets allowed. The trap does not read $?: macOS's sh, bash 3.2,
# hands it 0 after an unbound variable, and would then exit 0.
allowed=0
on_exit() {
    [ "$allowed" = 1 ] && return 0
    set +e
    [ "$refused" = 1 ] || refuse
    exit 1
}
trap on_exit EXIT

trusted=0
case "$GITHUB_EVENT_NAME" in
    push)
        [ "$GITHUB_REF" = refs/heads/main ] && trusted=1
        ;;
    pull_request)
        head=$("$jq" -r '.pull_request.head.repo.full_name // empty' "$GITHUB_EVENT_PATH")
        author=$("$jq" -r '.pull_request.user.type // empty' "$GITHUB_EVENT_PATH")
        branch=$("$jq" -r '.pull_request.head.ref // empty' "$GITHUB_EVENT_PATH")
        # A bot's pull request is refused, and so is anything on a dependabot/
        # branch, whoever pushed to it last: nobody wrote the bumped packages.
        # Any field missing reads empty and is refused.
        case "$branch" in
            '' | dependabot/*) ;;
            *) if [ "$head" = "$GITHUB_REPOSITORY" ] && [ "$author" = User ]; then trusted=1; fi ;;
        esac
        ;;
esac
if [ "$trusted" = 1 ]; then
    allowed=1
    exit 0
fi

refuse
exit 1
