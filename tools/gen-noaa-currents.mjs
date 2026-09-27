/**
 * Generate Resources/currents.json — every bundled NOAA tidal-current station.
 *
 * Source: the NOAA current records in @slackwater/database, the same release
 * gen-tides.mjs reads. The database's own source workspace extracts them from
 * NOAA CO-OPS (public domain), keeps the reviewed bundle, and asserts the
 * cross-flow bound there: every station here is modelled as one signed speed
 * along a fixed flood axis, and a station whose perpendicular flow exceeds
 * half its axis peak is refused at extraction, not here.
 *
 * Filters, all inherited from slackwater-web's build-currents.mjs, all still
 * load-bearing:
 *   1. Harmonic and subordinate stations (#268). A subordinate has no
 *      constituents: it ships with `reference` and NOAA's six offsets, in the
 *      engine's own field names, for SlackwaterKit's SubordinateStation —
 *      and only if its reference ships too (the 147 whose reference is a
 *      non-primary bin are #269).
 *   2. Primary bin only (id without "@") — one station, one prediction — except
 *      a bin that a shipped subordinate reduces from (#269). That bin ships as
 *      a reference-only record: `referenceOnly: true`, harmonic shape, named
 *      for its surface station, no slug. The app never lists it.
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
 * NAMING is the tide generator's, verbatim: station-metadata resolve(),
 * with a DERIVED context replaced by the nearest tide station's region —
 * the bundled gazetteer is 19 Salish towns and nationally invents nonsense
 * ("Pollock Rip Channel · near Everett, WA") — and the same dangling-
 * preposition strip ("0.9 nm east of" -> "0.9 nm east"), which 199 of these
 * 842 need against the Salish bundle's 0.
 *
 * Run: cd tools && npm install && node gen-tides.mjs && node gen-noaa-currents.mjs
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import tzLookup from "tz-lookup";
import { allStations } from "@slackwater/database";
import { here, placesResolver, byNameThenId, undangle, round3, writeBundle } from "./bundle.mjs";
import { km } from "./geo.mjs";

const res = join(here, "..", "Slackwater", "Resources");
const NOAA = "noaa/";
const MINUTE = 60;

/**
 * A database record in the extract's own shape, so the filters below read as
 * NOAA describes a station. The database splits a name into the place and
 * the water ("Eastport" / "Friar Roads"); joined back, resolve() names it the
 * way it names a tide station. Its offsets are minutes; the engine's
 * SubordinateStation takes seconds.
 */
function fromDatabase(s) {
  const c = s.current ?? {};
  const o = c.offsets;
  return {
    id: s.id.slice(NOAA.length),
    name: s.context && !s.context_derived ? `${s.name}, ${s.context}` : s.name,
    type: o ? "subordinate" : "harmonic",
    latitude: s.latitude,
    longitude: s.longitude,
    floodDirection: c.flood_direction == null ? null : round3(c.flood_direction),
    ebbDirection: c.ebb_direction == null ? null : round3(c.ebb_direction),
    offset: c.mean_flow == null ? undefined : round3(c.mean_flow),
    constituents: (s.harmonic_constituents ?? [])
      .map((k) => ({ name: k.name, amplitude: round3(k.amplitude), phase: round3(k.phase) })),
    ...(o && {
      reference: o.reference.slice(NOAA.length),
      slackBeforeFloodOffset: o.slack_before_flood * MINUTE,
      slackBeforeEbbOffset: o.slack_before_ebb * MINUTE,
      floodTimeOffset: o.flood_time * MINUTE,
      ebbTimeOffset: o.ebb_time * MINUTE,
      floodSpeedRatio: round3(o.flood_speed_ratio),
      ebbSpeedRatio: round3(o.ebb_speed_ratio),
    }),
  };
}
const bundle = {
  stations: allStations.filter((s) => s.kind === "current" && s.id.startsWith(NOAA)).map(fromDatabase),
};
const tides = JSON.parse(readFileSync(join(res, "stations.json"), "utf8"));
const resolve = placesResolver();

/** Distance wins outright under this (slackwater-web tides.ts matchQuality). */
const PAIR_KM = 2.0;
/** A current station further than this from any tide gauge is somewhere the
 *  tide network does not reach, and its region line would be a guess. */
const REGION_SANITY_KM = 250;

// Harmonic stations first (#229): a subordinate tide station is a lower
// accuracy class and 302 of them carry a bare state code for a region, so it
// never names a current station's region and only pairs where no harmonic
// gauge is within PAIR_KM — otherwise adding subordinates would have moved 30
// regions and 16 existing pairings.
const harmonic = tides.filter((t) => !t.reference);
const subordinates = tides.filter((t) => t.reference);
const nearestIn = (list, s) =>
  list.reduce((best, t) => {
    const d = km(s, t);
    return best && best.d <= d ? best : { t, d };
  }, null);
const nearestTide = (s) => nearestIn(harmonic, s);

