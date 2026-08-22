#!/bin/bash
# Grade every patch-vs-check-station pair with tools/FitValidation — the M47
# bars, unmodified. Fork of fill-pipeline/run_matrix.sh (own data dirs, plus
# a .status file capturing the tool's exit code = its own PASS/FAIL verdict).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data/verdicts
REPORTS=/tmp/fit-validation/reports

jq -c '.[]' data/certify/index.json | while read -r row; do
  label=$(jq -r .slug <<<"$row")
  [ -f "data/verdicts/${label}.done" ] && continue
  report="${REPORTS}/${label}-210d-report.json"
  rm -f "$report"
  if (cd ../FitValidation && swift run -c release fit-validation \
      --samples "../patch-pipeline/$(jq -r .samples <<<"$row")" \
      --events  "../patch-pipeline/$(jq -r .events  <<<"$row")" \
      --flood "$(jq -r .flood <<<"$row")" --ebb "$(jq -r .ebb <<<"$row")" \
      --label "$label") 2>&1 | tee "data/verdicts/${label}.log"; then
    echo PASS > "data/verdicts/${label}.status"
  else
    echo FAIL > "data/verdicts/${label}.status"
  fi
  [ -f "$report" ] && cp "$report" "data/verdicts/${label}.json"
  touch "data/verdicts/${label}.done"
done
