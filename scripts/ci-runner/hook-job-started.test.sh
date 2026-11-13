#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
event=$(mktemp)
stub=$(mktemp -d)
sleeper=
# The sleep the kill test starts is the only process this test signals, and
# only while it is still a sleep.
cleanup() {
    if [ -n "$sleeper" ] && [ "$(/bin/ps -o comm= -p "$sleeper" 2>/dev/null)" = sleep ]; then
        kill "$sleeper" 2>/dev/null || true
    fi
    rm -f "$event" "$event.err"; rm -rf "$stub"
}
trap cleanup EXIT
# CI runs this inside a real job, under a Runner.Worker, and every refusal
# below walks its ancestry. A stand-in ps first on PATH reports a parent of
# pid 1 named sh, so no case can ever find, or kill, a real Runner.Worker.
# With STUB_WORKER set it reports that pid as every other process's parent,
# named Runner.Worker, and its parent as pid 1: the kill test's own sleep.
printf '%s\n' '#!/bin/sh' "printf '%s\\n' \"\$2\" >> '$stub/calls'" \
    'w=${STUB_WORKER:-}' \
    'case "$2" in' \
    '    ppid=) if [ -n "$w" ] && [ "$4" != "$w" ]; then echo "$w"; else echo 1; fi ;;' \
    '    comm=) if [ -n "$w" ] && [ "$4" = "$w" ]; then echo /opt/runner/bin/Runner.Worker; else echo /bin/sh; fi ;;' \
    'esac' > "$stub/ps"
chmod +x "$stub/ps"
PATH="$stub:$PATH"
export PATH
[ "$(command -v ps)" = "$stub/ps" ] || { printf 'the stand-in ps is not first on PATH\n' >&2; exit 1; }
check() {
    expected=$1
    GITHUB_EVENT_NAME=$2
    GITHUB_REF=$3
    GITHUB_REPOSITORY=$4
    GITHUB_ACTOR=$5
    printf '%s\n' "$6" > "$event"
    GITHUB_EVENT_PATH=$event
    export GITHUB_EVENT_NAME GITHUB_REF GITHUB_REPOSITORY GITHUB_ACTOR GITHUB_EVENT_PATH
    if sh "$root/scripts/ci-runner/hook-job-started.sh" 2>/dev/null; then actual=0; else actual=1; fi
    [ "$actual" = "$expected" ] || { printf 'unexpected hook result for %s from %s on %s: %s\n' "$2" "$5" "$3" "$6" >&2; exit 1; }
}
# A pull request event: head repository, author type, head branch.
pr() {
    printf '{"pull_request":{"user":{"type":"%s"},"head":{"ref":"%s","repo":{"full_name":"%s"}}}}' "$2" "$3" "$1"
}
repo=openwatersio/slackwater-ios
check 0 push    refs/heads/main    $repo clarkbw        '{}'
check 1 push    refs/heads/feature $repo clarkbw        '{}'
check 0 pull_request refs/pull/1/merge $repo clarkbw "$(pr $repo User feature)"
check 1 pull_request refs/pull/1/merge $repo someone "$(pr someone/slackwater-ios User feature)"
check 1 pull_request refs/pull/1/merge $repo 'dependabot[bot]' "$(pr $repo Bot dependabot/npm_and_yarn/x-1.2.3)"
# Another bot's pull request from a branch here.
check 1 pull_request refs/pull/1/merge $repo 'renovate[bot]' "$(pr $repo Bot renovate/x)"
# A person who rebased or edited a Dependabot branch does not make its bumps trusted.
check 1 pull_request refs/pull/1/merge $repo clarkbw "$(pr $repo User dependabot/npm_and_yarn/x-1.2.3)"
# Missing fields fail closed.
check 1 pull_request refs/pull/1/merge $repo clarkbw '{"pull_request":{"head":{"ref":"feature","repo":{"full_name":"openwatersio/slackwater-ios"}}}}'
check 1 pull_request refs/pull/1/merge $repo clarkbw '{"pull_request":{"user":{"type":"User"},"head":{"repo":{"full_name":"openwatersio/slackwater-ios"}}}}'
check 1 pull_request refs/pull/1/merge $repo clarkbw '{"pull_request":{"user":{"type":"User"},"head":{"ref":"feature"}}}'
check 1 workflow_dispatch refs/heads/main $repo clarkbw '{}'
check 1 pull_request refs/pull/1/merge $repo clarkbw '{}'

