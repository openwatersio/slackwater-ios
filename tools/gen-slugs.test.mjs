/** Invariants for the generated Resources/slugs.json (gen-slugs.mjs). */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { here, stationSuccessors } from "./bundle.mjs";

const res = join(here, "..", "Slackwater", "Resources");
const read = (file) => JSON.parse(readFileSync(join(res, file), "utf8"));
const slugs = read("slugs.json");

test("every bundled station has a slug, keyed by its catalog id", () => {
  const expect = (kind, files) => {
    for (const file of files) {
      for (const s of read(file)) {
        if (s.referenceOnly) continue;
        assert.ok(slugs[kind][s.id], `${file}: ${s.id} has no ${kind} slug`);
      }
    }
  };
  expect("tide", ["stations.json", "chs-stations.json"]);
  expect("current", ["currents.json", "chs-current-gates.json", "chs-gates.json"]);
});

test("a slug is a URL path segment: lowercase, digits and hyphens only", () => {
  for (const kind of ["tide", "current"]) {
    for (const [id, slug] of Object.entries(slugs[kind])) {
      assert.match(slug, /^[a-z0-9]+(-[a-z0-9]+)*$/, `${kind} ${id}: ${slug}`);
    }
    for (const old of Object.keys(slugs.former[kind])) {
      assert.match(old, /^[a-z0-9]+(-[a-z0-9]+)*$/, `${kind} former: ${old}`);
    }
  }
});

test("a former slug names a bundled station, and never a slug that is live", () => {
  // The whole point of the table: an old shared link opens the same water it
  // always did, and cannot open different water. A former slug that is also
  // some station's current slug would do exactly that.
  for (const kind of ["tide", "current"]) {
    const live = new Set(Object.values(slugs[kind]));
    for (const [old, id] of Object.entries(slugs.former[kind])) {
      assert.ok(slugs[kind][id], `${kind} former ${old} -> ${id}, which is not bundled`);
      assert.ok(!live.has(old), `${kind} former ${old} is also a live slug`);
      assert.notEqual(slugs[kind][id], old, `${kind} former ${old} is its own current slug`);
    }
  }
});

test("history is kept only for stations still bundled", () => {
  // A former entry for an id the app no longer carries can never resolve;
  // the database's former paths bring it back if the station returns.
  for (const kind of ["tide", "current"]) {
    for (const [old, id] of Object.entries(slugs.former[kind])) assert.ok(slugs[kind][id], `${kind} former ${old} -> ${id} left the bundle`);
  }
});

test("the slugs this table published before are still reachable", () => {
  // Sawyer Key's two stations were `sawyer-key` and `sawyer-key-fl` before the
  // database named the water. Both must still open the station they did.
  assert.equal(slugs.former.tide["sawyer-key"], "noaa/8724369");
  assert.equal(slugs.tide["noaa/8724369"], "sawyer-key-inside-cudjoe-channel");
});

// --- Successors and tombstones (station-successors.json, station-tombstones.json)

const who = (id, extra = {}) => ({ id, name: `Name ${id}`, region: "Region", latitude: -41, longitude: 174, ...extra });

test("a departed station with a bundled twin on its route gets that twin as successor", () => {
  const got = stationSuccessors({
    departed: ["ticon/wellington", "ticon/sumner"],
    live: new Set(["linz/071", "linz/370"]),
    successorOf: (id) => ({ "ticon/wellington": "linz/071" })[id],
    identityOf: (id) => who(id),
  });
  assert.deepEqual(got.successors, { "ticon/wellington": "linz/071" });
  assert.deepEqual(got.tombstones.map((t) => t.id), ["ticon/sumner"]);
  assert.deepEqual(got.tombstones[0], { id: "ticon/sumner", name: "Name ticon/sumner", region: "Region", latitude: -41, longitude: 174 });
});

test("successors and tombstones are cumulative and stable across releases", () => {
  const first = stationSuccessors({
    departed: ["a", "gone"],
    live: new Set(["b"]),
    successorOf: (id) => ({ a: "b" })[id],
    identityOf: (id) => who(id),
  });
  // The next release: nothing departs, so the carried entries are the output.
  const again = stationSuccessors({
    departed: [], live: new Set(["b"]), successorOf: () => undefined, identityOf: () => undefined,
    previousSuccessors: first.successors, previousTombstones: first.tombstones,
  });
  assert.deepEqual(again, first);
  // A release after that moves `b` on to `c`: the old id follows the chain.
  const later = stationSuccessors({
    departed: ["b"], live: new Set(["c"]), successorOf: (id) => ({ b: "c" })[id], identityOf: (id) => who(id),
    previousSuccessors: again.successors, previousTombstones: again.tombstones,
  });
  assert.deepEqual(later.successors, { a: "c", b: "c" });
  assert.deepEqual(later.tombstones.map((t) => t.id), ["gone"]);
});

test("a station that comes back drops out of both lists", () => {
  const got = stationSuccessors({
    departed: [], live: new Set(["a", "b", "gone"]), successorOf: () => undefined, identityOf: () => undefined,
    previousSuccessors: { a: "b" }, previousTombstones: [who("gone")],
  });
  assert.deepEqual(got, { successors: {}, tombstones: [] });
});

test("a successor chain that ends nowhere is dropped, and one that ends in a tombstone is kept", () => {
  const got = stationSuccessors({
    departed: ["b"], live: new Set(), successorOf: () => undefined, identityOf: (id) => who(id),
    previousSuccessors: { a: "b", x: "y" },
  });
  assert.deepEqual(got.successors, { a: "b" });
  assert.deepEqual(got.tombstones.map((t) => t.id), ["b"]);
});

test("a CHS port leaves through chs-tombstones, never twice", () => {
  const got = stationSuccessors({
    departed: ["chs-north-galiano"], live: new Set(), successorOf: () => undefined,
    identityOf: (id) => who(id), covered: new Set(["chs-north-galiano"]),
  });
  assert.deepEqual(got, { successors: {}, tombstones: [] });
});

test("every successor is bundled or tombstoned, and no tombstone is bundled", () => {
  const successors = read("station-successors.json");
  const stones = read("station-tombstones.json");
  const chsStones = new Set(read("chs-tombstones.json").map((t) => t.id));
  const itemIds = new Set([
    ...read("stations.json").map((s) => s.id),
    ...read("chs-stations.json").map((s) => s.id),
    ...read("currents.json").filter((s) => !s.referenceOnly).map((s) => `current:${s.id}`),
    ...read("chs-gates.json").map((s) => s.id),
    ...read("chs-current-gates.json").map((s) => s.id),
  ]);
  const stoneIds = new Set(stones.map((t) => t.id));
  for (const [old, next] of Object.entries(successors)) {
    assert.ok(!itemIds.has(old), `${old} ships and still has a successor`);
    assert.ok(itemIds.has(next) || stoneIds.has(next) || chsStones.has(next), `${old} -> ${next}, which is nowhere`);
  }
  for (const t of stones) {
    assert.ok(!itemIds.has(t.id), `${t.id} is tombstoned and ships`);
    assert.ok(!chsStones.has(t.id), `${t.id} is tombstoned twice`);
    assert.ok(t.name && Number.isFinite(t.latitude) && Number.isFinite(t.longitude), `${t.id} has no identity`);
  }
});
