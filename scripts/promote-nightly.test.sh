#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ORIGIN=$TMP/origin.git
REPO=$TMP/repo
STATE=$TMP/state
FAKEBIN=$TMP/bin
REAL_NODE=$(command -v node)
mkdir -p "$STATE" "$FAKEBIN"
: > "$STATE/events"

git init --bare -q "$ORIGIN"
git init -q -b main "$REPO"
git -C "$REPO" config user.name 'Promotion Test'
git -C "$REPO" config user.email promotion@example.test
mkdir -p "$REPO/scripts" "$REPO/.github"
cp "$ROOT/scripts/promote-nightly.sh" "$REPO/scripts/promote-nightly.sh" 2>/dev/null || true
print Beta > "$REPO/.github/testflight-beta-groups.txt"
print base > "$REPO/app.txt"
git -C "$REPO" add .
git -C "$REPO" commit -qm 'Release 1.14.0'
git -C "$REPO" tag v1.14.0
print arrows >> "$REPO/app.txt"
git -C "$REPO" commit -qam 'Improve current arrows'
print favorites >> "$REPO/app.txt"
git -C "$REPO" commit -qam 'Fix favorite station ordering'
git -C "$REPO" tag nightly-1.15.0-48
NIGHTLY_COMMIT=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" remote add origin "$ORIGIN"
git -C "$REPO" push -q -u origin main --tags

cat > "$FAKEBIN/node" <<'EOF'
#!/bin/zsh
set -euo pipefail
if [[ "$1" == scripts/asc.mjs ]]; then
  print "asc:${2}" >> "$PROMOTE_STATE/events"
  [[ -f "$PROMOTE_STATE/asc-fail" ]] && { print -u2 'App Store Connect mismatch'; exit 1; }
  exit 0
fi
exec "$PROMOTE_REAL_NODE" "$@"
EOF

cat > "$FAKEBIN/gh" <<'EOF'
#!/bin/zsh
set -euo pipefail
case "$1 $2" in
  'release view')
    tag=$3
    if [[ $tag == nightly-* ]]; then
      if [[ -f "$PROMOTE_STATE/annotated" ]]; then
        print 'Nightly notes\n\nPromoted to v1.15.0.'
      else
        print 'Nightly notes'
      fi
      exit 0
    fi
    marker="$PROMOTE_STATE/release-${tag}"
    [[ -f $marker ]] || exit 1
    if [[ "$*" == *'--json targetCommitish'* ]]; then
      print "$(< "$marker")"
    else
      print '{}'
    fi
    ;;
  'release create')
    tag=$3
    shift 3
    target=
    while (( $# )); do
      if [[ $1 == --target ]]; then target=$2; break; fi
      shift
    done
    print -r -- "$target" > "$PROMOTE_STATE/release-${tag}"
    git -C "$PROMOTE_REPO" tag "$tag" "$target"
    print "release:create:$tag:$target" >> "$PROMOTE_STATE/events"
    ;;
  'release edit')
    [[ $3 == nightly-* ]] && touch "$PROMOTE_STATE/annotated"
    print "release:edit:$3" >> "$PROMOTE_STATE/events"
    ;;
  'api '*)
    sha=${2##*/commits/}
    sha=${sha%/pulls}
    git -C "$PROMOTE_REPO" show -s --format=%s "$sha"
    ;;
  'pr list')
    exit 0
    ;;
  'pr create')
    print "pr:create:$*" >> "$PROMOTE_STATE/events"
    ;;
  'pr edit')
    print "pr:edit:$*" >> "$PROMOTE_STATE/events"
    ;;
  *)
    print -u2 "unexpected gh call: $*"
    exit 1
    ;;
esac
EOF
chmod +x "$FAKEBIN/node" "$FAKEBIN/gh"

