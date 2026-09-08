/** Invariants for the generated Resources/station-index.json (gen-station-index.mjs). */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { here } from "./bundle.mjs";

const res = join(here, "..", "Slackwater", "Resources");
const read = (file) => JSON.parse(readFileSync(join(res, file), "utf8"));
const index = read("station-index.json");

const FIELDS = ["id", "name", "region", "aliases", "latitude", "longitude", "timezone"];
const pairs = [
  ["tides", "stations.json"],
  ["currents", "currents.json"],
];

test("the index carries every rendered station, with identical identity fields", () => {
  for (const [key, file] of pairs) {
    const rows = new Map(index[key].map((s) => [s.id, s]));
    let expected = 0;
    for (const station of read(file)) {
      // A reference-only bin is never rendered, so it is deliberately absent.
      if (station.referenceOnly) {
        assert.ok(!rows.has(station.id), `${file}: ${station.id} is reference-only`);
        continue;
      }
      expected += 1;
      const row = rows.get(station.id);
      assert.ok(row, `${file}: ${station.id} missing from station-index.json`);
      for (const field of FIELDS) {
        assert.deepEqual(row[field], station[field], `${station.id}: ${field}`);
      }
    }
    assert.equal(index[key].length, expected, `${key}: extra rows in the index`);
  }
});

test("the index carries identity only — no constituents", () => {
  for (const key of ["tides", "currents"]) {
    for (const row of index[key]) {
      assert.deepEqual(Object.keys(row).sort(), [...FIELDS].sort(), row.id);
    }
  }
});
