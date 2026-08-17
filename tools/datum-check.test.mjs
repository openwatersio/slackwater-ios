/**
 * The datum gate, and the control that proves it measures what it claims.
 *
 * A quality gate that has never been run against known-good data is a coin
 * flip with a threshold on it. NOAA rows are public-domain and authoritative,
 * so they are the control: if the check reads more than a few centimetres on
 * those, the check is broken, not the data.
 *
 * The reduction is the whole trick — NOAA publishes datums against STATION
 * datum (STND = 0) and TICON against something near chart datum, so both
 * sides get `- datums[chart_datum]` applied before they are compared.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { allStations } from "@neaps/tide-database";
import { datumDeviation, passesDatumCheck, DATUM_TOLERANCE_M } from "./datum-check.mjs";

const checkable = (s) =>
  s.license?.commercial_use === true && s.type === "reference"
  && s.harmonic_constituents?.some((c) => c.amplitude > 0)
  && s.datums?.MHW !== undefined && s.datums?.MLW !== undefined;

const median = (a) => [...a].sort((x, y) => x - y)[Math.floor(a.length / 2)];

// THE CONTROL. NOAA is public-domain and authoritative; measured at 0.011 m
// median / 0.018 m max over 25 stations on 2026-08-16. A regression here means
// the reduction broke — most likely someone dropped the `- cd` on one side.
test("the check reads near-zero on known-good NOAA stations", () => {
  const noaa = allStations.filter((s) => s.id.startsWith("noaa/") && checkable(s)).slice(0, 25);
  assert.ok(noaa.length >= 20, `only ${noaa.length} checkable NOAA rows`);
  const devs = noaa.map((s) => datumDeviation(s));
  const nullRows = noaa.filter((s) => datumDeviation(s) === null);
  assert.deepEqual(nullRows.map((s) => s.id), []);
  assert.ok(median(devs) < 0.05, `NOAA control median ${median(devs).toFixed(3)} m — the check is broken, not the data`);
  const bad = noaa.filter((s) => datumDeviation(s) > 0.10);
  assert.deepEqual(bad.map((s) => s.id), []);
});

// A station with no published MHW/MLW cannot be judged, and an unjudgeable
// station is not a failing one — NOAA's own rows predate these fields upstream.
test("a station with no published MHW/MLW is uncheckable, not failing", () => {
  const fake = { chart_datum: "MLLW", datums: { MLLW: 0, MSL: 1 }, harmonic_constituents: [] };
  assert.equal(datumDeviation(fake), null);
  assert.equal(passesDatumCheck(fake), true);
});

// Southampton is the double-tide port the spec named as the UK risk, and it
// is one of exactly two UK stations that fail. If this starts passing, either
// upstream fixed the station or the tolerance was widened — find out which.
test("Southampton fails the gate and Aberdeen passes it", () => {
  const pick = (name) => allStations.find(
    (s) => s.name === name && s.country === "United Kingdom" && checkable(s));
  const soton = pick("Southampton");
  const aberdeen = pick("Aberdeen");
  assert.ok(soton && aberdeen, "the two calibration stations must both be in the database");
  assert.ok(datumDeviation(soton) > DATUM_TOLERANCE_M,
            `Southampton deviation ${datumDeviation(soton).toFixed(3)} m no longer exceeds the gate`);
  assert.ok(datumDeviation(aberdeen) <= DATUM_TOLERANCE_M,
            `Aberdeen deviation ${datumDeviation(aberdeen).toFixed(3)} m now exceeds the gate`);
});
