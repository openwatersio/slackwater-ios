# World Tide Stations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship tide stations worldwide — starting with the UK — behind a calibrated datum-validation gate that refuses to bundle a station whose predictions disagree with its own published datums.

**Architecture:** Two hardcoded allowlists in `tools/gen-tides.mjs` are what confine the app to North America, not the licence and not the engine. `COUNTRIES` is deleted outright; `NETWORKS` is inverted from an operator allowlist into a freshwater *denylist*, which admits 29 national hydrographic networks and still drops the 1,128 US river gauges it was written to exclude. A new `tools/datum-check.mjs` replaces the sovereignty gate with a quality one: predict a year from a station's own constituents, reduce both prediction and published `MHW`/`MLW` to chart datum, and reject any station that disagrees by more than the tolerance.

**Health warning (`CLAUDE.md`, "Plans and briefs are intent, not source"):** every Swift
block below is hand-written and **has never been compiled**. The Node blocks were run. Swift
API names were checked against the tree on 2026-08-16 (`RecentsStore` has `record(_:)`/`items`
and no `clear()`; `LocationService` publishes `location`, not `lastFix`; `distanceKm` takes
four `Double`s), but signatures still drift. **If a block looks wrong, check it and say so
rather than complying.**

**Tech Stack:** Node 24 ESM (`node:test`, `node:assert/strict`, no test dependencies), `@neaps/tide-database`, `@neaps/tide-predictor`, Swift 6 / SwiftUI / XCTest.

## Global Constraints

- **Licence gate is inviolable.** `license?.commercial_use === true`, re-asserted on output. From `chs-data-model.md` §3: "Unknown terms are worse than 'no' — silence is not permission."
- **Assert on the artefact, not the generator.** Every `tools/*.test.mjs` loads `Slackwater/Resources/*.json` and asserts on it, because the artefact is what an Xcode build reads.
- **CI regenerates and diffs.** `.github/workflows/ci.yml` runs `node gen-tides.mjs && node gen-noaa-currents.mjs` then `git diff --exit-code Slackwater/Resources/stations.json Slackwater/Resources/currents.json`. **Any generator edit must ship its regenerated artefact in the same commit.**
- **`gen-chs-stations.mjs` is not run by CI** (20-minute live DFO probe). Use `cd tools && node --test` to assert on committed artefacts; `npm test` regenerates everything including that probe.
- **No `86_400` for calendar days** (`CLAUDE.md`). Durations only.
- **Test style:** `final class XTests: XCTestCase`, `func testThing() throws`, `try XCTUnwrap(x, "message")`, `XCTAssertEqual(..., accuracy:)` for floats. No swift-testing.
- **Assertion idiom:** `assert.deepEqual(offenders.map((s) => s.id), [])` — never `assert.equal(count, 0)`. The failure message must name the offenders.
- **Prove every new assertion red** before believing it (`CLAUDE.md`, "A green suite is not a working feature").
- **Currents stay North America only.** Nothing in this plan may imply current coverage outside it.

---

### Task 1: Bump `@neaps/tide-database` to 0.9.20260801

The datum gate needs `datums.MHW`/`MLW`, and 0.8.20260722 is a version behind. `commitments.md` line 29 already carries this bump as open work: 0.9 keeps the licence invariant and adds 49 public-domain rows.

**Files:**
- Modify: `tools/package.json:9`
- Modify: `tools/package-lock.json` (regenerated)
- Modify: `Slackwater/Resources/stations.json` (regenerated artefact)
- Test: `tools/gen-tides.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: `allStations` rows carrying `datums.MHW`, `datums.MLW`, `datums.MHWS`, `datums.MLWS` for all 4,164 TICON rows. Task 2 depends on these fields existing.

- [ ] **Step 1: Write the failing test**

Append to `tools/gen-tides.test.mjs`:

```js
// Task 1 (world coverage): the datum gate reads MHW/MLW off the upstream row.
// 0.8.20260722 does not publish them on every TICON row; 0.9.20260801 does.
// If this fails after an upstream bump, the gate in gen-tides.mjs is running
// blind and silently passing everything.
test("every TICON row carries the datums the quality gate reads", () => {
  const ticon = allStations.filter(
    (s) => s.id.startsWith("ticon/") && s.license?.commercial_use === true);
  assert.ok(ticon.length > 4000, `only ${ticon.length} commercial-ok TICON rows`);
  const blind = ticon.filter(
    (s) => s.datums?.MHW === undefined || s.datums?.MLW === undefined);
  assert.deepEqual(blind.map((s) => s.id), []);
});
```

- [ ] **Step 2: Run it to verify it fails**

```sh
cd tools && node --test gen-tides.test.mjs
```

Expected: FAIL — on 0.8.20260722 the `blind` array is non-empty.

- [ ] **Step 3: Bump the dependency**

In `tools/package.json`, change the `devDependencies` entry:

```json
    "@neaps/tide-database": "^0.9.20260801",
