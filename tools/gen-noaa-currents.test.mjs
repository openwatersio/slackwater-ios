/**
 * Invariants for the generated Resources/currents.json — asserted on the
 * artefact, like gen-tides.test.mjs. Run after the generator: `npm test`.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { stationsById } from "@slackwater/database";
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

test("Pollock Rip Channel ships NOAA's own axis, mean flow and M2", () => {
  const pollock = stations.find((s) => s.id === "noaa/ACT1616");
  assert.ok(pollock, "noaa/ACT1616 is not in the bundle");
  assert.deepEqual([pollock.floodDirection, pollock.ebbDirection, pollock.meanFlow], [37, 217, 0.15]);
  assert.deepEqual(pollock.constituents.find((k) => k.name === "M2"),
    { name: "M2", amplitude: 1.818, phase: 322.3 });
});

// The database stores float32; the bundle ships NOAA's three decimals.
const near = (a, b) => Math.abs(a - b) < 5e-4;

test("every station carries its database record's fields, in the engine's units", () => {
  for (const s of stations) {
    const record = stationsById.get(s.id);
    const c = record?.current;
    assert.ok(c, `${s.id} is not a current station in the database`);
    assert.ok(near(s.floodDirection, c.flood_direction), `${s.id} flood direction`);
    assert.ok(near(s.ebbDirection, c.ebb_direction), `${s.id} ebb direction`);
    assert.ok(near(s.meanFlow, c.mean_flow ?? 0), `${s.id} mean flow`);
    if (s.reference) {
      const o = c.offsets;
      assert.equal(s.reference, o.reference);
      // Minutes in the database; SlackwaterKit's SubordinateStation takes seconds.
      assert.deepEqual(OFFSETS.slice(0, 4).map((k) => s[k]),
        [o.slack_before_flood, o.slack_before_ebb, o.flood_time, o.ebb_time].map((m) => m * 60), s.id);
      assert.ok(near(s.floodSpeedRatio, o.flood_speed_ratio), `${s.id} flood ratio`);
      assert.ok(near(s.ebbSpeedRatio, o.ebb_speed_ratio), `${s.id} ebb ratio`);
    } else {
      const source = record.harmonic_constituents.filter((k) => k.amplitude > 0);
      assert.equal(s.constituents.length, source.length, `${s.id} constituent count`);
      for (const k of source) {
        const shipped = s.constituents.find((x) => x.name === k.name);
        assert.ok(shipped && near(shipped.amplitude, k.amplitude) && near(shipped.phase, k.phase),
          `${s.id} ${k.name}`);
      }
    }
  }
});

test("every subordinate's reference ships in the bundle", () => {
  const ids = new Set(stations.map((s) => s.id));
  assert.ok(subordinates.length > 1650, `only ${subordinates.length} subordinates`);
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

// Reference-only records (#269): a non-primary bin ships only because a
// subordinate reduces from it. It is a harmonic record with one flag, no
// station of its own, and never a slug.
const referenceOnly = stations.filter((s) => s.referenceOnly);

test("Eastport, Friar Roads ships as a subordinate of the Estes Head bin", () => {
  const friar = stations.find((s) => s.id === "noaa/ACT0091");
  assert.ok(friar, "noaa/ACT0091 is not in the bundle");
  assert.equal(friar.reference, "noaa/EPT0003@11");
  assert.ok(OFFSETS.every((k) => typeof friar[k] === "number"));
});

test("exactly the referenced bins ship, flagged, harmonic, and each one used", () => {
  assert.equal(referenceOnly.length, 13);
  const referenced = new Set(subordinates.map((s) => s.reference));
  for (const bin of referenceOnly) {
    assert.ok(bin.id.includes("@"), `${bin.id} is not a bin`);
    assert.equal(bin.referenceOnly, true);
    assert.ok(bin.constituents.length > 0, `${bin.id} has no constituents`);
    assert.equal(bin.reference, undefined);
    assert.ok(OFFSETS.every((k) => bin[k] === undefined), `${bin.id} carries offsets`);
    assert.ok(referenced.has(bin.id), `${bin.id} is referenced by nobody`);
  }
  assert.deepEqual(
    stations.filter((s) => s.id.includes("@") && !s.referenceOnly).map((s) => s.id), []);
});

test("a bin is named for its surface station", () => {
  const bin = stations.find((s) => s.id === "noaa/EPT0003@11");
  const surface = stations.find((s) => s.id === "noaa/EPT0003");
  assert.equal(bin.name, surface.name);
  assert.equal(bin.region, surface.region);
  assert.equal(bin.latitude, surface.latitude);
});
