/**
 * Invariants for the generated Resources/stations.json.
 *
 * These assert on the ARTEFACT, not on the generator's internals, because the
 * artefact is what ships and it is the only thing an Xcode build reads. Run
 * after the generator: `npm test`.
 *
 * node:test and node:assert are stdlib — this deliberately adds no dependency.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { allStations } from "@neaps/tide-database";
import { here, REGION_WORD } from "./bundle.mjs";
import { km } from "./geo.mjs";

const stations = JSON.parse(
  readFileSync(join(here, "..", "Slackwater", "Resources", "stations.json"), "utf8"));

// The one failure that is a legal problem rather than a quality one, checked
// independently of the generator that is supposed to prevent it.
test("no station without commercial-use rights ships", () => {
  const rights = new Map(allStations.map((s) => [s.id, s.license?.commercial_use]));
  const bad = stations.filter((s) => rights.get(s.id) !== true);
  assert.deepEqual(bad.map((s) => s.id), []);
});

// TICON rows yield to anything already kept; NOAA-vs-NOAA pairs are NOAA's
// call and were shipping before this filter existed.
test("no TICON station sits within the dedupe radius of another station", () => {
  const grid = new Map();
  const cell = (la, lo) => `${Math.round(la * 20)}:${Math.round(lo * 20)}`;
  const collisions = [];
  for (const s of stations) {
    for (let i = -2; i <= 2; i++) {
      for (let j = -2; j <= 2; j++) {
        for (const k of grid.get(cell(s.latitude + i / 20, s.longitude + j / 20)) ?? []) {
          if (km(s, k) < 1.0 && (s.id.startsWith("ticon/") || k.id.startsWith("ticon/"))) {
            collisions.push(`${s.name} / ${k.name}`);
          }
        }
      }
    }
    const k = cell(s.latitude, s.longitude);
    grid.set(k, [...(grid.get(k) ?? []), s]);
  }
  assert.deepEqual(collisions, []);
});

// untrail(): TICON repeats the state the region line already shows, as the
// code ("... Savannah Ga · GA") and as the word ("Brockville Ontario · ON").
test("no name ends in its own region", () => {
  const doubled = stations
    .filter((s) => new RegExp(
      `\\s(${s.region}${REGION_WORD[s.region] ? `|${REGION_WORD[s.region]}` : ""})$`, "i").test(s.name))
    .map((s) => `${s.name} · ${s.region}`);
  assert.deepEqual(doubled, []);
});

test("every station has a region line and a usable model", () => {
  for (const s of stations) {
    assert.ok(s.region, `${s.name} has no region`);
    assert.ok(s.constituents.length > 0, `${s.name} has no constituents`);
    assert.ok(s.constituents.every((c) => c.amplitude > 0), `${s.name} has a dead constituent`);
  }
});

// TICON fills gaps in Canadian water; it must never compete with CHS, whose
// datums are the adopted ones. Two Victorias is the failure this catches.
test("no bundled Canadian station duplicates a CHS station", () => {
  const chs = JSON.parse(readFileSync(
    join(here, "..", "Slackwater", "Resources", "chs-stations.json"), "utf8"));
  // The province code either IS the region line or ends it — "BC" and
  // "~Sidney, BC" are both Canadian. Matching only the bare code quietly
  // shrank this check to 25 stations the day nearest-town labels landed, which
  // is the wrong way for a duplicate-detector to fail. Read from the shipped
  // file rather than the generator's own bookkeeping, deliberately: that is
  // what makes this an independent check and not a restatement.
  const ca = stations.filter((s) =>
    /(^|,\s)(AB|BC|MB|NB|NL|NS|ON|PE|QC|SK|YT|NT|NU)$/.test(s.region));
  // NOAA rows are exempt: their datums are adopted, and Hyder was already
  // shipping when CHS gauges Stewart 1.3 km away.
  const contested = ca
    .filter((s) => s.id.startsWith("ticon/") && chs.some((c) => km(s, c) <= 10))
    .map((s) => s.name);
  assert.deepEqual(contested, []);
  assert.ok(ca.length > 30, `only ${ca.length} Canadian gap-fills`);
});

// COUNTRY_FIX: upstream reads NOAA's operating agency as the country.
test("stations NOAA runs abroad do not ship as US", () => {
  const foreign = stations.filter((s) =>
    ["Dakar", "Lagos", "Suva", "Easter Island", "Diego Garcia"].includes(s.name));
  assert.deepEqual(foreign, []);
});

// Task 1 (world coverage): a precondition guard for the datum-validation
// gate Task 2 adds to gen-tides.mjs, which will read MHW/MLW off the
// upstream row. Both 0.8.20260722 and 0.9.20260801 already publish these on
// every commercial-ok TICON row (verified directly against allStations on
// each version — 4,164/4,164, zero blind), so this test is green today. It
// exists so that if a future upstream release drops the fields, this fails
// loudly here instead of Task 2's gate silently passing everything.
test("every TICON row carries the datums the quality gate reads", () => {
  const ticon = allStations.filter(
    (s) => s.id.startsWith("ticon/") && s.license?.commercial_use === true);
  assert.ok(ticon.length > 4000, `only ${ticon.length} commercial-ok TICON rows`);
  const blind = ticon.filter(
    (s) => s.datums?.MHW === undefined || s.datums?.MLW === undefined);
  assert.deepEqual(blind.map((s) => s.id), []);
});
