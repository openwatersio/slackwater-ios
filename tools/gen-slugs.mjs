/**
 * Generate Resources/slugs.json — the URL slug of every bundled station, for
 * the shared link `https://slackwater.xyz/<tides|currents>/<slug>` (#187).
 *
 * The vocabulary is @slackwater/database's route index: one slug per station,
 * allocated once and kept, so the app and the website mint the same link for
 * the same water. The table is narrowed to the ids the five committed catalogs
 * ship, keyed exactly as they key them (bare `noaa/…` for a current — the
 * app's `current:` prefix is its own). A bundled station with no published
 * route is a hard failure, not a gap: a link that can't be minted is the one
 * skew this file exists to rule out.
 *
 * `former` is the other half of the contract: every slug a bundled station
 * used to answer to, mapped to its id, so a link shared by an older build
 * still opens the same water. It is cumulative — this run carries forward
 * what the committed table already recorded, adds any slug the database has
 * retired for the station, and adds the slug this table itself published if
 * the database has since moved it. The slug of a station that left for the
 * record `quality.redundant` names moves to that record too, because the two
 * are separate routes in the database and nothing else carries the link.
 * An entry goes only when no bundled station can answer it, because the link
 * it serves may be in a message from years ago.
 *
 * Runs after the catalog generators (see `build:data`), reads local files
 * only, and is regenerated in CI to prove the committed table matches.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
// The route index comes from the release that publishes routes, aliased so the
// catalog generators can stay on the release their output was built from until
// #469 moves them: the URL a station is shared at and the record it is drawn
// from are two decisions, and this file is only the first.
import { stationRoutes, stationsById } from "@slackwater/database";
import { here, writeBundle, stationSuccessors, redundantChain, round3 } from "./bundle.mjs";

const res = join(here, "..", "Slackwater", "Resources");
const out = join(res, "slugs.json");
/** What this table said last time it was committed; an absent file is a first run. */
const previous = (() => {
  try {
    return JSON.parse(readFileSync(out, "utf8"));
  } catch (error) {
    // Only a missing table is a first run. A table that exists but cannot
    // be read or parsed must stop the build: rewriting it from nothing would
    // drop every former slug that lives only here.
    if (error.code === "ENOENT") return { tide: {}, current: {} };
    throw error;
  }
})();
// A reference-only bin (#269) is not a station and is never linked.
const ids = (file) =>
  JSON.parse(readFileSync(join(res, file), "utf8")).filter((s) => !s.referenceOnly).map((s) => s.id);

/**
 * Tide slugs that published a neighbour's gauge and now publish the one they
 * name, mirroring CORRECTED_PATHS in slackwater-database's
 * validate-database.ts (slackwater-database#287). Each was this table's slug
 * for the wrong id, so it is not history: it opens the station it names, and
 * nothing redirects, because the old link pointed at the wrong water.
 */
const CORRECTED = new Map([
  ["brighton", "ticon/brighton-btn-gbr-cco"],
  ["hastings-pier", "ticon/hastings_pier-hgp-gbr-cco"],
  ["teignmouth-pier", "ticon/teignmouth_pier-tnp-gbr-cco"],
  ["port-isaac", "ticon/port_isaac-pti-gbr-cco"],
  ["severn-bridge", "ticon/severn_bridge-ssc-gbr-cco"],
  ["scarborough", "ticon/scarborough-sca-gbr-cco"],
  ["west-bay-harbour", "ticon/west_bay_harbour-wbh-gbr-cco"],
]);

/** The database's route for every station id of one kind. */
function routesById(kind) {
  const table = new Map();
  for (const route of stationRoutes(kind)) {
    const former = route.formerPaths.map((path) => path.split("/").filter(Boolean).pop());
    for (const id of route.stationIds) table.set(id, { slug: route.slug, former, ids: route.stationIds });
  }
  return table;
}

