#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
event=$(mktemp)
trap 'rm -f "$event"' EXIT
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
    [ "$actual" = "$expected" ] || { printf 'unexpected hook result for %s from %s on %s\n' "$2" "$5" "$3" >&2; exit 1; }
}
check 0 push    refs/heads/main    openwatersio/slackwater-ios clarkbw        '{}'
check 1 push    refs/heads/feature openwatersio/slackwater-ios clarkbw        '{}'
check 0 pull_request refs/pull/1/merge openwatersio/slackwater-ios clarkbw '{"pull_request":{"head":{"repo":{"full_name":"openwatersio/slackwater-ios"}}}}'
check 1 pull_request refs/pull/1/merge openwatersio/slackwater-ios someone '{"pull_request":{"head":{"repo":{"full_name":"someone/slackwater-ios"}}}}'
check 1 pull_request refs/pull/1/merge openwatersio/slackwater-ios 'dependabot[bot]' '{"pull_request":{"head":{"repo":{"full_name":"openwatersio/slackwater-ios"}}}}'
check 1 workflow_dispatch refs/heads/main openwatersio/slackwater-ios clarkbw '{}'
check 1 pull_request refs/pull/1/merge openwatersio/slackwater-ios clarkbw '{}'
