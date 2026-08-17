/** Shared scaffolding for the Resources/*.json generators. Side-effect-free at
 *  import so gen-tides.test.mjs can pull constants without running a generator. */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { createPlacesResolver } from "@sailingnaturali/station-corrections";

/** tools/ — every generator resolves its paths from here. */
export const here = dirname(fileURLToPath(import.meta.url));

const require = createRequire(import.meta.url);
/** A @sailingnaturali/station-corrections data file, parsed. */
export const stationData = (file) =>
  JSON.parse(readFileSync(require.resolve(`@sailingnaturali/station-corrections/data/${file}`), "utf8"));

/** The places resolver every generator names stations with. */
export const placesResolver = () => createPlacesResolver(stationData("places.json"));

/** Codepoint compare with an id tiebreak, not localeCompare: the sort must be
 *  the same on every machine that regenerates these files. */
export const byNameThenId = (a, b) =>
  a.name < b.name ? -1 : a.name > b.name ? 1 : a.id < b.id ? -1 : 1;

/** "6.6 nm SSE of" -> "6.6 nm SSE". */
export const undangle = (s) => (s ?? "").replace(/\s+of$/i, "").trim();

/**
 * The word TICON trails a name with, where it is not the code itself:
 * "Brockville Ontario · ON". Only the regions that actually occur in the
 * bundle, because an entry here is only ever a way to DELETE text — a code
 * missing from this map costs a redundant word, not a wrong station.
 * Alternates exist because upstream's spelling is upstream's ("Massachussets").
 */
export const REGION_WORD = {
  AK: "Alaska", HI: "Hawaii", MA: "Massachusetts|Massachussets", ME: "Maine",
  MI: "Michigan", NU: "Nunavut", NY: "New York", ON: "Ontario",
  QC: "Quebec|Québec", BC: "British Columbia",
};

/**
 * Identity for every station that HAS shipped and no longer does — the list
 * `gen-chs-stations.mjs` writes to Resources/chs-tombstones.json. A favourite
 * persists a bare id and nothing else, so this is the only way the app can
 * still name what someone starred three releases ago, or offer them something
 * near it instead of silently dropping the row (issue #91).
 *
 * Cumulative, and unioned from three places because no one of them is enough:
 *
 * - `dead` — advertises `wlp`, serves no predictions. This run knows the most
 *   about these, so it wins the id.
 * - `previous` — the artifact as it stood before this run. A station IWLS
 *   withdraws OUTRIGHT never reaches `dead` at all; it just stops appearing,
 *   and this is the only place its identity survives.
 * - `existing` — the tombstone file, holding everything older than one
 *   generation. Without it the list would only ever remember one release back.
 *
 * A tombstoned station that starts serving again drops out, so the result only
 * ever describes the gap between what a device stored and what ships today.
 *
 * Lives here rather than in the generator so it can be tested without the
 * ~20-minute live DFO probe the generator opens with — the same reason this
 * module is side-effect-free at import.
 */
export function tombstones({ shipping, dead = [], previous = [], existing = [] }) {
  const live = new Set(shipping.map((s) => s.id));
  const gone = new Map();
  for (const s of [...dead, ...previous, ...existing]) {
    if (live.has(s.id) || gone.has(s.id)) continue;
    gone.set(s.id, {
      id: s.id, name: s.name.trim(), region: s.region,
      latitude: s.latitude, longitude: s.longitude,
    });
  }
  return [...gone.values()].sort(byNameThenId);
}

/** Write the bundle as compact JSON; returns its size for the census line. */
export function writeBundle(path, data) {
  const json = JSON.stringify(data);
  writeFileSync(path, json);
  return `${(json.length / 1024 / 1024).toFixed(2)} MB`;
}

/** The @neaps/tide-database `source.name` NOAA CO-OPS rows carry — mirrors the
 *  same-named constant in gen-tides.mjs, which also uses it outside network
 *  classification (licence sort, CHS cede rule) so isn't itself moved here. */
const NOAA = "US National Oceanic and Atmospheric Administration";

