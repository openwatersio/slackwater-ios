#!/bin/zsh
# macOS captures need a standard window; iPad-on-Mac also exposes tiny dialog windows.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage: scripts/mac-screenshots.sh --size
       scripts/mac-screenshots.sh --capture NAME
       scripts/mac-screenshots.sh --set
       scripts/mac-screenshots.sh --verify

--size          Resize Slackwater's standard window for MAC_PIXELS.
--capture NAME  Resize and capture the current screen as NAME.png.
--set           Guide you through five screens and capture each after Return.
--verify        Check the five exported PNGs without touching the app.

SHOT_DIR        Output directory (default /tmp/slackwater-appstore/mac).
MAC_BUNDLE_ID   Override automatic detection of the running Slackwater app.
MAC_PIXELS      2560x1600 (default), 1280x800, 1440x900, or 2880x1800.

Run Slackwater first. Grant your terminal Accessibility and Screen Recording
access in System Settings → Privacy & Security if macOS asks. Capture a normal
window, outside full screen, with no sheet or menu covering it.
EOF
}

[[ $# -gt 0 ]] || { usage; exit 2; }
mode="$1"
case "$mode" in
  --help|-h) usage; exit 0 ;;
  --size|--set|--verify) [[ $# -eq 1 ]] || { usage >&2; exit 2; } ;;
  --capture) [[ $# -eq 2 && "$2" != */* && "$2" != .* && -n "$2" ]] || { usage >&2; exit 2; } ;;
  *) usage >&2; exit 2 ;;
esac
pixels="${MAC_PIXELS:-2560x1600}"
case "$pixels" in
  1280x800|2560x1600) window_width=1280; window_height=800 ;;
  1440x900|2880x1800) window_width=1440; window_height=900 ;;
  *) print -u2 'MAC_PIXELS must be an Apple-accepted Mac screenshot size.'; exit 2 ;;
esac
shot_dir="${SHOT_DIR:-/tmp/slackwater-appstore/mac}"
mkdir -p build/mac-screenshots "$shot_dir"
helper="$PWD/build/mac-screenshots/mac-screenshot"
if [[ ! -x "$helper" || scripts/mac-screenshot.swift -nt "$helper" ]]; then
  xcrun swiftc -parse-as-library scripts/mac-screenshot.swift -o "$helper"
fi

names=(01-currents-slack 02-tide 03-scrubber 04-nearby 05-map)
if [[ "$mode" == --verify ]]; then
  for name in "${names[@]}"; do "$helper" verify "$shot_dir/$name.png" "$pixels"; done
  exit 0
fi
bundle_id="${MAC_BUNDLE_ID:-$("$helper" app)}"

size_window() {
  local placement
  placement=$("$helper" placement "$window_width" "$window_height")
  osascript - "$bundle_id" "$window_width" "$window_height" "${placement%%,*}" "${placement##*,}" <<'APPLESCRIPT'
on run argv
  tell application "System Events"
    set candidates to application processes whose bundle identifier is item 1 of argv
    if count of candidates is not 1 then error "Run exactly one Slackwater process."
    set appProcess to item 1 of candidates
    tell appProcess
      set frontmost to true
      set mainIndex to 0
      repeat with i from 1 to count of windows
        if subrole of window i is "AXStandardWindow" then
          if mainIndex is not 0 then error "Open exactly one normal Slackwater window."
          set mainIndex to i as integer
        end if
      end repeat
      if mainIndex is 0 then error "Open one normal Slackwater window."
      if value of attribute "AXFullScreen" of window mainIndex is true then error "Exit full screen before capturing."
      set position of window mainIndex to {(item 4 of argv) as integer, (item 5 of argv) as integer}
      set size of window mainIndex to {(item 2 of argv) as integer, (item 3 of argv) as integer}
      repeat 20 times
        if size of window mainIndex is {(item 2 of argv) as integer, (item 3 of argv) as integer} then return
        delay 0.25
      end repeat
      error "Slackwater refused the requested size. Check display space and window constraints."
    end tell
  end tell
end run
APPLESCRIPT
  sleep 1
}

capture() {
  local name="${1%.png}" raw window_id
  size_window
  window_id=$("$helper" window "$bundle_id" "$window_width" "$window_height")
  # screencapture refuses hidden filenames, even when the destination directory is writable.
  raw=$(mktemp "$shot_dir/capture-XXXXXX")
  rm -f "$raw"
  raw="$raw.png"
  # -o excludes the shadow, which otherwise changes both aspect ratio and dimensions.
  if ! screencapture -x -o -l "$window_id" -t png "$raw" || [[ ! -s "$raw" ]]; then
    rm -f "$raw"
    print -u2 'Capture failed. Enable Screen Recording for your terminal, then retry.'
    return 1
  fi
  if ! "$helper" export "$raw" "$shot_dir/$name.png" "$pixels"; then
    rm -f "$raw"
    return 1
  fi
  rm -f "$raw"
  "$helper" verify "$shot_dir/$name.png" "$pixels"
  "$helper" metadata "$bundle_id" > "$shot_dir/app-version.txt"
}

case "$mode" in
  --size) size_window; print "Slackwater sized to $window_width × $window_height points." ;;
  --capture) capture "$2" ;;
  --set)
    [[ -t 0 ]] || { print -u2 '--set is interactive; use --capture NAME for unattended captures.'; exit 2; }
    instructions=(
      'Open Deception Pass (Narrows), then click a SLACK row in its schedule.'
      'Open Seattle. Keep the graph and tide reading visible.'
      'Open Friday Harbor, then drag its graph to a nighttime reading away from now.'
      'Open a local place and scroll its detail to Nearby. Keep Favorites visible in the sidebar.'
      'Open the map. Double-click to zoom into the Salish Sea; click empty water to clear a preview. Wait for labels.'
    )
    size_window
    for i in {1..5}; do
      print "\n${names[$i]}: ${instructions[$i]}"
      read "?Press Return here when the screen is ready (Ctrl-C cancels): "
      capture "${names[$i]}"
    done
    print "\nFive Mac screenshots saved in $shot_dir. Upload the PNGs in filename order."
    ;;
esac
