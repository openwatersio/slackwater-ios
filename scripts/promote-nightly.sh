#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CLEANUP_TMP=
trap '[[ -z $CLEANUP_TMP ]] || rm -rf "$CLEANUP_TMP"' EXIT

fail() { print -u2 -- "$1"; exit 1; }

verify_release() {
  local version=$1 build=$2 tag=$3 commit=$4
  [[ $build == <-> ]] || fail 'build must contain digits only'
  [[ $tag == "nightly-$version-$build" ]] || fail "nightly tag does not match $version ($build)"
  [[ ${#commit} == 40 && $commit != *[^0-9a-f]* ]] || fail 'commit must be a 40-character lowercase SHA'
  [[ $(git rev-parse "$tag^{commit}") == $commit ]] || fail "$tag does not point to $commit"
  git merge-base --is-ancestor "$commit" origin/main || fail "$tag is not reachable from origin/main"
  node scripts/asc.mjs verify "$version" "$build" .github/testflight-beta-groups.txt
}

prepare() {
  local build=$1 tag_output tag version commit previous sha title branch existing tmp notes manifest body
  [[ $build == <-> ]] || fail 'build must contain digits only'
  local -a tags
  tag_output=$(git tag --list "nightly-*-$build")
  tags=()
  [[ -z $tag_output ]] || tags=("${(@f)tag_output}")
  (( ${#tags} == 1 )) || fail "expected one nightly tag for build $build, found ${#tags}"
  tag=$tags[1]
  version=${tag#nightly-}
  version=${version%-$build}
  commit=$(git rev-parse "$tag^{commit}")
  git merge-base --is-ancestor "$commit" origin/main || fail "$tag is not reachable from origin/main"
  git rev-parse -q --verify "refs/tags/v$version" >/dev/null && fail "v$version already exists"
  gh release view "v$version" >/dev/null 2>&1 && fail "GitHub release v$version already exists"
  node scripts/asc.mjs verify "$version" "$build" .github/testflight-beta-groups.txt

  previous=$(git describe --tags --abbrev=0 --match 'v*' "$commit^")
  tmp=$(mktemp -d)
  CLEANUP_TMP=$tmp
  notes=$tmp/notes.md
  manifest=$tmp/manifest.json
  body=$tmp/pr.md
  printf '%s (%s)\n\n' "$version" "$build" > "$notes"
  for sha in "${(@f)$(git rev-list --reverse --first-parent "$previous..$commit")}"; do
    title=$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/pulls" --jq '.[0].title // empty')
    [[ -n $title ]] || fail "commit $sha has no merged pull request title"
    print -r -- "· $title" >> "$notes"
  done
  printf '\nWorth testing: Test the changes listed above and report anything that behaves differently from the current Beta.\n' >> "$notes"
  printf '{\n  "version": "%s",\n  "build": %s,\n  "tag": "%s",\n  "commit": "%s"\n}\n' "$version" "$build" "$tag" "$commit" > "$manifest"
  {
    print -r -- "Promotes existing TestFlight build **$version ($build)** after review."
    print
    print -r -- "- Nightly: \`$tag\`"
    print -r -- "- Commit: \`$commit\`"
    print -r -- '- Groups: '
    sed 's/^/  - /' .github/testflight-beta-groups.txt
  } > "$body"

  branch="release/$version-$build"
  git checkout -B "$branch" origin/main
  mkdir -p docs/release-notes docs/release-promotions
  mv "$notes" "docs/release-notes/$version.md"
  mv "$manifest" "docs/release-promotions/$version.json"
  git add "docs/release-notes/$version.md" "docs/release-promotions/$version.json"
  git commit -m "Prepare $version ($build) for Beta"
  git push --force-with-lease -u origin "$branch"
  existing=$(gh pr list --head "$branch" --json number --jq '.[0].number // empty')
  if [[ -n $existing ]]; then
    gh pr edit "$existing" --title "Release $version ($build) to Beta" --body-file "$body"
  else
    gh pr create --base main --head "$branch" --title "Release $version ($build) to Beta" --body-file "$body"
  fi
}

release() {
  local manifest=$1 fields version build tag commit final_commit release_exists=no nightly_notes annotated
  fields=$(node -e 'const fs=require("fs"),m=JSON.parse(fs.readFileSync(process.argv[1],"utf8")),keys=Object.keys(m).sort().join(",");if(keys!=="build,commit,tag,version"||!Number.isSafeInteger(m.build))process.exit(1);process.stdout.write([m.version,m.build,m.tag,m.commit].join("\t"))' "$manifest") || fail "invalid promotion record: $manifest"
  IFS=$'\t' read -r version build tag commit <<< "$fields"
  verify_release "$version" "$build" "$tag" "$commit"

  final_commit=$(git rev-parse -q --verify "refs/tags/v$version^{commit}" 2>/dev/null || true)
  if [[ -n $final_commit && $final_commit != $commit ]]; then
    fail "v$version already points to $final_commit, expected $commit"
  fi
  if gh release view "v$version" >/dev/null 2>&1; then
    release_exists=yes
    [[ $final_commit == $commit ]] || fail "GitHub release v$version has no matching fetched tag"
  fi

  node scripts/asc.mjs notes "$build" "docs/release-notes/$version.md"
  node scripts/asc.mjs promote "$version" "$build" .github/testflight-beta-groups.txt
  if [[ $release_exists == no ]]; then
    gh release create "v$version" --title "$version ($build)" --notes-file "docs/release-notes/$version.md" --target "$commit"
  fi

  nightly_notes=$(gh release view "$tag" --json body --jq '.body')
  if [[ $nightly_notes != *"Promoted to v$version"* ]]; then
    annotated=$(mktemp)
    printf '%s\n\nPromoted to v%s.\n' "$nightly_notes" "$version" > "$annotated"
    gh release edit "$tag" --notes-file "$annotated"
    rm -f "$annotated"
  fi
}

case "${1:-}" in
  prepare) (( $# == 2 )) || fail 'usage: promote-nightly.sh prepare <build>'; prepare "$2" ;;
  release) (( $# == 2 )) || fail 'usage: promote-nightly.sh release <manifest>'; release "$2" ;;
  *) fail 'usage: promote-nightly.sh prepare <build> | release <manifest>' ;;
esac
