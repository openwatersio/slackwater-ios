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
