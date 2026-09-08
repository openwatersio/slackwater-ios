/**
 * Generate Resources/chs-gates.json — the derived current gates from the
 * station-metadata registry (a pass with NO current station of its own,
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
import { join } from "node:path";
import tzLookup from "tz-lookup";
import { currentGates as selectCurrentGates } from "@openwaters/station-metadata";
import { here, stationData } from "./bundle.mjs";

const res = join(here, "..", "Slackwater", "Resources");
const registry = stationData("registry.json");
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
    magnitudeNote: e.magnitudeNote,
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
//
// M51 — the WINDOW IS PER GATE, not a blanket 210 d. The same validation run
// scored both windows from one fetch, and four gates already meet the full bar
// at the 60-day tide window: those fetch 60 d (~45 s) and go straight to FINAL,
// no provisional stage. The rest need 210 d, so they fit at 60 d first (a
// prefix of the same fetch — no wasted request), show that PROVISIONAL, and
// refine in place.
//
//   fitDays                 the window whose fit is FINAL for this gate
//   provisionalSlackMinutes the honest worst-case slack error of the 60-day
//                           fast answer, rounded UP to 5 min — the number the
//                           app puts in front of the user, per gate, never a
//                           generic hedge. Absent ⇒ no provisional stage.
//
// USEFULNESS FLOOR — 45 min of 60-day WORST slack error. Past that the warning
// ("could be three quarters of an hour out") is itself the instruction not to
// use the answer, so showing it is theatre: the gate stays pending until its
// full model lands. Worst, not median, because worst is the number the copy
// quotes. 45 sits in the real gap in the data (worst shipped 34.1 → next 45.7).
const PROVISIONAL_FLOOR_MIN = 45;
// id → { fitDays, slack60Max } — slack60Max is the measured 60-day worst.
const SHIPPED = new Map([
  //                                 210 d: slack med/max · extrema med/max (min) · speed med (kn)
  //                                  60 d: slack med/max
  ["chs-active-pass", { fitDays: 60 }],              // 2.4/4.0 · 1.1/2.4 · 0.06 | 60 d 1.8/3.2 PASSES
  ["chs-first-narrows", { fitDays: 60 }],            // 2.8/5.8 · 1.9/3.0 · 0.09 | 60 d 2.6/4.8 PASSES
  ["chs-johnstone-strait-central", { fitDays: 60 }], // 1.3/5.4 · 4.5/12.8 · 0.05 | 60 d 3.8/11.4 PASSES
  ["chs-seymour-narrows", { fitDays: 60 }],          // 0.2/1.0 · 0.3/0.5 · 0.00 | 60 d 0.2/1.0 PASSES
  ["chs-blackney-passage", { fitDays: 210, slack60Max: 31.8 }], // 5.0/24.7 · 8.7/25.2 · 0.07 | 60 d 7.2/31.8
  ["chs-dodd-narrows", { fitDays: 210, slack60Max: 32.9 }],     // 2.1/18.6 · 13.1/26.0 · 0.16 | 60 d 15.1/32.9
  ["chs-gillard-passage", { fitDays: 210, slack60Max: 17.7 }],  // 3.7/9.1 · 12.4/22.8 · 0.42 | 60 d 12.4/17.7
  ["chs-hole-in-the-wall", { fitDays: 210, slack60Max: 19.7 }], // 3.6/9.6 · 13.7/26.9 · 0.42 | 60 d 10.5/19.7
  ["chs-porlier-pass", { fitDays: 210, slack60Max: 32.1 }],     // 2.2/18.8 · 10.6/38.1 · 0.16 | 60 d 12.3/32.1
  ["chs-race-passage", { fitDays: 210, slack60Max: 28.5 }],     // 4.2/11.6 · 9.9/50.4 · 0.44 | 60 d 7.8/28.5
  ["chs-weynton-passage", { fitDays: 210, slack60Max: 34.1 }],  // 3.0/19.2 · 5.6/25.5 · 0.12 | 60 d 2.9/34.1
  // M55 — the national gates (2026-08-15), same harness, same bar, same
  // held-out window. Two of the four passed; see ONLINE below for the others.
  ["chs-great-bras-dor", { fitDays: 60 }],                      // 4.2/14.1 · 15.6/31.5 · 0.10 | 60 d 4.6/23.8 PASSES
  ["chs-quatsino-narrows", { fitDays: 210, slack60Max: 24.4 }], // 6.1/16.5 · 11.6/52.0 · 0.30 | 60 d 14.1/24.4
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
//   chs-masset-sound      4.4/21.0 · 23.9/52.4 · 0.20 kn — extrema med (M55)
//   chs-nakwakto-rapids   6.1/25.1 · 11.9/50.2 · 0.80 kn — speed (M55)
// Nakwakto is the clearest case yet of finding 2 below: ~14 kn through a gap
// with a slack of minutes is not something a 23-constituent linear basis
// describes, and its slack numbers pass comfortably while its speeds are half
// a knot worse than any shipped gate. A better model, not a looser bar.
// Their 60-day worsts, for the record — all four are also below the M51
// usefulness floor, so they would not get a provisional stage either:
//   second-narrows 45.7 · sechelt-rapids 60.4 · tillicum-bridge 79.4 ·
//   juan-de-fuca-east 146.6
//
// ONLINE — those 7 (arran-rapids stays fully excluded, it's a shipped-water
// hazard call, not a fittability one) ship anyway as identities, backed by
// official CHS predictions fetched on demand rather than an on-device fit
// (online-gates spec §1: findable, never fitted, never provisional). Each
// note names THAT station's own actual failure mode from the table above —
// slack max for the slack-rejects, but Beazley/Dent/Second Narrows failed on
// SPEED or EXTREMA TIMING, not slack (their slack numbers are inside the
// passing range), so their notes quote peak-speed/extrema-timing error
// instead — rounded to a plain number, review 2026-08-08.
const ONLINE = new Map([
  ["chs-beazley-passage", { onlineNote:
    "Slackwater's on-device model predicted the peak speeds here off by up to ~0.5 kn in testing, so it won't guess at Beazley Passage." }],
  ["chs-dent-rapids", { onlineNote:
    "Slackwater's on-device model missed the timing of peak flows here by ~20 minutes in testing, so it won't guess at Dent Rapids." }],
  ["chs-gabriola-passage", { onlineNote:
    "Slackwater's on-device model missed the published slacks here by up to ~35 minutes in testing, so it won't guess at Gabriola Passage." }],
  ["chs-second-narrows", { onlineNote:
    "Slackwater's on-device model missed the timing of peak flows here by ~20 minutes in testing, so it won't guess at Second Narrows." }],
  ["chs-sechelt-rapids", { onlineNote:
    "Slackwater's on-device model missed the published slacks here by up to ~40 minutes in testing, so it won't guess at Sechelt Rapids." }],
  // Adapted wording (per the brief): the failure mode is worth a clause of
  // its own, not just a bare number.
  ["chs-juan-de-fuca-east", { onlineNote:
    "Juan de Fuca's current here is weak and slow to reverse, which makes slack hard to pin down — testing missed the published slacks by up to ~85 minutes, so Slackwater won't guess at Juan de Fuca - East." }],
  ["chs-tillicum-bridge", { onlineNote:
    "Tillicum Bridge sits on the Gorge Waterway's reversing tidal falls, where testing missed the published slacks by up to ~95 minutes, so Slackwater won't guess here." }],
  // M55 — the two national gates that failed. Same rule as above: each note
  // names THAT station's own failure mode. Nakwakto failed on peak speed and
  // Masset on the timing of peak flows; neither failed on slack, so neither
  // note quotes a slack number.
  ["chs-nakwakto-rapids", { onlineNote:
    "Nakwakto Rapids runs to about 14 knots and its slack lasts minutes — Slackwater's on-device model predicted the peak speeds here off by about 0.8 kn in testing, so it won't guess at Nakwakto." }],
  ["chs-masset-sound", { onlineNote:
    "Slackwater's on-device model missed the timing of peak flows here by about 25 minutes in testing, so it won't guess at Masset Sound." }],
]);

// The registry's own selector, not a filter of our own. Ours was
// `provider === "chs" && !e.kind && !e.derived`, which read "no kind" as "is a
// gate" — true only because the registry was gates-only before it grew the
// field. Every gate added since carries `kind: current` explicitly, so the
// national gates were dropped silently: no warning, just four missing passes.
// currentGates() treats an absent kind as current, which is the actual rule.
const gateEntries = [
  ...selectCurrentGates({ registry: new Map(Object.entries(registry)), provider: "chs" }),
];
const currentGates = gateEntries
  .filter(([id]) => SHIPPED.has(id))
  .map(([id, e]) => {
    const { fitDays, slack60Max } = SHIPPED.get(id);
    // The floor, enforced here so a future gate cannot silently ship a fast
    // answer nobody could act on: over it, the entry carries no provisional
    // number and the app holds the gate pending until the full model lands.
    const useful = slack60Max !== undefined && slack60Max <= PROVISIONAL_FLOOR_MIN;
    return {
      id,
      name: e.name,
      region: e.context,
      aliases: e.aliases ?? [],
      latitude: e.position[0],
      longitude: e.position[1],
      // From the position, the way the tide ports get theirs — not a constant.
      // Every gate was in one zone while every gate was Salish; a Bay of Fundy
      // gate stamped America/Vancouver would render its slacks four hours out.
      timezone: tzLookup(e.position[0], e.position[1]),
      // Registry pairing (dual-track detail) — only if that port is bundled.
      tideReference: ports.some((p) => p.id === e.tideReference) ? e.tideReference : undefined,
      fitDays,
      provisionalSlackMinutes: useful ? Math.ceil(slack60Max / 5) * 5 : undefined,
    };
  });

// The 7 online identities — same shape as the shipped gates (name/region/
// aliases/position/timezone/tideReference straight from the registry), but
// fitDays: 0 (the never-fitted sentinel: offersProvisional is naturally
// false) and online: true so the app fetches CHS predictions on demand
// instead of fitting.
for (const [id, { onlineNote }] of ONLINE) {
  const e = registry[id];
  currentGates.push({
    id,
    name: e.name,
    region: e.context,
    aliases: e.aliases ?? [],
    latitude: e.position[0],
    longitude: e.position[1],
    timezone: tzLookup(e.position[0], e.position[1]),
    tideReference: ports.some((p) => p.id === e.tideReference) ? e.tideReference : undefined,
    fitDays: 0,
    online: true,
    onlineNote,
    magnitudeNote: e.magnitudeNote,
  });
}

writeFileSync(join(res, "chs-current-gates.json"), JSON.stringify(currentGates, null, 1) + "\n");
console.log(`${currentGates.length}/${gateEntries.length} validated + ${ONLINE.size} online current gate(s):`);
for (const g of currentGates) {
  console.log(`  ${g.name.padEnd(26)} ${g.fitDays} d` +
    (g.online ? "  online (never fitted)"
     : g.fitDays === 60 ? "  (final on first fit)"
     : g.provisionalSlackMinutes ? `  provisional ±${g.provisionalSlackMinutes} min`
     : `  NO provisional — over the ${PROVISIONAL_FLOOR_MIN} min floor`));
}
