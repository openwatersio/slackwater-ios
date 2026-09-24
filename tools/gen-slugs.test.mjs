/** Invariants for the generated Resources/slugs.json (gen-slugs.mjs). */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { here } from "./bundle.mjs";

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

test("the slugs this table published before are still reachable", () => {
  // Sawyer Key's two stations were `sawyer-key` and `sawyer-key-fl` before the
  // database named the water. Both must still open the station they did.
  assert.equal(slugs.former.tide["sawyer-key"], "noaa/8724369");
  assert.equal(slugs.tide["noaa/8724369"], "sawyer-key-inside-cudjoe-channel");
});
