#!/bin/zsh
# Shoot a screenshot walk — a UI-test class that drives the app's surfaces and
# saves PNGs into SHOT_DIR. Two walks use it.
#
# The website's shots (SlackwaterUITests/WebsiteScreenshots.swift, iPhone 17
# Pro Max, 6.9", 1320×2868). They ship as WebP in slackwater.xyz/public/shots:
#
#   ./scripts/screenshots.sh
#   for f in $SHOT_DIR/*.png; do cwebp -q 85 -resize 780 0 $f -o .../public/shots/${f:t:r}.webp; done
#
# The App Store sets (SlackwaterUITests/AppStoreScreenshots.swift, #4) — five
# numbered frames on each of the two sizes App Store Connect requires, which
# upload as they come out. Run both, then upload each directory to its size:
#
#   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/iphone-6.9 \
#     ./scripts/screenshots.sh                                   # 1320×2868
#   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/ipad-13 \
#     SLACKWATER_SIM='iPad Pro 13-inch (M5)' ./scripts/screenshots.sh   # 2064×2752
#
#   SHOT_DIR=/tmp/shots ./scripts/screenshots.sh   where the PNGs land (default /tmp/slackwater-shots)
#   SLACKWATER_SIM='iPhone 17' ./scripts/screenshots.sh
#   WALK=WebsiteScreenshots ./scripts/screenshots.sh  which walk to run (default)
#
# Runs on the named device itself, not a clone (-parallel-testing-enabled NO),
# so the 9:41 status-bar override set below is what the shots carry. Takes the
# same lock as scripts/test.sh — see its header for why two runs can't share
# the machine.
set -euo pipefail
cd "$(dirname "$0")/.."

sim="${SLACKWATER_SIM:-iPhone 17 Pro Max}"
walk="${WALK:-WebsiteScreenshots}"
udid=$(xcrun simctl list devices available | grep -F "$sim (" | head -1 \
  | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[[ -n "$udid" ]] || { echo "no simulator named '$sim'" >&2; exit 1; }
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl status_bar "$udid" override --time 9:41 \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

export TEST_RUNNER_M1_SHOT_DIR="${SHOT_DIR:-/tmp/slackwater-shots}" TEST_RUNNER_SLACKWATER_SHOTS=1
mkdir -p "$TEST_RUNNER_M1_SHOT_DIR"
xcodegen generate
rm -rf build/results-shots.xcresult
lockf /tmp/slackwater-test.lock xcodebuild test \
  -project Slackwater.xcodeproj -scheme Slackwater -testPlan Slackwater \
  -destination "platform=iOS Simulator,id=$udid" \
  -only-testing:SlackwaterUITests/$walk \
  -parallel-testing-enabled NO \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -resultBundlePath build/results-shots.xcresult | tail -20
xcrun simctl status_bar "$udid" clear
ls -la "$TEST_RUNNER_M1_SHOT_DIR"/*.png
