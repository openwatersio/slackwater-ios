import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { prepare, refresh } from "./iwls-fixtures.mjs";

const samples = (days) => Array.from({ length: days * 96 }, (_, index) => ({
  eventDate: new Date(Date.parse("2026-09-01T00:00:00Z") - (days * 96 - index) * 900_000).toISOString(), value: 1,
}));
const valid = {
  schemaVersion: 1,
  capturedAt: "2026-09-08T00:00:00.000Z",
  bounds: { end: "2026-09-01T00:00:00.000Z" },
  stations: [
    { key: "victoria", id: "v", officialName: "Victoria Harbour", latitude: 48, longitude: -123,
      metadata: null, series: { wlp: samples(60) } },
    ...[["active", 60], ["dodd", 210], ["sechelt", 10]].map(([key, days]) => ({ key, id: key, officialName: key,
      latitude: 49, longitude: -123, metadata: { floodDirection: 1, ebbDirection: 181 },
      series: { wcsp1: samples(days), wcdp1: samples(days) } })),
  ],
};

test("prepare is offline and rejects missing or corrupt recordings", async () => {
  const dir = await mkdtemp(join(tmpdir(), "iwls-fixture-"));
  const staged = join(dir, "staged.json");
  await assert.rejects(prepare({ fixtureDir: dir, staged }), /refresh/);
  await writeFile(join(dir, "iwls-recording.json"), "nope");
  await assert.rejects(prepare({ fixtureDir: dir, staged }), /valid JSON/);
  await writeFile(join(dir, "iwls-recording.json"), JSON.stringify(valid));
  const oldFetch = globalThis.fetch;
  globalThis.fetch = () => { throw new Error("prepare fetched"); };
  try { await prepare({ fixtureDir: dir, staged }); } finally { globalThis.fetch = oldFetch; }
  assert.deepEqual(JSON.parse(await readFile(staged)), valid);
});

test("failed refresh preserves the previous recording", async () => {
  const dir = await mkdtemp(join(tmpdir(), "iwls-fixture-"));
  const recording = join(dir, "iwls-recording.json");
  await writeFile(recording, JSON.stringify(valid));
  await assert.rejects(refresh({ fixtureDir: dir, fetchImpl: async () => { throw new Error("offline"); }, paceMs: 0 }), /offline/);
  assert.deepEqual(JSON.parse(await readFile(recording)), valid);
});
