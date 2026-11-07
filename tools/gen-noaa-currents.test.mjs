/**
 * Invariants for the generated Resources/currents.json — asserted on the
 * artefact, like gen-tides.test.mjs. Run after the generator: `npm test`.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { loadStations } from "@slackwater/database";
import { here, undangle, minorAxis, round3 } from "./bundle.mjs";

const db = await loadStations();

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
// The minor axis's keys, which only a harmonic record publishing cross-flow carries.
const MINOR = ["minorConstituents", "minorMeanFlow", "azimuth"];

test("every station carries its database record's fields, in the engine's units", () => {
  for (const s of stations) {
    const record = db.byId(s.id);
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
    // The minor axis: NOAA's cross-flow constants, on harmonic records that publish any.
    const minor = c.minor_constituents ?? [];
    if (!s.reference && (minor.length > 0 || (c.minor_mean_flow ?? 0) !== 0)) {
      assert.equal(s.minorConstituents.length, minor.length, `${s.id} minor constituent count`);
      for (const k of minor) {
        const shipped = s.minorConstituents.find((x) => x.name === k.name);
        assert.ok(shipped && near(shipped.amplitude, k.amplitude) && near(shipped.phase, k.phase),
          `${s.id} minor ${k.name}`);
      }
      assert.ok(near(s.minorMeanFlow, c.minor_mean_flow ?? 0), `${s.id} minor mean flow`);
      assert.ok(near(s.azimuth, c.azimuth), `${s.id} azimuth`);
    } else {
      assert.deepEqual(MINOR.filter((k) => k in s), [], `${s.id} carries minor-axis keys`);
    }
  }
});

test("the rotary stations ship their minor axis, Kodiak's among them", () => {
  const rotary = stations.filter((s) => s.minorConstituents);
  assert.ok(rotary.length > 850, `only ${rotary.length} stations carry a minor axis`);
  const kod = stations.find((s) => s.id === "noaa/KOD0901");
  assert.ok(kod?.minorConstituents?.length > 0, "noaa/KOD0901 carries no minor constituents");
  assert.equal(kod.azimuth, kod.floodDirection);
});

test("no subordinate carries a minor axis", () => {
  assert.deepEqual(subordinates.filter((s) => MINOR.some((k) => k in s)).map((s) => s.id), []);
});

// Review Focus 5: a cross-flow with no constituents of its own is still a minor axis.
// No NOAA record publishes one today, so the shaping is asserted on a synthetic record.
test("a minor mean flow with no minor constituents ships an empty list and the flow", () => {
  assert.deepEqual(minorAxis({ azimuth: 12.34567, minor_mean_flow: -0.20004 }),
    { minorConstituents: [], minorMeanFlow: -0.2, azimuth: 12.346 });
  assert.deepEqual(minorAxis({ azimuth: 12, minor_mean_flow: 0, minor_constituents: [] }), {});
  assert.deepEqual(minorAxis({ azimuth: 12 }), {});
  assert.deepEqual(
    minorAxis({ azimuth: 90, minor_constituents: [{ name: "M2", amplitude: 0.09200000017, phase: 266 }] }),
    { minorConstituents: [{ name: "M2", amplitude: 0.092, phase: 266 }], minorMeanFlow: 0, azimuth: 90 });
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
  assert.equal(referenceOnly.length, 16);
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

// With no context in the database, the region is borrowed from the nearest tide station.
test("every station is named and placed by its database record", () => {
  for (const s of stations) {
    const d = db.byId(s.id.split("@")[0]) ?? db.byId(s.id);
    assert.equal(s.name, d.name, s.id);
    assert.deepEqual(s.aliases, d.aliases ?? [], s.id);
    if (d.context) assert.equal(s.region, undangle(d.context), s.id);
  }
});

// currents.tcdb is what the app reads; this holds it to currents.json field
// by field from the tools lane too, so a generator change that drops or
// reshapes a station in one file and not the other fails here as well as in
// the Swift tests.
test("currents.tcdb holds the stations of currents.json", async () => {
  const tcdb = await loadStations(new Uint8Array(
    readFileSync(join(here, "..", "Slackwater", "Resources", "currents.tcdb"))));
  assert.deepEqual(tcdb.all.map((s) => s.id).sort(), stations.map((s) => s.id).sort());
  for (const s of stations) {
    const t = tcdb.byId(s.id);
    assert.equal(t.kind, "current", s.id);
    assert.equal(t.name, s.name, s.id);
    assert.equal(t.region, s.region, s.id);
    assert.equal(t.timezone, s.timezone, s.id);
    assert.equal(t.current.tide_reference, s.tideReference, s.id);
    assert.equal(t.current.offsets?.reference, s.reference, s.id);
    // Three places, as the generator writes them; float32 in the database.
    const r = (v) => (v === undefined ? undefined : round3(v));
    const cons = (list) => (list ?? []).map((c) => [c.name, r(c.amplitude), r(c.phase)]);
    assert.deepEqual(cons(t.harmonic_constituents), cons(s.constituents), s.id);
    assert.deepEqual(cons(t.current.minor_constituents), cons(s.minorConstituents), s.id);
    assert.equal(r(t.current.flood_direction), s.floodDirection, s.id);
    assert.equal(r(t.current.ebb_direction), s.ebbDirection, s.id);
    assert.equal(r(t.current.mean_flow), s.meanFlow, s.id);
    if (s.reference) {
      const o = t.current.offsets;
      assert.equal(o.slack_before_flood * 60, s.slackBeforeFloodOffset, s.id);
      assert.equal(o.slack_before_ebb * 60, s.slackBeforeEbbOffset, s.id);
      assert.equal(o.flood_time * 60, s.floodTimeOffset, s.id);
      assert.equal(o.ebb_time * 60, s.ebbTimeOffset, s.id);
      assert.equal(r(o.flood_speed_ratio), s.floodSpeedRatio, s.id);
      assert.equal(r(o.ebb_speed_ratio), s.ebbSpeedRatio, s.id);
    }
    // float32 in the database; the generator writes three places.
    assert.equal(t.current.minor_mean_flow === undefined ? undefined : round3(t.current.minor_mean_flow), s.minorMeanFlow, s.id);
  }
});
