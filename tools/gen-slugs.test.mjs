/** Invariants for the generated Resources/slugs.json (gen-slugs.mjs). */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { stationRoutes } from "@slackwater/database";
import { here, stationSuccessors, gateTombstones } from "./bundle.mjs";

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
const to = (id, datumShiftM) => (datumShiftM === undefined ? { id } : { id, datumShiftM });

test("a departed station with a bundled twin on its route gets that twin as successor", () => {
  const got = stationSuccessors({
    departed: ["ticon/wellington", "ticon/sumner"],
    live: new Set(["linz/071", "linz/370"]),
    successorOf: (id) => ({ "ticon/wellington": to("linz/071", 0.12) })[id],
    identityOf: (id) => who(id),
  });
  assert.deepEqual(got.successors, { "ticon/wellington": to("linz/071", 0.12) });
  assert.deepEqual(got.tombstones.map((t) => t.id), ["ticon/sumner"]);
  assert.deepEqual(got.tombstones[0], { id: "ticon/sumner", name: "Name ticon/sumner", region: "Region", latitude: -41, longitude: 174 });
});

test("successors and tombstones are cumulative and stable across releases", () => {
  const first = stationSuccessors({
    departed: ["a", "gone"],
    live: new Set(["b"]),
    successorOf: (id) => ({ a: to("b", 0.1) })[id],
    identityOf: (id) => who(id),
  });
  // The next release: nothing departs, so the carried entries are the output.
  const again = stationSuccessors({
    departed: [], live: new Set(["b"]), successorOf: () => undefined, identityOf: () => undefined,
    previousSuccessors: first.successors, previousTombstones: first.tombstones,
  });
  assert.deepEqual(again, first);
  // A release after that moves `b` on to `c`: the old id follows the chain,
  // and the datum shifts add up along it.
  const later = stationSuccessors({
    departed: ["b"], live: new Set(["c"]), successorOf: (id) => ({ b: to("c", 0.25) })[id], identityOf: (id) => who(id),
    previousSuccessors: again.successors, previousTombstones: again.tombstones,
  });
  assert.deepEqual(later.successors, { a: to("c", 0.35), b: to("c", 0.25) });
  assert.deepEqual(later.tombstones.map((t) => t.id), ["gone"]);
});

test("a chain with one unknown datum shift has no shift", () => {
  const got = stationSuccessors({
    departed: ["b"], live: new Set(["c"]), successorOf: (id) => ({ b: to("c") })[id], identityOf: () => undefined,
    previousSuccessors: { a: to("b", 0.1) },
  });
  assert.deepEqual(got.successors, { a: to("c"), b: to("c") });
});

test("a station that comes back drops out of both lists", () => {
  const got = stationSuccessors({
    departed: [], live: new Set(["a", "b", "gone"]), successorOf: () => undefined, identityOf: () => undefined,
    previousSuccessors: { a: to("b") }, previousTombstones: [who("gone")],
  });
  assert.deepEqual(got, { successors: {}, tombstones: [] });
});

test("a successor chain that ends nowhere is dropped, and one that ends in a tombstone is kept", () => {
  const got = stationSuccessors({
    departed: ["b"], live: new Set(), successorOf: () => undefined, identityOf: (id) => who(id),
    previousSuccessors: { a: to("b"), x: to("y") },
  });
  assert.deepEqual(got.successors, { a: to("b") });
  assert.deepEqual(got.tombstones.map((t) => t.id), ["b"]);
});

test("a successor that arrives releases after the tombstone revives the id and its aliases", () => {
  // Release 1 tombstones `a` (nothing else on its route ships) and keeps an
  // older alias `z` ending at it. Release 2 ships nothing new. Release 3
  // bundles `b` on a's route: a is no longer in any previous table, so only
  // the carried tombstone can bring it back.
  const r1 = stationSuccessors({
    departed: ["a"], live: new Set(), successorOf: () => undefined, identityOf: (id) => who(id),
    previousSuccessors: { z: to("a", 0.05) },
  });
  assert.deepEqual(r1.tombstones.map((t) => t.id), ["a"]);
  const r2 = stationSuccessors({
    departed: [], live: new Set(), successorOf: () => undefined, identityOf: () => undefined,
    previousSuccessors: r1.successors, previousTombstones: r1.tombstones,
  });
  const r3 = stationSuccessors({
    departed: [], live: new Set(["b"]), successorOf: (id) => ({ a: to("b", 0.2) })[id], identityOf: () => undefined,
    previousSuccessors: r2.successors, previousTombstones: r2.tombstones,
  });
  assert.deepEqual(r3.successors, { a: to("b", 0.2), z: to("b", 0.25) });
  assert.deepEqual(r3.tombstones, []);
});

