#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
actual=$(jq -r -f "$root/scripts/test-failed-selectors.jq" <<'JSON'
{"testNodes":[{"nodeType":"Test Plan","children":[
  {"nodeType":"Unit test bundle","name":"SlackwaterTests","children":[
    {"nodeType":"Test Suite","children":[
      {"nodeType":"Test Case","result":"Failed","nodeIdentifier":"UnitTests/testTimeout()"},
      {"nodeType":"Test Case","result":"Passed","nodeIdentifier":"UnitTests/testPassed()"}
    ]}
  ]},
  {"nodeType":"UI test bundle","name":"SlackwaterUITests","children":[
    {"nodeType":"Test Suite","children":[
      {"nodeType":"Test Case","result":"Failed","nodeIdentifier":"UITests/testTimeout()"},
      {"nodeType":"Test Case","result":"Skipped","nodeIdentifier":"UITests/testSkipped()"}
    ]}
  ]}
]}]}
JSON
)
expected='SlackwaterTests/UnitTests/testTimeout
SlackwaterUITests/UITests/testTimeout'
[ "$actual" = "$expected" ] || { printf 'incorrect failed selectors:\n%s\n' "$actual" >&2; exit 1; }
[ -z "$(printf '%s' '{"testNodes":[]}' | jq -r -f "$root/scripts/test-failed-selectors.jq")" ]
printf 'failed-selector checks passed\n'
