/**
 * Invariants for the generated Resources/chs-stations.json.
 *
 * On the ARTEFACT, not the generator's internals — it is what ships, and the
 * only thing an Xcode build reads. Run after the generator: `npm test`.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { here } from "./bundle.mjs";

const stations = JSON.parse(
  readFileSync(join(here, "..", "Slackwater", "Resources", "chs-stations.json"), "utf8"));

// IWLS advertises the wlp series on stations it serves no predictions for.
// These two are the known ones: they return [] for every window and every
// series, so they can only ever be a permanent "Failed" row in Downloads
// behind a Retry that cannot succeed. The generator probes for real water; if
// that probe is ever dropped, these come back and this goes red.
test("stations that advertise wlp but serve no data do not ship", () => {
  const ids = new Set(stations.map((s) => s.id));
  for (const dead of ["chs-ogdensburg", "chs-peace-bridge-below"]) {
    assert.equal(ids.has(dead), false, `${dead} serves no wlp data and must not ship`);
  }
});

// Ids are what stored fitted models are keyed by, and what gen-chs-gates.mjs
// points its derived gates at.
test("ids are unique", () => {
  const ids = stations.map((s) => s.id);
  assert.equal(new Set(ids).size, ids.length);
});
