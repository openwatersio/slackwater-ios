#!/bin/bash
# Slackwater — GPL v3. Parity gate: proves fit_batch.mjs (node vm run of the
# shipping chs-bundle.js/chs-glue.js) reproduces a real FitValidation fit
# (run in JSCore via tools/FitValidation, Swift) on the exact same sample
# bytes. Wire this as the first line of any real batch invocation — the
# guard file it writes on success is what fit_batch.mjs checks for.
#
# NOT literal byte-identity. spikes/chs-currents-fit/README.md's own M47
# finding #4 measured amplitude diffs up to ~9e-16 between node and JSCore on
# identical samples ("machine epsilon (FP reassociation between engines) ...
# physically nil") — re-checking empirically against these cached fits
# reproduces the same ~1e-15 order noise, not zero. So this gate tolerates
# < 1e-9 absolute difference per number — 6+ orders of magnitude above the
# measured engine noise, 8+ below anything a downstream R²/floor decision
# would ever see — and still fails hard past that, with the failing values
# printed.
#
# Usage: parity_check.sh [samples-file] [fit-file]
#   Defaults to the first cached pair under /tmp/fit-validation/reports/ (the
#   sscofs-field spike matrix's *-210d-samples.json / *-fit.json). If that
#   directory has nothing, regenerate one pair via the spike's own matrix
#   runner on a single row:
#     cd ../../spikes/sscofs-field && \
#       MATRIX_INDEX=<(jq -c '.[0:1]' samples/index.json) ./run_matrix.sh
#   then re-run this script.
set -euo pipefail
cd "$(dirname "$0")"
REPORTS="${FIT_VALIDATION_REPORTS:-/tmp/fit-validation/reports}"

shopt -s nullglob
candidates=("$REPORTS"/*-210d-samples.json)
SAMPLES="${1:-${candidates[0]:-}}"
if [ -z "${SAMPLES:-}" ]; then
  echo "parity_check.sh: no cached FitValidation samples found under $REPORTS" >&2
  echo "  regenerate one pair: cd ../../spikes/sscofs-field && MATRIX_INDEX=<(jq -c '.[0:1]' samples/index.json) ./run_matrix.sh" >&2
  exit 1
fi
FIT="${2:-${SAMPLES/-samples.json/-fit.json}}"
[ -f "$SAMPLES" ] || { echo "parity_check.sh: missing samples file $SAMPLES" >&2; exit 1; }
[ -f "$FIT" ] || { echo "parity_check.sh: missing fit file $FIT" >&2; exit 1; }

echo "parity_check.sh: $SAMPLES vs $FIT"
LINE=$(jq -c '{elem: 0, axis: "u", samples: .}' "$SAMPLES")
NODE_OUT=$(echo "$LINE" | FIT_BATCH_SKIP_PARITY=1 node fit_batch.mjs)

node -e '
const node = JSON.parse(process.argv[1]);
const jscore = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"));
const TOL = 1e-9;
let worst = 0;
const bad = [];
const angDiff = (a, b) => { const d = Math.abs(a - b) % 360; return Math.min(d, 360 - d); };
const check = (label, a, b, diff) => {
  const d = diff(a, b);
  worst = Math.max(worst, d);
  if (d > TOL) bad.push(`${label}: ${a} vs ${b} (diff ${d})`);
};
check("offset", node.offset, jscore.offset, (a, b) => Math.abs(a - b));
if (node.constituents.length !== jscore.constituents.length) {
  console.error(`constituent count mismatch: ${node.constituents.length} vs ${jscore.constituents.length}`);
  process.exit(1);
}
for (let i = 0; i < node.constituents.length; i++) {
  const a = node.constituents[i], b = jscore.constituents[i];
  if (a.name !== b.name) {
    console.error(`order mismatch at ${i}: ${a.name} vs ${b.name}`);
    process.exit(1);
  }
  check(`${a.name} amplitude`, a.amplitude, b.amplitude, (x, y) => Math.abs(x - y));
  check(`${a.name} phase`, a.phase, b.phase, angDiff);
}
console.log(`worst diff ${worst} (tolerance ${TOL})`);
if (bad.length) {
  console.error("PARITY FAILED:\n" + bad.join("\n"));
  process.exit(1);
}
console.log("PARITY OK");
' "$NODE_OUT" "$FIT"

mkdir -p data
touch data/.parity-ok
echo "parity_check.sh: wrote data/.parity-ok"
