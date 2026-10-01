#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { print -u2 -- "$1"; exit 1; }

(( $# == 1 )) || fail 'usage: promote-nightly.sh <build>'
build=$1
[[ $build == <-> ]] || fail 'build must contain digits only'
tag_output=$(git tag --list "nightly-*-$build")
tags=()
[[ -z $tag_output ]] || tags=("${(@f)tag_output}")
(( ${#tags} == 1 )) || fail "expected one nightly tag for build $build, found ${#tags}"
tag=$tags[1]
version=${tag#nightly-}
version=${version%-$build}
commit=$(git rev-parse "$tag^{commit}")
git merge-base --is-ancestor "$commit" origin/main || fail "$tag is not reachable from origin/main"
node scripts/asc.mjs verify "$version" "$build" .github/testflight-beta-groups.txt

notes=$TMP/notes.md
saved="docs/release-notes/$version-$build.md"
if [[ -f $saved ]]; then
  cp "$saved" "$notes"
else
  previous_build=$(node scripts/asc.mjs previous-beta "$build")
  previous=$(git tag --list "nightly-*-$previous_build")
  [[ -n $previous ]] || previous=$(git describe --tags --abbrev=0 --match 'v*' "$commit^")
  git merge-base --is-ancestor "$previous" "$commit" || fail "previous Beta is not an ancestor of $tag"
  printf '%s (%s)\n\n' "$version" "$build" > "$notes"
  for sha in "${(@f)$(git rev-list --reverse --first-parent "$previous..$commit")}"; do
    title=$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/pulls" --jq '.[0].title // empty')
    [[ -n $title ]] || title=$(git show -s --format=%s "$sha")
    print -r -- "· $title" >> "$notes"
  done
fi
cat "$notes"
[[ -z ${GITHUB_STEP_SUMMARY:-} ]] || cat "$notes" >> "$GITHUB_STEP_SUMMARY"
node scripts/asc.mjs notes "$build" "$notes"
node scripts/asc.mjs promote "$version" "$build" .github/testflight-beta-groups.txt