# A refusal with no Runner.Worker above it kills nothing: it says why once
# and exits 1. It still walks its ancestry, through the stand-in ps: one
# parent lookup, one name lookup, then pid 1 ends the walk.
printf '{}\n' > "$event"
: > "$stub/calls"
if GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/feature sh "$root/scripts/ci-runner/hook-job-started.sh" 2>"$event.err"; then
    printf 'the refusal exited 0\n' >&2; exit 1
fi
refusals=$(grep -c '^refusing ' "$event.err" || true)
lines=$(wc -l < "$event.err" | tr -d ' ')
[ "$refusals" = 1 ] && [ "$lines" = 1 ] || { printf 'the refusal printed %s lines, %s of them refusing\n' "$lines" "$refusals" >&2; exit 1; }
walk=$(cat "$stub/calls")
[ "$walk" = "$(printf '%s\n' ppid= comm=)" ] || { printf 'the refusal walked its ancestry as:\n%s\n' "$walk" >&2; exit 1; }

# A hook that aborts before it decides is a refusal: it exits non-zero, says
# why once, and walks its ancestry to kill the job like any other refusal.
# $1 names the case; the rest is the command that runs the hook.
aborts() {
    what=$1; shift
    : > "$stub/calls"
    if "$@" 2>"$event.err"; then printf 'the hook exited 0 %s\n' "$what" >&2; exit 1; fi
    [ "$(grep -c '^refusing ' "$event.err" || true)" = 1 ] || { printf 'the hook %s said:\n%s\n' "$what" "$(cat "$event.err")" >&2; exit 1; }
    walk=$(cat "$stub/calls")
    [ "$walk" = "$(printf '%s\n' ppid= comm=)" ] || { printf 'the hook %s walked its ancestry as:\n%s\n' "$what" "$walk" >&2; exit 1; }
}
# jq failing, as when it is missing or the event file cannot be read.
mkdir "$stub/badjq"
printf '%s\n' '#!/bin/sh' 'exit 2' > "$stub/badjq/jq"
chmod +x "$stub/badjq/jq"
pr $repo User feature > "$event"
aborts 'with a failing jq' env PATH="$stub/badjq:$PATH" GITHUB_EVENT_NAME=pull_request \
    sh "$root/scripts/ci-runner/hook-job-started.sh"
# GITHUB_EVENT_NAME unset, which set -u turns into an exit.
aborts 'with GITHUB_EVENT_NAME unset' env -u GITHUB_EVENT_NAME sh "$root/scripts/ci-runner/hook-job-started.sh"

# A refusal kills the Runner.Worker it finds. The stand-in ps names a sleep
# this test started as the hook's parent Runner.Worker. The sleep is started
# from a subshell that exits at once, so launchd, not this test, reaps it and
# kill -0 stops seeing it as soon as it is gone.
sleeper=$(sh -c 'sleep 60 >/dev/null 2>&1 & echo $!')
[ "$(/bin/ps -o comm= -p "$sleeper" 2>/dev/null)" = sleep ] || { printf 'the kill test could not start its sleep\n' >&2; exit 1; }
printf '{}\n' > "$event"
if STUB_WORKER=$sleeper GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/feature sh "$root/scripts/ci-runner/hook-job-started.sh" 2>/dev/null; then
    printf 'the refusal under a Runner.Worker exited 0\n' >&2; exit 1
fi
tries=0
while kill -0 "$sleeper" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 50 ] || { printf 'the refusal left its Runner.Worker, pid %s, running\n' "$sleeper" >&2; exit 1; }
    sleep 0.1
done
sleeper=
