#!/bin/zsh
# Shoot a screenshot walk — a UI-test class that drives the app's surfaces and
# saves PNGs into SHOT_DIR. Two walks use it.
#
# The website's shots (SlackwaterUITests/WebsiteScreenshots.swift, iPhone 18
# Pro Max, 6.9", 1320×2868). They ship as WebP in slackwater.xyz/public/shots:
#
#   ./scripts/screenshots.sh
#   for f in $SHOT_DIR/*.png; do cwebp -q 85 -resize 780 0 $f -o .../public/shots/${f:t:r}.webp; done
#
# The App Store sets (SlackwaterUITests/AppStoreScreenshots.swift, #4) — five
# numbered frames per size, which upload as they come out. App Store Connect
# requires the 6.3" iPhone (it does not scale the 6.9" set into that slot) and
# the 13" iPad; the 6.9" iPhone is optional. Upload each directory to its size:
#
#   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/iphone-6.3 \
#     SLACKWATER_SIM='iPhone 18 Pro' ./scripts/screenshots.sh    # 1206×2622
#   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/iphone-6.9 \
#     ./scripts/screenshots.sh                                   # 1320×2868
#   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/ipad-13 \
#     SLACKWATER_SIM='iPad Pro 13-inch (M5)' ./scripts/screenshots.sh   # 2064×2752
#
#
# The iPhone Duo takes an optional set of its own, either screen's size. The
# simulator boots folded, and only Xcode's device view folds it, so unfold it
# there before the inner run and leave it open. Each shot is of the screen the
# app is on, saved upright at the size App Store Connect takes:
#
#   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/duo-cover \
#     SLACKWATER_SIM='iPhone Duo' ./scripts/screenshots.sh       # 1398×2034, folded
#   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/duo-inner \
#     SLACKWATER_SIM='iPhone Duo' ./scripts/screenshots.sh       # 2853×2007, unfolded
#
# The watch set (SlackwaterWatchUITests/WatchAppStoreScreenshots.swift) runs
# on the largest watch, which App Store Connect scales down for the rest:
#
#   WALK=WatchAppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/watch \
#     ./scripts/screenshots.sh                                   # 422×514
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

walk="${WALK:-WebsiteScreenshots}"
if [[ $walk == Watch* ]]; then
  sim="${SLACKWATER_SIM:-Apple Watch Ultra 4 (49mm)}"
  scheme=(-scheme SlackwaterWatch) target=SlackwaterWatchUITests platform="watchOS Simulator"
else
  sim="${SLACKWATER_SIM:-iPhone 18 Pro Max}"
  scheme=(-scheme Slackwater -testPlan Slackwater) target=SlackwaterUITests platform="iOS Simulator"
fi
udid=$(xcrun simctl list devices available | grep -F "$sim (" | head -1 \
  | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[[ -n "$udid" ]] || { echo "no simulator named '$sim'" >&2; exit 1; }
xcrun simctl bootstatus "$udid" -b >/dev/null   # boots if needed, waits until ready
# The walks' pinned clock (ShotWalk.shotEpoch), date included: an iPad's
# status bar prints the date, and it must agree with the frames' readings.
# simctl takes only UTC with milliseconds and shows it in the host's zone,
# so the bar reads 9:41 on a Mac set to Pacific time. Inside the app the
# iPad's bar names the weekday Sep 26 had in 2000 ("Tue"), a simulator bug;
# the right date with that weekday still beats the host's real date.
shot_time=$(date -u -r 1790440860 +%Y-%m-%dT%H:%M:%S.000Z)
# watchOS has no status-bar overrides; its corner clock reads the host's.
[[ $walk == Watch* ]] || xcrun simctl status_bar "$udid" override --time "$shot_time" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

export TEST_RUNNER_M1_SHOT_DIR="${SHOT_DIR:-/tmp/slackwater-shots}" TEST_RUNNER_SLACKWATER_SHOTS=1
mkdir -p "$TEST_RUNNER_M1_SHOT_DIR"
xcodegen generate
rm -rf build/results-shots.xcresult
mkdir -p build
lockf build/xcodebuild.lock xcodebuild test \
  -project Slackwater.xcodeproj "${scheme[@]}" \
  -destination "platform=$platform,id=$udid" \
  -only-testing:$target/$walk \
  -parallel-testing-enabled NO \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -resultBundlePath build/results-shots.xcresult | tail -20
[[ $walk == Watch* ]] || xcrun simctl status_bar "$udid" clear
ls -la "$TEST_RUNNER_M1_SHOT_DIR"/*.png
