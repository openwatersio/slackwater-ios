/**
 * Report the peak-magnitude distributions that set the colour-ramp domain
 * for the speed/rate encoding (issue #97) — current speed in knots across
 * the bundled NOAA current stations, and tide rate of rise in ft/hr across
 * the bundled NOAA tide stations.
 *
 * WHY THIS EXISTS: the ramp is absolutely scaled, so one number decides
 * whether a mild pass and a lethal one render differently. Picking it from
 * the observed maximum compresses ~90% of stations into the bottom third of
 * the ramp; picking it from a percentile makes the colour mean nothing
 * physical. This prints the shape so the anchors can be argued from data
 * rather than from memory. Rerun it whenever the bundled sets change.
 *
 * WHAT IT IS NOT: the maxima here are a lower bound on what the app actually
 * renders. CHS stations carry no harmonic constants until a model is fitted
 * on device, so every Canadian station — including Sechelt Rapids at ~16 kn
 * and the Bay of Fundy ports — is ABSENT from these distributions. The
 * bundled current maximum is ~10 kn. Do not read the max as the app's
 * ceiling; it is the ceiling of the half of the data that ships.
 *
 * Method: each station's series synthesized over a full year at 15-minute
 * steps, taking the true maximum — not the sum-of-amplitudes bound, which
 * overstates by 15–25% because it assumes every constituent peaks together.
 * Currents include the station's mean flow. Tide rate is the analytic
 * derivative (a sum of cosines differentiates to a sum of sines), never a
 * difference of neighbouring samples — near a turn the curve is flat and
 * differencing picks up numerical noise (same trap as `cardState`'s
 * direction, TideStation.swift).
 *
 * Accepted imprecision, none of which moves a ramp anchor:
 *   - Phase epoch is arbitrary. For a maximum over a whole year this costs
 *     almost nothing: relative phasing between constituents sets the peak,
 *     and that is preserved.
 *   - No nodal (f/u) corrections — an 18.6-year modulation, a few percent.
 *   - SPEED below covers the standard constituents only: 99.3% of bundled
 *     tide amplitude and 100% of current amplitude. Anything omitted is
 *     reported so the gap can never go silent.
 *
 * Run: node tools/ramp-domain.mjs        (~1 min, no dependencies)
 */
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const res = join(dirname(fileURLToPath(import.meta.url)), "..", "Slackwater", "Resources");

/** IHO constituent speeds, degrees per solar hour. */
const SPEED = {
  M2: 28.9841042, S2: 30.0, N2: 28.4397295, K1: 15.0410686, O1: 13.9430356,
  P1: 14.9589314, K2: 30.0821373, Q1: 13.3986609, NU2: 28.5125831,
  J1: 15.5854433, L2: 29.5284789, T2: 29.9589333, R2: 30.0410667,
  "2N2": 27.8953548, MU2: 27.9682084, LAM2: 29.4556253, S1: 15.0,
  M1: 14.4966939, OO1: 16.1391017, RHO: 13.4715145, "2Q1": 12.8542862,
  M4: 57.9682084, M6: 86.9523127, M8: 115.9364169, S4: 60.0, S6: 90.0,
  MN4: 57.4238337, MS4: 58.9841042, MK3: 44.0251729, "2MK3": 42.9271398,
  M3: 43.4761563, "2SM2": 31.0158958, SA: 0.0410686, SSA: 0.0821373,
  MF: 1.0980331, MM: 0.5443747, MSF: 1.0158958,
};

const HOURS = 365 * 24;
const STEP = 0.25;                       // 15-minute sampling
const STEPS = Math.round(HOURS / STEP);
const RAD = Math.PI / 180;
const FT_PER_M = 3.28084;

/** Amplitudes, angular speeds (rad/hr) and phases (rad) we have speeds for. */
function series(station, dropped) {
  const a = [], w = [], p = [];
  for (const c of station.constituents) {
    const s = SPEED[c.name];
    if (s === undefined) {
      dropped.set(c.name, (dropped.get(c.name) ?? 0) + Math.abs(c.amplitude));
      continue;
    }
    a.push(c.amplitude);
    w.push(s * RAD);
    p.push(c.phase * RAD);
  }
  return [Float64Array.from(a), Float64Array.from(w), Float64Array.from(p)];
}

