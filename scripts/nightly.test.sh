#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ORIGIN=$TMP/origin.git
REPO=$TMP/repo
STATE=$TMP/state
FAKEBIN=$TMP/bin
mkdir -p "$STATE" "$FAKEBIN"

git init --bare -q "$ORIGIN"
git init -q -b main "$REPO"
git -C "$REPO" config user.name 'Nightly Test'
git -C "$REPO" config user.email nightly@example.test
mkdir -p "$REPO/scripts"
# Older eligible commits can have release scripts with no CI gate.
sed '/^python3 scripts\/nightly-validation.py /d' "$ROOT/scripts/nightly.sh" > "$REPO/scripts/nightly.sh"
cp "$ROOT/scripts/nightly-validation.py" "$REPO/scripts/nightly-validation.py"
cp "$ROOT/scripts/nightly-validation.py" "$TMP/nightly-validation.py"

cat > "$REPO/project.yml" <<'EOF'
settings:
  base:
    MARKETING_VERSION: 1.13.0
    CURRENT_PROJECT_VERSION: 38
EOF
print 'base' > "$REPO/app.txt"
git -C "$REPO" add .
git -C "$REPO" commit -qm 'Release 1.13.0'
git -C "$REPO" tag v1.13.0
print 'changed' >> "$REPO/app.txt"
git -C "$REPO" commit -qam 'Feature after release'
git -C "$REPO" remote add origin "$ORIGIN"
git -C "$REPO" push -q -u origin main --tags

# Nightly leaves the suite to CI; any call here is a regression.
cat > "$REPO/scripts/test.sh" <<'EOF'
#!/bin/zsh
print 'test-called' >> "$NIGHTLY_STATE/events"
exit 1
EOF
cat > "$REPO/scripts/testflight.sh" <<'EOF'
#!/bin/zsh
set -euo pipefail
print "upload:$BUILD_NUMBER" >> "$NIGHTLY_STATE/events"
print "$BUILD_NUMBER" > "$NIGHTLY_STATE/asc-build"
if [[ -f "$NIGHTLY_STATE/processing" ]]; then
  mv "$NIGHTLY_STATE/processing" "$NIGHTLY_STATE/unlisted"
fi
if [[ -f "$NIGHTLY_STATE/group-pending" ]]; then
  mv "$NIGHTLY_STATE/group-pending" "$NIGHTLY_STATE/unassigned"
fi
git rev-parse HEAD > "$NIGHTLY_STATE/archive-sha"
[[ ${NIGHTLY_LIST_ERROR:-} != yes ]] || touch "$NIGHTLY_STATE/list-error"
if [[ -f "$NIGHTLY_STATE/list-errors-next" ]]; then
  mv "$NIGHTLY_STATE/list-errors-next" "$NIGHTLY_STATE/list-errors"
fi
BUILD=$BUILD_NUMBER
VERSION=1.13.0
EOF
# Exercise the real post-upload notes path as well as Nightly's caller.
sed -n '/^# What to Test/,$p' "$ROOT/scripts/testflight.sh" >> "$REPO/scripts/testflight.sh"
mkdir -p "$REPO/docs/release-notes"
print 'Nightly notes' > "$REPO/docs/release-notes/1.13.0.md"
chmod +x "$REPO/scripts/test.sh" "$REPO/scripts/testflight.sh"

