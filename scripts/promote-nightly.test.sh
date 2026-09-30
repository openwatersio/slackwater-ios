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
      print 'Nightly notes'
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
    print "release:create:$tag:$target" >> "$PROMOTE_STATE/events"
    ;;
  'release edit')
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

prepare 48
grep -qx '1.15.0 (48)' "$REPO/docs/release-notes/1.15.0.md"
grep -qx '· Improve current arrows' "$REPO/docs/release-notes/1.15.0.md"
grep -qx '· Fix favorite station ordering' "$REPO/docs/release-notes/1.15.0.md"
grep -q '^Worth testing:' "$REPO/docs/release-notes/1.15.0.md"
"$REAL_NODE" -e 'const m=require(process.argv[1]); if (m.version!=="1.15.0" || m.build!==48 || m.tag!=="nightly-1.15.0-48" || !/^[0-9a-f]{40}$/.test(m.commit)) process.exit(1)' "$REPO/docs/release-promotions/1.15.0.json"
[[ $(events '^asc:verify$') == 1 ]]
[[ $(events '^pr:create:') == 1 ]]

release docs/release-promotions/1.15.0.json
[[ $(events '^asc:notes$') == 1 ]]
[[ $(events '^asc:promote$') == 1 ]]
grep -q "^release:create:v1.15.0:$NIGHTLY_COMMIT$" "$STATE/events"
[[ $(events '^release:edit:nightly-1.15.0-48$') == 1 ]]

# A matching existing final release makes reruns repair-only.
release docs/release-promotions/1.15.0.json
[[ $(events '^release:create:v1.15.0:') == 1 ]]

# A changed manifest commit cannot promote another binary.
"$REAL_NODE" -e 'const fs=require("fs"),p=process.argv[1],m=require(p);m.commit="0000000000000000000000000000000000000000";fs.writeFileSync(p,JSON.stringify(m))' "$REPO/docs/release-promotions/1.15.0.json"
before=$(events '^asc:promote$')
! release docs/release-promotions/1.15.0.json || fail 'accepted a changed manifest commit'
[[ $(events '^asc:promote$') == $before ]]

legacy=$(cd "$ROOT" && zsh scripts/testflight.sh --external 2>&1) && fail 'testflight.sh accepted manual promotion'
[[ $legacy == *'takes no arguments'* ]] || fail 'testflight.sh did not explain that manual promotion is gone'

print 'nightly promotion checks passed'
