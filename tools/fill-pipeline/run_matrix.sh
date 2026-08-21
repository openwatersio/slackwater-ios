#!/bin/bash
# Run fit-validation file mode over every (station, element) pair in
# data/index.json. Resumable: data/verdicts/<label>.done marks a pair already
# run, so a killed/retried run only redoes what's left.
#
# Forked from spikes/sscofs-field/run_matrix.sh per fill-phase-b-design.md §1 /
# task-2-brief.md: index/verdicts paths point at tools/fill-pipeline/data/
# instead of the spike's box-scoped dirs. Same resumability + stale-report
# pattern (rm -f before each run) carried over unchanged.
#
# MATRIX_INDEX overrides the index file for a filtered/subset run without
# touching this script; the committed default is the full index.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data/verdicts
INDEX="${MATRIX_INDEX:-data/index.json}"
REPORTS=/tmp/fit-validation/reports

jq -c '.[]' "$INDEX" | while read -r row; do
  slug=$(jq -r .slug <<<"$row"); elem=$(jq -r .elem <<<"$row")
  label="${slug}-e${elem}"
  [ -f "data/verdicts/${label}.done" ] && continue
  # Clear any stale report from a prior run before this one starts — a run
  # that fails early (e.g. FAIL-FOR-FITTING) never writes a new one, and
  # without this the copy below would grab yesterday's numbers and mark the
  # pair done with no signal that they're stale.
  report="${REPORTS}/${label}-210d-report.json"
  rm -f "$report"
  (cd ../FitValidation && swift run -c release fit-validation \
    --samples "../fill-pipeline/$(jq -r .samples <<<"$row")" \
    --events  "../fill-pipeline/$(jq -r .events  <<<"$row")" \
    --flood "$(jq -r .flood <<<"$row")" --ebb "$(jq -r .ebb <<<"$row")" \
    --label "$label") 2>&1 | tee "data/verdicts/${label}.log" || true
  # The tool's own 210d report (the window its exit code reflects) is the
  # per-pair verdict of record; a FAIL-FOR-FITTING pair (e.g. no usable
  # events) never writes one, so downstream reporting just sees it missing.
  [ -f "$report" ] && cp "$report" "data/verdicts/${label}.json"
  touch "data/verdicts/${label}.done"
done
