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
//       "offset": <n>, "rms": <n>}
//
// R²: chs-glue's fitTides() (Slackwater/Resources/chs-glue.js) does not
// expose a prediction function — only the fit's own residual rms, not a
// per-sample R². This filter cannot compute R² itself, so no "r2" key ships
// from here; the Python driver computes it from these constituents (evaluate
// the cos-sum at each sample time, compare to the samples) per
// task-3-brief.md. `rms` rides along since fitTides already returns it for
// free — a cheap sanity signal, not a substitute for the driver's R².
//
// Parity gate: run parity_check.sh first. This filter refuses to process
// stdin without data/.parity-ok present, unless FIT_BATCH_SKIP_PARITY=1
// (set by parity_check.sh itself — it has to call this filter to prove
// parity before the guard file can exist).
import { readFileSync } from "node:fs";
import { createInterface } from "node:readline";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import path from "node:path";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const RESOURCES = path.join(HERE, "../../Slackwater/Resources");
const GUARD = path.join(HERE, "data/.parity-ok");

if (process.env.FIT_BATCH_SKIP_PARITY !== "1") {
  try {
    readFileSync(GUARD);
  } catch {
    console.error(
      "fit_batch.mjs: parity gate not proven — run tools/fill-pipeline/parity_check.sh first",
    );
    process.exit(1);
  }
}

const ctx = vm.createContext({ Date, Math, JSON });
vm.runInContext("var console={log(){},warn(){},error(){},info(){},debug(){}};", ctx);
vm.runInContext(readFileSync(path.join(RESOURCES, "chs-bundle.js"), "utf8"), ctx);
vm.runInContext(readFileSync(path.join(RESOURCES, "chs-glue.js"), "utf8"), ctx);

const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  if (!line.trim()) return;
  const { elem, axis, samples } = JSON.parse(line);
  ctx.__s = JSON.stringify(samples);
  const fit = JSON.parse(vm.runInContext("fitTides(__s)", ctx));
  process.stdout.write(
    JSON.stringify({
      elem,
      axis,
      constituents: fit.constituents,
      offset: fit.offset,
      rms: fit.rms,
    }) + "\n",
  );
});
