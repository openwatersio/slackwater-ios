#!/usr/bin/env node
// Slackwater — GPL v3. Fill-pipeline batch fitter: the app's own committed
// chs-bundle.js + chs-glue.js, run in a node vm context (precedent:
// spikes/chs-currents-fit/node-control.mjs — same artifacts, same fitTides()
// call). Pure stdin->stdout JSONL filter; no npz reading, no resumability —
// that's the Python driver's job (T4's survivors.py streams samples in and
// skips elems already present in its output).
//
// in:  {"elem": <i>, "axis": "u"|"v", "samples": [{"t": <epochMs>, "v": <kn>}...]}
// out: {"elem": <i>, "axis": "u"|"v", "constituents": [{name,amplitude,phase}...],
//       "offset": <n>, "rms": <n>, "unseparable": [<"NAME1/NAME2">...]}
//
// R²: chs-glue's fitTides() (Slackwater/Resources/chs-glue.js) does not
// expose a prediction function — only the fit's own residual rms, not a
// per-sample R². This filter cannot compute R² itself, so no "r2" key ships
// from here; the Python driver computes it exactly from this rms alone
// (survivors.py's r2_from_rms: ss_res = rms^2 * n, n the sample count the
// driver itself sent — no cos-sum evaluation, no re-derivation of the fit)
// per task-3-brief.md's "simpler and correct" note. `rms` rides along since
// fitTides already returns it for free — the input the driver's R² is
// computed from, not a separate sanity signal.
//
// unseparable: fitTides() also returns this for free (Rayleigh-unseparable
// name-pairs, e.g. "S2/T2" at this corpus's 190-day window) -- previously
// dropped here (task-3-report.md fix round 2 flagged it as a T4 wiring
// note, not a bug). Now passed through unchanged so the Python driver can
// treat it as authoritative for "known limit vs. real problem" instead of
// re-deriving it by eyeballing which constituent won.
//
// Parity gate: run parity_check.sh first. This filter refuses to process
// stdin unless data/.parity-ok's recorded sha256 of BOTH artifacts matches
// what's on disk right now — existence alone isn't enough, since a
// chs-bundle.js/chs-glue.js edit after the guard was written would
// otherwise fit silently against a fitter the gate never actually checked.
// FIT_BATCH_SKIP_PARITY=1 (set by parity_check.sh itself) bypasses this —
// it has to call this filter to prove parity before the guard can exist.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { createInterface } from "node:readline";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import path from "node:path";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const RESOURCES = path.join(HERE, "../../Slackwater/Resources");
const GUARD = path.join(HERE, "data/.parity-ok");

function loadArtifact(name) {
  const src = readFileSync(path.join(RESOURCES, name), "utf8");
  const hash = createHash("sha256").update(src).digest("hex");
  return { src, hash };
}
const bundle = loadArtifact("chs-bundle.js");
const glue = loadArtifact("chs-glue.js");

if (process.env.FIT_BATCH_SKIP_PARITY !== "1") {
  let guard;
  try {
    guard = JSON.parse(readFileSync(GUARD, "utf8"));
  } catch {
    guard = null;
  }
  const stale =
    !guard || guard["chs-bundle.js"] !== bundle.hash || guard["chs-glue.js"] !== glue.hash;
  if (stale) {
    console.error(
      "fit_batch.mjs: parity gate not proven (or chs-bundle.js/chs-glue.js changed " +
        "since it last ran) — re-run tools/fill-pipeline/parity_check.sh",
    );
    process.exit(1);
  }
}

const ctx = vm.createContext({ Date, Math, JSON });
vm.runInContext("var console={log(){},warn(){},error(){},info(){},debug(){}};", ctx);
vm.runInContext(bundle.src, ctx);
vm.runInContext(glue.src, ctx);

// Per-line fault isolation: a 300k-element run WILL hit degenerate series
// (dry cells with <2 samples, malformed input) and one bad line must not
// take the whole batch down. Failures report as {elem,axis,error} on stdout
// (same stream as successes — the driver counts them per-elem) rather than
// crashing the process; elem/axis fall back to null if the line's JSON
// itself didn't parse.
const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  if (!line.trim()) return;
  let elem = null;
  let axis = null;
  try {
    const parsed = JSON.parse(line);
    ({ elem, axis } = parsed);
    ctx.__s = JSON.stringify(parsed.samples);
    const fit = JSON.parse(vm.runInContext("fitTides(__s)", ctx));
    process.stdout.write(
      JSON.stringify({
        elem,
        axis,
        constituents: fit.constituents,
        offset: fit.offset,
        rms: fit.rms,
        unseparable: fit.unseparable,
      }) + "\n",
    );
  } catch (err) {
    process.stdout.write(
      JSON.stringify({ elem, axis, error: `${err.constructor.name}: ${err.message}` }) + "\n",
    );
  }
});