/** The published `kind` table, narrowed to the ids in `files`, and its history. */
function narrow(kind, files) {
  const routes = routesById(kind);
  const table = {};
  const former = { ...(previous.former?.[kind] ?? {}) };
  const missing = [];
  for (const id of files.flatMap(ids)) {
    const route = routes.get(id);
    if (!route) {
      missing.push(id);
      continue;
    }
    table[id] = route.slug;
    for (const old of [previous[kind]?.[id], ...route.former]) {
      const corrected = kind === "tide" && CORRECTED.has(old);
      if (old && old !== route.slug && !corrected) former[old] = id;
    }
  }
  // A station that left for the record `quality.redundant` names hands that
  // record its slugs: the two are separate routes, so neither the database's
  // former paths nor a shared route carries the link across.
  const liveSlugs = new Set(Object.values(table));
  for (const [id, slug] of Object.entries(previous[kind] ?? {})) {
    if (!table[id] && !liveSlugs.has(slug)) former[slug] = id;
  }
  for (const [old, id] of Object.entries(former)) {
    const heir = table[id] ? undefined : redundantChain(id, stationsById).find((other) => table[other]);
    if (heir) former[old] = heir;
  }
  if (missing.length) {
    throw new Error(`${missing.length} bundled ${kind} station(s) have no published route: ${missing.slice(0, 5).join(", ")}`);
  }
  if (kind === "tide") {
    for (const [slug, id] of CORRECTED) {
      if (table[id] !== slug) throw new Error(`corrected slug ${slug} no longer names ${id}`);
    }
  }
  // A slug the database gave back to the station that used to answer to it is
  // live again, not history.
  for (const [old, id] of Object.entries(former)) if (table[id] === old) delete former[old];
  // History only for stations still in the bundle: the app cannot open an id
  // it does not carry, and the database's own former paths bring the entry
  // back if the station returns.
  for (const [old, id] of Object.entries(former)) if (!table[id]) delete former[old];
  // A former slug that is some station's live slug would send an old link to
  // the wrong water. Against the bundle that is an error outright. Against the
  // whole database it is an error only when the live owner is bundled — the
  // resolver tries live before former, so a bundled owner wins and the history
  // entry is a lie. An unbundled owner is reported and kept: `ogdensburg` is
  // the NOAA twin's slug in the database and the MEDS copy's here, the same
  // gauge a kilometre apart (tide-database#168), and without the entry a link
  // to the copy this app carries would open nothing.
  const live = new Set(Object.values(table));
  const clash = Object.keys(former).filter((old) => live.has(old));
  if (clash.length) throw new Error(`${kind}: former slug(s) also live: ${clash.slice(0, 5).join(", ")}`);
  const elsewhere = [];
  for (const route of stationRoutes(kind)) {
    if (!(route.slug in former)) continue;
    if (route.stationIds.some((id) => table[id]))
      throw new Error(`${kind}: former slug ${route.slug} is live for bundled ${route.stationIds.join(",")}`);
    elsewhere.push(`${route.slug} (${route.stationIds.join(",")})`);
  }
  if (elsewhere.length) console.log(`${kind}: ${elsewhere.length} former slug(s) live for an unbundled station: ${elsewhere.join("; ")}`);
  return { table, former: Object.fromEntries(Object.entries(former).sort()) };
}

// A CHS derived gate (chs-gates.json) is a current station on the web too.
const tide = narrow("tide", ["stations.json", "chs-stations.json"]);
const current = narrow("current", ["currents.json", "chs-current-gates.json", "chs-gates.json"]);
const slugs = { tide: tide.table, current: current.table, former: { tide: tide.former, current: current.former } };
const size = writeBundle(out, slugs);

/**
 * Resources/station-successors.json and station-tombstones.json — see
 * `stationSuccessors` in bundle.mjs. A departed station is one the previous
 * table slugged and this one does not. Its successor is the bundled id on its
 * database route, else the bundled record its `quality.redundant` names; its
 * identity, for a tombstone, is what the committed
 * station-index.json still says, since gen-station-index runs after this.
 * Gates are not in that index, so gen-chs-gates.mjs writes a departing gate's
 * tombstone before it rewrites the gate catalogs, and this carries it.
 * Keyed by `StationItem` id, the id a device saved: a NOAA current carries the
 * app's `current:` prefix, everything else is the catalog id.
 */