```

Then:

```sh
cd tools && npm install
```

- [ ] **Step 4: Regenerate and verify the test passes**

```sh
cd tools && node gen-tides.mjs && node gen-noaa-currents.mjs && node --test
```

Expected: PASS. `gen-tides.mjs` prints a station count ~1,478 (up from 1,429 — the 49 added public-domain rows). If it prints fewer than 1,429, stop: the bump lost rows and that is not what the commitment predicted.

- [ ] **Step 5: Commit**

```sh
git add tools/package.json tools/package-lock.json tools/gen-tides.test.mjs \
        Slackwater/Resources/stations.json Slackwater/Resources/currents.json
git commit -m "data: bump @neaps/tide-database to 0.9.20260801

Adds 49 public-domain rows and publishes MHW/MLW on every TICON row, which
the datum-validation gate reads. Licence invariant unchanged."
```

---

### Task 2: The datum-validation check, calibrated against NOAA

A station's predictions must agree with the datums its own authority publishes. This is the honest version of "coverage stops where we can still tell when the numbers are wrong."

**The one trap, which cost a full investigation cycle:** `datums` are published relative to *different references by source*. NOAA rows are relative to **station datum** (`STND: 0`), so Ford Island reads `MHW: 7.532` with an `MLLW` of `7.078`. TICON rows are relative to something near chart datum (Southampton's `LAT` is `0.066`). **Both sides of the comparison must be reduced to chart datum by subtracting `datums[chart_datum]`**, or NOAA stations appear to be 7 m wrong and UK stations only look right by the accident of `LAT ≈ 0`.

Calibration run on 2026-08-16 with the reduction correct — this is what makes the tolerance defensible, not a guess:

| Group | n | median | p90 | max | ≤0.30 m |
|---|---|---|---|---|---|
| NOAA control (public domain, trusted) | 25 | **0.011 m** | 0.017 | 0.018 | 100% |
| UK home waters (TICON) | 68 | 0.026 m | 0.085 | 0.591 | **97%** |
| Europe non-UK (TICON) | 40 | 0.017 m | 0.127 | 1.313 | 98% |

The NOAA control reading 1 cm on data we already trust is what proves the check measures what it claims. UK failures at 0.30 m are exactly two: **Penarth (0.59 m)** and **Southampton (0.53 m)** — the double-tide port the spec named as the risk.

**Files:**
- Create: `tools/datum-check.mjs`
- Create: `tools/datum-check.test.mjs`
- Modify: `tools/package.json` (add `@neaps/tide-predictor` devDependency)

**Interfaces:**
- Consumes: `allStations` rows with `datums.MHW`/`MLW` (Task 1).
- Produces:
  - `export const DATUM_TOLERANCE_M = 0.30`
  - `export function datumDeviation(station): number | null` — metres; `null` when the station publishes no `MHW`/`MLW` and cannot be checked.
  - `export function passesDatumCheck(station): boolean` — `true` when deviation is `null` (uncheckable) or `<= DATUM_TOLERANCE_M`.

  Task 3 imports all three.

- [ ] **Step 1: Add the predictor dependency**

In `tools/package.json` `devDependencies`, add:

```json
    "@neaps/tide-predictor": "^0.10.0",
```

```sh
cd tools && npm install
```

- [ ] **Step 2: Write the failing test**

Create `tools/datum-check.test.mjs`:

```js
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
  assert.ok(devs.every((d) => d !== null), "a checkable NOAA row returned null");
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
```

- [ ] **Step 3: Run it to verify it fails**

```sh
cd tools && node --test datum-check.test.mjs
```

Expected: FAIL with `Cannot find module './datum-check.mjs'`.

- [ ] **Step 4: Write the implementation**

Create `tools/datum-check.mjs`:

```js
/**
 * Does a station's own model agree with the datums its authority publishes?
 *
 * Predict a year of extremes from the station's constituents, take the mean
 * high and mean low, and compare to published MHW/MLW. Both sides are reduced
 * to CHART DATUM first, which is the step that makes the comparison mean
 * anything: NOAA publishes its datums against station datum (STND = 0, so
 * Ford Island's MHW is 7.532 with an MLLW of 7.078), TICON against something
 * near chart datum (Southampton's LAT is 0.066). Skip the reduction and NOAA
 * looks 7 m wrong while UK rows look right by the accident of LAT being ~0.
 *
 * Calibrated 2026-08-16 — NOAA control 0.011 m median / 0.018 m max over 25
 * stations, which is what licenses the tolerance below. Full numbers in
 * docs/validation/world-tide-stations.md.
 *
 * ponytail: one year of extremes per station, no caching. It is ~2 minutes for
 * the whole world bundle and it runs at build time. Cache it when a human is
 * waiting on it.
 */
import { createTidePredictor } from "@neaps/tide-predictor";

/**
 * 0.30 m. Set from the measured distribution, not from taste: it clears 97% of
 * UK home waters and 98% of non-UK Europe while still failing Southampton
 * (0.53) and Penarth (0.59). The NOAA control sits two orders of magnitude
 * below it. Tighten to 0.15 m and 7% of good European stations go with it.
 */
export const DATUM_TOLERANCE_M = 0.30;

const YEAR_START = new Date("2026-01-01T00:00:00Z");
const YEAR_END = new Date("2027-01-01T00:00:00Z");

