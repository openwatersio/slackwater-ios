/**
 * Generate Resources/slugs.json — the URL slug of every bundled station, for
 * the shared link `https://slackwater.xyz/<tides|currents>/<slug>` (#187).
 *
 * The vocabulary is @neaps/tide-database's route index: one slug per station,
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
 * the database has since moved it. Nothing here is ever dropped, because the
 * link it serves may be in a message from years ago.
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
import { stationRoutes } from "@neaps/tide-database-routes";
import { here, writeBundle } from "./bundle.mjs";

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

/** The database's route for every station id of one kind. */
function routesById(kind) {
  const table = new Map();
  for (const route of stationRoutes(kind)) {
    const former = route.formerPaths.map((path) => path.split("/").filter(Boolean).pop());
    for (const id of route.stationIds) table.set(id, { slug: route.slug, former });
  }
  return table;
}

/** The published `kind` table, narrowed to the ids in `files`, and its history. */
function narrow(kind, files) {
  const routes = routesById(kind);
  const table = {};
  const former = { ...(previous.former?.[kind] ?? {}) };
  const missing = [];
  let reserved = 0;
  for (const id of files.flatMap(ids)) {
    const route = routes.get(id);
    if (!route) {
      // A CHS port the database reserves a slug for but does not route — the
      // 1,050 whose identity is published nowhere yet (#17). It keeps the slug
      // this table last shipped, which is the reservation. Anything else with
      // no route is a broken catalog, not a gap to paper over.
      const carried = id.startsWith("chs-") ? previous[kind]?.[id] : undefined;
      if (carried) {
        table[id] = carried;
        reserved++;
      } else missing.push(id);
      continue;
    }
    table[id] = route.slug;
    for (const old of [previous[kind]?.[id], ...route.former]) {
      if (old && old !== route.slug) former[old] = id;
    }
  }
  if (missing.length) {
    throw new Error(`${missing.length} bundled ${kind} station(s) have no published route: ${missing.slice(0, 5).join(", ")}`);
  }
  if (reserved) console.log(`${kind}: ${reserved} CHS stations on a reserved slug the database does not route yet`);
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
console.log(
  `slugs.json: ${Object.keys(slugs.tide).length} tide + ${Object.keys(slugs.current).length} current, ` +
    `${Object.keys(tide.former).length + Object.keys(current.former).length} former, ${size}`,
);
