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
 * SOURCE. @slackwater/database's CHS tide records: its curated tide ports plus
 * the identity-only records its `sources/chs` import keeps — IWLS stations
 * serving `wlp` that answer a one-hour prediction probe. Selection, the probe,
 * names and contexts all live there, so the app and the website carry the same
 * stations under the same names.
 *
 * IDS are the database's, which kept every id this generator used to mint.
 * That is load-bearing: stored fitted models are keyed by id, and
 * gen-chs-gates.mjs points its derived gates and tide pairings at those same
 * ids. A station the database drops becomes a tombstone here, never a new id.
 *
 * Run: cd tools && npm install && node gen-chs-stations.mjs
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { here, curatedRecords, byNameThenId, tombstones, writeBundle } from "./bundle.mjs";

const out = join(here, "..", "Slackwater", "Resources", "chs-stations.json");
const tombstonesOut = join(here, "..", "Slackwater", "Resources", "chs-tombstones.json");
/** Both artifacts as they stand BEFORE this run — read here because
 *  writeTombstones needs the previous station list and writeBundle has
 *  overwritten it by then. Missing file reads as empty: first run. */
const readArtifact = (p) => { try { return JSON.parse(readFileSync(p, "utf8")); } catch { return []; } };
const wasShipped = readArtifact(out);
const wasTombstoned = readArtifact(tombstonesOut);

/**
 * Coarse coast labels, first match wins, for a station the database gives
 * neither a context nor a province (the high Arctic, Sable Island). Chosen so
 * that every station the rule catches is genuinely in that water: the Pacific
 * and Arctic bands are separated by a 10° latitude gap with no stations in it,
 * Hudson/James Bay is the only Canadian water in its box, and "Atlantic Coast"
 * is the basin every remaining station drains to.
 * ponytail: delete once the database derives a context for every CHS station
 * (openwatersio/slackwater-database#213).
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

const census = { context: 0, province: 0, coast: 0 };
const stations = Object.entries(await curatedRecords())
  .filter(([, e]) => e.provider === "chs" && e.kind === "tide")
  .map(([id, e]) => {
    census[e.context ? "context" : e.province ? "province" : "coast"]++;
    return {
      id, name: e.name,
      // The same fallback gen-tides.mjs uses — context, then province — with
      // the coast in place of a bare "Canada" on the few with neither.
      region: e.context ?? e.province ?? coastOf(...e.position),
      aliases: e.aliases,
      latitude: e.position[0], longitude: e.position[1],
      timezone: e.timezone,
    };
  })
  .sort(byNameThenId);

const size = writeBundle(out, stations);
const tombstoneCount = writeTombstones(stations);

const renamed = wasShipped.filter((w) => stations.some((s) => s.id === w.id && s.name !== w.name)).length;
const relabelled = wasShipped.filter((w) => stations.some((s) => s.id === w.id && s.region !== w.region)).length;
console.log(`${stations.length} CHS tide stations (was ${wasShipped.length}), ${size}`);
console.log(`  ${renamed} renamed, ${relabelled} with a new context line`);
console.log(`  context lines: ${census.context} database context, ${census.province} province, ${census.coast} coast`);
console.log(`${tombstoneCount} tombstones (cumulative)`);

/**
 * Resources/chs-tombstones.json — see `tombstones()` in bundle.mjs for what
 * goes in it and why. Deliberately a SEPARATE file from chs-stations.json:
 * that one is a bare array and the Swift loader decodes it as one, so a new
 * top-level key there would take every Canadian station out of the app
 * silently (`bundled`'s `try?` swallows the failure into an empty catalog).
 */
function writeTombstones(shipping) {
  const list = tombstones({ shipping, previous: wasShipped, existing: wasTombstoned });
  writeBundle(tombstonesOut, list);
  return list.length;
}