cat > "$FAKEBIN/node" <<'EOF'
#!/bin/zsh
set -eu
if [[ "$1 $2" == 'scripts/asc.mjs builds' ]]; then
  print 'listing' >> "$NIGHTLY_STATE/listings"
  build=$(< "$NIGHTLY_STATE/asc-build")
  pending=$(cat "$NIGHTLY_STATE/list-errors" 2>/dev/null || print 0)
  if (( pending > 0 )); then
    print $(( pending - 1 )) > "$NIGHTLY_STATE/list-errors"
    print -u2 "ASC API temporarily unavailable"
    exit 1
  fi
  [[ ! -f "$NIGHTLY_STATE/list-error" ]] || { print -u2 "ASC API unavailable"; exit 1; }
  groups='[Nightly]'
  processing=${NIGHTLY_PROCESSING_STATE:-VALID}
  pending=$(cat "$NIGHTLY_STATE/processing-listed" 2>/dev/null || print 0)
  if (( pending > 0 )); then
    processing=PROCESSING
    print $(( pending - 1 )) > "$NIGHTLY_STATE/processing-listed"
  fi
  [[ "${NIGHTLY_WRONG_GROUP:-}" == yes ]] && groups='[Nightly, Beta]'
  pending=$(cat "$NIGHTLY_STATE/unlisted" 2>/dev/null || print 0)
  if (( pending > 0 )); then
    print $(( pending - 1 )) > "$NIGHTLY_STATE/unlisted"
    exit 0
  fi
  # The first N listings show the build before its group assignment.
  pending=$(cat "$NIGHTLY_STATE/unassigned" 2>/dev/null || print 0)
  if (( pending > 0 )); then
    groups='[]'
    print $(( pending - 1 )) > "$NIGHTLY_STATE/unassigned"
  fi
  [[ -z $build ]] || print "11.13.0 ($build)  VALID  2026-09-15T09:00:00Z  [Beta]"
  [[ -z $build ]] || print "1.13.0 ($build)  $processing  2026-09-15T09:00:00Z  $groups"
elif [[ "$1 $2" == 'scripts/asc.mjs notes' ]]; then
  for counter in unlisted processing-listed; do
    pending=$(cat "$NIGHTLY_STATE/$counter" 2>/dev/null || print 0)
    (( pending == 0 )) || { print -u2 'notes called before Nightly finished waiting'; exit 1; }
  done
  print "$3" >> "$NIGHTLY_STATE/notes"
else
  print -u2 "unexpected node call: $*"
  exit 1
fi
EOF

cat > "$FAKEBIN/gh" <<'EOF'
#!/bin/zsh
set -euo pipefail
if [[ "$1" == api ]]; then
  [[ ${NIGHTLY_API_ERROR:-} != yes ]] || exit 1
  python3 - "$NIGHTLY_REPO" "$*" <<'PYGH'
import json, os, subprocess, sys
sha = os.environ.get("NIGHTLY_GREEN_SHA") or subprocess.check_output(["git", "-C", sys.argv[1], "rev-parse", "HEAD"], text=True).strip()
if "workflows/ci.yml" in sys.argv[2]:
    run = {"id": 123, "run_attempt": 1, "head_sha": sha, "head_branch": "main", "event": "push", "status": "completed", "conclusion": os.environ.get("NIGHTLY_CI_CONCLUSION", "success")}
    runs = [run]
    if "head_sha=" not in sys.argv[2] and os.environ.get("NIGHTLY_NEWER_SHA"):
        runs.insert(0, {**run, "id": 124, "head_sha": os.environ["NIGHTLY_NEWER_SHA"], "status": "in_progress", "conclusion": None})
    print(json.dumps([{"workflow_runs": runs}]))
else:
    names = ["Build for testing"] + [f"App tests · {s}{d}" for s in ("offline", "list", "transition", "detail", "rest") for d in ("", " · iPad")]
    print(json.dumps([{"jobs": [{"id": i, "run_attempt": 1, "name": n, "status": "completed", "conclusion": "success"} for i, n in enumerate(names)]}]))
PYGH
  exit
fi
[[ "$1 $2" == 'release create' ]] || { print -u2 "unexpected gh call: $*"; exit 1; }
tag=$3
shift 3
while [[ "$1" != --target ]]; do shift; done
git -C "$NIGHTLY_REPO" tag "$tag" "$2"
git -C "$NIGHTLY_REPO" push -q origin "$tag"
print "release:$tag" >> "$NIGHTLY_STATE/events"
EOF
chmod +x "$FAKEBIN/node" "$FAKEBIN/gh"

