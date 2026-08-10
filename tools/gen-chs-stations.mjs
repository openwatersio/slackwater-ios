/**
 * Generate Resources/chs-stations.json — the bundled IDENTITY of every
 * Canadian tide station Slackwater can fit.
 *
 * LICENSING POSTURE, unchanged (chs-online-design §2): the app bundles station
 * IDENTITY — name, position, provider — and nothing CHS-published. Predictions
 * are fetched by each user under DFO's own terms, fitted on-device, stored
 * locally, and never re-served. What is NOT bundled, deliberately: the IWLS
 * station id. It resolves at runtime by position (ChsFitService.resolve, 3 km
 * tolerance), the same posture station-corrections took in v2.0.0 — the
 * provider-minted id is looked up under the operator's own licence, never
 * shipped in an artifact.
 *
 * Identity is bundled rather than fetched because a station has to be VISIBLE
 * and SEARCHABLE with no signal. A Canadian station the app cannot name is a
 * station the user cannot find, and "we have no Canadian coverage" would be
 * the wrong answer — it has coverage, it just has to download the water.
 *
 * SOURCE. IWLS /stations, filtered to those serving `wlp` (water level
 * predictions) — that is the series the on-device fit reads, so a station
 * without it could never become a working station.
 *
 * IDS. A registry entry wins outright: an IWLS station within
 * REGISTRY_MATCH_KM of a `station-corrections` CHS tide port takes that
 * entry's id, curated name, context and aliases. This is load-bearing, not
 * tidiness — stored fitted models are keyed by id, and gen-chs-gates.mjs
 * points its derived gates and tide pairings at those same ids. Everything
 * else gets `chs-<slug>`, deterministic and collision-suffixed in IWLS
 * station-code order so the id a device stored yesterday is the id it reads
 * today.
 *
 * CONTEXT. IWLS publishes no region, so the label is derived here, in two
 * tiers. First the NEAREST TOWN from station-corrections' national places list
 * ("~Nanaimo, BC") — capped at 40 km and skipped when it would only restate
 * the station's own name, so Halifax does not read "~Halifax, NS". Then, for a
 * station with no town in range, a COARSE COAST label from position,
 * deliberately coarse enough to stay true at every boundary (an Ungava Bay
 * station reading "Atlantic Coast" is a fact about the ocean basin, not a
 * guess about a county).
 *
 * The coast tier used to be the ONLY tier, because the gazetteer that fed the
 * derived one held 19 Salish towns and would have labelled Halifax "near
 * Nanaimo, BC". station-corrections 2.8.0 added the national list, which is
 * what makes the first tier safe; it is passed in rather than bundled because
 * it is ~890 KB. The generator prints the census so the labelling stays
 * reviewable, and the way to make any one station better is still the
 * registry, which is where curated identity belongs.
 * ponytail: two derived tiers; per-station context goes in station-corrections.
 *
 * Run: cd tools && npm install && node gen-chs-stations.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { createPlacesResolver } from "@sailingnaturali/station-corrections";
import tzLookup from "tz-lookup";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const out = join(here, "..", "Slackwater", "Resources", "chs-stations.json");
const places = JSON.parse(readFileSync(
  require.resolve("@sailingnaturali/station-corrections/data/places.json"), "utf8"));
const resolvePlace = createPlacesResolver(places);
const registry = JSON.parse(readFileSync(
  createRequire(import.meta.url).resolve("@sailingnaturali/station-corrections/data/registry.json"),
  "utf8",
));

/** Same tolerance the app resolves with (ChsFitService.resolveToleranceKm). */
const REGISTRY_MATCH_KM = 3.0;
const IWLS = "https://api-iwls.dfo-mpo.gc.ca/api/v1/stations";

