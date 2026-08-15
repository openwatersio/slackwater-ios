# Cross-flow check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `@sailingnaturali/current-stations` measure and bound its own 1-D major-axis approximation, by recording a cross-flow census in the bundle metadata and asserting a ratio bound on it.

**Architecture:** NOAA's `harcon.json` carries `minorMeanSpeed` — DC flow perpendicular to the flood axis, present at all times including slack — which this package fetches and currently discards. A new `src/cross-flow.js` owns the census shape and the bound constant. `src/extract.js` samples each harmonic record as it builds it and stores a ~200-byte summary on the bundle. `src/validate.js` asserts the bound, which then works offline against any bundle. No per-station field is added and nothing new reaches a device.

**Tech Stack:** Node ≥20, ESM, zero runtime dependencies, `node:test` + `node:assert/strict`.

## Global Constraints

- **Zero runtime dependencies.** This package has none and must keep none. No harmonic evaluator, no date library.
- **Node ≥20**, ESM only (`"type": "module"`). Use `node:` prefixed builtins.
- **No per-station field may be added to any station record.** The census is bundle-level metadata only. This is the settled outcome of #102 — see the spec.
- **`cons[0]` is the correct accessor** for `minorMeanSpeed`, `majorMeanSpeed` and `azi`. Verified: 0 of 2,800 harmonic bin-records vary `minorMeanSpeed` across their constituents. This matches the extractor's existing idiom.
- **Bound value: `0.5`.** Worst real ratio today is 0.241 (`BOS1130`), measured across all 2,800 harmonic bin-records. The bound is a regression guard and must reject nothing that exists now.
- Speeds are **knots** (the extractor fetches `units=english`).
- Tests must run without network. The extractor accepts `fetchFn` injection; `test/extract.test.js` has a `fakeNoaa` helper — use it.
- Repo is `~/src/sailingnaturali/current-stations`. Work in a git worktree on branch **`feat/cross-flow-census`**, per workspace CLAUDE.md — another session may be in the shared checkout:
  ```bash
  cd ~/src/sailingnaturali/current-stations
  git worktree add ../current-stations-wt-crossflow -b feat/cross-flow-census
  cd ../current-stations-wt-crossflow && npm install
  ```
  Before opening the PR, confirm `git log --oneline origin/main..HEAD` shows only your commits.

---

### Task 1: Census computation, and storing it on the bundle

**Files:**
- Create: `src/cross-flow.js`
- Create: `test/cross-flow.test.js`
- Modify: `src/extract.js` (imports at top; `ensureHarmonic` ~lines 56-80; return ~lines 136-139)
- Modify: `test/extract.test.js` (the `con()` helper ~line 9; add one test)
- Modify: `schema/currents.schema.json` (root `properties`, ~line 9-15)
- Modify: `index.d.ts` (`Bundle` interface, ~lines 79-83)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `crossFlowCensus(samples: {id: string, crossFlow: number, alongAxisPeak: number}[]): CrossFlowCensus | null`
  - `CROSS_FLOW_RATIO_MAX: number` (value `0.5`)
  - `CrossFlowCensus` shape: `{measured: string, records: number, gte0_25kn: number, gte0_50kn: number, worstRatio: {id, crossFlow, alongAxisPeak, ratio}, worstAbsolute: {id, crossFlow}}`
  - `extractBundle()`'s returned `bundle` gains an optional `crossFlow` property carrying that census.
  - Task 2 imports `CROSS_FLOW_RATIO_MAX` and reads `bundle.crossFlow`. Task 3 reads `bundle.crossFlow` and `validateBundle()`'s returned `crossFlow`.

- [ ] **Step 1: Write the failing test for the pure census function**

