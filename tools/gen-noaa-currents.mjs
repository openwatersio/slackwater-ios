/**
 * Generate Resources/currents.json — every bundled NOAA tidal-current station.
 *
 * Source: data/noaa-currents.json, the national extract vendored from
 * @sailingnaturali/current-stations (its `currents.min.json`; the package ships
 * the extractor and schema on npm but not the data, so it is vendored here the
 * same way slackwater-web vendors its Salish subset — see that repo's README to
 * re-extract). NOAA CO-OPS data is public domain.
 *
 * Filters, all inherited from slackwater-web's build-currents.mjs, all still
 * load-bearing:
 *   1. Harmonic stations only — a subordinate is offsets against a reference
 *      and needs reduction math slackwater-engine has not ported.
 *      ponytail: harmonic-only; port the engine's subordinate reduction when a
 *      pass we care about turns out to be subordinate-only.
 *   2. Primary bin only (id without "@") — one station, one prediction.
 *   3. At least one non-zero constituent; zero-amplitude ones are dropped.
 * The web's fourth filter — a Salish bounding box — is gone: national IS the
 * scope now, and the extract is US waters throughout.
 *
 * TIMEZONE. The extract carries none. The web hardcoded America/Los_Angeles
 * with a note saying "the bbox is single-zone; add a per-station field only if
 * it widens" — it just widened, from one zone to ten. Resolved by position with
 * `tz-lookup` (build-time devDependency, never shipped): a longitude rule would
 * be wrong at every zone boundary, and a displayed slack time an hour out is
 * the worst kind of quietly wrong.
 *
 * PAIRING (`tideReference`) — was tools/enrich-currents.mjs, folded in here so
 * the file that writes a record also writes its pairing. Two rungs, in order:
 *   1. The registry's curated pairing, surfaced by resolve() (the v2.5.0 type
 *      contract). Today the registry pairs only CHS gates, so this is the
 *      wire-through that picks curation up the moment it lands for a NOAA gate.
 *   2. Proximity fallback, bounded at the web's own "standing at the station"
 *      threshold: a bundled tide station within 2 km (slackwater-web
 *      src/tides.ts matchQuality — distance wins outright under 2 km). The
 *      current-detail spec §2 requires the association be a data-layer field,
 *      honestly nearby; recording it at build time, at a threshold the web
 *      already codified, keeps it out of UI-guess territory.
 *      ponytail: proximity fallback at 2 km; delete it when the registry
 *      curates NOAA pairings.
 *
 * NAMING is the tide generator's, verbatim: station-corrections resolve(),
 * with a DERIVED context replaced by the nearest tide station's region —
 * the bundled gazetteer is 19 Salish towns and nationally invents nonsense
 * ("Pollock Rip Channel · near Everett, WA") — and the same dangling-
 * preposition strip ("0.9 nm east of" -> "0.9 nm east"), which 199 of these
 * 842 need against the Salish bundle's 0.
 *
 * Run: cd tools && npm install && node gen-tides.mjs && node gen-noaa-currents.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { createPlacesResolver } from "@sailingnaturali/station-corrections";
import tzLookup from "tz-lookup";

const here = dirname(fileURLToPath(import.meta.url));
const res = join(here, "..", "Slackwater", "Resources");
const bundle = JSON.parse(readFileSync(join(here, "..", "data", "noaa-currents.json"), "utf8"));
const tides = JSON.parse(readFileSync(join(res, "stations.json"), "utf8"));
const resolve = createPlacesResolver(JSON.parse(readFileSync(
  createRequire(import.meta.url).resolve("@sailingnaturali/station-corrections/data/places.json"),
  "utf8")));

/** "0.9 nm east of" -> "0.9 nm east" (see gen-tides.mjs). */
const undangle = (s) => (s ?? "").replace(/\s+of$/i, "").trim();

/** Distance wins outright under this (slackwater-web tides.ts matchQuality). */
const PAIR_KM = 2.0;
/** A current station further than this from any tide gauge is somewhere the
 *  tide network does not reach, and its region line would be a guess. */
const REGION_SANITY_KM = 250;

function km(a, b) {
  const R = 6371, toR = (x) => (x * Math.PI) / 180;
  const dLa = toR(b.latitude - a.latitude), dLo = toR(b.longitude - a.longitude);
  const h = Math.sin(dLa / 2) ** 2 +
    Math.cos(toR(a.latitude)) * Math.cos(toR(b.latitude)) * Math.sin(dLo / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

const nearestTide = (s) =>
  tides.reduce((best, t) => {
    const d = km(s, t);
    return best && best.d <= d ? best : { t, d };
  }, null);

let curated = 0, paired = 0, worstNeighbour = 0;
const stations = bundle.stations
  .filter((s) => s.type === "harmonic")
  .filter((s) => !s.id.includes("@"))
  .filter((s) => s.constituents.some((c) => c.amplitude > 0))
  .map((s) => {
    const id = `noaa/${s.id}`;
    const near = nearestTide(s);
    worstNeighbour = Math.max(worstNeighbour, near.d);
    const r = resolve({ id, name: s.name, latitude: s.latitude, longitude: s.longitude });
    const out = {
      id,
      name: r.name,
      // A derived context is kept now, and outranks the borrowed one. It used
      // to be discarded in favour of the nearest tide station's region because
      // the gazetteer behind it was 19 Salish towns; since station-corrections
      // 2.8.0 it is a national list capped at 40 km, which is both closer to
      // this station than its neighbouring gauge and more specific than that
      // gauge's own label.
      region: undangle(r.context) || near.t.region,
      aliases: r.aliases ?? [],
      latitude: s.latitude,
      longitude: s.longitude,
      timezone: tzLookup(s.latitude, s.longitude),
      floodDirection: s.floodDirection,
      ebbDirection: s.ebbDirection,
      meanFlow: s.offset,
      constituents: s.constituents.filter((c) => c.amplitude > 0),
    };
    if (r.tideReference && tides.some((t) => t.id === r.tideReference)) {
      out.tideReference = r.tideReference;
      curated += 1;
    } else if (near.d <= PAIR_KM) {
      out.tideReference = near.t.id;
      paired += 1;
    }
    return out;
  })
  // Codepoint compare with an id tiebreak, not localeCompare: the sort must be
  // the same on every machine that regenerates this file (37 station names
  // collide, and locale collation of punctuation varies across ICU builds).
  .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.id < b.id ? -1 : 1));

if (stations.length < 700) {
  throw new Error(`only ${stations.length} current stations survived the filters — refusing to ship`);
}
if (worstNeighbour > REGION_SANITY_KM) {
  throw new Error(`a current station is ${worstNeighbour.toFixed(0)} km from the nearest tide ` +
    "station — its region line would be a guess; check the extract's extent");
}

writeFileSync(join(res, "currents.json"), JSON.stringify(stations));
console.log(
  `${stations.length} NOAA current stations, ` +
  `${(JSON.stringify(stations).length / 1024 / 1024).toFixed(2)} MB; ` +
  `${curated} curated + ${paired} proximity-paired (<= ${PAIR_KM} km); ` +
  `farthest tide gauge for a region line: ${worstNeighbour.toFixed(0)} km`);
