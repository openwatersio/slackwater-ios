import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

test("both Maizuru gauges ship with their own station links", () => {
  const resources = new URL("../Slackwater/Resources/", import.meta.url);
  const read = (name) => JSON.parse(readFileSync(new URL(name, resources), "utf8"));
  const ids = ["jma/MZ", "ticon/maizuru-hd24-jpn-jodc_jcg"];
  const stations = read("stations.json");
  const index = read("station-index.json");
  const slugs = read("slugs.json");
  const tombstones = read("station-tombstones.json");
  for (const id of ids) {
    assert.ok(stations.some((station) => station.id === id), id);
    assert.ok(index.tides.some((station) => station.id === id), id);
    assert.ok(slugs.tide[id], id);
    assert.ok(!tombstones.some((station) => station.id === id), id);
  }
  assert.notEqual(slugs.tide[ids[0]], slugs.tide[ids[1]]);
});