const itemId = (kind, id) => (kind === "current" && !id.startsWith("chs-") ? `current:${id}` : id);
const readOr = (file, fallback) => {
  try {
    return JSON.parse(readFileSync(join(res, file), "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return fallback;
    throw error;
  }
};
const lastIndex = readOr("station-index.json", { tides: [], currents: [] });
const lastIdentity = new Map([
  ...lastIndex.tides.map((s) => [s.id, s]),
  ...lastIndex.currents.map((s) => [itemId("current", s.id), s]),
]);
const live = new Set();
const departed = [];
const nowByKind = { tide: tide.table, current: current.table };
const routesByKind = { tide: routesById("tide"), current: routesById("current") };
for (const [kind, now] of Object.entries(nowByKind)) {
  for (const id of Object.keys(now)) live.add(itemId(kind, id));
  for (const id of Object.keys(previous[kind] ?? {})) {
    if (!now[id]) departed.push(itemId(kind, id));
  }
}

/**
 * Metres to add to a height above `from`'s chart datum to put it above `to`'s:
 * the database publishes both records as one gauge, by a route or by
 * `quality.redundant`, so their mean sea level is the same water, and each
 * record's MSL above its own chart datum is exactly the `datumOffset`
 * gen-tides ships. Undefined unless both are harmonic references carrying MSL
 * and their chart datum; a subordinate's heights come from its reference's
 * datum and offsets, and a CHS port is fitted on the device from heights the
 * database does not carry.
 */
const msl = (id) => {
  const s = stationsById.get(id);
  const zero = s?.datums?.[s?.chart_datum];
  return s && s.type === "reference" && s.datums?.MSL != null && zero != null ? s.datums.MSL - zero : undefined;
};
const datumShift = (from, to) => {
  const a = msl(from);
  const b = msl(to);
  return a === undefined || b === undefined ? undefined : round3(b - a);
};

/**
 * The bundled station the database publishes for a departed id, as
 * `{ id, datumShiftM? }`: the one on its route, else the one `quality.redundant`
 * leads to. A record that left as a duplicate usually has a route of its own,
 * so the route alone would tombstone a gauge that still ships.
 */
const successorOf = (item) => {
  const kind = item.startsWith("current:") || (!routesByKind.tide.has(item) && routesByKind.current.has(item))
    ? "current" : "tide";
  const id = item.replace(/^current:/, "");
  const bundled = (other) => nowByKind[kind][other];
  const twin = (routesByKind[kind].get(id)?.ids ?? []).filter(bundled).sort()[0] ??
    redundantChain(id, stationsById).find(bundled);
  if (!twin) return undefined;
  const shift = kind === "tide" ? datumShift(id, twin) : undefined;
  return shift === undefined ? { id: itemId(kind, twin) } : { id: itemId(kind, twin), datumShiftM: shift };
};
const { successors, tombstones } = stationSuccessors({
  departed,
  live,
  successorOf,
  identityOf: (id) => lastIdentity.get(id),
  previousSuccessors: readOr("station-successors.json", {}),
  previousTombstones: readOr("station-tombstones.json", []),
  covered: new Set(readOr("chs-tombstones.json", []).map((t) => t.id)),
});
writeBundle(join(res, "station-successors.json"), successors);
writeBundle(join(res, "station-tombstones.json"), tombstones);
console.log(`station-successors.json: ${Object.keys(successors).length}; station-tombstones.json: ${tombstones.length}`);
console.log(
  `slugs.json: ${Object.keys(slugs.tide).length} tide + ${Object.keys(slugs.current).length} current, ` +
    `${Object.keys(tide.former).length + Object.keys(current.former).length} former, ${size}`,
);
