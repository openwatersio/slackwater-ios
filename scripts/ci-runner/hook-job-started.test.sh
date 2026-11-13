#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
event=$(mktemp)
trap 'rm -f "$event"' EXIT
# CI runs this inside a real job, under a Runner.Worker; without the runner's
# hook path the refusals below can never kill it.
unset ACTIONS_RUNNER_HOOK_JOB_STARTED
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

# A refusal with no Runner.Worker above it, as here, kills nothing: it says
# why once and exits 1.
printf '{}\n' > "$event"
if GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/feature sh "$root/scripts/ci-runner/hook-job-started.sh" 2>"$event.err"; then
    printf 'the refusal exited 0\n' >&2; exit 1
fi
refusals=$(grep -c '^refusing ' "$event.err" || true)
lines=$(wc -l < "$event.err" | tr -d ' ')
rm -f "$event.err"
[ "$refusals" = 1 ] && [ "$lines" = 1 ] || { printf 'the refusal printed %s lines, %s of them refusing\n' "$lines" "$refusals" >&2; exit 1; }

# As the runner's own hook, the refusal walks its ancestry. A stand-in ps
# reports a parent of launchd's pid 1, named sh, so the walk finds no
# Runner.Worker, ends, and kills nothing; no real process is read.
stub=$(mktemp -d)
printf '%s\n' '#!/bin/sh' 'case "$2" in ppid=) echo 1 ;; comm=) echo /bin/sh ;; esac' > "$stub/ps"
chmod +x "$stub/ps"
if PATH="$stub:$PATH" ACTIONS_RUNNER_HOOK_JOB_STARTED="$root/scripts/ci-runner/hook-job-started.sh" \
    GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/feature sh "$root/scripts/ci-runner/hook-job-started.sh" 2>"$stub/err"; then
    rm -rf "$stub"; printf 'the runner-hook refusal exited 0\n' >&2; exit 1
fi
refusals=$(grep -c '^refusing ' "$stub/err" || true)
rm -rf "$stub"
[ "$refusals" = 1 ] || { printf 'the runner-hook refusal printed %s refusing lines\n' "$refusals" >&2; exit 1; }
