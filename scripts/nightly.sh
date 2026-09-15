#!/bin/zsh
# Cut a Nightly-only release from trusted main. The workflow owns the trigger gate.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

BASE_SHA=$(git rev-parse HEAD)
MARKER=$(git describe --tags --abbrev=0 --match 'v*' --match 'nightly-*' "$BASE_SHA" 2>/dev/null || true)
if [[ -n $MARKER && $(git rev-parse "$MARKER^{commit}") == $BASE_SHA ]]; then
  echo "No changes since $MARKER."
  exit 0
fi
if [[ $(git log -1 --format=%s) == Nightly\ * ]]; then
  echo "main ends in an unfinished nightly release; recover that build before retrying." >&2
  exit 1
fi

VERSION=$(awk '$1 == "MARKETING_VERSION:" { print $2; exit }' project.yml)
CURRENT_BUILD=$(awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2; exit }' project.yml)
ASC_BUILDS=$(node scripts/asc.mjs builds)
ASC_ROW=${ASC_BUILDS%%$'\n'*}
if [[ -z $VERSION || $CURRENT_BUILD != <-> || ! $ASC_ROW =~ '\(([0-9]+)\)' ]]; then
  echo "Could not determine the current version/build from project.yml and App Store Connect." >&2
  exit 1
fi
ASC_BUILD=$match[1]
NEXT_BUILD=$(( CURRENT_BUILD > ASC_BUILD ? CURRENT_BUILD + 1 : ASC_BUILD + 1 ))
BRANCH=automation/nightly-$NEXT_BUILD

OPEN_PR=$(gh pr list --state open --head "$BRANCH" --json url --jq '.[0].url // empty')
if [[ -n $OPEN_PR ]]; then
  gh pr close "$OPEN_PR" --delete-branch
fi

git switch -C "$BRANCH" "$BASE_SHA"
sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION: )[0-9]+$/\\1$NEXT_BUILD/" project.yml
git diff --check
git add project.yml
git commit -m "Prepare Slackwater nightly $VERSION ($NEXT_BUILD) [skip ci]"
HEAD_SHA=$(git rev-parse HEAD)
git push origin "HEAD:$BRANCH"

mkdir -p build
NOTES=build/nightly-notes.md
{
  echo "Nightly $VERSION ($NEXT_BUILD)"
  echo
  if [[ -n $MARKER ]]; then
    git log --first-parent --format='· %s' "$MARKER..$BASE_SHA"
  else
    git log --first-parent --format='· %s' "$BASE_SHA"
  fi
} > "$NOTES"

PR_URL=$(gh pr create \
  --base main \
  --head "$BRANCH" \
  --title "Nightly $VERSION ($NEXT_BUILD)" \
  --body "Automated build-number bump for the Nightly-only TestFlight release.")
MERGED=no
cleanup() {
  local exit_code=$?
  trap - EXIT
  if (( exit_code != 0 )) && [[ $MERGED == no ]]; then
    gh pr close "$PR_URL" --delete-branch || true
  fi
  exit $exit_code
}
trap cleanup EXIT

./scripts/test.sh --full

git fetch --quiet origin main
git fetch --quiet origin "$BRANCH"
if [[ $(git rev-parse origin/main) != $BASE_SHA || $(git rev-parse "origin/$BRANCH") != $HEAD_SHA ]]; then
  echo "main or the nightly PR moved during validation; refusing to merge." >&2
  exit 1
fi

gh pr merge "$PR_URL" --squash --delete-branch --match-head-commit "$HEAD_SHA"
MERGED=yes
MERGE_SHA=$(gh pr view "$PR_URL" --json mergeCommit --jq '.mergeCommit.oid')
git fetch --quiet origin main
git checkout --detach "$MERGE_SHA"
if [[ $(git rev-parse "$HEAD_SHA^{tree}") != $(git rev-parse "$MERGE_SHA^{tree}") ]]; then
  echo "Merged tree differs from the validated nightly PR; refusing to upload." >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Validated checkout has tracked changes; refusing to upload." >&2
  exit 1
fi

./scripts/testflight.sh
node scripts/asc.mjs notes "$NEXT_BUILD" "$NOTES"

BUILD_ROW=$(node scripts/asc.mjs builds | grep -F -m1 "$VERSION ($NEXT_BUILD)" || true)
if ! print -r -- "$BUILD_ROW" | grep -Eq 'VALID.*\[Nightly\]$'; then
  echo "Build did not land exclusively in Nightly: $BUILD_ROW" >&2
  exit 1
fi

gh release create "nightly-$VERSION-$NEXT_BUILD" \
  --title "Nightly $VERSION ($NEXT_BUILD)" \
  --notes-file "$NOTES" \
  --prerelease \
  --target "$MERGE_SHA"