export PATH="$FAKEBIN:$PATH"
export NIGHTLY_STATE=$STATE
export NIGHTLY_REPO=$REPO
export GITHUB_REPOSITORY=example/slackwater
export NIGHTLY_POLL_SECONDS=0
export RUNNER_TEMP=$TMP
fail() { print -u2 "check failed: $1"; exit 1; }
RELEASE_COMMAND=$(ruby -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0]), aliases: true).dig("jobs", "release", "steps").find { |s| s["run"]&.include?("zsh scripts/nightly.sh") }.fetch("run")' "$ROOT/.github/workflows/nightly.yml")
nightly() { (cd "$REPO" && bash -e -c "$RELEASE_COMMAND") }
new_commit() { print "$1" >> "$REPO/app.txt"; git -C "$REPO" commit -qam "$1"; }

# A new app with no uploads yet numbers from project.yml, commits nothing, and
# tags the commit it built.
: > "$STATE/asc-build"
head=$(git -C "$REPO" rev-parse HEAD)
SELECT_COMMAND=$(ruby -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0]), aliases: true).dig("jobs", "authorize", "steps").find { |s| s["id"] == "select" }.fetch("run")' "$ROOT/.github/workflows/nightly.yml")
select_candidate() {
  : > "$STATE/output"
  (cd "$REPO" && GITHUB_SHA="$1" GITHUB_OUTPUT="$STATE/output" bash -e -c "$SELECT_COMMAND")
}
# No candidate skips release; an API outage must still fail the workflow step.
NIGHTLY_CI_CONCLUSION=failure select_candidate "$head"
[[ ! -s "$STATE/output" ]] || fail 'selection emitted an unvalidated SHA'
! NIGHTLY_API_ERROR=yes select_candidate "$head" || fail 'selection swallowed an API failure'
[[ ! -s "$STATE/output" ]] || fail 'API failure emitted a SHA'

export NIGHTLY_GREEN_SHA=$head
new_commit 'Still running CI'
export NIGHTLY_NEWER_SHA=$(git -C "$REPO" rev-parse HEAD)
select_candidate "$NIGHTLY_NEWER_SHA"
selected=$(< "$STATE/output")
[[ $selected == "sha=$head" ]] || fail "selected the pending commit: $selected"
git -C "$REPO" checkout -q --detach "${selected#sha=}"
unset NIGHTLY_GREEN_SHA NIGHTLY_NEWER_SHA
# A refusal is a quiet skip, not a red run.
NIGHTLY_CI_CONCLUSION=failure nightly | grep -q '::warning::Nightly blocked' || fail "refusal was not a warning"
[[ ! -e "$STATE/events" ]] || fail "published before full validation"
nightly
diff -u <(printf 'upload:39\nrelease:nightly-1.13.0-39\n') "$STATE/events"
[[ $(git -C "$REPO" rev-parse HEAD) == $head ]]
[[ $(< "$STATE/archive-sha") == $head ]] || fail 'archived a commit other than the green selection'
[[ $(git -C "$REPO" rev-parse 'nightly-1.13.0-39^{commit}') == $head ]]
git -C "$REPO" diff --quiet
grep -q 'Feature after release' "$REPO/build/nightly-notes.md"

# Nothing new since the tag: no upload.
before=$(wc -l < "$STATE/events")
nightly
[[ $(wc -l < "$STATE/events") == $before ]]

# ASC is ahead of project.yml now, so it sets the number.
new_commit 'Another feature'
nightly
tail -2 "$STATE/events" | diff -u - <(printf 'upload:40\nrelease:nightly-1.13.0-40\n')
grep -q 'Another feature' "$REPO/build/nightly-notes.md"
! grep -q 'Feature after release' "$REPO/build/nightly-notes.md" || fail 'notes repeat commits from before the last tag'

# A build listed before its group assignment is waited for, then tagged.
new_commit 'Late group'
print 3 > "$STATE/group-pending"
nightly
tail -2 "$STATE/events" | diff -u - <(printf 'upload:41\nrelease:nightly-1.13.0-41\n')