const mean = (a) => a.reduce((x, y) => x + y, 0) / a.length;

/**
 * Metres of disagreement between predicted and published mean high/low water,
 * whichever is worse. `null` when the station publishes nothing to check
 * against — an unjudgeable station is not a failing one.
 */
export function datumDeviation(station) {
  const d = station.datums;
  const cd = d?.[station.chart_datum];
  if (cd === undefined || d?.MSL === undefined) return null;
  if (d?.MHW === undefined || d?.MLW === undefined) return null;

  const constituents = (station.harmonic_constituents ?? [])
    .filter((c) => c.amplitude > 0)
    .map((c) => ({ name: c.name, amplitude: c.amplitude, phase: c.phase }));
  if (constituents.length === 0) return null;

  const z0 = d.MSL - cd;                       // MSL above chart datum
  const extremes = createTidePredictor(constituents)
    .getExtremesPrediction({ start: YEAR_START, end: YEAR_END });
  const highs = extremes.filter((e) => e.high).map((e) => e.level + z0);
  const lows = extremes.filter((e) => e.low).map((e) => e.level + z0);
  if (highs.length === 0 || lows.length === 0) return null;

  return Math.max(Math.abs(mean(highs) - (d.MHW - cd)),
                  Math.abs(mean(lows) - (d.MLW - cd)));
}