Create `test/cross-flow.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { crossFlowCensus, CROSS_FLOW_RATIO_MAX } from '../src/cross-flow.js';

const s = (id, crossFlow, alongAxisPeak) => ({ id, crossFlow, alongAxisPeak });

test('counts the knot thresholds and finds both worsts', () => {
  const c = crossFlowCensus([
    s('A', 0.10, 5.0),   // under both thresholds
    s('B', 0.30, 4.0),   // >= 0.25
    s('C', 0.60, 2.0),   // >= 0.25 and >= 0.50; worst absolute
    s('D', 0.20, 0.5),   // ratio 0.4 — worst ratio, but small in knots
  ]);
  assert.equal(c.records, 4);
  assert.equal(c.gte0_25kn, 2);
  assert.equal(c.gte0_50kn, 1);
  assert.equal(c.worstRatio.id, 'D');
  assert.equal(c.worstRatio.ratio, 0.4);
  assert.equal(c.worstAbsolute.id, 'C');
  assert.equal(c.worstAbsolute.crossFlow, 0.6);
});

test('the two worsts are independent — a big ratio is not a big current', () => {
  // D above has 4x C's ratio and a third of its cross-flow. Reporting only one
  // would hide either "the axis is wrong here" or "there is real water moving".
  const c = crossFlowCensus([s('C', 0.60, 2.0), s('D', 0.20, 0.5)]);
  assert.notEqual(c.worstRatio.id, c.worstAbsolute.id);
});

test('a zero along-axis peak yields ratio 0, not Infinity or NaN', () => {
  const c = crossFlowCensus([s('A', 0.3, 0)]);
  assert.equal(c.worstRatio.ratio, 0);
});

test('an empty sample set is null, not a census of nothing', () => {
  assert.equal(crossFlowCensus([]), null);
});

test('rounds to 3 decimals so a re-extract diff is reviewable', () => {
  const c = crossFlowCensus([s('A', 0.1234567, 1.9876543)]);
  assert.equal(c.worstRatio.crossFlow, 0.123);
  assert.equal(c.worstRatio.alongAxisPeak, 1.988);
  assert.equal(c.worstRatio.ratio, 0.062);
});

test('the bound rejects nothing that exists in the real data', () => {
  // Worst measured ratio across all 2,800 harmonic bin-records is 0.241 (BOS1130).
  assert.ok(CROSS_FLOW_RATIO_MAX > 0.241, 'bound must not reject current NOAA data');
});
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `cd ~/src/sailingnaturali/current-stations && node --test test/cross-flow.test.js`
Expected: FAIL — `Cannot find module '../src/cross-flow.js'`

- [ ] **Step 3: Write `src/cross-flow.js`**

```js
// What this package emits is a MAJOR-AXIS model: one signed speed along a fixed
// flood axis. NOAA also publishes `minorMeanSpeed` — the DC component of flow
// perpendicular to that axis, running at all times INCLUDING slack — and a
// major-axis model drops it.
//
// The per-station minor axis is deliberately not carried (docs/schema.md). But a
// bundle should be able to state the bound on its own approximation rather than
// leave it unmeasured, so the extractor records this census instead.
//
// Measured 2026-08-15. Across the 856 records a full US bundle holds: worst
// ratio 0.241 (BOS1130), worst absolute 0.80 kn (PUG1619 Marrowstone Point).
// The 0.241 also holds across all 2,800 bin-records NOAA publishes, so the
// bound below is safe for bins we don't currently take. Full investigation:
// openwatersio/slackwater-ios#102.

/** Provenance, carried in the census so the number explains itself in the file. */
const MEASURED =
  'NOAA minorMeanSpeed — flow perpendicular to the flood axis, present at all times including slack';

/**
 * Ratio of cross-flow to along-axis peak above which the flood axis is a poor
 * description of the station, and so the major-axis model there is suspect.
 * ~2x the worst real value: a regression guard, not a quality gate.
 */
export const CROSS_FLOW_RATIO_MAX = 0.5;

const r3 = (n) => Math.round(n * 1000) / 1000;

/**
 * @param {{id: string, crossFlow: number, alongAxisPeak: number}[]} samples
 * @returns {object|null} the census, or null when there is nothing to measure
 */