# Listing can take the full 15 minutes, with a separate group wait afterward.
new_commit 'Slow processing'
print 30 > "$STATE/processing"
print 10 > "$STATE/group-pending"
nightly
tail -2 "$STATE/events" | diff -u - <(printf 'upload:42\nrelease:nightly-1.13.0-42\n')

# An upload never listed has its own timeout and creates no release.
new_commit 'Never listed'
print 99 > "$STATE/processing"
output=$(nightly 2>&1) && fail 'an unlisted build passed'
[[ $output == *'never listed on App Store Connect after 15 minutes'* ]] || fail "$output"
[[ $(< "$STATE/unlisted") == 68 ]] || fail 'listing wait exceeded its budget'
rm "$STATE/unlisted"

# A build that reaches an external group is not tagged.
new_commit 'Third feature'
output=$(NIGHTLY_WRONG_GROUP=yes nightly 2>&1) && fail 'a build in an external group passed'
[[ $output == *'wrong group'* ]] || fail "$output"
! grep -q 'release:nightly-1.13.0-44' "$STATE/events" || fail 'a build in an external group was tagged'

# A group that never shows still fails.
new_commit 'Never assigned'
print 99 > "$STATE/group-pending"
output=$(nightly 2>&1) && fail 'a build with no group passed'
[[ $output == *'listed without a group after 5 minutes'* ]] || fail "$output"
! grep -Eq 'release:nightly-1.13.0-(43|44|45)' "$STATE/events" || fail 'a timed-out build was tagged'
[[ $(< "$STATE/unassigned") == 88 ]] || fail 'group wait exceeded its budget'
rm "$STATE/unassigned"

# A listed build may still be processing even with its group already assigned.
new_commit 'Listed but processing'
print 35 > "$STATE/processing-listed"
print 10 > "$STATE/group-pending"
nightly
[[ $(< "$STATE/processing-listed") == 0 ]] || fail 'did not wait for processing'

# Processing keeps its 30-minute budget.
new_commit 'Processing timeout'
before=$(wc -l < "$STATE/listings")
output=$(NIGHTLY_PROCESSING_STATE=PROCESSING nightly 2>&1) && fail 'a processing build passed'
[[ $output == *'still processing after 30 minutes'* ]] || fail "$output"
(( $(wc -l < "$STATE/listings") - before == 62 )) || fail 'processing wait exceeded its budget'

# Terminal processing failures fail immediately.
new_commit 'Invalid upload'
output=$(NIGHTLY_PROCESSING_STATE=INVALID nightly 2>&1) && fail 'an invalid build passed'
[[ $output == *'failed processing'* ]] || fail "$output"

new_commit 'API unavailable'
before=$(wc -l < "$STATE/listings")
output=$(NIGHTLY_LIST_ERROR=yes nightly 2>&1) && fail 'an API failure passed'
[[ $output == *'ASC API unavailable'* && $output == *'failed after 3 retries'* && $output != *'never listed'* ]] || fail 'API failure disguised as processing timeout'
(( $(wc -l < "$STATE/listings") - before == 5 )) || fail 'API retry limit exceeded'
! grep -q 'release:nightly-1.13.0-49' "$STATE/events" || fail 'API failure created a release'
rm "$STATE/list-error"

new_commit 'Transient API errors'
print 3 > "$STATE/list-errors-next"
nightly
tail -2 "$STATE/events" | diff -u - <(printf 'upload:50\nrelease:nightly-1.13.0-50\n')

# Notes target each VALID upload, including builds that fail the group gate.
diff -u <(printf '39\n40\n41\n42\n44\n45\n46\n50\n') "$STATE/notes"

# Manual uploads still attach notes through the real nondeferred tail.
(cd "$REPO" && BUILD_NUMBER=51 ./scripts/testflight.sh)
[[ $(tail -1 "$STATE/notes") == 51 ]] || fail 'manual upload did not attach notes'

! grep -q 'test-called' "$STATE/events" || fail 'nightly ran the test suite'
print 'nightly release checks passed'