export function passesDatumCheck(station) {
  const deviation = datumDeviation(station);
  return deviation === null || deviation <= DATUM_TOLERANCE_M;
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```sh
cd tools && node --test datum-check.test.mjs
```

Expected: PASS, 3/3.

- [ ] **Step 6: Prove the control red**

Temporarily change `(d.MHW - cd)` to `d.MHW` in `datumDeviation`, re-run, and confirm the NOAA control test fails with a median around 0.9 m. Restore it. This is the assertion that matters most in the file; it must be shown to bite.

- [ ] **Step 7: Commit**

```sh
git add tools/datum-check.mjs tools/datum-check.test.mjs tools/package.json tools/package-lock.json
git commit -m "data: datum-validation check, calibrated against NOAA

Predict a year, compare mean high/low to published MHW/MLW, both reduced to
chart datum. NOAA control reads 0.011 m median over 25 known-good stations,
which is what licenses the 0.30 m tolerance. Catches Southampton (0.53) and
Penarth (0.59)."
```

---

### Task 3: Delete `COUNTRIES`, invert `NETWORKS`, apply the gate

The sovereignty allowlist goes; the quality gate takes its place. `NETWORKS` inverts from an operator allowlist to a freshwater denylist — its own `ponytail:` comment already says the honest filter is "is there navigable water here", and the denylist is that filter's closest cheap proxy.

Measured 2026-08-16 on the eligible pool of 5,416: the current allowlist keeps 3,146; the denylist keeps 4,288. It drops exactly the 1,128 freshwater rows the generator documents (`usgs` 591, `crms` 328, `cdwr` 131, `ncdem` 26, `sfwmd` 43, `nwfwmd` 9) and admits 1,142 across 29 national networks — German `wsv` 142, Australian `bom` 125, Dutch `rws`+`rws_hist` 179, French `refmar` 106, Japanese `jodc_*` 207, UK `bodc` 41 + `cco` 16 + `noc` 5.

**Files:**
- Modify: `tools/gen-tides.mjs:78-82` (delete `COUNTRIES`), `:163-171` (invert `NETWORKS`), `:293-300` (the filter chain), `:352` (the count guard)
- Modify: `Slackwater/Resources/stations.json` (regenerated)
- Test: `tools/gen-tides.test.mjs`

**Interfaces:**
- Consumes: `passesDatumCheck`, `DATUM_TOLERANCE_M` from `./datum-check.mjs` (Task 2).
- Produces: a `stations.json` of ~3,800 stations including UK home waters. Task 4 asserts on its region lines.

- [ ] **Step 1: Write the failing tests**

Append to `tools/gen-tides.test.mjs`:

```js
// Task 3 (world coverage). The two gates that confined the app to North
// America were an allowlist of seven sovereignty strings and an allowlist of
// eight operator codes — neither about licence, and the second written only to
// keep US river gauges out.
test("the bundle reaches beyond North America", () => {
  const countries = new Set(stations.map((s) => s.country));
  for (const expected of ["United Kingdom", "France", "Germany", "Netherlands"]) {
    assert.ok(countries.has(expected), `${expected} is missing from the bundle`);
  }
});

// Bryan opened the app in the Solent and Near Me ranked stations 4,700 nm
// away. These four are the acceptance test for that.
test("the Solent is in the bundle", () => {
  const want = ["Portsmouth", "Southampton", "Lymington", "Bournemouth"];
  const solent = stations.filter(
    (s) => want.includes(s.name) && s.latitude > 50 && s.latitude < 51
           && s.longitude > -2.5 && s.longitude < -0.5);
  assert.deepEqual(solent.map((s) => s.name).sort(), want.sort());
});

// Freshwater instrumentation is still the thing being excluded — 328 Louisiana
// marsh platforms named after the nearest town is nine "Abbeville · LA" rows on
// nine bayou platforms nobody can moor at.
test("no freshwater-network station ships", () => {
  const network = new Map(allStations.map((s) => [s.id, networkOf(s)]));
  const fresh = stations.filter((s) => FRESHWATER_NETWORKS.has(network.get(s.id)));
  assert.deepEqual(fresh.map((s) => s.id), []);
});

// The gate is only worth having if it actually removed something. Southampton
// is a double high water port whose model disagrees with its own published
// datums by 0.53 m; it must not be in the bundle at any range.
test("stations that fail the datum gate are not bundled", () => {
  const bundled = new Set(stations.map((s) => s.id));
  const rejected = allStations.filter(
    (s) => s.license?.commercial_use === true && !passesDatumCheck(s) && bundled.has(s.id));
  assert.deepEqual(rejected.map((s) => s.id), []);
  const soton = allStations.find(
    (s) => s.name === "Southampton" && s.country === "United Kingdom");
  assert.ok(!bundled.has(soton.id), "Southampton failed the gate but shipped anyway");
});
```

Add to that file's import block:

```js
import { passesDatumCheck } from "./datum-check.mjs";
import { FRESHWATER_NETWORKS, networkOf } from "./gen-tides.mjs";
```

- [ ] **Step 2: Run to verify they fail**

```sh
cd tools && node --test gen-tides.test.mjs
```

Expected: FAIL — `FRESHWATER_NETWORKS` and `networkOf` are not exported, and no UK station is in the bundle.

- [ ] **Step 3: Make the generator changes**

In `tools/gen-tides.mjs`, delete the `COUNTRIES` set (lines 78-82) entirely. Replace the `NETWORKS` set and `networkOf` (lines 163-171) with:

```js
/**
 * INVERTED at world coverage. This was an allowlist of eight operator codes,
 * which was the right shape while the bundle was one continent and the only
 * thing to exclude was US freshwater instrumentation. Worldwide it excluded 29
 * national hydrographic networks — BODC, REFMAR, RWS, WSV, JODC, BoM — for no
 * reason anyone had stated.
 *
 * So it is a denylist now, and it names exactly what the allowlist was written
 * to keep out: river and marsh gauges upstream of anywhere with water under a
 * keel. Measured — it drops the same 1,128 rows the allowlist did and admits
 * 1,142 across 29 networks.
 *
 * ponytail: still a proxy. The honest filter is "is there navigable water
 * here", which no field in this database answers, and this is the cheapest
 * thing that behaves like it.
 */
export const FRESHWATER_NETWORKS = new Set([
  "crms",    // 328  Louisiana marsh platforms, each named for the nearest town
  "usgs",    // 591  river and creek stage gauges
  "cdwr",    // 131  California Delta
  "sfwmd",   //  43  Florida canals
  "nwfwmd",  //   9  Florida canals
  "ncdem",   //  26  North Carolina emergency-management gauges
]);

export const networkOf = (s) =>
  s.source?.name === NOAA ? "coops" : (s.id.split("-").pop() ?? "");
```

Replace the filter chain (lines 293-300) with:

```js
let dropped = 0;
let failedDatum = 0;
const stations = shippable
  .filter((s) => !FRESHWATER_NETWORKS.has(networkOf(s)))
  .filter((s) => (servedByChs(s) ? (cededToChs++, false) : true))
  .filter((s) => s.type === "reference")
  .filter((s) => s.harmonic_constituents?.some((c) => c.amplitude > 0))
  .filter((s) => (passesDatumCheck(s) ? true : (failedDatum++, false)))
  .sort((a, b) =>
```

Add the import at the top of the file, beside the existing `./bundle.mjs` import:

```js
import { passesDatumCheck, DATUM_TOLERANCE_M } from "./datum-check.mjs";
```

Change the count guard at line 352 — the old floor was a North-America number:

```js
if (stations.length < 3000) {
  throw new Error(`only ${stations.length} stations survived the filters — refusing to ship`);
}
```

And extend the summary line at the end of the file so the drop is visible rather than silent:

```js
console.log(`${stations.length} reference tide stations, ${mb} MB (${contexts}; `
  + `${canadianGapFills} Canadian gap-fills, ${cededToChs} ceded to CHS; `
  + `${dropped} duplicates dropped; ${failedDatum} failed the ${DATUM_TOLERANCE_M} m datum check)`);
```

- [ ] **Step 4: Regenerate and run the tests**

```sh
cd tools && node gen-tides.mjs && node gen-noaa-currents.mjs && node --test
```

Expected: PASS. The generator prints roughly `3800 reference tide stations, ~10 MB (…; N failed the 0.3 m datum check)`. If `failedDatum` is 0, the gate is not wired in — check the import.

- [ ] **Step 5: Verify the Solent by hand**

```sh
cd tools && node -e "
const s=require('fs').readFileSync('../Slackwater/Resources/stations.json','utf8');
const a=JSON.parse(s).filter(x=>x.latitude>50&&x.latitude<51&&x.longitude>-2.5&&x.longitude<-0.5);
console.log(a.map(x=>x.name+' · '+x.region+' · '+x.timezone).join('\n'));"
```

Expected: Portsmouth, Lymington, Bournemouth and neighbours, each `Europe/London`. **Southampton must be absent** — it failed the gate.

- [ ] **Step 6: Commit**

```sh
git add tools/gen-tides.mjs tools/gen-tides.test.mjs Slackwater/Resources/stations.json Slackwater/Resources/currents.json
git commit -m "data: world tide coverage behind the datum gate

Delete the COUNTRIES sovereignty allowlist; invert NETWORKS into a freshwater
denylist, which admits 29 national hydrographic networks and still drops the
same 1,128 river gauges. Quality replaces geography as the gate: a station
ships when its own model agrees with its own published datums."
```

---

### Task 4: Region lines for the world

`bundle.mjs`'s resolver has a fourth tier of "nearest place from the bundled gazetteer", and that gazetteer holds 9,660 US and Canadian towns. Worldwide it produces "Portsmouth · ~Portsmouth Heights, VA". The generator already throws when a station has no region line; this makes sure the line is not actively wrong.

`COUNTRY_FIX`'s 17 rows stay, but their job changes: with `COUNTRIES` gone they no longer decide what ships, only how it is labelled. That is why they were written as corrections rather than a deny-list — the spec's §4 note that they "do not scale" is now moot, because there is nothing left for them to gate.

**Files:**
- Modify: `tools/gen-tides.mjs` (the context resolution block, ~line 300)
- Test: `tools/gen-tides.test.mjs`

**Interfaces:**
- Consumes: `stations.json` from Task 3.
- Produces: no new exports. Task 5 is independent of this.

- [ ] **Step 1: Write the failing test**

Append to `tools/gen-tides.test.mjs`:

```js
// The gazetteer is 9,660 US and Canadian towns. Nationally its fourth tier
// produced "San Francisco · near Olympia, WA"; worldwide it would put a
// Virginia suburb under an English harbour.
test("no station outside North America borrows a US or Canadian place name", () => {
  const overseas = stations.filter(
    (s) => !["United States", "Canada"].includes(s.country));
  const borrowed = overseas.filter((s) => /~|, [A-Z]{2}$/.test(s.region ?? ""));
  assert.deepEqual(borrowed.map((s) => `${s.name} · ${s.region}`), []);
});
```

- [ ] **Step 2: Run to verify it fails**

```sh
cd tools && node --test gen-tides.test.mjs
```

Expected: FAIL, listing UK and European stations carrying `~Somewhere, VA`-shaped regions.

- [ ] **Step 3: Restrict the gazetteer tier to where the gazetteer applies**

In `tools/gen-tides.mjs`, where the resolved context is assigned, guard the derived tier by country:

```js
// The gazetteer is North American, so its "nearest town" tier is too. Anywhere
// else the upstream region field ("England", "Scotland", "Bretagne") is both
// correct and the presentation the authority itself uses.
const NORTH_AMERICA = new Set(["United States", "Canada", "Puerto Rico",
  "Virgin Islands", "Guam", "Northern Mariana Islands", "American Samoa"]);

const contextFor = (s, resolved) =>
  NORTH_AMERICA.has(countryOf(s)) ? resolved : (s.region || countryOf(s));
```

and route the region assignment through `contextFor`.

- [ ] **Step 4: Regenerate and verify**

```sh
cd tools && node gen-tides.mjs && node --test
```

Expected: PASS. Spot-check that US stations still read "Boston, MA" and UK ones read "England".

- [ ] **Step 5: Commit**

```sh
git add tools/gen-tides.mjs tools/gen-tides.test.mjs Slackwater/Resources/stations.json
git commit -m "data: region lines outside North America use the upstream field

The bundled gazetteer is 9,660 US and Canadian towns; its nearest-town tier
put a Virginia suburb under an English harbour."
```

---

### Task 4b: Dedup across overlapping national publishers

`DUPLICATE_KM = 1.0` was written for two publishers (NOAA and TICON) plus the CHS cede rule. The UK has **four** overlapping ones. Measured in the raw database: 12 duplicate station *names* among the 89 commercial-ok UK rows — `Ascension` ×3 (`uhslc_fd`, `uhslc_rq`, `noc`), `Bermuda` ×3, `Gibraltar` ×3, `Diego Garcia` ×3, `Lerwick` ×3 (`uhslc_fd`, `uhslc_rq`, `bodc`), `Devonport` ×2 (`bodc`, `da_idh`).

The 1 km proximity rule collapses the co-located ones. It does **not** collapse two gauges on the same harbour a few km apart, and three pins on one anchorage is a worse map than one.

**Files:**
- Modify: `tools/gen-tides.mjs` (the dedupe block, ~line 262)
- Test: `tools/gen-tides.test.mjs`

**Interfaces:**
- Consumes: `stations.json` from Task 4.
- Produces: no new exports.

- [ ] **Step 1: Write the failing test**

Append to `tools/gen-tides.test.mjs`:

```js
// Four UK publishers cover the same harbours — bodc, cco, noc and da_idh, plus
// two UHSLC feeds. The 1 km rule collapses co-located gauges; two gauges on one
// harbour a few km apart survive it and put three pins on one anchorage.
test("no two bundled stations share a name within sight of each other", () => {
  const byName = new Map();
  for (const s of stations) {
    const key = s.name.toLowerCase();
    byName.set(key, [...(byName.get(key) ?? []), s]);
  }
  const collisions = [];
  for (const [, group] of byName) {
    for (let i = 0; i < group.length; i++) {
      for (let j = i + 1; j < group.length; j++) {
        if (km(group[i], group[j]) < SAME_PLACE_KM) {
          collisions.push(`${group[i].name} (${group[i].id} / ${group[j].id})`);
        }
      }
    }
  }
  assert.deepEqual(collisions, []);
});
```

Import `SAME_PLACE_KM` alongside the other generator exports in that file's import block.

- [ ] **Step 2: Run to verify it fails**

```sh
cd tools && node --test gen-tides.test.mjs
```

Expected: FAIL — `SAME_PLACE_KM` is not exported, then once exported, a list of same-name pairs.

- [ ] **Step 3: Widen the rule for same-name pairs only**

In `tools/gen-tides.mjs`, beside `DUPLICATE_KM`:

```js
/**
 * Two rules, because they answer different questions.
 *
 * DUPLICATE_KM (1 km) asks "is this the same gauge, published twice" and is
 * name-blind — two genuinely different stations can sit 800 m apart in a busy
 * harbour and both deserve a pin.
 *
 * SAME_PLACE_KM (10 km) asks "is this the same PLACE, gauged twice" and only
 * applies when the names already match. Four UK publishers cover the same
 * harbours (bodc, cco, noc, da_idh) and upstream names them all after the
 * harbour, so "Lerwick" arrives three times from three networks. Ten km is the
 * CHS_COVERAGE_KM radius, and for the same reason: it asks whether this water
 * is already served, not whether this is the same instrument.
 */
const SAME_PLACE_KM = 10.0;
export { SAME_PLACE_KM };
```

Extend the existing dedupe predicate so a candidate is dropped when an already-kept station either sits within `DUPLICATE_KM`, or shares its name within `SAME_PLACE_KM`. Keep the existing precedence — NOAA over TICON, first-kept wins — so the survivor is deterministic.

- [ ] **Step 4: Regenerate and verify**

```sh
cd tools && node gen-tides.mjs && node --test
```

Expected: PASS. The generator's `duplicates dropped` count rises. Read the diff on `stations.json` before assuming it is noise — `CLAUDE.md` is explicit that a regenerated bundle's surprises are often real stations.

- [ ] **Step 5: Commit**

```sh
git add tools/gen-tides.mjs tools/gen-tides.test.mjs Slackwater/Resources/stations.json
git commit -m "data: collapse same-name stations from overlapping publishers

The UK has four national publishers covering the same harbours, so Lerwick
arrived three times from three networks. 1 km asks 'same gauge'; 10 km with a
matching name asks 'same place'."
```

---

### Task 5: De-Victoria the app's defaults

Three constants assume the user is in the Salish Sea. In the UK they produce a map framed on Vancouver Island and a Near Me list anchored 4,700 nm away.

**Files:**
- Modify: `Slackwater/LocationService.swift:10`
- Modify: `Slackwater/TideStation.swift:26` and the `all` initialiser below it
- Modify: `Slackwater/MapScreen.swift:13-14` (usage, not the constant)
- Test: `SlackwaterTests/WorldDefaultsTests.swift` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `RecentsStore.lastOpened: StationItem?` — new derived property. `RecentsStore` (Theme.swift:777) today exposes `@Published private(set) var ids: [String]`, `func record(_ id: String)`, `func remove(_ id: String)` and `var items: [StationItem]`. There is **no** `clear()`; tests seed by calling `record(_:)`.
  - `LocationService.rankingAnchor: (lat: Double, lon: Double)?` — reads the existing `@Published var location: CLLocation?` (LocationService.swift:16). **There is no `lastFix`.**

- [ ] **Step 1: Write the failing test**

Create `SlackwaterTests/WorldDefaultsTests.swift`:

```swift
// Slackwater — GPL v3.
// World coverage: the app must not assume the user is in the Salish Sea.
// Bryan opened it in the Solent and got a Vancouver Island camera and a Near
// Me list ranked from Victoria Harbour.

import XCTest
@testable import Slackwater

final class WorldDefaultsTests: XCTestCase {

    /// Friday Harbor was pinned to the head of the station list. That is a
    /// home-water courtesy that reads as a bug from anywhere else.
    func testStationListIsNotPinnedToOneStation() throws {
        let all = TideStationRecord.all
        XCTAssertGreaterThan(all.count, 3000, "world bundle expected")
        XCTAssertNotEqual(all.first?.id, "noaa/9449880",
                          "Friday Harbor must no longer be pinned to the head of the list")
    }

    /// The no-fix fallback must come from what the user last opened, and only
    /// fall back to a fixed coordinate on a genuinely first run.
    func testFallbackAnchorPrefersTheLastOpenedStation() throws {
        // RecentsStore has no clear() — seed it by recording, and read back
        // through `items`, which is the accessor the app already uses.
        let pompey = try XCTUnwrap(TideStationRecord.all.first {
            $0.name == "Portsmouth" && $0.latitude > 50 && $0.longitude < 0 })
        RecentsStore.shared.record(pompey.id)

        let last = try XCTUnwrap(RecentsStore.shared.lastOpened,
                                 "lastOpened must follow the most recent record()")
        XCTAssertEqual(last.id, pompey.id)

        // LocationService.location is nil in a test process, so the anchor
        // falls through to the last-opened station rather than to Victoria.
        let anchor = try XCTUnwrap(LocationService.shared.rankingAnchor)
        XCTAssertEqual(anchor.lat, pompey.latitude, accuracy: 0.001,
                       "with no fix, the ranking anchor must follow the last opened station")
        XCTAssertNotEqual(anchor.lat, firstRunFix.lat, accuracy: 0.001,
                          "Victoria Harbour is the first-run value only")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```sh
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```

Expected: compile failure — `rankingAnchor` and `RecentsStore.lastOpened` do not exist.

- [ ] **Step 3: Implement**

In `Slackwater/Theme.swift`, add to `RecentsStore` (beside `var items`):

```swift
    /// The most recently opened station, which is the best guess at where the
    /// user is when Core Location has told us nothing.
    var lastOpened: StationItem? { items.first }
```

In `Slackwater/LocationService.swift`, rename `fallbackFix` and add the anchor. The published property is `location: CLLocation?` (line 16) — there is no `lastFix`:

```swift
/// Victoria Harbour — the last-resort ranking anchor, used only on a first run
/// with no fix and nothing opened yet. Everywhere else the anchor follows the
/// user: a real fix first, then the station they last opened. Before world
/// coverage this was `fallbackFix` and it was the ONLY fallback, which is why
/// the app opened in the Solent and ranked from Vancouver Island.
let firstRunFix = (lat: 48.4235, lon: -123.3705)

extension LocationService {
    /// What Near Me ranks distances from.
    @MainActor var rankingAnchor: (lat: Double, lon: Double)? {
        if let fix = location { return (fix.coordinate.latitude, fix.coordinate.longitude) }
        if let last = RecentsStore.shared.lastOpened { return (last.latitude, last.longitude) }
        return firstRunFix
    }
}
```

`ChsFitService.init()` reads `fallbackFix` at ChsFitService.swift:194 — update that call site to `firstRunFix` in the same edit or the build breaks.

In `Slackwater/TideStation.swift`, delete `fridayHarborID` and the pin in `all`, leaving the sort alphabetical.

In `Slackwater/MapScreen.swift`, use the anchor for the opening camera rather than `SALISH_CENTER`, keeping `SALISH_CENTER` only as the first-run value.

- [ ] **Step 4: Run the tests**

```sh
./scripts/test.sh
```

Expected: PASS on both simulators. `NationalScaleTests` and `TimelineTests` must stay green — if `testFallbackStyleCarriesTheChartPastTheSalishBox` fails, that is Plan B's territory and this task went too far.

- [ ] **Step 5: Commit**

```sh
git add Slackwater/LocationService.swift Slackwater/TideStation.swift \
        Slackwater/MapScreen.swift SlackwaterTests/WorldDefaultsTests.swift
git commit -m "app: ranking anchor and station list stop assuming the Salish Sea"
```

---

### Task 6: Say plainly that currents are North America only

The app's wedge is currents. Worldwide it has none outside North America, and the honest thing is to say so rather than let an empty list imply the water is slack. The copy in `OfflineDownloads.swift` and `ChsDetailView.swift` also says "Canadian" in five places where it now means "Canadian".

**Files:**
- Modify: `Slackwater/CardStatus.swift` (add a case)
- Modify: `Slackwater/SlackwaterApp.swift` (the Near Me currents section)
- Test: `SlackwaterTests/WorldDefaultsTests.swift` (extend)

**Interfaces:**
- Consumes: `CardStatus` from `CardStatus.swift:14`.
- Produces: `CardStatus.noCurrentCoverage`, rendered by the existing `CardStatusStrip`.

- [ ] **Step 1: Write the failing test**

Append to `SlackwaterTests/WorldDefaultsTests.swift`:

```swift
    /// An empty currents list outside North America must read as "we do not
    /// have this here", never as "the water is slack".
    func testCurrentsAbsenceIsStatedNotImplied() throws {
        let status = currentCoverage(latitude: 50.80, longitude: -1.11)   // Portsmouth
        XCTAssertEqual(status, .noCurrentCoverage)
        XCTAssertTrue(status.label.lowercased().contains("not available"),
                      "the label must say so in words, got \(status.label)")

        let salish = currentCoverage(latitude: 48.42, longitude: -123.37)  // Victoria
        XCTAssertNotEqual(salish, .noCurrentCoverage)
    }
```

- [ ] **Step 2: Run to verify it fails**

```sh
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```

Expected: compile failure — `currentCoverage` and `.noCurrentCoverage` do not exist.

- [ ] **Step 3: Implement**

In `Slackwater/CardStatus.swift`, add to `enum CardStatus`:

```swift
    /// Tides ship worldwide; currents are NOAA and CHS only. Outside their
    /// coverage the absence is stated, because an empty list where a mariner
    /// expects a current reads as slack water.
    case noCurrentCoverage
```

and in the `label` / `icon` / `tint` switches:

```swift
        case .noCurrentCoverage: return "Current predictions not available here"
```

Add the coverage predicate beside it:

```swift
/// The bundled current stations are NOAA (US) and CHS (Canada). This is a
/// coverage question about the DATA, not about the boat's position, so it asks
/// the bundle rather than a hardcoded box.
@MainActor func currentCoverage(latitude: Double, longitude: Double) -> CardStatus {
    let nearest = CurrentStationRecord.all.min {
        distanceKm($0.latitude, $0.longitude, latitude, longitude)
            < distanceKm($1.latitude, $1.longitude, latitude, longitude)
    }
    guard let nearest,
          distanceKm(nearest.latitude, nearest.longitude, latitude, longitude) < 300
    else { return .noCurrentCoverage }
    return .offline
}
```

Render it in the Near Me currents section of `SlackwaterApp.swift` with the existing `CardStatusStrip(status:)`.

- [ ] **Step 4: Run the tests**

```sh
./scripts/test.sh
```

Expected: PASS. Then open the screenshots — `SHOT_DIR=/tmp/shots ./scripts/test.sh` and look at the Near Me list. `CLAUDE.md`: for anything visual, open the screenshot.

- [ ] **Step 5: Commit**

```sh
git add Slackwater/CardStatus.swift Slackwater/SlackwaterApp.swift SlackwaterTests/WorldDefaultsTests.swift
git commit -m "app: state that currents are North America only

An empty currents list where a mariner expects a current reads as slack water."
```

---

### Task 7: Write the validation report

The repo's template for this is `spikes/chs-currents-fit/README.md` — method, then **the bar stated before the results**, then the table.

**Files:**
- Create: `docs/validation/world-tide-stations.md`

**Interfaces:** none.

- [ ] **Step 1: Regenerate the numbers**

```sh
cd tools && node -e "
import('./datum-check.mjs').then(async ({datumDeviation, DATUM_TOLERANCE_M}) => {
  const {allStations} = await import('@neaps/tide-database');
  const ok = s => s.license?.commercial_use===true && s.type==='reference'
                  && s.harmonic_constituents?.some(c=>c.amplitude>0);
  const groups = {
    'NOAA control': allStations.filter(s=>ok(s)&&s.id.startsWith('noaa/')).slice(0,25),
    'UK home waters': allStations.filter(s=>ok(s)&&s.country==='United Kingdom'&&s.latitude>49&&s.latitude<61),
  };
  for (const [k,v] of Object.entries(groups)) {
    const d=v.map(datumDeviation).filter(x=>x!==null).sort((a,b)=>a-b);
    console.log(k, 'n='+d.length, 'median='+d[d.length>>1].toFixed(3),
                'p90='+d[Math.floor(d.length*0.9)].toFixed(3), 'max='+d[d.length-1].toFixed(3),
                'pass='+(100*d.filter(x=>x<=DATUM_TOLERANCE_M).length/d.length).toFixed(0)+'%');
  }
});"
```

- [ ] **Step 2: Write the report**

Create `docs/validation/world-tide-stations.md` with: the question, the method (predict a year, reduce both sides to chart datum, compare to published MHW/MLW), **the bar stated before the results** (0.30 m, and why — the NOAA control), the group table from Step 1, the named failures (Southampton 0.53 m, Penarth 0.59 m) with the note that Southampton is a double high water port, and the honest limitation: **this validates datum and amplitude, not timing.** Timing needs an external reference, and every UK one is licence-restricted — see `docs/research/european-currents-licensing-2026-08-16.md`.

- [ ] **Step 3: Commit**

```sh
git add docs/validation/world-tide-stations.md
git commit -m "docs: world tide station validation report"
```

---

## What this plan does NOT do

**The map.** Opening the gates puts UK pins on blank tiles, which is exactly what `commitments.md` line 29 warned against. The world basemap floor and downloadable region packs are **Plan B** (`docs/superpowers/specs/2026-08-16-global-coverage-design.md` §2), and **neither plan ships to TestFlight alone.** Plan A is mergeable and testable on its own; the two must land together before a build goes to testers.

**Correction to the spec, found while planning:** §2 says the resolver change touches `MapScreen.swift:374` and `:546`. There are **six** call sites — `MapScreen.swift:374` (pmtiles), `:375` (layer-slice JSON), `:381` (sprite JSON), `:414` (the glyph probe, which derives the whole glyph directory from one file's parent), `:547` (`pmtilesUrl`), and `CurrentStation.swift:41` (the single loader for all five station catalogs). Plan B must cover all six.

**Timing validation.** Task 2 checks datum and amplitude. Nothing here proves a UK high water happens at the right *minute*, and every UK reference that would prove it is licence-restricted.
