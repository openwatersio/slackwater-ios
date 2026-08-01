/**
 * Enrich the bundled currents.json in place: the station-corrections v2.5.0
 * gate→tide pairing (`tideReference`), and the region line's presentation.
 *
 * ## Regions (M50)
 *
 * A NOAA current station's `region` is the comma qualifier off its own name
 * ("Discovery Island, 7.6 mi. SSE of"), split out by station-corrections'
 * resolver. Two things arrive broken and are fixed here, at the data layer,
 * once — not on every render:
 *
 * 1. **Compass abbreviations get title-cased.** station-corrections'
 *    `cleanName` re-cases ALL-CAPS words and its KEEP set holds only the
 *    two-letter points (NE/NW/SE/SW), so the eight three-letter ones come out
 *    "Sse", "Nne", "Ene", "Wnw"… The real root cause is upstream in
 *    `station-corrections/src/clean.js`; slackwater-web resolves at runtime
 *    through the same function and has the identical bug (web follow-up).
 * 2. **Statute miles in a marine app.** NOAA writes some qualifiers in miles
 *    and some in nautical miles, so a card could say "7.6 mi." above a
 *    computed "6.6 nm" pill — one card, two distance units. Everything
 *    becomes nautical miles.
 *
 * Both passes are idempotent (a converted string carries "nm", not "mi."), so
 * this stays safe to re-run after any regeneration.
 *
 * Two rungs, in order:
 * 1. The registry's curated pairing, surfaced by resolve() (the v2.5.0 type
 *    contract). Today the registry pairs only CHS gates, none of which are
 *    bundled here — this rung is the wire-through that picks curation up the
 *    moment it lands for a NOAA gate.
 * 2. Proximity fallback, bounded at the web's own "standing at the station"
 *    threshold: a bundled tide station within 2 km of the gate
 *    (slackwater-web src/tides.ts matchQuality — distance wins outright
 *    under 2 km). The spec (current-detail §2) requires the association be a
 *    data-layer field, honestly nearby; recording it here at build time, at a
 *    threshold the web already codified, keeps it out of UI-guess territory.
 *    ponytail: proximity fallback at 2 km; delete it when the registry
 *    curates NOAA pairings.
 *
 * Run: cd tools && npm install && node enrich-currents.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createBundledResolver } from "@sailingnaturali/station-corrections";

const here = dirname(fileURLToPath(import.meta.url));
const res = join(here, "..", "Slackwater", "Resources");
const currents = JSON.parse(readFileSync(join(res, "currents.json"), "utf8"));
const tides = JSON.parse(readFileSync(join(res, "stations.json"), "utf8"));

const resolve = createBundledResolver();
const PAIR_KM = 2.0;

function km(a, b) {
  const R = 6371, toR = (x) => (x * Math.PI) / 180;
  const dLa = toR(b.latitude - a.latitude), dLo = toR(b.longitude - a.longitude);
  const h = Math.sin(dLa / 2) ** 2 +
    Math.cos(toR(a.latitude)) * Math.cos(toR(b.latitude)) * Math.sin(dLo / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** The 12 abbreviated compass points that can survive a title-casing pass. */
const COMPASS = /\b(NNE|ENE|ESE|SSE|SSW|WSW|WNW|NNW|NE|SE|SW|NW)\b/gi;
/** 1 statute mile = 1.609344 km; 1 nautical mile = 1.852 km. */
const MI_TO_NM = 1.609344 / 1.852;

export function normalizeRegion(region) {
  return region
    .replace(/(\d+(?:\.\d+)?)\s*(?:mi\.|miles?\b)/gi,
             (_, n) => `${(Number(n) * MI_TO_NM).toFixed(1)} nm`)
    .replace(COMPASS, (p) => p.toUpperCase());
}

let curated = 0, derived = 0, recased = 0;
for (const gate of currents) {
  const region = normalizeRegion(gate.region ?? "");
  if (region !== gate.region) { gate.region = region; recased += 1; }
  delete gate.tideReference; // regenerate, never accrete
  const r = resolve({ id: gate.id, name: gate.name, latitude: gate.latitude, longitude: gate.longitude });
  if (r.tideReference) {
    // Registry keys are not bundled-station ids; only record a pairing the app
    // can actually open.
    const port = tides.find((t) => t.id === r.tideReference);
    if (port) { gate.tideReference = port.id; curated += 1; continue; }
    console.warn(`${gate.id}: curated tideReference ${r.tideReference} not bundled — skipped`);
  }
  const ranked = tides.map((t) => ({ t, d: km(gate, t) })).sort((a, b) => a.d - b.d);
  if (ranked[0] && ranked[0].d <= PAIR_KM) {
    gate.tideReference = ranked[0].t.id;
    derived += 1;
    console.log(`${gate.name} -> ${ranked[0].t.name} (${ranked[0].d.toFixed(2)} km)`);
  }
}

writeFileSync(join(res, "currents.json"), JSON.stringify(currents));
console.log(`${currents.length} gates: ${curated} curated + ${derived} proximity-paired (<= ${PAIR_KM} km), ${recased} regions normalized`);
