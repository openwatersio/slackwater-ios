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
beta="beta-$version-$build"
if git rev-parse -q --verify "refs/tags/$beta" >/dev/null; then
  [[ $(git rev-parse "$beta^{commit}") == $commit ]] || fail "$beta points to a different commit"
fi
node scripts/asc.mjs verify "$version" "$build" .github/testflight-beta-groups.txt

notes=$TMP/notes.md
saved="docs/release-notes/$version-$build.md"
if [[ -f $saved ]]; then
  cp "$saved" "$notes"
else
  previous=$(git describe --tags --abbrev=0 --match 'v*' --match 'beta-*' "$commit^")
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

# Each promoted build is the baseline for the next collection of notes.
if gh release view "$beta" >/dev/null 2>&1; then
  [[ $(git rev-parse "$beta^{commit}") == $commit ]] || fail "$beta points to a different commit"
  gh release edit "$beta" --notes-file "$notes"
else
  gh release create "$beta" --title "$version ($build) Beta" --notes-file "$notes" --target "$commit"
fi
