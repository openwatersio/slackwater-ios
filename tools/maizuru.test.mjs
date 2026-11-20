import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadStations } from "@slackwater/database";

test("both Maizuru gauges ship with distinct labels and station links", async () => {
  const resources = new URL("../Slackwater/Resources/", import.meta.url);
  const read = (name) => JSON.parse(readFileSync(new URL(name, resources), "utf8"));
  const ids = ["jma/MZ", "ticon/maizuru-hd24-jpn-jodc_jcg"];
  const stations = read("stations.json");
  const index = read("station-index.json");
  const slugs = read("slugs.json");
  const tombstones = read("station-tombstones.json");
  const database = await loadStations(new URL("stations.tcdb", resources));
  for (const id of ids) {
    assert.ok(stations.some((station) => station.id === id), id);
    assert.ok(database.byId(id), id);
    assert.ok(index.tides.some((station) => station.id === id), id);
    assert.ok(slugs.tide[id], id);
    assert.ok(!tombstones.some((station) => station.id === id), id);
  }
  assert.notEqual(slugs.tide[ids[0]], slugs.tide[ids[1]]);
  assert.equal(index.tides.find((station) => station.id === ids[1]).region, "Kyoto · Japan Coast Guard");
  assert.notEqual(index.tides.find((station) => station.id === ids[0]).region, index.tides.find((station) => station.id === ids[1]).region);
});
