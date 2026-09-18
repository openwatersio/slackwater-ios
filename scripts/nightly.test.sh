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
git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main

cat > "$REPO/scripts/test.sh" <<'EOF'
#!/bin/zsh
print 'full-test' >> "$NIGHTLY_STATE/events"
[[ "${1:-}" == --full ]]
if [[ "${NIGHTLY_DRIFT:-}" == yes ]]; then
  drift_repo=$(mktemp -d "$NIGHTLY_STATE/drift.XXXXXX")
  git clone -q "$NIGHTLY_ORIGIN" "$drift_repo"
  git -C "$drift_repo" config user.name 'Nightly Test'
  git -C "$drift_repo" config user.email nightly@example.test
  print 'drift' >> "$drift_repo/app.txt"
  git -C "$drift_repo" commit -qam 'Main moved during validation'
  git -C "$drift_repo" push -q origin main
fi
EOF
cat > "$REPO/scripts/testflight.sh" <<'EOF'
#!/bin/zsh
print "upload:$*" >> "$NIGHTLY_STATE/events"
awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2; exit }' project.yml > "$NIGHTLY_STATE/asc-build"
EOF
chmod +x "$REPO/scripts/test.sh" "$REPO/scripts/testflight.sh"

cat > "$FAKEBIN/node" <<'EOF'
#!/bin/zsh
set -eu
if [[ "$1 $2" == 'scripts/asc.mjs builds' ]]; then
  build=$(< "$NIGHTLY_STATE/asc-build")
  groups='[Nightly]'
  [[ "${NIGHTLY_WRONG_GROUP:-}" == yes ]] && groups='[Nightly, Friends & Family]'
  [[ -z $build ]] || print "1.13.0 ($build)  VALID  2026-09-15T09:00:00Z  $groups"
elif [[ "$1 $2" == 'scripts/asc.mjs notes' ]]; then
  print "notes:$3" >> "$NIGHTLY_STATE/events"
else
  print -u2 "unexpected node call: $*"
  exit 1
fi
EOF

cat > "$FAKEBIN/gh" <<'EOF'
#!/bin/zsh
set -euo pipefail
case "$1 $2" in
  'pr list')
    ;;
  'pr create')
    print 'pr-create' >> "$NIGHTLY_STATE/events"
    print 'https://github.test/openwatersio/slackwater-ios/pull/1'
    ;;
  'pr merge')
    print 'merge' >> "$NIGHTLY_STATE/events"
    branch=$(git -C "$NIGHTLY_REPO" branch --show-current)
    merge_repo=$(mktemp -d "$NIGHTLY_STATE/merge.XXXXXX")
    git clone -q "$NIGHTLY_ORIGIN" "$merge_repo"
    git -C "$merge_repo" config user.name 'Nightly Test'
    git -C "$merge_repo" config user.email nightly@example.test
    git -C "$merge_repo" merge -q --squash "origin/$branch"
    git -C "$merge_repo" commit -qm 'Nightly release PR'
    git -C "$merge_repo" push -q origin main
    git -C "$merge_repo" rev-parse HEAD > "$NIGHTLY_STATE/merge-sha"
    git -C "$merge_repo" push -q origin --delete "$branch"
    ;;
  'pr close')
    print 'pr-close' >> "$NIGHTLY_STATE/events"
    branch=$(git -C "$NIGHTLY_REPO" branch --show-current)
    git --git-dir="$NIGHTLY_ORIGIN" branch -D "$branch" >/dev/null 2>&1 || true
    ;;
  'pr view')
    < "$NIGHTLY_STATE/merge-sha"
    ;;
  'release create')
    tag=$3
    target=''
    shift 3
    while (( $# )); do
      if [[ "$1" == --target ]]; then target=$2; break; fi
      shift
    done
    [[ -n "$target" ]]
    git -C "$NIGHTLY_REPO" tag "$tag" "$target"
    git -C "$NIGHTLY_REPO" push -q origin "$tag"
    print "release:$tag" >> "$NIGHTLY_STATE/events"
    ;;
  *)
    print -u2 "unexpected gh call: $*"
    exit 1
    ;;
esac
EOF
chmod +x "$FAKEBIN/node" "$FAKEBIN/gh"

export PATH="$FAKEBIN:$PATH"
export NIGHTLY_STATE=$STATE
export NIGHTLY_REPO=$REPO
export NIGHTLY_ORIGIN=$ORIGIN
export GITHUB_REPOSITORY=openwatersio/slackwater-ios
# The first run sees a new app with no uploads yet.
: > "$STATE/asc-build"

(cd "$REPO" && zsh scripts/nightly.sh)

cat > "$STATE/want-events" <<'EOF'
pr-create
full-test
merge
upload:
release:nightly-1.13.0-39
EOF
diff -u "$STATE/want-events" "$STATE/events"
git -C "$REPO" show origin/main:project.yml | grep -q 'CURRENT_PROJECT_VERSION: 39'
grep -q 'Feature after release' "$REPO/build/nightly-notes.md"

before=$(wc -l < "$STATE/events")
(cd "$REPO" && zsh scripts/nightly.sh)
after=$(wc -l < "$STATE/events")
[[ "$before" == "$after" ]]

change_repo=$(mktemp -d "$STATE/change.XXXXXX")
git clone -q "$ORIGIN" "$change_repo"
git -C "$change_repo" config user.name 'Nightly Test'
git -C "$change_repo" config user.email nightly@example.test
print 'another change' >> "$change_repo/app.txt"
git -C "$change_repo" commit -qam 'Another feature'
git -C "$change_repo" push -q origin main
git -C "$REPO" fetch -q origin main
git -C "$REPO" checkout -q --detach origin/main

export NIGHTLY_DRIFT=yes
! (cd "$REPO" && zsh scripts/nightly.sh)
unset NIGHTLY_DRIFT
tail -3 "$STATE/events" | diff -u - <(printf 'pr-create\nfull-test\npr-close\n')
[[ $(< "$STATE/asc-build") == 39 ]]

git -C "$REPO" fetch -q origin main
git -C "$REPO" checkout -q --detach origin/main
export NIGHTLY_WRONG_GROUP=yes
! (cd "$REPO" && zsh scripts/nightly.sh)
unset NIGHTLY_WRONG_GROUP
! grep -q 'release:nightly-1.13.0-40' "$STATE/events"

before=$(wc -l < "$STATE/events")
! (cd "$REPO" && zsh scripts/nightly.sh)
after=$(wc -l < "$STATE/events")
[[ "$before" == "$after" ]]

print 'nightly release checks passed'
