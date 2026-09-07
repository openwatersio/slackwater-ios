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
        if (s.referenceOnly) {
          assert.equal(slugs[kind][s.id], undefined, `${file}: ${s.id} is reference-only but has a ${kind} slug`);
          continue;
        }
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
  }
});