export function crossFlowCensus(samples) {
  if (!samples?.length) return null;

  let gte0_25kn = 0;
  let gte0_50kn = 0;
  let worstRatio = null;
  let worstAbsolute = null;

  for (const s of samples) {
    // A station with no along-axis flow has no axis to be wrong about.
    const ratio = s.alongAxisPeak > 0 ? s.crossFlow / s.alongAxisPeak : 0;
    if (s.crossFlow >= 0.25) gte0_25kn += 1;
    if (s.crossFlow >= 0.5) gte0_50kn += 1;

    // Tracked separately on purpose: the largest ratio and the largest current
    // are usually different stations, and they answer different questions.
    if (!worstRatio || ratio > worstRatio.ratio) {
      worstRatio = {
        id: s.id,
        crossFlow: r3(s.crossFlow),
        alongAxisPeak: r3(s.alongAxisPeak),
        ratio: r3(ratio),
      };
    }
    if (!worstAbsolute || s.crossFlow > worstAbsolute.crossFlow) {
      worstAbsolute = { id: s.id, crossFlow: r3(s.crossFlow) };
    }
  }

  return { measured: MEASURED, records: samples.length, gte0_25kn, gte0_50kn, worstRatio, worstAbsolute };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `node --test test/cross-flow.test.js`
Expected: PASS, 6 tests.

- [ ] **Step 5: Write the failing test for extractor wiring**

In `test/extract.test.js`, first extend the `con()` helper at line 9 to carry a minor axis (default 0, so every existing test is unaffected):

```js
const con = (name, amplitude, phase, azi = 90, majorMeanSpeed = -0.5, minorMeanSpeed = 0) => ({
  constituentName: name, majorAmplitude: amplitude, majorPhaseGMT: phase, azi,
  majorMeanSpeed, minorMeanSpeed,
});
```

Then append this test:

```js
test('records a cross-flow census on the bundle, without touching station records', async () => {
  const fake = fakeNoaa({
    stations: [
      { id: 'A', name: 'A', lat: 48, lng: -123, type: 'H', currbin: 1 },
      { id: 'B', name: 'B', lat: 48, lng: -123, type: 'H', currbin: 1 },
    ],
    harcon: {
      // A: 0.30 kn cross on a 2.5 kn axis (2.0 amplitude + 0.5 |Z0|) -> ratio 0.12
      'A@1': [con('M2', 2.0, 100, 90, -0.5, 0.30)],
      // B: 0.60 kn cross on a 1.2 kn axis -> ratio 0.5, and the worst on both counts
      'B@1': [con('M2', 1.0, 100, 90, -0.2, 0.60)],
    },
  });
  const { bundle } = await run(fake);

  assert.equal(bundle.crossFlow.records, 2);
  assert.equal(bundle.crossFlow.gte0_25kn, 2);
  assert.equal(bundle.crossFlow.gte0_50kn, 1);
  assert.equal(bundle.crossFlow.worstRatio.id, 'B');
  assert.equal(bundle.crossFlow.worstRatio.ratio, 0.5);
  assert.equal(bundle.crossFlow.worstAbsolute.id, 'B');

  // The whole point of #102: no minor-axis data reaches a station record.
  for (const s of bundle.stations) {
    assert.equal(JSON.stringify(s).includes('minor'), false, 'no per-station minor field');
  }
});

test('a bundle with no harmonic stations carries no census rather than an empty one', async () => {
  const fake = fakeNoaa({
    stations: [{ id: 'W1', name: 'Rotary', lat: 48, lng: -123, type: 'W', currbin: 1 }],
  });
  const { bundle } = await run(fake);
  assert.equal(bundle.crossFlow, null);
});

test('subordinates are not sampled — they have no harcon of their own', async () => {
  const fake = fakeNoaa({
    stations: [
      { id: 'REF', name: 'Ref', lat: 41, lng: -71, type: 'H', currbin: 5 },
      { id: 'ACT1234', name: 'True sub', lat: 41, lng: -71, type: 'S', currbin: 2 },
    ],
    harcon: { 'REF@5': [con('M2', 1.8, 322, 90, -0.2, 0.4)] },
    offsets: { ACT1234: { refStationId: 'REF', refStationBin: 5, mfcAmpAdj: 0.9, mecAmpAdj: 1.1 } },
  });
  const { bundle } = await run(fake);
  assert.equal(bundle.stations.length, 2, 'both stations are in the bundle');
  assert.equal(bundle.crossFlow.records, 1, 'but only the harmonic one is measured');
  assert.equal(bundle.crossFlow.worstAbsolute.id, 'REF');
});
```

- [ ] **Step 6: Run it to make sure it fails**

Run: `node --test test/extract.test.js`
Expected: FAIL — reading `records` of undefined, because `bundle.crossFlow` does not exist yet.

- [ ] **Step 7: Wire it into `src/extract.js`**

Add to the imports at the top of the file:

```js
import { crossFlowCensus } from './cross-flow.js';
```

Inside `extractBundle`, next to the existing `const harmonic = new Map();` declaration, add:

```js
  // Sampled as each harmonic record is built, because the minor axis is in the
  // harcon we already hold here and nowhere else downstream.
  const crossFlowSamples = [];
```

Inside `ensureHarmonic`, immediately after the existing `harmonic.set(key, {...})` call, add:

```js
    crossFlowSamples.push({
      id: key,
      crossFlow: Math.abs(cons[0].minorMeanSpeed ?? 0),
      alongAxisPeak: cons.reduce((sum, c) => sum + Math.abs(c.majorAmplitude ?? 0), 0)
        + Math.abs(cons[0].majorMeanSpeed ?? 0),
    });
```

Change the return statement's bundle object to include the census:

```js
  return {
    bundle: {
      note: BUNDLE_NOTE,
      generated: new Date().toISOString(),
      crossFlow: crossFlowCensus(crossFlowSamples),
      stations,
    },
    skipped: { ...skipped, unresolvable },
  };
```

- [ ] **Step 8: Run the full suite to verify it passes**

Run: `node --test`
Expected: PASS. All pre-existing tests still green — `con()` gained a defaulted parameter, so no existing call site changes behaviour.

- [ ] **Step 9: Update the bundle contract — schema and types**

In `schema/currents.schema.json`, add to the root `properties` object, after `"generated"`:

```json
    "crossFlow": {
      "type": ["object", "null"],
      "description": "Census of NOAA `minorMeanSpeed` — flow perpendicular to the flood axis, present at all times including slack. This bundle's major-axis model drops it; this records how much it drops. Not carried per station. Null when the bundle has no harmonic stations.",
      "properties": {
        "measured": { "type": "string" },
        "records": { "type": "integer", "description": "Harmonic records sampled, `@bin` entries included." },
        "gte0_25kn": { "type": "integer" },
        "gte0_50kn": { "type": "integer" },
        "worstRatio": {
          "type": "object",
          "description": "Largest crossFlow/alongAxisPeak — where the flood axis describes the station worst.",
          "properties": {
            "id": { "type": "string" },
            "crossFlow": { "type": "number" },
            "alongAxisPeak": { "type": "number" },
            "ratio": { "type": "number" }
          }
        },
        "worstAbsolute": {
          "type": "object",
          "description": "Largest crossFlow in knots — usually a different station from worstRatio.",
          "properties": {
            "id": { "type": "string" },
            "crossFlow": { "type": "number" }
          }
        }
      }
    },
```

In `index.d.ts`, replace the `Bundle` interface:

```ts
export interface CrossFlowCensus {
  /** What was measured, carried inline so the number explains itself. */
  measured: string;
  /** Harmonic records sampled, `@bin` entries included. */
  records: number;
  gte0_25kn: number;
  gte0_50kn: number;
  /** Where the flood axis describes the station worst. */
  worstRatio: { id: string; crossFlow: number; alongAxisPeak: number; ratio: number };
  /** Largest cross-flow in knots — usually a different station from `worstRatio`. */
  worstAbsolute: { id: string; crossFlow: number };
}

export interface Bundle {
  note: string;
  generated: string;
  /**
   * How much the major-axis model drops. Null when the bundle has no harmonic
   * stations. Never carried per station — see docs/schema.md.
   */
  crossFlow: CrossFlowCensus | null;
  stations: (HarmonicStation | SubordinateStation)[];
}
```

- [ ] **Step 10: Verify the schema still parses and the suite is green**

Run: `node -e "JSON.parse(require('fs').readFileSync('schema/currents.schema.json','utf8')); console.log('schema parses')" && node --test`
Expected: `schema parses`, then all tests PASS.

- [ ] **Step 11: Commit**

```bash
git add src/cross-flow.js test/cross-flow.test.js src/extract.js test/extract.test.js schema/currents.schema.json index.d.ts
git commit -m "feat: record a cross-flow census on the bundle

NOAA publishes minorMeanSpeed — DC flow perpendicular to the flood axis,
present at all times including slack — which this package fetches and
discards. The major-axis model that discards it now states its own bound.

~200 bytes of bundle metadata. No per-station field: bundling the minor
axis was measured and rejected in openwatersio/slackwater-ios#102."
```

---

### Task 2: Assert the bound in `validateBundle`

**Files:**
- Modify: `src/validate.js` (imports; the checks block; the return object)
- Modify: `test/validate.test.js` (add tests)
- Modify: `docs/schema.md` (the "Not in the bundle" section, ~lines 99-101)
- Modify: `docs/noaa-api.md` (the field-mapping table, ~line 80)

**Interfaces:**
- Consumes: `CROSS_FLOW_RATIO_MAX` from `src/cross-flow.js` (Task 1); `bundle.crossFlow` shape from Task 1.
- Produces: `validateBundle()`'s return object gains `crossFlow: CrossFlowCensus | null`. Task 3 reads it.

- [ ] **Step 1: Write the failing tests**

Append to `test/validate.test.js`:

```js
const census = (extra = {}) => ({
  measured: 'NOAA minorMeanSpeed …', records: 2, gte0_25kn: 1, gte0_50kn: 0,
  worstRatio: { id: 'A', crossFlow: 0.1, alongAxisPeak: 1.0, ratio: 0.1 },
  worstAbsolute: { id: 'A', crossFlow: 0.1 }, ...extra,
});

test('accepts a bundle whose cross-flow ratio is within the bound', () => {
  const v = validateBundle({ stations: [harmonic('A')], crossFlow: census() });
  assert.equal(v.ok, true);
  assert.equal(v.crossFlow.worstRatio.ratio, 0.1);
});

test('rejects a bundle where the flood axis stops describing a station', () => {
  const v = validateBundle({
    stations: [harmonic('A')],
    crossFlow: census({ worstRatio: { id: 'BAD', crossFlow: 0.9, alongAxisPeak: 1.0, ratio: 0.9 } }),
  });
  assert.equal(v.ok, false);
  assert.match(v.errors.join(), /BAD/);
  assert.match(v.errors.join(), /cross-flow/i);
});

test('a bundle predating the census is valid, not broken', () => {
  // The vendored extract in slackwater-ios has no crossFlow block. A check that
  // postdates a bundle must not turn that bundle red.
  const v = validateBundle({ stations: [harmonic('A')] });
  assert.equal(v.ok, true);
  assert.equal(v.crossFlow, null);
});

test('a null census (no harmonic stations) is valid', () => {
  const v = validateBundle({ stations: [harmonic('A')], crossFlow: null });
  assert.equal(v.ok, true);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `node --test test/validate.test.js`
Expected: FAIL — the bound test passes `ok: true` (no such check yet), and `v.crossFlow` is `undefined` not `null`.

- [ ] **Step 3: Implement the check**

In `src/validate.js`, add the import at the top:

```js
import { CROSS_FLOW_RATIO_MAX } from './cross-flow.js';
```

Add this check after the existing `unknownType` / `badPosition` checks, before the `return`:

```js
  // The bundle's whole model is one signed speed along a fixed flood axis. When
  // cross-axis flow gets large next to the along-axis flow, that axis has stopped
  // describing the station and the model there is suspect. A bundle predating this
  // census carries no block — absent is "not measured", not "failed".
  const cf = bundle.crossFlow ?? null;
  if (cf?.worstRatio && cf.worstRatio.ratio > CROSS_FLOW_RATIO_MAX) {
    errors.push(
      `cross-flow ratio ${cf.worstRatio.ratio} at ${cf.worstRatio.id} exceeds ${CROSS_FLOW_RATIO_MAX} `
      + '— the flood axis no longer describes that station, so its major-axis model is suspect',
    );
  }
```

Change the return to carry it:

```js
  return {
    ok: errors.length === 0,
    counts: { harmonic: harmonic.length, subordinate: subordinate.length, total: stations.length },
    crossFlow: cf,
    errors,
  };
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test`
Expected: PASS, including all pre-existing validate tests.

- [ ] **Step 5: Prove the new assertion red**

Temporarily change `CROSS_FLOW_RATIO_MAX` in `src/cross-flow.js` to `0.05`, then run `node --test test/validate.test.js`.
Expected: the "accepts a bundle whose cross-flow ratio is within the bound" test now FAILS. This confirms the assertion is load-bearing rather than vacuously true.
**Restore the value to `0.5`** and re-run — expected PASS.

- [ ] **Step 6: Update the docs that now say something incomplete**

In `docs/schema.md`, replace the "Minor-axis constituents" bullet under "Not in the bundle":

```markdown
- **Minor-axis constituents.** NOAA publishes `minorAmplitude`/`minorPhaseGMT` for a 2D
  rotary model; a major-axis model doesn't use them, so they aren't carried per station.
  Bundling them was measured and rejected — worth a median 4% of peak speed, and a 2D
  magnitude series never crosses zero, which silently yields no slack events at all
  (openwatersio/slackwater-ios#102).

  The bundle does carry a **`crossFlow` census** at the root: how much perpendicular flow
  the major-axis model drops, and the worst station by ratio and by knots. `validate`
  fails a bundle whose worst ratio exceeds 0.5.
```

In `docs/noaa-api.md`, replace the minor-axis row of the field-mapping table:

```markdown
| minor axis | `minorAmplitude`/`minorPhaseGMT` | for a 2D/rotary model; unused by a major-axis model — but see `minorMeanSpeed` below |
| cross-flow | `minorMeanSpeed` | DC flow perpendicular to the axis, running at ALL times including slack. Not carried per station; summarised in the bundle's `crossFlow` census |
```

- [ ] **Step 7: Commit**

```bash
git add src/validate.js test/validate.test.js docs/schema.md docs/noaa-api.md
git commit -m "feat: fail validation when the flood axis stops describing a station

Asserts crossFlow.worstRatio.ratio <= 0.5. Because the census is stored on
the bundle rather than printed, this runs offline against any bundle with
no re-extract.

A bundle predating the census has no block and stays valid — absent is
'not measured', not 'failed'."
```

---

### Task 3: Surface it in the CLI

**Files:**
- Modify: `bin/current-stations.mjs` (the `extract` branch ~lines 41-52; the `validate` branch ~lines 81-85)
- Modify: `README.md` (the "What a bundle looks like" JSON block, ~lines 60-80)

**Interfaces:**
- Consumes: `bundle.crossFlow` (Task 1) and `validateBundle()`'s returned `crossFlow` (Task 2).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add a shared formatter and print it in the `extract` branch**

In `bin/current-stations.mjs`, add this helper immediately after the existing `const log = (m) => console.error(m);` line:

```js
const logCrossFlow = (cf) => {
  if (!cf) return log('cross-flow: not measured');
  log(`cross-flow (${cf.records} harmonic records): `
    + `${cf.gte0_25kn} >= 0.25 kn, ${cf.gte0_50kn} >= 0.50 kn`);
  log(`  worst ratio    ${cf.worstRatio.ratio} at ${cf.worstRatio.id} `
    + `(${cf.worstRatio.crossFlow} kn across a ${cf.worstRatio.alongAxisPeak} kn axis)`);
  log(`  worst absolute ${cf.worstAbsolute.crossFlow} kn at ${cf.worstAbsolute.id}`);
};
```

In the `extract` branch, replace the existing `log(\`wrote ${out} — ${bundle.stations.length} stations\`);` line with:

```js
  log(`wrote ${out} — ${bundle.stations.length} stations`);
  logCrossFlow(bundle.crossFlow);
```

- [ ] **Step 2: Print it in the `validate` branch too**

In the `validate` branch, replace:

```js
  const v = validateBundle(JSON.parse(readFileSync(out, 'utf8')));
  log(`${out}: ${v.counts.harmonic} harmonic, ${v.counts.subordinate} subordinate`);
  for (const e of v.errors) log(`  ERROR: ${e}`);
  if (!v.ok) process.exitCode = 1;
```

with:

```js
  const v = validateBundle(JSON.parse(readFileSync(out, 'utf8')));
  log(`${out}: ${v.counts.harmonic} harmonic, ${v.counts.subordinate} subordinate`);
  logCrossFlow(v.crossFlow);
  for (const e of v.errors) log(`  ERROR: ${e}`);
  if (!v.ok) process.exitCode = 1;
```

- [ ] **Step 3: Verify both branches by hand against a real fixture**

The CLI has no unit tests in this repo; verify it end to end instead. Build a fixture and run both commands:

```bash
cd ~/src/sailingnaturali/current-stations
node -e '
const b = {
  note: "test", generated: new Date().toISOString(),
  crossFlow: { measured: "x", records: 2, gte0_25kn: 1, gte0_50kn: 0,
    worstRatio: {id:"A", crossFlow:0.1, alongAxisPeak:1, ratio:0.1},
    worstAbsolute: {id:"A", crossFlow:0.1} },
  stations: [{ id:"A", name:"A", type:"harmonic", latitude:48, longitude:-123,
    floodDirection:90, ebbDirection:270, offset:-0.5,
    constituents:[{name:"M2",amplitude:2,phase:100}] }],
};
require("fs").writeFileSync("/tmp/cf-ok.json", JSON.stringify(b));
b.crossFlow.worstRatio = {id:"BAD", crossFlow:0.9, alongAxisPeak:1, ratio:0.9};
require("fs").writeFileSync("/tmp/cf-bad.json", JSON.stringify(b));
'
node bin/current-stations.mjs validate /tmp/cf-ok.json;  echo "exit=$?"
node bin/current-stations.mjs validate /tmp/cf-bad.json; echo "exit=$?"
```

Expected: the first prints the census and `exit=0`. The second prints the census, an `ERROR:` line naming `BAD`, and `exit=1`.

Then confirm the `extract` path prints it, using a two-station live extract (small, polite):

```bash
node bin/current-stations.mjs extract /tmp/cf-live.json --stations PUG1717,PUG1619
```

Expected: `wrote … — 2 stations` followed by the cross-flow lines, with `PUG1619` as `worstAbsolute` at roughly 0.8 kn.

- [ ] **Step 4: Update the README bundle example**

In `README.md`, in the "What a bundle looks like" JSON block, add after the `"note"` line:

```json
  "crossFlow": {
    "records": 856, "gte0_25kn": 61, "gte0_50kn": 12,
    "worstRatio": { "id": "BOS1130", "crossFlow": 0.178, "alongAxisPeak": 0.74, "ratio": 0.241 },
    "worstAbsolute": { "id": "PUG1619", "crossFlow": 0.8 }
  },
```

And add a fourth bullet to the "Three details that are easy to get wrong" list — renaming it to **Four details**:

```markdown
- **The model is one axis, and the bundle says how much that costs.** `crossFlow` is a
  census of NOAA's `minorMeanSpeed`, the flow perpendicular to the flood axis that runs
  even at slack. `validate` fails above a 0.5 ratio. Bundling the full minor axis was
  measured and rejected: a 2D magnitude series never crosses zero, so slack detection
  silently returns nothing.
```

- [ ] **Step 5: Run the full suite and commit**

Run: `node --test`
Expected: PASS.

```bash
git add bin/current-stations.mjs README.md
git commit -m "feat: print the cross-flow census in extract and validate

Both commands now report what the major-axis model drops, and validate
exits 1 above the bound."
```

---

### Task 4: Release

**Files:**
- Modify: `package.json` (`version`)

**Interfaces:**
- Consumes: everything above.
- Produces: a published version `slackwater-ios` can pin when step 2 (re-extract and re-vendor) happens.

- [ ] **Step 1: Confirm the working tree is clean and the suite is green**

Run: `git status --porcelain && node --test`
Expected: no output from `git status`; all tests PASS.

- [ ] **Step 2: Bump the minor version**

Additive, backward compatible — a bundle without `crossFlow` still validates. `0.2.1` → `0.3.0` in `package.json`.

- [ ] **Step 3: Commit and tag**

Per workspace CLAUDE.md, every version bump gets a matching tag or `version-tag.yml` fails the build.

```bash
git add package.json
git commit -m "chore: 0.3.0 — cross-flow census and bound"
git tag v0.3.0
```

- [ ] **Step 4: Push and open the PR**

```bash
git push -u origin feat/cross-flow-census && git push --tags
gh pr create --repo sailingnaturali/current-stations --base main \
  --title "Measure and bound the 1-D major-axis approximation" --body "$(cat <<'EOF'
This package emits a **major-axis model**: one signed speed along a fixed flood axis. NOAA also publishes `minorMeanSpeed` — the DC component of flow perpendicular to that axis, running at all times **including slack** — which we fetch and discard.

This makes the bundle state the bound on its own approximation.

## What's added

A `crossFlow` census at the bundle root, ~200 bytes:

- `records`, `gte0_25kn`, `gte0_50kn`
- `worstRatio` — where the flood axis describes a station worst
- `worstAbsolute` — the largest cross-flow in knots, usually a different station

`validateBundle` fails above `ratio > 0.5`, and because the census is stored rather than printed, that check runs **offline against any bundle** with no re-extract.

## What's deliberately NOT added

**No per-station minor-axis field.** Bundling the minor axis was measured and rejected in openwatersio/slackwater-ios#102: it's worth a median 4% of peak speed, and a 2-D magnitude series never crosses zero — so slack detection silently returns *nothing* at 836 of 850 stations. The census gets the diagnostic without the payload.

## The bound

Worst real ratio is **0.241** (`BOS1130`), verified across all 2,800 bin-records NOAA publishes — a superset of the 856 a bundle holds. `0.5` gives 2.08× headroom and rejects nothing today. It is a regression guard, not a quality gate: if a future extract trips it, that is a finding about NOAA's data.

Expected census on a full US extract: `856 records, 61 >= 0.25 kn, 12 >= 0.50 kn`.

## Consumers

`slackwater-ios` is untouched. Its vendored extract has no `crossFlow` block, and a bundle without one stays valid — absent is "not measured", not "failed". Re-extract, re-vendor and the `build:data` re-assert are a separate change, tracked by openwatersio/slackwater-ios#104.
EOF
)"
```

**Do not merge your own PR** (workspace CLAUDE.md). The `gh release create v0.3.0` that triggers OIDC publish happens after merge.

---

## Notes for the implementer

- **The bound must reject nothing today.** If a real extract trips it, that is a finding about NOAA's data, not a reason to raise the number. Report it.
- **Do not add a per-station minor field**, however convenient it looks. That is the exact thing #102 measured and rejected; the census exists so we get the diagnostic without the payload.
- `test/extract.test.js`'s `con()` helper gains a defaulted trailing parameter in Task 1. Existing call sites keep working unchanged — if any test breaks, the change was wrong.
- The census counts **all** harmonic records the bundle holds, `@bin` entries included — 856 in a full US extract (850 primary-bin plus 14 subordinate-referenced bins). Not the 2,800 bin-records NOAA publishes, and not the 842 stations `slackwater-ios` ships after its own filters. Do not filter.
- **Expected first-extract census:** `records 856, gte0_25kn 61, gte0_50kn 12, worstRatio 0.241 BOS1130, worstAbsolute 0.80 kn PUG1619`. A material divergence is a finding about NOAA's data — report it rather than adjusting the plan to match.
