#!/bin/bash
# Run fit-validation file mode over every (station, element) pair in
# samples/index.json. Resumable: results/<label>.done marks a pair already
# run, so a killed/retried run only redoes what's left.
#
# MATRIX_INDEX overrides the index file for a filtered/subset run without
# touching this script; the committed default is the full index.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p results
INDEX="${MATRIX_INDEX:-samples/index.json}"
REPORTS=/tmp/fit-validation/reports

jq -c '.[]' "$INDEX" | while read -r row; do
  slug=$(jq -r .slug <<<"$row"); elem=$(jq -r .elem <<<"$row")
  label="${slug}-e${elem}"
  [ -f "results/${label}.done" ] && continue
  (cd ../../tools/FitValidation && swift run -c release fit-validation \
    --samples "../../spikes/sscofs-field/$(jq -r .samples <<<"$row")" \
    --events  "../../spikes/sscofs-field/$(jq -r .events  <<<"$row")" \
    --flood "$(jq -r .flood <<<"$row")" --ebb "$(jq -r .ebb <<<"$row")" \
    --label "$label") 2>&1 | tee "results/${label}.log" || true
  # The tool's own 210d report (the window its exit code reflects) is the
  # per-pair verdict of record; a FAIL-FOR-FITTING pair (e.g. no usable
  # events) never writes one, so report.py just sees it missing.
  report="${REPORTS}/${label}-210d-report.json"
  [ -f "$report" ] && cp "$report" "results/${label}.json"
  touch "results/${label}.done"
done
