/**
 * Generate Resources/station-index.json — the identity half of the two large
 * NOAA catalogs, so the first frame never decodes their constituents (#317).
 *
 * stations.json is 7.2 MB and currents.json 1.9 MB, almost all of it harmonic
 * constituents, and the station list renders from names and coordinates alone.
 * This narrows both to the seven identity fields `StationItem` reads.
 *
 * Derived from the committed catalogs, never from upstream, so it cannot name
 * a station the catalogs don't ship or drift from what they say. Runs after
 * the catalog generators (see `build:data`) and is regenerated in CI.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { here, writeBundle } from "./bundle.mjs";

const res = join(here, "..", "Slackwater", "Resources");

const FIELDS = ["id", "name", "region", "aliases", "latitude", "longitude", "timezone"];

/**
 * The identity rows of one catalog, in its own order. A reference-only bin
 * (#269) is carried for its harmonic shape and never rendered as a station,
 * so it has no row here — matching `StationItem.all`'s filter.
 */
function identities(catalog) {
  return catalog
    .filter((s) => !s.referenceOnly)
    .map((s) => Object.fromEntries(FIELDS.map((f) => [f, s[f]])));
}

const read = (file) => JSON.parse(readFileSync(join(res, file), "utf8"));
const index = {
  tides: identities(read("stations.json")),
  currents: identities(read("currents.json")),
};
const size = writeBundle(join(res, "station-index.json"), index);
console.log(
  `station-index.json: ${index.tides.length} tide + ${index.currents.length} current, ${size}`);
