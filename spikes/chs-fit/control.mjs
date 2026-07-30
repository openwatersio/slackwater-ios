// Node control: same bundle + glue as the JSCore run, plus metrics. If this
// fails, the problem is library/data, not JSCore.
import { readFileSync, writeFileSync } from "node:fs";
import vm from "node:vm";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const ctx = vm.createContext({ Date, Math, JSON });
vm.runInContext(readFileSync(join(here, "chs-bundle.js"), "utf8"), ctx);
vm.runInContext(readFileSync(join(here, "glue.js"), "utf8"), ctx);

const fitJson = readFileSync(join(here, process.argv[2] ?? "fit-window.json"), "utf8");
const val = JSON.parse(readFileSync(join(here, "validation-window.json"), "utf8"));
const hilo = JSON.parse(readFileSync(join(here, "validation-hilo.json"), "utf8"));

const valStart = val[0].t, valEnd = val[val.length - 1].t;
ctx.__args = [fitJson, valStart, valEnd, 900];
const out = JSON.parse(vm.runInContext("runSpike(__args[0], __args[1], __args[2], __args[3])", ctx));

// --- metrics (plain JS, reused mentally by the Swift runner) ---
const byT = new Map(out.predictions.map((p) => [p.t, p.v]));
let n = 0, sq = 0, maxAbs = 0;
for (const p of val) {
  const pred = byT.get(p.t);
  if (pred === undefined) continue;
  const e = (pred - p.v) * 100; // cm
  n++; sq += e * e; if (Math.abs(e) > maxAbs) maxAbs = Math.abs(e);
}
const rmse = Math.sqrt(sq / n);

// classify hilo events by value vs neighbours, pair with nearest same-kind extremum
const timing = [];
for (let i = 0; i < hilo.length; i++) {
  const prev = hilo[i - 1], next = hilo[i + 1];
  const kind = (prev && hilo[i].v > prev.v) || (next && hilo[i].v > next.v) ? "high" : "low";
  let best = null;
  for (const e of out.extremes) {
    if (e.kind !== kind) continue;
    const dt = Math.abs(e.t - hilo[i].t) / 60000;
    if (!best || dt < best.dt) best = { dt, e };
  }
  if (best && best.dt < 180) timing.push({ iwls: hilo[i], kind, dtMin: best.dt, pred: best.e });
}
const dts = timing.map((x) => x.dtMin).sort((a, b) => a - b);
const median = dts[Math.floor(dts.length / 2)];
const heightErr = timing.map((x) => Math.abs(x.pred.v - x.iwls.v) * 100);

const report = {
  engine: "node-control",
  fitMs: out.fitMs, rmsFitM: out.rms, nConstituents: out.nConstituents,
  unseparable: out.unseparable,
  comparedPoints: n, rmseCm: +rmse.toFixed(2), maxAbsCm: +maxAbs.toFixed(2),
  extremes: { matched: timing.length, of: hilo.length, medianTimingMin: +median.toFixed(1), maxTimingMin: +dts[dts.length - 1].toFixed(1), meanHeightErrCm: +(heightErr.reduce((a, b) => a + b, 0) / heightErr.length).toFixed(2) },
};
writeFileSync(join(here, "node-control-report.json"), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
