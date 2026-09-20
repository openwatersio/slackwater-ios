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
cp "$ROOT/scripts/nightly.sh" "$REPO/scripts/nightly.sh"

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
print "upload:$BUILD_NUMBER" >> "$NIGHTLY_STATE/events"
print "$BUILD_NUMBER" > "$NIGHTLY_STATE/asc-build"
EOF
chmod +x "$REPO/scripts/test.sh" "$REPO/scripts/testflight.sh"

cat > "$FAKEBIN/node" <<'EOF'
#!/bin/zsh
set -eu
if [[ "$1 $2" == 'scripts/asc.mjs builds' ]]; then
  build=$(< "$NIGHTLY_STATE/asc-build")
  groups='[Nightly]'
  [[ "${NIGHTLY_WRONG_GROUP:-}" == yes ]] && groups='[Nightly, Beta]'
  [[ -z $build ]] || print "1.13.0 ($build)  VALID  2026-09-15T09:00:00Z  $groups"
else
  print -u2 "unexpected node call: $*"
  exit 1
fi
EOF

cat > "$FAKEBIN/gh" <<'EOF'
#!/bin/zsh
set -euo pipefail
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
fail() { print -u2 "check failed: $1"; exit 1; }
nightly() { (cd "$REPO" && zsh scripts/nightly.sh) }
new_commit() { print "$1" >> "$REPO/app.txt"; git -C "$REPO" commit -qam "$1"; }

# A new app with no uploads yet numbers from project.yml, commits nothing, and
# tags the commit it built.
: > "$STATE/asc-build"
head=$(git -C "$REPO" rev-parse HEAD)
nightly
diff -u <(printf 'upload:39\nrelease:nightly-1.13.0-39\n') "$STATE/events"
[[ $(git -C "$REPO" rev-parse HEAD) == $head ]]
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

# A build that reaches an external group is not tagged.
new_commit 'Third feature'
! NIGHTLY_WRONG_GROUP=yes nightly || fail 'a build in an external group passed'
! grep -q 'release:nightly-1.13.0-41' "$STATE/events" || fail 'a build in an external group was tagged'

! grep -q 'test-called' "$STATE/events" || fail 'nightly ran the test suite'
print 'nightly release checks passed'