let curated = 0, paired = 0, worstNeighbour = 0, orphaned = 0, undirected = 0;
const isSubordinate = (s) => s.type === "subordinate";
const OFFSETS = ["slackBeforeFloodOffset", "slackBeforeEbbOffset", "floodTimeOffset",
  "ebbTimeOffset", "floodSpeedRatio", "ebbSpeedRatio"];
const directed = (s) => Number.isFinite(s.floodDirection) && Number.isFinite(s.ebbDirection);
// #269: a non-primary bin ships only as the reference of a subordinate that
// itself ships. Reference-only: in the file for the reduction, never a station.
const referencedBins = new Set(
  bundle.stations
    .filter((s) => isSubordinate(s) && directed(s) && s.reference.includes("@"))
    .map((s) => s.reference));
const isReferenceOnly = (s) => s.id.includes("@");
const kept = bundle.stations
  .filter((s) => s.type === "harmonic" || isSubordinate(s))
  .filter((s) => !s.id.includes("@") || referencedBins.has(s.id))
  .filter((s) => isSubordinate(s) || s.constituents.some((c) => c.amplitude > 0))
  // Nine subordinates publish one direction and null for the other; the app
  // draws a set arrow from both, and guessing the reciprocal is a claim about
  // the water nobody made.
  .filter((s) => directed(s) || (undirected++, false))
  .map((s) => {
    const id = `noaa/${s.id}`;
    const near = nearestTide(s);
    // A bin is named for its surface station: same water, same resolved name.
    const r = resolve({ id: `noaa/${s.id.split("@")[0]}`, name: s.name, latitude: s.latitude, longitude: s.longitude });
    // The neighbour only matters when it names the region. Three subordinates
    // (Rat Islands, Meyers Passage) sit 250-350 km from any harmonic gauge and
    // carry their own context, so their distance is nobody's business.
    if (!undangle(r.context)) worstNeighbour = Math.max(worstNeighbour, near.d);
    const out = {
      id,
      name: r.name,
      // A derived context is kept now, and outranks the borrowed one. It used
      // to be discarded in favour of the nearest tide station's region because
      // the gazetteer behind it was 19 Salish towns; since station-metadata
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
      meanFlow: s.offset ?? 0,
      constituents: isSubordinate(s) ? [] : s.constituents.filter((c) => c.amplitude > 0),
      // Seconds and ratios, exactly as the bundle (and the engine) spell them.
      ...(isSubordinate(s) && {
        reference: `noaa/${s.reference}`,
        ...Object.fromEntries(OFFSETS.map((k) => [k, s[k]])),
      }),
      ...(isReferenceOnly(s) && { referenceOnly: true }),
    };
    if (!isReferenceOnly(s)) {
      if (r.tideReference && tides.some((t) => t.id === r.tideReference)) {
        out.tideReference = r.tideReference;
        curated += 1;
      } else if (near.d <= PAIR_KM) {
        out.tideReference = near.t.id;
        paired += 1;
      } else if (nearestIn(subordinates, s)?.d <= PAIR_KM) {
        out.tideReference = nearestIn(subordinates, s).t.id;
        paired += 1;
      }
    }
    return out;
  })
  // (37 station names collide, and locale collation of punctuation varies
  // across ICU builds — hence byNameThenId's codepoint compare.)
  .sort(byNameThenId);
// A subordinate whose reference is not on the device is a dead pin.
const shipped = new Set(kept.filter((s) => !s.reference).map((s) => s.id));
const stations = kept.filter((s) =>
  !s.reference || shipped.has(s.reference) || (orphaned++, false));

const used = new Set(stations.filter((s) => s.reference).map((s) => s.reference));
const unused = stations.filter((s) => s.referenceOnly && !used.has(s.id)).map((s) => s.id);
if (unused.length) {
  throw new Error(`reference-only bins nobody references: ${unused.join(", ")} — a filter was reordered`);
}

if (stations.length < 700) {
  throw new Error(`only ${stations.length} current stations survived the filters — refusing to ship`);
}
if (worstNeighbour > REGION_SANITY_KM) {
  throw new Error(`a current station is ${worstNeighbour.toFixed(0)} km from the nearest tide ` +
    "station — its region line would be a guess; check the extract's extent");
}

const size = writeBundle(join(res, "currents.json"), stations);
const subordinateCount = stations.filter((s) => s.reference).length;
const referenceOnlyCount = stations.filter((s) => s.referenceOnly).length;
const binSubordinates = stations.filter((s) => s.reference?.includes("@")).length;
console.log(
  `${stations.length} NOAA current stations (${stations.length - subordinateCount - referenceOnlyCount} harmonic, ` +
  `${subordinateCount} subordinate, ${referenceOnlyCount} reference-only bins serving ${binSubordinates}; ` +
  `${orphaned} orphaned and ${undirected} direction-less subordinates dropped), ${size}; ` +
  `${curated} curated + ${paired} proximity-paired (<= ${PAIR_KM} km); ` +
  `farthest tide gauge for a region line: ${worstNeighbour.toFixed(0)} km`);
