/**
 * Invariants for the generated Resources/currents.json — asserted on the
 * artefact, like gen-tides.test.mjs. Run after the generator: `npm test`.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { here } from "./bundle.mjs";

const stations = JSON.parse(
  readFileSync(join(here, "..", "Slackwater", "Resources", "currents.json"), "utf8"));

// Subordinate current stations (#268). No constituents of their own: the
// reference's events, shifted by four time offsets and scaled by two speed
// ratios, all in the engine's own field names. A subordinate whose reference
// is not on the device is a dead pin, so it must not ship (#269 covers the
// ones whose reference is a non-primary bin).
const subordinates = stations.filter((s) => s.reference);
const OFFSETS = ["slackBeforeFloodOffset", "slackBeforeEbbOffset", "floodTimeOffset",
  "ebbTimeOffset", "floodSpeedRatio", "ebbSpeedRatio"];

test("Point Bonita ships as a subordinate of a bundled reference", () => {
  const bonita = stations.find((s) => s.id === "noaa/PCT0236");
  assert.ok(bonita, "noaa/PCT0236 is not in the bundle");
  assert.equal(bonita.reference, "noaa/SFB1201");
  assert.deepEqual(OFFSETS.map((k) => bonita[k]), [-4080, -5280, -3840, -5100, 0.3, 0.5]);
});

test("every subordinate's reference ships in the bundle", () => {
  const ids = new Set(stations.map((s) => s.id));
  assert.ok(subordinates.length > 1500, `only ${subordinates.length} subordinates`);
  assert.deepEqual(subordinates.filter((s) => !ids.has(s.reference)).map((s) => s.id), []);
});

test("no subordinate carries constituents, and every one carries all six offsets", () => {
  assert.deepEqual(subordinates.filter((s) => s.constituents?.length).map((s) => s.id), []);
  assert.deepEqual(
    subordinates.filter((s) => OFFSETS.some((k) => typeof s[k] !== "number")).map((s) => s.id), []);
});

test("every station carries both set directions", () => {
  assert.deepEqual(
    stations.filter((s) => !Number.isFinite(s.floodDirection) || !Number.isFinite(s.ebbDirection)).map((s) => s.id), []);
});
