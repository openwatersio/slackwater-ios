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

TESTFLIGHT_DEFER_NOTES=1 BUILD_NUMBER=$NEXT_BUILD ./scripts/testflight.sh

# An unlisted upload gets 15 minutes; total processing keeps its 30-minute
# allowance. Automatic group assignment has a separate five-minute budget.
UNLISTED_POLLS=0
PROCESSING_POLLS=0
UNGROUPED_POLLS=0
NOTES_ATTACHED=0
API_FAILURES=0
while true; do
  if ! ASC_BUILDS=$(node scripts/asc.mjs builds); then
    if (( API_FAILURES >= 3 )); then
      echo "App Store Connect build listing failed after 3 retries." >&2
      exit 1
    fi
    API_FAILURES=$(( API_FAILURES + 1 ))
    echo "App Store Connect build listing failed; retry $API_FAILURES/3." >&2
    sleep ${NIGHTLY_POLL_SECONDS:-30}
    continue
  fi
  BUILD_ROW=$(print -r -- "$ASC_BUILDS" | awk -v prefix="$VERSION ($NEXT_BUILD)  " 'index($0, prefix) == 1 { print; exit }')
  if [[ $BUILD_ROW == *'  INVALID  '* || $BUILD_ROW == *'  FAILED  '* ]]; then
    echo "Build failed processing: $BUILD_ROW" >&2
    exit 1
  fi
  if [[ -z $BUILD_ROW || $BUILD_ROW == *'  PROCESSING  '* ]]; then
    if [[ -z $BUILD_ROW ]] && (( UNLISTED_POLLS >= 30 )); then
      echo "Build $VERSION ($NEXT_BUILD) never listed on App Store Connect after 15 minutes." >&2
      exit 1
    fi
    if (( PROCESSING_POLLS >= 60 )); then
      echo "Build still processing after 30 minutes: $BUILD_ROW" >&2
      exit 1
    fi
    [[ -n $BUILD_ROW ]] || UNLISTED_POLLS=$(( UNLISTED_POLLS + 1 ))
    PROCESSING_POLLS=$(( PROCESSING_POLLS + 1 ))
  else
    if [[ $BUILD_ROW != *'  VALID  '* ]]; then
      echo "Build has unexpected processing state: $BUILD_ROW" >&2
      exit 1
    fi
    if (( NOTES_ATTACHED == 0 )); then
      RELEASE_NOTES=docs/release-notes/$VERSION.md
      if [[ -f $RELEASE_NOTES ]]; then
        node scripts/asc.mjs notes "$NEXT_BUILD" "$RELEASE_NOTES"
      else
        echo "no $RELEASE_NOTES — build $NEXT_BUILD ships with no release notes"
      fi
      NOTES_ATTACHED=1
    fi
    if [[ $BUILD_ROW != *'[]' ]]; then
      break
    fi
    if (( UNGROUPED_POLLS >= 10 )); then
      echo "Build listed without a group after 5 minutes: $BUILD_ROW" >&2
      exit 1
    fi
    UNGROUPED_POLLS=$(( UNGROUPED_POLLS + 1 ))
  fi
  sleep ${NIGHTLY_POLL_SECONDS:-30}
done
if ! print -r -- "$BUILD_ROW" | grep -Eq 'VALID.*\[Nightly\]$'; then
  echo "Build listed in the wrong group: $BUILD_ROW" >&2
  exit 1
fi

gh release create "nightly-$VERSION-$NEXT_BUILD" \
  --title "Nightly $VERSION ($NEXT_BUILD)" \
  --notes-file "$NOTES" \
  --prerelease \
  --target "$SHA"
