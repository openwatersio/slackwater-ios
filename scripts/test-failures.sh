#!/bin/sh
# Print every failed test in the given result bundles with its failure
# messages, one test per line and its messages indented under it.
#
#   scripts/test-failures.sh build/*.xcresult
#
# `scripts/test.sh` pipes xcodebuild through tail, so its output names a
# failed test and nothing else; the assertion text lives in the bundle. CI
# runs this into the job log and step summary, and reads the same messages to
# decide whether a shard's failures were all XCUITest's own services timing
# out (CLAUDE.md, "Reading a CI failure").
set -eu
for bundle in "$@"; do
  [ -d "$bundle" ] || continue
  xcrun xcresulttool get test-results tests --path "$bundle" 2>/dev/null \
    | jq -r '.. | objects | select(.nodeType == "Test Case" and .result == "Failed")
             | .name, (.. | objects | select(.nodeType == "Failure Message") | "    " + .name)'
done
