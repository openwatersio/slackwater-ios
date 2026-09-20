#!/bin/zsh
# Archive, export, and upload Slackwater to TestFlight — fully headless.
# Credentials come from the environment (repo secrets in the Nightly
# workflow; see docs/testflight.md for the one-time setup and local runs):
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY    App Store Connect API key (.p8 contents)
#   SIGNING_P12, SIGNING_P12_PASSWORD     Apple Distribution identity, base64 .p12
set -euo pipefail
cd "$(dirname "$0")/.."

# --external also promotes the finished build to EVERY external beta group.
# Opt-in rather than the default because those groups sit behind public links
# and the promotion submits the build to Apple's beta review — a real release,
# not another nightly. The internal Nightly group needs no flag; it takes every
# upload on its own.
#
# It was --family, and that named ONE group. A second external group was added
# later and nothing here knew: build 27 reached three groups, build 28 reached
# two, and the public link kept serving the older release. asc.mjs now
# discovers the external groups instead of naming one, so adding another needs
# no change here. --family still works and means the same thing.
EXTERNAL=no
case "${1:-}" in --external|--family) EXTERNAL=yes ;; esac

: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY:?}" "${SIGNING_P12:?}" "${SIGNING_P12_PASSWORD:?}"
mkdir -p build
TMP=$(mktemp -d)
P8=$TMP/AuthKey_$ASC_KEY_ID.p8
print -r -- "$ASC_KEY" > $P8

# A throwaway keychain holding only the distribution identity. Non-GUI
# sessions see the login keychain as locked, and a keychain with one identity
# makes "Apple Distribution" unambiguous.
KC=$TMP/signing.keychain-db
KC_PASS=$(uuidgen)
OLD_KCS=("${(@f)$(security list-keychains -d user | tr -d ' "')}")
cleanup() {
  security list-keychains -d user -s "${OLD_KCS[@]}"
  security delete-keychain $KC 2>/dev/null || true
  rm -rf $TMP
}
trap cleanup EXIT
security create-keychain -p "$KC_PASS" $KC
security set-keychain-settings -lut 21600 $KC
security unlock-keychain -p "$KC_PASS" $KC
print -r -- "$SIGNING_P12" | base64 --decode > $TMP/signing.p12
security import $TMP/signing.p12 -k $KC -P "$SIGNING_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" $KC > /dev/null
security list-keychains -d user -s $KC "${OLD_KCS[@]}"

node scripts/asc.mjs install-profiles "Slackwater App Store" "Slackwater Widgets App Store"

xcodegen generate
# -clonedSourcePackagesDirPath: repo-local SPM cache so CLI builds never share
# ~/Library/Caches/org.swift.swiftpm with the Xcode GUI — two resolvers racing
# on the MapLibre binary artifact corrupts the shared cache ("already exists
# in file system", 2026-07-31). Agent-run builds should pass the same flag.
# BUILD_NUMBER overrides project.yml's CURRENT_PROJECT_VERSION for every
# target, the widget included (nightly.sh numbers builds from ASC this way).
xcodebuild archive -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'generic/platform=iOS' -archivePath build/Slackwater.xcarchive \
  -clonedSourcePackagesDirPath build/SourcePackages \
  ${BUILD_NUMBER:+CURRENT_PROJECT_VERSION=$BUILD_NUMBER}

cat > build/exportUpload.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <!-- Defaults to YES, and that default is why builds 1-21 numbered themselves:
       Xcode rewrites CFBundleVersion to the next number free on App Store
       Connect at upload time, so the archive's own build number never mattered
       and the ASC number was an upload counter. NO makes project.yml's
       CURRENT_PROJECT_VERSION the build number. It must exceed the highest
       already uploaded or the upload is rejected as a duplicate. -->
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>Z59BQLF5VQ</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <!-- Every signed bundle in the archive needs an entry, the appex included:
       an app's profile does not cover its extensions, and a missing entry
       fails the export AFTER a successful archive. -->
  <key>provisioningProfiles</key>
  <dict>
    <key>io.openwaters.slackwater</key><string>Slackwater App Store</string>
    <key>io.openwaters.slackwater.widgets</key><string>Slackwater Widgets App Store</string>
  </dict>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath build/Slackwater.xcarchive \
  -exportOptionsPlist build/exportUpload.plist -exportPath build/upload \
  -allowProvisioningUpdates \
  -authenticationKeyPath $P8 \
  -authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID

echo "Uploaded. Build appears in App Store Connect → TestFlight in ~5–15 min (processing)."

# Name the build we just uploaded. Bare `promote` takes the newest build ASC
# LISTS, and a fresh upload takes minutes to be listed at all — build 23's
# promote landed on build 22 that way, then 422'd on its already-reviewed state.
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' \
  build/Slackwater.xcarchive/Info.plist)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' \
  build/Slackwater.xcarchive/Info.plist)

# What to Test, from the repo rather than the ASC UI — typed by hand it lands on
# whatever build is selected, which is how builds 22 and 23 shipped with none and
# build 21 ended up carrying 0.6.0's. Waits out processing, like promote does.
NOTES=docs/release-notes/$VERSION.md
if [[ -f $NOTES ]]; then
  node scripts/asc.mjs notes "$BUILD" "$NOTES"
else
  echo "no $NOTES — build $BUILD ships with no release notes"
fi

if [[ $EXTERNAL == yes ]]; then
  # Waits out processing itself, so this blocks for as long as Apple takes.
  node scripts/asc.mjs promote "$BUILD"

  # One GitHub release per TestFlight release, from the same notes file ASC got
  # so the two can never disagree. Only on the external path: a bare run is a
  # build Nightly needs, not a release, and tagging those would put two tags on
  # one version. Never fatal — the build is uploaded and promoted by the time we
  # get here, and a missing tag is a one-liner to add by hand.
  git diff --quiet || echo "warning: working tree dirty — v$VERSION tags HEAD, not what was archived"
  if [[ -f $NOTES ]]; then
    gh release create "v$VERSION" --title "$VERSION ($BUILD)" --notes-file "$NOTES" \
      --target "$(git rev-parse HEAD)" \
      || echo "github release failed — by hand: gh release create v$VERSION --title '$VERSION ($BUILD)' --notes-file $NOTES"
  else
    echo "no $NOTES — no GitHub release for $VERSION ($BUILD)"
  fi
else
  echo "Nightly has it. For the external groups: node scripts/asc.mjs promote $BUILD"
fi

node scripts/asc.mjs builds