export PATH="$FAKEBIN:$PATH"
export PROMOTE_STATE=$STATE PROMOTE_REPO=$REPO PROMOTE_REAL_NODE=$REAL_NODE
export GITHUB_REPOSITORY=openwatersio/slackwater-ios
fail() { print -u2 "check failed: $1"; exit 1; }
prepare() { (cd "$REPO" && zsh scripts/promote-nightly.sh prepare "$1"); }
release() { (cd "$REPO" && zsh scripts/promote-nightly.sh release "$1"); }
events() { grep -c "$1" "$STATE/events" 2>/dev/null || true; }

# Invalid input is rejected before external commands.
! prepare 48x || fail 'accepted a nonnumeric build'
[[ $(events '^asc:') == 0 ]]

missing=$(prepare 49 2>&1) && fail 'accepted a missing nightly tag'
[[ $missing == *'expected one nightly tag for build 49, found 0'* ]] || fail 'missing tag was not reported clearly'

git -C "$REPO" tag nightly-9.9.9-48 "$NIGHTLY_COMMIT"
! prepare 48 || fail 'accepted multiple nightly tags'
git -C "$REPO" tag -d nightly-9.9.9-48 >/dev/null

git -C "$REPO" checkout -qb unmerged
print unmerged >> "$REPO/app.txt"
git -C "$REPO" commit -qam 'Unmerged change'
git -C "$REPO" tag nightly-1.15.0-49
git -C "$REPO" checkout -q main
! prepare 49 || fail 'accepted an unmerged nightly'

touch "$STATE/asc-fail"
! prepare 48 || fail 'continued after ASC verification failed'
rm "$STATE/asc-fail"
[[ $(events '^pr:create:') == 0 ]]
: > "$STATE/events"

prepare 48
grep -qx '1.15.0 (48)' "$REPO/docs/release-notes/1.15.0.md"
grep -qx '· Improve current arrows' "$REPO/docs/release-notes/1.15.0.md"
grep -qx '· Fix favorite station ordering' "$REPO/docs/release-notes/1.15.0.md"
grep -q '^Worth testing:' "$REPO/docs/release-notes/1.15.0.md"
"$REAL_NODE" -e 'const m=require(process.argv[1]); if (m.version!=="1.15.0" || m.build!==48 || m.tag!=="nightly-1.15.0-48" || !/^[0-9a-f]{40}$/.test(m.commit)) process.exit(1)' "$REPO/docs/release-promotions/1.15.0.json"
[[ $(events '^asc:verify$') == 1 ]]
[[ $(events '^pr:create:') == 1 ]]

# A final tag created after preparation blocks every external mutation.
git -C "$REPO" tag v1.15.0 HEAD
before=$(events '^asc:promote$')
! release docs/release-promotions/1.15.0.json || fail 'accepted a conflicting final tag'
[[ $(events '^asc:promote$') == $before ]]
git -C "$REPO" tag -d v1.15.0 >/dev/null

release docs/release-promotions/1.15.0.json
[[ $(events '^asc:notes$') == 1 ]]
[[ $(events '^asc:promote$') == 1 ]]
grep -q "^release:create:v1.15.0:$NIGHTLY_COMMIT$" "$STATE/events"
[[ $(events '^release:edit:nightly-1.15.0-48$') == 1 ]]

# A matching existing final release makes reruns repair-only.
release docs/release-promotions/1.15.0.json
[[ $(events '^release:create:v1.15.0:') == 1 ]]
[[ $(events '^release:edit:nightly-1.15.0-48$') == 1 ]]

# A changed manifest commit cannot promote another binary.
"$REAL_NODE" -e 'const fs=require("fs"),p=process.argv[1],m=require(p);m.commit="0000000000000000000000000000000000000000";fs.writeFileSync(p,JSON.stringify(m))' "$REPO/docs/release-promotions/1.15.0.json"
before=$(events '^asc:promote$')
! release docs/release-promotions/1.15.0.json || fail 'accepted a changed manifest commit'
[[ $(events '^asc:promote$') == $before ]]

legacy=$(cd "$ROOT" && zsh scripts/testflight.sh --external 2>&1) && fail 'testflight.sh accepted manual promotion'
[[ $legacy == *'takes no arguments'* ]] || fail 'testflight.sh did not explain that manual promotion is gone'

print 'nightly promotion checks passed'
