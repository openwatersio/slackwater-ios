/**
 * Generate Resources/slugs.json — the URL slug of every bundled station, for
 * the shared link `https://slackwater.xyz/<tides|currents>/<slug>` (#187).
 *
 * The vocabulary is @openwaters/station-metadata's data/slugs.json, allocated
 * once per station and permanent from then on; this only narrows it to the
 * ids the five committed catalogs ship, keyed exactly as they key them (bare
 * `noaa/…` for a current — the app's `current:` prefix is its own). A bundled
 * station with no published slug is a hard failure, not a gap: a link that
 * can't be minted is the one skew this file exists to rule out.
 *
 * Runs after the catalog generators (see `build:data`), reads local files
 * only, and is regenerated in CI to prove the committed table matches.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { here, stationData, writeBundle } from "./bundle.mjs";

const res = join(here, "..", "Slackwater", "Resources");
const published = stationData("slugs.json");
// A reference-only bin (#269) is not a station and is never linked.
const ids = (file) =>
  JSON.parse(readFileSync(join(res, file), "utf8")).filter((s) => !s.referenceOnly).map((s) => s.id);

/** The published `kind` table, narrowed to the ids in `files`. */
function narrow(kind, files) {
  const table = {};
  const missing = [];
  for (const id of files.flatMap(ids)) {
    const slug = published[kind][id];
    if (slug) table[id] = slug;
    else missing.push(id);
  }
  if (missing.length) {
    throw new Error(`${missing.length} bundled ${kind} station(s) have no published slug: ${missing.slice(0, 5).join(", ")}`);
  }
  return table;
}

// A CHS derived gate (chs-gates.json) is a current station on the web too.
const slugs = {
  tide: narrow("tide", ["stations.json", "chs-stations.json"]),
  current: narrow("current", ["currents.json", "chs-current-gates.json", "chs-gates.json"]),
};
const size = writeBundle(join(res, "slugs.json"), slugs);
console.log(`slugs.json: ${Object.keys(slugs.tide).length} tide + ${Object.keys(slugs.current).length} current, ${size}`);
