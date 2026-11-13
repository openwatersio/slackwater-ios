#!/bin/sh
# Refuse any job that is not a push to main or a same-repository pull request
# from a human. Runs on the runner before every job, where a pull request
# cannot edit it.
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
[ "$trusted" = 1 ] || {
    printf 'refusing %s from %s: not a trusted run for this runner\n' "$GITHUB_EVENT_NAME" "$GITHUB_ACTOR" >&2
    exit 1
}