function km(aLat, aLon, bLat, bLon) {
  const R = 6371, toR = (x) => (x * Math.PI) / 180;
  const dLa = toR(bLat - aLat), dLo = toR(bLon - aLon);
  const h = Math.sin(dLa / 2) ** 2 +
    Math.cos(toR(aLat)) * Math.cos(toR(bLat)) * Math.sin(dLo / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/**
 * Coarse coast labels, first match wins. Chosen so that every station the rule
 * catches is genuinely in that water: the Pacific and Arctic bands are
 * separated by a 10° latitude gap with no stations in it, Hudson/James Bay is
 * the only Canadian water in its box, and "Atlantic Coast" is the basin every
 * remaining station drains to.
 */
const COASTS = [
  ["Great Lakes & St. Lawrence", (la, lo) => la <= 45.5 && lo >= -84 && lo <= -74],
  ["Arctic Coast", (la, lo) => lo <= -110 && la >= 66],
  ["Pacific Coast", (la, lo) => lo <= -110],
  ["Hudson Bay", (la, lo) => la >= 51 && la <= 65 && lo >= -96 && lo <= -76],
  ["Arctic Coast", (la) => la >= 60],
  ["St. Lawrence", (la, lo) => la >= 45.5 && la <= 51 && lo >= -73 && lo <= -58],
  ["Atlantic Coast", () => true],
];
const coastOf = (la, lo) => COASTS.find(([, hit]) => hit(la, lo))[0];

/**
 * Nearest town, else the coast. The id is one this generator is about to mint
 * and the registry has already declined, so the resolver only ever reaches its
 * derived tier here — the call is for the town, not for an identity.
 *
 * The raw name goes in because the resolver needs it to suppress a context
 * that only restates it: a station called Halifax must not be labelled
 * "~Halifax, NS". Its cleaned name comes back out unused, deliberately —
 * renaming a thousand IWLS stations is a separate change from labelling them.
 */
function contextOf(id, name, latitude, longitude) {
  const r = resolvePlace({ id, name, latitude, longitude });
  // `derived` only. The resolver's other unowned tier splits a name on its
  // comma qualifier, which IWLS names are not written for: "Charlottetown,
  // PEI" came back with the context "Pei", and a dozen more like it. The coast
  // label is a better answer than a miscased fragment of the name above it.
  return r.derived ? r.context : coastOf(latitude, longitude);
}

const slug = (name) =>
  "chs-" + name.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

const response = await fetch(IWLS);
if (!response.ok) throw new Error(`IWLS /stations: HTTP ${response.status}`);
const iwls = (await response.json())
  .filter((s) => s.timeSeries?.some((t) => t.code === "wlp"))
  // Station code, not name: the collision suffixes below have to be stable.
  .sort((a, b) => (a.code < b.code ? -1 : a.code > b.code ? 1 : 0));

const ports = Object.entries(registry).filter(([, e]) => e.provider === "chs" && e.kind === "tide");
const claimed = new Set();
// Every registry key is reserved up front, not just the tide ports: IWLS has
// wlp stations named "Porlier Pass" and "Seymour Narrows", which slug straight
// onto two CURRENT-gate ids. Two StationItems with one id is a duplicate row,
// a duplicate map pin, and a model store that can't tell them apart.
const taken = new Set(Object.keys(registry));
const stations = [];

for (const s of iwls) {
  const match = ports.find(([id, e]) =>
    !claimed.has(id) && km(e.position[0], e.position[1], s.latitude, s.longitude) <= REGISTRY_MATCH_KM);
  if (match) {
    const [id, e] = match;
    claimed.add(id);
    taken.add(id);
    stations.push({
      id, name: e.name, region: e.context, aliases: e.aliases ?? [],
      // The registry's curated position, not the published one: it is the
      // corrected one, and it is what every other consumer already uses.
      latitude: e.position[0], longitude: e.position[1],
      timezone: tzLookup(e.position[0], e.position[1]),
    });
    continue;
  }
  let id = slug(s.officialName);
  for (let n = 2; taken.has(id); n += 1) id = `${slug(s.officialName)}-${n}`;
  taken.add(id);
  // alternativeName is a comma-separated pile of French/former/variant names —
  // exactly what someone might type, which is what aliases are for.
  const aliases = [...new Set((s.alternativeName ?? "").split(",")
    .map((a) => a.trim().toLowerCase()).filter((a) => a && a !== s.officialName.toLowerCase()))];
  stations.push({
    id, name: s.officialName,
    region: contextOf(id, s.officialName, s.latitude, s.longitude), aliases,
    latitude: s.latitude, longitude: s.longitude,
    timezone: tzLookup(s.latitude, s.longitude),
  });
}

const missing = ports.filter(([id]) => !claimed.has(id)).map(([id]) => id);
if (missing.length) {
  throw new Error(`registry tide ports with no IWLS station within ${REGISTRY_MATCH_KM} km: ` +
    `${missing.join(", ")} — their ids would change, orphaning every stored model`);
}

stations.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.id < b.id ? -1 : 1));
writeFileSync(out, JSON.stringify(stations));

const census = {};
for (const s of stations) census[s.region] = (census[s.region] ?? 0) + 1;
console.log(`${stations.length} CHS tide stations (${claimed.size} registry-curated), ` +
  `${(JSON.stringify(stations).length / 1024).toFixed(0)} KB`);
console.log(Object.entries(census).sort((a, b) => b[1] - a[1])
  .map(([k, n]) => `  ${String(n).padStart(4)}  ${k}`).join("\n"));
