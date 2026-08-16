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
import { here, tombstones } from "./bundle.mjs";

const resource = (name) =>
  JSON.parse(readFileSync(join(here, "..", "Slackwater", "Resources", name), "utf8"));
const stations = resource("chs-stations.json");
const shipped = resource("chs-tombstones.json");

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

// The union itself, on fixtures — the generator opens with a ~20-minute live
// DFO probe, so this is the only way these branches get exercised routinely.
const station = (id, extra = {}) =>
  ({ id, name: id, region: "Pacific Coast", latitude: 48, longitude: -123, ...extra });

test("a station that stops serving gets a tombstone", () => {
  const got = tombstones({ shipping: [station("a")], dead: [station("b")] });
  assert.deepEqual(got.map((t) => t.id), ["b"]);
});

// The case `dead` cannot see: IWLS drops the station from /stations entirely,
// so it is never probed and never lands in `dead`. Only the previous artifact
// remembers it existed.
test("a station withdrawn from IWLS outright is caught by the previous artifact", () => {
  const got = tombstones({ shipping: [station("a")], previous: [station("a"), station("b")] });
  assert.deepEqual(got.map((t) => t.id), ["b"]);
});

test("history survives regeneration", () => {
  const got = tombstones({
    shipping: [station("a")],
    dead: [station("c")],
    previous: [station("a")],
    existing: [station("old")],
  });
  assert.deepEqual(got.map((t) => t.id).sort(), ["c", "old"]);
});

test("a station that starts serving again loses its tombstone", () => {
  const got = tombstones({ shipping: [station("b")], existing: [station("b")], dead: [] });
  assert.deepEqual(got, []);
});

// Ids are what favorites persist, so a duplicated one would render the row
// twice — and the freshest identity has to win, or a renamed station keeps
// showing the name it had when it died.
test("the freshest identity wins a repeated id", () => {
  const got = tombstones({
    shipping: [],
    dead: [station("b", { name: "New Name" })],
    previous: [station("b", { name: "Stale Name" })],
    existing: [station("b", { name: "Ancient Name" })],
  });
  assert.equal(got.length, 1);
  assert.equal(got[0].name, "New Name");
});

// IWLS pads several officialNames with trailing spaces ("La Salle ", "Peace
// Bridge Below        ") and they reached the shipped bundle that way.
test("names are trimmed on the way in", () => {
  const got = tombstones({ shipping: [], dead: [station("b", { name: "  Padded  " })] });
  assert.equal(got[0].name, "Padded");
});

// The tombstone list is what a device with a favorite from an older bundle
// resolves the name and position of (issue #91). Two ways it can be wrong:
// naming a station that still ships, or losing an identity it once carried.
test("no tombstone names a station that still ships", () => {
  const live = new Set(stations.map((s) => s.id));
  for (const t of shipped) {
    assert.equal(live.has(t.id), false, `${t.id} is tombstoned and shipping`);
  }
});

test("every tombstone carries the identity the app renders", () => {
  for (const t of shipped) {
    assert.ok(t.id && t.name && t.region, `${t.id} is missing name or region`);
    assert.equal(t.name, t.name.trim(), `${t.id} name is untrimmed`);
    assert.equal(typeof t.latitude, "number");
    assert.equal(typeof t.longitude, "number");
  }
});

// Cumulative on purpose: the 28 CHS withdrew in c3ed4a0 are the whole reason
// the file exists, and a regeneration that quietly forgot them would leave
// every device that favorited one back to a silently vanishing row.
test("the withdrawn stations stay tombstoned", () => {
  const ids = new Set(shipped.map((t) => t.id));
  // The count is what catches a regeneration that lost history — the union in
  // writeTombstones only ever grows. It can legitimately SHRINK if IWLS starts
  // serving one of these again, which is a real event worth reading rather
  // than a number to bump: check the generator's dropped list before editing.
  assert.ok(shipped.length >= 28,
    `${shipped.length} tombstones, was 28 — did a regeneration lose history, or did a station come back?`);
  for (const dead of ["chs-ogdensburg", "chs-peace-bridge-below", "chs-north-galiano"]) {
    assert.ok(ids.has(dead), `${dead} lost its tombstone`);
  }
});
