#!/bin/zsh
# Archive, export, and upload Slackwater to TestFlight — fully headless.
# Prereqs (one-time, already done 2026-07-30 — see docs/testflight.md):
#   ~/.appstoreconnect/private_keys/AuthKey_VM6W5HP585.p8   (ASC API key, App Manager)
#   ~/Library/Keychains/slackwater-ci.keychain-db           (Apple Distribution identity)
#   "Slackwater App Store" provisioning profile installed   (scripts/asc.mjs create-profile)
set -euo pipefail
cd "$(dirname "$0")/.."

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
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>R3H8DPTV9C</string>
  <key>signingCertificate</key><string>02FBDB9A5D2DB409A4331349069A8C8B09D73069</string>
  <key>provisioningProfiles</key>
  <dict><key>org.openwaters.slackwater</key><string>Slackwater App Store</string></dict>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath build/Slackwater.xcarchive \
  -exportOptionsPlist build/exportUpload.plist -exportPath build/upload \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8 \
  -authenticationKeyID $KEY_ID -authenticationKeyIssuerID $ISSUER

echo "Uploaded. Build appears in App Store Connect → TestFlight in ~5–15 min (processing)."
