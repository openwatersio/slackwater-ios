#!/bin/zsh
# Archive, export, and upload Slackwater to TestFlight — fully headless.
# Prereqs (one-time, already done 2026-07-30 — see docs/testflight.md):
#   ~/.appstoreconnect/private_keys/AuthKey_VM6W5HP585.p8   (ASC API key, App Manager)
#   ~/Library/Keychains/slackwater-ci.keychain-db           (Apple Distribution identity)
#   "Slackwater App Store" provisioning profile installed   (scripts/asc.mjs create-profile)
set -euo pipefail
cd "$(dirname "$0")/.."

# --family also promotes the finished build to the external Friends & Family
# group. Opt-in rather than the default because that group sits behind a public
# link and every promotion submits the build to Apple's beta review — a real
# release, not another nightly. The internal Nightly group needs no flag; it
# takes every upload on its own.
FAMILY=no
[[ "${1:-}" == "--family" ]] && FAMILY=yes

KEY_ID=VM6W5HP585
ISSUER=69a6de81-5896-47e3-e053-5b8c7c11a4d1
KC=~/Library/Keychains/slackwater-ci.keychain-db
# The identity is pinned by SHA-1 in project.yml (Release CODE_SIGN_IDENTITY)
# and in signingCertificate below: the login keychain holds a second
# same-named "Apple Distribution" identity, and the bare name resolves
# ambiguously (cost the build-10 upload). NOT a CLI override — that would
# leak onto SPM package targets, which must stay unsigned.

security unlock-keychain -p "$(cat ~/.appstoreconnect/ci-keychain-pass)" $KC

xcodegen generate
# -clonedSourcePackagesDirPath: repo-local SPM cache so CLI builds never share
# ~/Library/Caches/org.swift.swiftpm with the Xcode GUI — two resolvers racing
# on the MapLibre binary artifact corrupts the shared cache ("already exists
# in file system", 2026-07-31). Agent-run builds should pass the same flag.
xcodebuild archive -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'generic/platform=iOS' -archivePath build/Slackwater.xcarchive \
  -clonedSourcePackagesDirPath build/SourcePackages

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
  <key>teamID</key><string>R3H8DPTV9C</string>
  <key>signingCertificate</key><string>02FBDB9A5D2DB409A4331349069A8C8B09D73069</string>
  <!-- Every signed bundle in the archive needs an entry, the appex included:
       an app's profile does not cover its extensions, and a missing entry
       fails the export AFTER a successful archive. -->
  <key>provisioningProfiles</key>
  <dict>
    <key>org.openwaters.slackwater</key><string>Slackwater App Store</string>
    <key>org.openwaters.slackwater.widgets</key><string>Slackwater Widgets App Store</string>
  </dict>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath build/Slackwater.xcarchive \
  -exportOptionsPlist build/exportUpload.plist -exportPath build/upload \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8 \
  -authenticationKeyID $KEY_ID -authenticationKeyIssuerID $ISSUER

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

if [[ $FAMILY == yes ]]; then
  # Waits out processing itself, so this blocks for as long as Apple takes.
  node scripts/asc.mjs promote "$BUILD"
else
  echo "Nightly has it. For Friends & Family: node scripts/asc.mjs promote $BUILD"
fi

node scripts/asc.mjs builds
