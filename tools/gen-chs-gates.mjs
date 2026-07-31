/**
 * Generate Resources/chs-gates.json — the derived current gates from the
 * station-corrections registry (a pass with NO current station of its own,
 * where slack is the reference tide port's high/low water plus a fixed lag —
 * Malibu Rapids today; generic over every `derived` entry so a new gate is a
 * registry bump + rerun, no app edit) — and Resources/chs-current-gates.json,
 * the VALIDATED CHS current gates (M47): registry gates with a live IWLS
 * current station whose on-device fit passed the validation bar.
 *
 * Identity only (name/region/position/aliases/lags/pairing) — nothing
 * CHS-published, same licensing posture as chs-stations.json. The reference
 * must be a bundled CHS tide port (chs-stations.json): the app derives the
 * gate's slacks from that port's on-device fitted model.
 *
 * Run: cd tools && npm install && node gen-chs-gates.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const res = join(here, "..", "Slackwater", "Resources");
const registry = JSON.parse(readFileSync(
  createRequire(import.meta.url).resolve("@sailingnaturali/station-corrections/data/registry.json"),
  "utf8",
));
const ports = JSON.parse(readFileSync(join(res, "chs-stations.json"), "utf8"));

const gates = [];
for (const [id, e] of Object.entries(registry)) {
  if (!e.derived) continue;
  const port = ports.find((p) => p.id === e.derived.reference);
  if (!port) {
    console.warn(`${id}: reference ${e.derived.reference} not bundled — skipped`);
    continue;
  }
  gates.push({
    id,
    name: e.name,
    region: e.context,
    aliases: e.aliases ?? [],
    latitude: e.position[0],
    longitude: e.position[1],
    timezone: port.timezone,
    reference: port.id,
    referenceName: port.name,
    hwLagMinutes: e.derived.hwLagMinutes,
    lwLagMinutes: e.derived.lwLagMinutes,
  });
}

writeFileSync(join(res, "chs-gates.json"), JSON.stringify(gates, null, 1) + "\n");
console.log(`${gates.length} derived gate(s): ${gates.map((g) => g.name).join(", ")}`);

// ---------------------------------------------------------------------------
// Validated CHS current gates (M47). Only gates that PASSED the fit-validation
// bar ship (spikes/chs-currents-fit/README.md — 210 d fit vs CHS's own
// published wcp1-events, held out +28..+35 d: slack median ≤15 / worst ≤30
// min, extrema median ≤20 min, peak-speed median ≤0.5 kn, no reversed axis).
// A failed gate is ABSENT, not broken-looking. Numbers recorded 2026-07-31.
const SHIPPED = new Set([
  // slack med/max · extrema med/max (min) · peak-speed med (kn)
  "chs-active-pass",              // 2.4/4.0 · 1.1/2.4 · 0.06
  "chs-blackney-passage",         // 5.0/24.7 · 8.7/25.2 · 0.07
  "chs-dodd-narrows",             // 2.1/18.6 · 13.1/26.0 · 0.16
  "chs-first-narrows",            // 2.8/5.8 · 1.9/3.0 · 0.09
  "chs-gillard-passage",          // 3.7/9.1 · 12.4/22.8 · 0.42
  "chs-hole-in-the-wall",         // 3.6/9.6 · 13.7/26.9 · 0.42
  "chs-johnstone-strait-central", // 1.3/5.4 · 4.5/12.8 · 0.05
  "chs-porlier-pass",             // 2.2/18.8 · 10.6/38.1 · 0.16
  "chs-race-passage",             // 4.2/11.6 · 9.9/50.4 · 0.44
  "chs-seymour-narrows",          // 0.2/1.0 · 0.3/0.5 · 0.00
  "chs-weynton-passage",          // 3.0/19.2 · 5.6/25.5 · 0.12
]);
// EXCLUDED — failed the bar (210 d window; slack med/max · extrema med/max ·
// peak-speed med). Kept out entirely per §6a: wrong water under a trusted
// name. Revisit only with a method change, not a rerun.
//   chs-arran-rapids      4.9/11.4 · 14.5/34.5 · 0.66 kn — violent rapids, speed
//   chs-beazley-passage   3.6/10.5 · 16.2/39.3 · 0.51 kn — speed (near miss)
//   chs-dent-rapids       3.2/8.6 · 20.1/38.0 · 0.27 kn — extrema med (near miss)
//   chs-gabriola-passage  19.2/33.1 · 14.9/38.2 · 0.22 kn — slack
//   chs-juan-de-fuca-east 18.1/84.5 · 22.6/46.7 · 0.11 kn — slack (weak, slow-reversing)
//   chs-sechelt-rapids    15.5/39.5 · 11.7/55.7 · 0.94 kn — slack + speed (Skookumchuck)
//   chs-second-narrows    5.9/13.5 · 20.6/48.1 · 0.26 kn — extrema med (near miss)
//   chs-tillicum-bridge   19.0/93.0 · 19.1/96.5 · 0.15 kn — slack (Gorge Waterway)

const gateEntries = Object.entries(registry).filter(
  ([, e]) => e.provider === "chs" && !e.kind && !e.derived,
);
const currentGates = gateEntries
  .filter(([id]) => SHIPPED.has(id))
  .map(([id, e]) => ({
    id,
    name: e.name,
    region: e.context,
    aliases: e.aliases ?? [],
    latitude: e.position[0],
    longitude: e.position[1],
    timezone: "America/Vancouver",
    // Registry pairing (dual-track detail) — only if that port is bundled.
    tideReference: ports.some((p) => p.id === e.tideReference) ? e.tideReference : undefined,
  }));

writeFileSync(join(res, "chs-current-gates.json"), JSON.stringify(currentGates, null, 1) + "\n");
console.log(`${currentGates.length}/${gateEntries.length} validated current gate(s): ${currentGates.map((g) => g.name).join(", ")}`);
