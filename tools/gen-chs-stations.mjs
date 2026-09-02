/**
 * Generate Resources/chs-stations.json — the bundled IDENTITY of every
 * Canadian tide station Slackwater can fit — and Resources/chs-tombstones.json,
 * the same identity for the ones that USED to ship (see writeTombstones).
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
 * ("Nanaimo, BC") — capped at 40 km and skipped when it would only restate
 * the station's own name, so Halifax does not read "Halifax, NS". Then, for a
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
import { readFileSync } from "node:fs";
import { join } from "node:path";
import tzLookup from "tz-lookup";
import { here, placesResolver, stationData, byNameThenId, tombstones, writeBundle } from "./bundle.mjs";
import { km } from "./geo.mjs";

const out = join(here, "..", "Slackwater", "Resources", "chs-stations.json");
const tombstonesOut = join(here, "..", "Slackwater", "Resources", "chs-tombstones.json");
/** Both artifacts as they stand BEFORE this run — read here because
 *  writeTombstones needs the previous station list and writeBundle has
 *  overwritten it by then. Missing file reads as empty: first run. */
const readArtifact = (p) => { try { return JSON.parse(readFileSync(p, "utf8")); } catch { return []; } };
const wasShipped = readArtifact(out);
const wasTombstoned = readArtifact(tombstonesOut);
const resolvePlace = placesResolver();
const registry = stationData("registry.json");

/** Same tolerance the app resolves with (ChsFitService.resolveToleranceKm). */
const REGISTRY_MATCH_KM = 3.0;
const IWLS = "https://api-iwls.dfo-mpo.gc.ca/api/v1/stations";

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
 * "Halifax, NS". Its cleaned name comes back out unused, deliberately —
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

/**
 * IWLS publishes exactly one broken officialName — station 00550, "Sable
 * Island/Sable, ÃŽle de". That is UTF-8 "Île" decoded as CP1252 and re-encoded,
 * in DFO's own feed; nothing here mis-decodes it. It is also the feed's only
 * bilingual name, so it renders on the card as an English name followed by a
 * mangled French restatement of itself.
 *
 * Repaired by table rather than by a general latin1 round-trip: the other 89
 * accented names in the feed are clean UTF-8, and re-decoding them yields
 * replacement characters, so a general pass would need a guard that matches
 * exactly this one row. The French half goes to aliases — it is a real name and
 * someone might type it.
 * ponytail: one row, one entry. A second broken name is another line, not a parser.
 *
 * BOTH spellings are keyed, because this was reported to CHS and they do fix
 * names (they renamed two BC stations by notice in 2023). **They did**: Michel
 * Leger at CHS repaired the database on 2026-08-17, one day after the report,
 * and `/stations` now returns "Sable Island/Sable, Île de" — so the second key
 * is the live one and the mangled key is the one kept for history.
 *
 * Which is why the id is pinned here rather than slugged. The id slugs the RAW
 * officialName, and the raw name just changed: a regenerate would rename
 * `…-azle-de` to `…-ile-de` and orphan every fitted model stored under the old
 * id on a shipped build. The ugly slug is the correct one — it is what is out
 * there.
 */
const FIXED_SABLE = {
  id: "chs-sable-island-sable-azle-de",
  name: "Sable Island",
  aliases: ["sable, île de"],
};
const NAME_FIXES = {
  "Sable Island/Sable, ÃŽle de": FIXED_SABLE,
  "Sable Island/Sable, Île de": FIXED_SABLE,
};

const slug = (name) =>
  "chs-" + name.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

const response = await fetch(IWLS);
if (!response.ok) throw new Error(`IWLS /stations: HTTP ${response.status}`);
const iwls = (await response.json())
  .filter((s) => s.timeSeries?.some((t) => t.code === "wlp"))
  // Station code, not name: the collision suffixes below have to be stable.
  .sort((a, b) => (a.code < b.code ? -1 : a.code > b.code ? 1 : 0));

/**
 * The `wlp` claim above is metadata, and IWLS publishes it for stations it
 * serves no predictions for. Ogdensburg and Peace Bridge Below advertise the
 * series and return `[]` for every window and every series, permanently.
 *
 * Nothing else in the record separates them from a good station: both read
 * `operating: false` with type DISCONTINUED/TEMPORARY — and so do Joggins and
 * Ile Haute, which answer fine. `operating` marks a live gauge, not a
 * predictable port, and it is false on 991 of these 1086. The only signal that
 * works is asking for water and seeing whether any arrives.
 *
 * The cost of shipping one is a station the user can find, tap, and queue,
 * that then sits in Downloads as a permanent "Failed" behind a Retry button
 * that cannot ever succeed — and burns ten paced requests on every press.
 *
 * Probed AFTER the ids are assigned, never before: the `-2` collision suffixes
 * are positional, so dropping a station ahead of that loop renumbers the ones
 * behind it and orphans every model already stored under the old id.
 */
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// IWLS 429s well inside the app's own 2.5 s pacing, so probe politely and back
// off; 1086 stations at this spacing is a ~20 min generator run, once.
const PROBE_SPACING_MS = 1200;

