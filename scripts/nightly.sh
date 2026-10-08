#!/bin/zsh
# Cut a Nightly-only release from trusted main. The workflow owns the trigger
# gate; require the full CI suite for this exact checkout before archiving.
#
# Nothing is committed. The build number comes from App Store Connect and is
# passed to the archive, so project.yml's CURRENT_PROJECT_VERSION only floors it.
# The nightly-<version>-<build> tag on the built commit is the record.
set -euo pipefail
cd "$(dirname "$0")/.."

SHA=$(git rev-parse HEAD)
MARKER=$(git describe --tags --abbrev=0 --match 'v*' --match 'nightly-*' "$SHA" 2>/dev/null || true)
if [[ -n $MARKER && $(git rev-parse "$MARKER^{commit}") == $SHA ]]; then
  echo "No changes since $MARKER."
  exit 0
fi

# Exit 3 is the gate refusing an unvalidated commit: nothing to release, not a failure.
python3 scripts/nightly-validation.py "$SHA" || exit $(( $? == 3 ? 0 : 1 ))

VERSION=$(awk '$1 == "MARKETING_VERSION:" { print $2; exit }' project.yml)
CURRENT_BUILD=$(awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2; exit }' project.yml)
ASC_BUILDS=$(node scripts/asc.mjs builds)
ASC_ROW=${ASC_BUILDS%%$'\n'*}
# An app with no uploads yet lists no builds; count from project.yml alone.
ASC_BUILD=0
if [[ -n $ASC_ROW ]]; then
  [[ $ASC_ROW =~ '\(([0-9]+)\)' ]] && ASC_BUILD=$match[1] || ASC_BUILD=
fi
if [[ -z $VERSION || $CURRENT_BUILD != <-> || $ASC_BUILD != <-> ]]; then
  echo "Could not determine the current version/build from project.yml and App Store Connect." >&2
  exit 1
fi
NEXT_BUILD=$(( CURRENT_BUILD > ASC_BUILD ? CURRENT_BUILD + 1 : ASC_BUILD + 1 ))

mkdir -p build
NOTES=build/nightly-notes.md
{
  echo "Nightly $VERSION ($NEXT_BUILD)"
  echo
  if [[ -n $MARKER ]]; then
    git log --first-parent --format='· %s' "$MARKER..$SHA"
  else
    git log --first-parent --format='· %s' "$SHA"
  fi
} > "$NOTES"

BUILD_NUMBER=$NEXT_BUILD ./scripts/testflight.sh

# ASC can list a processed build before its automatic Nightly assignment shows;
# an empty group column there means not yet, so poll it before judging.
# ponytail: 5 min budget; raise it if [] still outlasts it.
for _ in {1..10}; do
  BUILD_ROW=$(node scripts/asc.mjs builds | grep -F -m1 "$VERSION ($NEXT_BUILD)" || true)
  [[ -z $BUILD_ROW || $BUILD_ROW == *'[]' ]] || break
  sleep ${NIGHTLY_POLL_SECONDS:-30}
done
if ! print -r -- "$BUILD_ROW" | grep -Eq 'VALID.*\[Nightly\]$'; then
  echo "Build did not land exclusively in Nightly: $BUILD_ROW" >&2
  exit 1
fi

gh release create "nightly-$VERSION-$NEXT_BUILD" \
  --title "Nightly $VERSION ($NEXT_BUILD)" \
  --notes-file "$NOTES" \
  --prerelease \
  --target "$SHA"