/**
 * INVERTED at world coverage. This was an allowlist of eight operator codes,
 * which was the right shape while the bundle was one continent and the only
 * thing to exclude was US freshwater instrumentation. Worldwide it excluded 29
 * national hydrographic networks — BODC, REFMAR, RWS, WSV, JODC, BoM — for no
 * reason anyone had stated.
 *
 * So it is a denylist now, and it names exactly what the allowlist was written
 * to keep out: river and marsh gauges upstream of anywhere with water under a
 * keel. Measured — it drops 1,137 of the 5,416-station eligible pool and
 * admits 1,133 across the remaining 28 networks.
 *
 * The six US codes are the brief's original list, ported verbatim; `mi_r` was
 * added after review caught it leaking through unaudited — see its own
 * comment below. Every other network the inversion admits was checked by name
 * and amplitude before being left out of this list.
 *
 * ponytail: still a proxy. The honest filter is "is there navigable water
 * here", which no field in this database answers, and this is the cheapest
 * thing that behaves like it.
 */
export const FRESHWATER_NETWORKS = new Set([
  "crms",    // 328  Louisiana marsh platforms, each named for the nearest town
  "usgs",    // 591  river and creek stage gauges
  "cdwr",    // 131  California Delta
  "sfwmd",   //  43  Florida canals
  "nwfwmd",  //   9  Florida canals
  "ncdem",   //  26  North Carolina emergency-management gauges
  // Ireland's Marine Institute publishes two codes: mi_c is coastal harbours
  // (Dublin Port, Galway, Killybegs — legitimate, stays admitted) and mi_r is
  // its Burrishoole salmonid-research catchment in Co. Mayo plus one Dublin
  // urban river — the non-US analogue of usgs/crms above. 9 stations, all
  // river names ("Newport Black River", "River Tolka"), amplitude 0.04-0.76 m.
  "mi_r",    //   9  Irish river gauges (Burrishoole catchment + River Tolka)
]);

export const networkOf = (s) =>
  s.source?.name === NOAA ? "coops" : (s.id.split("-").pop() ?? "");

/**
 * Everywhere station-corrections' bundled gazetteer (places.json, 9,660
 * towns) can legitimately label a station — its own countries, plus the
 * territories it also carries towns for. Matamoros, MX sits 2.8 km from
 * Brownsville, TX, inside the resolver's own 40 km derivation radius;
 * nothing this close currently reaches gen-tides.mjs's naming stage (it
 * ships as a `subordinate` row and is filtered out earlier), but the
 * resolver has no way to know that, and a future upstream row could. So
 * gen-tides.mjs trusts a DERIVED context (the resolver's `derived: true`)
 * only inside this set — everywhere else the upstream region field is used
 * instead (see upstreamRegion in gen-tides.mjs).
 *
 * Shared with gen-tides.test.mjs so the region-line tests can classify a
 * station the same way the generator does, without importing gen-tides.mjs
 * itself (that module writes the bundle and prints at top level).
 */
export const NORTH_AMERICA = new Set(["United States", "Canada", "Puerto Rico",
  "Virgin Islands", "Guam", "Northern Mariana Islands", "American Samoa"]);

/**
 * Two rules, because they answer different questions.
 *
 * DUPLICATE_KM (in gen-tides.mjs, 1 km) asks "is this the same gauge,
 * published twice" and is name-blind — two genuinely different stations can
 * sit 800 m apart in a busy harbour and both deserve a pin.
 *
 * SAME_PLACE_KM (10 km) asks "is this the same PLACE, gauged twice" and only
 * applies when the names already match. Four UK publishers cover the same
 * harbours (bodc, cco, noc, da_idh) and upstream names them all after the
 * harbour, so "Lerwick" arrives three times from three networks. Ten km is
 * the CHS_COVERAGE_KM radius, and for the same reason: it asks whether this
 * water is already served, not whether this is the same instrument.
 *
 * Lives here, not in gen-tides.mjs, so gen-tides.test.mjs can import it
 * without importing the generator itself (that module writes the bundle and
 * prints at top level — no test may import it).
 */
export const SAME_PLACE_KM = 10.0;