async function servesPredictions({ id }, from, to) {
  const url = `${IWLS}/${id}/data?time-series-code=wlp&from=${from}&to=${to}`;
  for (let attempt = 0; ; attempt += 1) {
    const r = await fetch(url);
    if (r.ok) return (await r.json()).length > 0;
    if (attempt === 4) throw new Error(`IWLS probe ${id}: HTTP ${r.status}`);
    await sleep(2000 * 2 ** attempt);
  }
}

// One hour, yesterday: the smallest window that answers the question, on a day
// every real station has both predictions and history for.
const probeDay = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);
const [probeFrom, probeTo] = [`${probeDay}T00:00:00Z`, `${probeDay}T01:00:00Z`];

const served = new Set();
for (const [n, s] of iwls.entries()) {
  if (await servesPredictions(s, probeFrom, probeTo)) served.add(s.id);
  if (n % 100 === 0) console.log(`  probing wlp… ${n}/${iwls.length}, ${served.size} serving`);
  await sleep(PROBE_SPACING_MS);
}
const dead = [];

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
    !claimed.has(id) &&
    km({ latitude: e.position[0], longitude: e.position[1] }, s) <= REGISTRY_MATCH_KM);
  if (match) {
    const [id, e] = match;
    claimed.add(id);
    taken.add(id);
    // A curated port is pointed at by gen-chs-gates.mjs and by stored models,
    // so a dead one is a registry problem to fix, not a station to quietly drop.
    if (!served.has(s.id)) {
      throw new Error(`registry tide port ${id} (${e.name}) serves no wlp data — ` +
        `IWLS returns [] for it; correct or remove it in station-corrections`);
    }
    stations.push({
      id, name: e.name, region: e.context, aliases: e.aliases ?? [],
      // The registry's curated position, not the published one: it is the
      // corrected one, and it is what every other consumer already uses.
      latitude: e.position[0], longitude: e.position[1],
      timezone: tzLookup(e.position[0], e.position[1]),
    });
    continue;
  }
  const fix = NAME_FIXES[s.officialName];
  let id = fix?.id ?? slug(s.officialName);
  for (let n = 2; taken.has(id); n += 1) id = `${slug(s.officialName)}-${n}`;
  taken.add(id);
  // alternativeName is a comma-separated pile of French/former/variant names —
  // exactly what someone might type, which is what aliases are for.
  const name = fix?.name ?? s.officialName;
  const aliases = [...new Set([...(fix?.aliases ?? []), ...(s.alternativeName ?? "").split(",")
    .map((a) => a.trim().toLowerCase()).filter((a) => a && a !== name.toLowerCase())])];
  if (!served.has(s.id)) {
    // The repaired name, not the raw one: a tombstone is what a favorite renders
    // as after the station leaves the bundle, so mangled text there is the same
    // bug one screen later.
    dead.push({
      id, name: name.trim(),
      region: contextOf(id, name, s.latitude, s.longitude),
      latitude: s.latitude, longitude: s.longitude,
    });
    continue;
  }
  stations.push({
    id, name,
    region: contextOf(id, name, s.latitude, s.longitude), aliases,
    latitude: s.latitude, longitude: s.longitude,
    timezone: tzLookup(s.latitude, s.longitude),
  });
}

const missing = ports.filter(([id]) => !claimed.has(id)).map(([id]) => id);
if (missing.length) {
  throw new Error(`registry tide ports with no IWLS station within ${REGISTRY_MATCH_KM} km: ` +
    `${missing.join(", ")} — their ids would change, orphaning every stored model`);
}

stations.sort(byNameThenId);
const size = writeBundle(out, stations);
const tombstoneCount = writeTombstones(stations, dead);

const census = {};
for (const s of stations) census[s.region] = (census[s.region] ?? 0) + 1;
console.log(`${stations.length} CHS tide stations (${claimed.size} registry-curated), ${size}`);
console.log(`${dead.length} dropped — advertise wlp, serve none:\n` +
  dead.map((d) => `  ${d.id} (${d.name})`).join("\n"));
console.log(`${tombstoneCount} tombstones (cumulative)`);
console.log(Object.entries(census).sort((a, b) => b[1] - a[1])
  .map(([k, n]) => `  ${String(n).padStart(4)}  ${k}`).join("\n"));

/**
 * Resources/chs-tombstones.json — see `tombstones()` in bundle.mjs for what
 * goes in it and why. Deliberately a SEPARATE file from chs-stations.json:
 * that one is a bare array and the Swift loader decodes it as one, so a new
 * top-level key there would take every Canadian station out of the app
 * silently (`bundled`'s `try?` swallows the failure into an empty catalog).
 */
function writeTombstones(shipping, dead) {
  const list = tombstones({
    shipping, dead, previous: wasShipped, existing: wasTombstoned,
  });
  writeBundle(tombstonesOut, list);
  return list.length;
}