/** max |Σ A·cos(ωt − φ) + offset| over the year. */
function peakValue(station, dropped, offset = 0) {
  const [a, w, p] = series(station, dropped);
  let peak = 0;
  for (let i = 0; i < STEPS; i++) {
    const t = i * STEP;
    let v = offset;
    for (let k = 0; k < a.length; k++) v += a[k] * Math.cos(w[k] * t - p[k]);
    const m = Math.abs(v);
    if (m > peak) peak = m;
  }
  return peak;
}

/** max |d/dt Σ A·cos(ωt − φ)| = max |Σ A·ω·sin(ωt − φ)|, units per hour. */
function peakRate(station, dropped) {
  const [a, w, p] = series(station, dropped);
  let peak = 0;
  for (let i = 0; i < STEPS; i++) {
    const t = i * STEP;
    let r = 0;
    for (let k = 0; k < a.length; k++) r += a[k] * w[k] * Math.sin(w[k] * t - p[k]);
    const m = Math.abs(r);
    if (m > peak) peak = m;
  }
  return peak;
}

const pct = (sorted, q) => sorted[Math.min(sorted.length - 1, Math.floor((q / 100) * sorted.length))];

function report(label, pairs, unit, marks) {
  const sorted = pairs.map(([v]) => v).sort((x, y) => x - y);
  const n = sorted.length;
  console.log(`\n${label}  (n=${n}, ${unit})`);
  console.log("  " + [50, 75, 90, 95, 99].map((q) => `p${q}=${pct(sorted, q).toFixed(2)}`).join("  ") +
              `  max=${sorted[n - 1].toFixed(2)}`);
  for (const m of marks) {
    const c = sorted.filter((v) => v >= m).length;
    console.log(`    >= ${String(m).padStart(4)} ${unit}: ${String(c).padStart(4)} stations  (${(100 * c / n).toFixed(1)}%)`);
  }
  const top = [...pairs].sort((x, y) => y[0] - x[0]).slice(0, 6);
  console.log("  fastest: " + top.map(([v, name]) => `${v.toFixed(1)} ${name}`).join(", "));
}

/** Anything SPEED doesn't know, so an unmodelled constituent is never silent. */
function reportDropped(dropped, kept) {
  if (dropped.size === 0) return;
  const lost = [...dropped.values()].reduce((s, v) => s + v, 0);
  const worst = [...dropped.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);
  console.log(`  omitted ${dropped.size} constituents without a listed speed — ` +
              `${(100 * lost / (lost + kept)).toFixed(2)}% of total amplitude ` +
              `(largest: ${worst.map(([k]) => k).join(", ")})`);
}

function totalAmplitude(stations) {
  let kept = 0;
  for (const s of stations)
    for (const c of s.constituents)
      if (SPEED[c.name] !== undefined) kept += Math.abs(c.amplitude);
  return kept;
}

const load = (f) => JSON.parse(readFileSync(join(res, f), "utf8"));

// ---- currents: peak speed, knots -----------------------------------------
const currents = load("currents.json");
const curDropped = new Map();
report("NOAA current stations — true peak speed",
       currents.map((s) => [peakValue(s, curDropped, s.meanFlow ?? 0), s.name]),
       "kn", [1, 2, 3, 4, 5, 6, 8, 10]);
reportDropped(curDropped, totalAmplitude(currents));

// ---- tides: peak rate of rise, ft/hr -------------------------------------
const tides = load("stations.json");
const tideDropped = new Map();
report("NOAA tide stations — true peak rate of rise",
       tides.map((s) => [peakRate(s, tideDropped) * FT_PER_M, s.name]),
       "ft/hr", [1, 2, 3, 4, 5, 6, 8]);
reportDropped(tideDropped, totalAmplitude(tides));

console.log("\nCHS stations are absent from both sets — see the header.");