test("a CHS port leaves through chs-tombstones, never twice", () => {
  const got = stationSuccessors({
    departed: ["chs-north-galiano"], live: new Set(), successorOf: () => undefined,
    identityOf: (id) => who(id), covered: new Set(["chs-north-galiano"]),
  });
  assert.deepEqual(got, { successors: {}, tombstones: [] });
});

test("a departing CHS gate keeps its name and position", () => {
  // gen-chs-gates.mjs records it before overwriting the gate catalogs, since
  // station-index.json never held gates; gen-slugs then carries it.
  const gate = { id: "chs-gone-pass", name: "Gone Pass", region: "Somewhere Sound", aliases: [],
    latitude: 50.1, longitude: -125.2, timezone: "America/Vancouver", fitDays: 60 };
  const stones = gateTombstones({ previous: [gate], shipping: [], existing: [who("ticon/sumner")] });
  assert.deepEqual(stones.find((t) => t.id === "chs-gone-pass"),
    { id: "chs-gone-pass", name: "Gone Pass", region: "Somewhere Sound", latitude: 50.1, longitude: -125.2 });
  assert.ok(stones.some((t) => t.id === "ticon/sumner"), "other tombstones are kept");
  const carried = stationSuccessors({
    departed: ["chs-gone-pass"], live: new Set(), successorOf: () => undefined, identityOf: () => undefined,
    previousTombstones: stones,
  });
  assert.ok(carried.tombstones.some((t) => t.id === "chs-gone-pass"));
  assert.deepEqual(gateTombstones({ previous: [gate], shipping: [gate], existing: [] }), []);
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
  for (const [old, { id: next, datumShiftM }] of Object.entries(successors)) {
    assert.ok(datumShiftM === undefined || Number.isFinite(datumShiftM), `${old}: datum shift ${datumShiftM}`);
    assert.ok(!itemIds.has(old), `${old} ships and still has a successor`);
    assert.ok(itemIds.has(next) || stoneIds.has(next) || chsStones.has(next), `${old} -> ${next}, which is nowhere`);
  }
  for (const t of stones) {
    assert.ok(!itemIds.has(t.id), `${t.id} is tombstoned and ships`);
    assert.ok(!chsStones.has(t.id), `${t.id} is tombstoned twice`);
    assert.ok(t.name && Number.isFinite(t.latitude) && Number.isFinite(t.longitude), `${t.id} has no identity`);
  }
});

test("a corrected UK slug opens the gauge it names, with no history", () => {
  // slackwater-database#287: these seven published a neighbour's gauge, so the
  // slug this table used to give each id is not that id's history.
  assert.equal(slugs.tide["ticon/brighton-btn-gbr-cco"], "brighton");
  assert.equal(slugs.tide["ticon/hastings_pier-hgp-gbr-cco"], "hastings-pier");
  assert.equal(slugs.former.tide["brighton"], undefined);
  assert.equal(slugs.former.tide["teignmouth-pier"], undefined);
});

test("a link to a merged station's departed record opens the record that replaced it", () => {
  // TICON's Napier gauge left the bundle for LINZ's record of the same gauge,
  // which the database publishes as one station.
  assert.equal(slugs.tide["linz/097"], "napier");
  assert.equal(slugs.former.tide["napier-ruawharo-harbour-te-whanga-o-ruawharo"], "linz/097");
});

test("no database route holds two bundled stations", () => {
  // One gauge, one pin, and one id behind each slug (gen-tides.mjs, ONE
  // STATION PER ROUTE): a shared link must not depend on which id the app's
  // resolver happens to meet first.
  for (const kind of ["tide", "current"]) {
    const bundled = new Set(Object.keys(slugs[kind]));
    const doubled = stationRoutes(kind)
      .map((r) => r.stationIds.filter((id) => bundled.has(id)))
      .filter((ids) => ids.length > 1);
    assert.deepEqual(doubled, [], kind);
  }
});

test("a saved New Zealand TICON station moves to LINZ's record of the same gauge", () => {
  const successors = read("station-successors.json");
  // A known datum shift moves a saved tide height; a CHS port has none.
  assert.deepEqual(successors["ticon/wellington-071-nzl-uhslc_fd"], { id: "linz/071", datumShiftM: 0.416 });
  assert.deepEqual(successors["noaa/8218617"], { id: "chs-mill-bay" });
  const stones = read("station-tombstones.json").map((t) => t.id);
  assert.deepEqual(stones.sort(), [
    "ticon/auckland-070a-nzl-uhslc_rq", "ticon/jackson_bay-65180-nzl-bom", "ticon/sumner-sumt-nzl-ttw",
  ]);
});
