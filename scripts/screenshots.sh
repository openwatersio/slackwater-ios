#!/bin/zsh
# Shoot the website's screenshots — SlackwaterUITests/WebsiteScreenshots.swift
# walks the states and saves PNGs (iPhone 17 Pro Max, 6.9", 1320×2868) into
# SHOT_DIR. They ship as WebP in slackwater.xyz/public/shots:
#
#   ./scripts/screenshots.sh
#   for f in $SHOT_DIR/*.png; do cwebp -q 85 -resize 780 0 $f -o .../public/shots/${f:t:r}.webp; done
#
#   SHOT_DIR=/tmp/shots ./scripts/screenshots.sh   where the PNGs land (default /tmp/slackwater-shots)
#   SLACKWATER_SIM='iPhone 17' ./scripts/screenshots.sh
#
# Runs on the named device itself, not a clone (-parallel-testing-enabled NO),
# so the 9:41 status-bar override set below is what the shots carry. Takes the
# same lock as scripts/test.sh — see its header for why two runs can't share
# the machine.
set -euo pipefail
cd "$(dirname "$0")/.."

sim="${SLACKWATER_SIM:-iPhone 17 Pro Max}"
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
  -only-testing:SlackwaterUITests/WebsiteScreenshots \
  -parallel-testing-enabled NO \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -resultBundlePath build/results-shots.xcresult | tail -20
xcrun simctl status_bar "$udid" clear
ls -la "$TEST_RUNNER_M1_SHOT_DIR"/*.png
