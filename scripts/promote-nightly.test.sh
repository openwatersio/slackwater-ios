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
print direct >> "$REPO/app.txt"
git -C "$REPO" commit -qam 'Direct commit without a PR'
git -C "$REPO" tag nightly-1.15.0-48
NIGHTLY_COMMIT=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" remote add origin "$ORIGIN"
git -C "$REPO" push -q -u origin main --tags

cat > "$FAKEBIN/node" <<'EOF'
#!/bin/zsh
set -euo pipefail
if [[ "$1" == scripts/asc.mjs ]]; then
  [[ $2 != previous-beta ]] || exit 0
  print "asc:${2}" >> "$PROMOTE_STATE/events"
  [[ $2 != notes ]] || cp "$4" "$PROMOTE_STATE/notes"
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
    title=$(git -C "$PROMOTE_REPO" show -s --format=%s "$sha")
    [[ $title != "Direct commit without a PR" ]] || exit 0
    print -r -- "$title"
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
promote() { (cd "$REPO" && zsh scripts/promote-nightly.sh "$1"); }
events() { grep -c "$1" "$STATE/events" 2>/dev/null || true; }

! promote 48x || fail 'accepted a nonnumeric build'
[[ $(events '^asc:') == 0 ]]
missing=$(promote 49 2>&1) && fail 'accepted a missing nightly tag'
[[ $missing == *'expected one nightly tag for build 49, found 0'* ]]
git -C "$REPO" tag nightly-9.9.9-48 "$NIGHTLY_COMMIT"
! promote 48 || fail 'accepted ambiguous tags'
git -C "$REPO" tag -d nightly-9.9.9-48 >/dev/null

touch "$STATE/asc-fail"
! promote 48 || fail 'continued after ASC verification failed'
rm "$STATE/asc-fail"
[[ $(events '^asc:promote$') == 0 ]]
: > "$STATE/events"

promote 48
grep -qx '1.15.0 (48)' "$STATE/notes"
grep -qx '· Improve current arrows' "$STATE/notes"
grep -qx '· Fix favorite station ordering' "$STATE/notes"
grep -qx '· Direct commit without a PR' "$STATE/notes"
[[ $(events '^asc:notes$') == 1 ]]
[[ $(events '^asc:promote$') == 1 ]]
[[ $(events '^release:') == 0 ]]
[[ $(git -C "$REPO" rev-parse HEAD) == $NIGHTLY_COMMIT ]]
[[ $(events '^pr:') == 0 ]]

# A rerun updates Apple without writing GitHub releases or branches.
promote 48
[[ $(events '^release:') == 0 ]]

mkdir -p "$REPO/docs/release-notes"
print 'Collected notes for build 48' > "$REPO/docs/release-notes/1.15.0-48.md"
promote 48
grep -qx 'Collected notes for build 48' "$STATE/notes"

print 'direct nightly promotion checks passed'
