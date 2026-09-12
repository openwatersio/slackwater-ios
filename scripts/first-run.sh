#!/bin/zsh
# A true first launch: erase a dedicated simulator, boot it, then build and run
# onto it from Xcode. Uninstalling the app is not enough — the simulator keeps
# the location permission, the App Group defaults and iCloud across it.
#
#   ./scripts/first-run.sh                          # "SW First Run iPhone 17"
#   ./scripts/first-run.sh "iPad Pro 11-inch (M5)"  # "SW First Run iPad Pro 11-inch (M5)"
#
# The "SW First Run" prefix is what keeps this away from a simulator you keep
# state on: erase is total.
set -euo pipefail

type="${1:-iPhone 17}"
sim="SW First Run $type"
udid=$(xcrun simctl list devices available | grep -F "$sim (" | head -1 \
  | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/') || true
[[ -n "$udid" ]] || udid=$(xcrun simctl create "$sim" "$type")
xcrun simctl shutdown "$udid" 2>/dev/null || true
xcrun simctl erase "$udid"
xcrun simctl boot "$udid"
open -a Simulator
echo "Erased and booted '$sim'. Choose it in Xcode and run."
