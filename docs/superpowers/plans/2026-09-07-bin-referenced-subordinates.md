# Bin-Referenced Subordinate Current Stations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the 143 NOAA subordinate current stations whose reference is a non-primary bin, by carrying the 13 bins as hidden reference-only records in `currents.json`.

**Architecture:** The generator keeps a referenced bin as an ordinary harmonic record flagged `referenceOnly: true`. The app adds one optional field and filters flagged records out of `StationItem.all` and the catalog snapshot; every id-keyed reference lookup already works because the record is in the same file. station-metadata allocates slugs for the 143 first, and skips flagged records so bins never get one.

**Tech Stack:** Node 24 generators under `tools/` (`node --test`), Swift/XCTest app, `@openwaters/station-metadata` CLI.

**Spec:** `docs/superpowers/specs/2026-09-07-bin-referenced-subordinates-design.md`

## Global Constraints

- A reference-only record carries no `reference`, no offsets, no `tideReference`, and no slug.
- Its `id` is the NOAA id with the bin suffix (`noaa/EPT0003@11`); its name, region and aliases are the surface station's.
- No depth, bin or layer label in any UI string.
- Sequence is fixed: ios generator (Task 1–2) → station-metadata release (Task 3) → ios dependency bump, app change, tests (Tasks 4–7). Tasks 1–2 and 5–7 live in the worktree `../slackwater-ios-wt-bin-references` on branch `feat/269-bin-references`.
- Repos are public: no session links in commits or PRs.
- ios test runs go through `scripts/test.sh` or `lockf -t 0 /tmp/slackwater-test.lock xcodebuild …`; never a bare `xcodebuild test` (CI shares this Mac).

---

### Task 1: Generator keeps referenced bins as reference-only records

**Files:**
- Modify: `tools/gen-noaa-currents.mjs` (header comment filter 2; the `kept` pipeline; the summary line)
- Test: `tools/gen-noaa-currents.test.mjs`

**Interfaces:**
- Produces: records in `Slackwater/Resources/currents.json` with `referenceOnly: true`, harmonic shape, id containing `@`. Tasks 2, 3, 4 and 5 read this flag by that exact name.

- [ ] **Step 1: Write the failing tests**

Append to `tools/gen-noaa-currents.test.mjs`:

```js
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
```

Also raise the floor in the existing test:

```js
  assert.ok(subordinates.length > 1650, `only ${subordinates.length} subordinates`);
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd tools && node gen-noaa-currents.mjs && node --test gen-noaa-currents.test.mjs`
Expected: the three new tests FAIL (ACT0091 missing, 0 reference-only records, bin not found). The floor test FAILS at 1,549.

- [ ] **Step 3: Implement the generator change**

In `tools/gen-noaa-currents.mjs`, replace the `kept` pipeline's first three filters and the start of the map. Compute the referenced-bin set from subordinates that survive the type and direction filters, before `kept`:

```js
const directed = (s) => Number.isFinite(s.floodDirection) && Number.isFinite(s.ebbDirection);
// #269: a non-primary bin ships only as the reference of a subordinate that
// itself ships. Reference-only: in the file for the reduction, never a station.
const referencedBins = new Set(
  bundle.stations
    .filter((s) => isSubordinate(s) && directed(s) && s.reference.includes("@"))
    .map((s) => s.reference));
const isReferenceOnly = (s) => s.id.includes("@");
```

Then the filters:

```js
const kept = bundle.stations
  .filter((s) => s.type === "harmonic" || isSubordinate(s))
  .filter((s) => !s.id.includes("@") || referencedBins.has(s.id))
  .filter((s) => isSubordinate(s) || s.constituents.some((c) => c.amplitude > 0))
  // Nine subordinates publish one direction and null for the other; the app
  // draws a set arrow from both, and guessing the reciprocal is a claim about
  // the water nobody made.
  .filter((s) => directed(s) || (undirected++, false))
  .map((s) => {
    const id = `noaa/${s.id}`;
    const near = nearestTide(s);
    // A bin is named for its surface station: same water, same resolved name.
    const r = resolve({ id: `noaa/${s.id.split("@")[0]}`, name: s.name, latitude: s.latitude, longitude: s.longitude });
```

And in the `out` object, after `constituents`:

```js
      ...(isReferenceOnly(s) && { referenceOnly: true }),
```

Skip `tideReference` for a bin: wrap the existing pairing block in `if (!isReferenceOnly(s)) { … }`.

After the orphan filter, add the guard:

```js
const used = new Set(stations.filter((s) => s.reference).map((s) => s.reference));
const unused = stations.filter((s) => s.referenceOnly && !used.has(s.id)).map((s) => s.id);
if (unused.length) {
  throw new Error(`reference-only bins nobody references: ${unused.join(", ")} — a filter was reordered`);
}
```

Extend the summary line:

```js
const referenceOnlyCount = stations.filter((s) => s.referenceOnly).length;
const binSubordinates = stations.filter((s) => s.reference?.includes("@")).length;
console.log(
  `${stations.length} NOAA current stations (${stations.length - subordinateCount - referenceOnlyCount} harmonic, ` +
  `${subordinateCount} subordinate, ${referenceOnlyCount} reference-only bins serving ${binSubordinates}; ` +
  `${orphaned} orphaned and ${undirected} direction-less subordinates dropped), ${size}; ` +
  …
```

Rewrite header filter 2:

```
 *   2. Primary bin only (id without "@") — one station, one prediction — except
 *      a bin that a shipped subordinate reduces from (#269). That bin ships as
 *      a reference-only record: `referenceOnly: true`, harmonic shape, named
 *      for its surface station, no slug. The app never lists it.
```

- [ ] **Step 4: Run the generator and tests**

Run: `cd tools && node gen-noaa-currents.mjs && node --test gen-noaa-currents.test.mjs`
Expected: summary reports 13 reference-only bins serving 143; all tests PASS. `orphaned` drops from 143 to 0.

- [ ] **Step 5: Commit**

```bash
git add tools/gen-noaa-currents.mjs tools/gen-noaa-currents.test.mjs Slackwater/Resources/currents.json
git commit -m "feat: ship non-primary bins as reference-only current records (#269)"
```

---

### Task 2: gen-slugs skips reference-only records

**Files:**
- Modify: `tools/gen-slugs.mjs` (the `ids` helper)

**Interfaces:**
- Consumes: `referenceOnly` from Task 1.

- [ ] **Step 1: Observe the failure**

Run: `cd tools && node gen-slugs.mjs`
Expected: throws `13 bundled current station(s) have no published slug: noaa/ACT8851@2, …`. (It will also list the 143 until Task 4 lands; that is the expected state at this point.)

- [ ] **Step 2: Skip flagged records**

```js
// A reference-only bin (#269) is not a station and is never linked.
const ids = (file) =>
  JSON.parse(readFileSync(join(res, file), "utf8")).filter((s) => !s.referenceOnly).map((s) => s.id);
```

- [ ] **Step 3: Verify the bins are no longer reported**

Run: `cd tools && node gen-slugs.mjs 2>&1 | head -2`
Expected: the error names 143 stations, none containing `@`.

- [ ] **Step 4: Commit**

```bash
git add tools/gen-slugs.mjs
git commit -m "build: reference-only bins need no slug"
```

---

### Task 3: station-metadata allocates slugs for the 143 and ignores bins

Work in `../station-metadata` on a branch `feat/269-bin-subordinate-slugs`. This must be merged and released as v5.3.0 before Task 4.

**Files:**
- Modify: `bin/station-metadata.mjs` (`readCatalogues`, after `readStationsFile`)
- Modify: `data/slugs.json` (allocator output), `package.json` (version 5.3.0)
- Test: `bin/station-metadata.test.mjs`

**Interfaces:**
- Consumes: the regenerated `Slackwater/Resources/currents.json` from Task 1 as `--currents` input.
- Produces: `data/slugs.json` with a `current` slug for each of the 143.

- [ ] **Step 1: Write the failing test**

Find the existing `slugs` test in `bin/station-metadata.test.mjs` that writes a temp catalogue and runs the CLI; add a sibling using the same helper:

```js
test("slugs: a referenceOnly record is not a station and gets no slug", () => {
  const currents = [
    { id: "noaa/EPT0003", name: "Estes Head, Eastport", region: "Maine", latitude: 44.88, longitude: -66.99 },
    { id: "noaa/EPT0003@11", name: "Estes Head, Eastport", region: "Maine", latitude: 44.88, longitude: -66.99, referenceOnly: true },
  ];
  const table = runSlugs({ tides: [], currents });
  assert.equal(table.current["noaa/EPT0003"], "estes-head-eastport");
  assert.equal(table.current["noaa/EPT0003@11"], undefined);
});
```

Adapt `runSlugs` to whatever the file's existing temp-dir + `execFileSync` helper is called; it must write the catalogue files, run `slugs` against a copy of `data/slugs.json`, and return the parsed table.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ../station-metadata && node --test bin/station-metadata.test.mjs`
Expected: FAIL, `noaa/EPT0003@11` is allocated a slug.

- [ ] **Step 3: Skip flagged records in readCatalogues**

In `readCatalogues`, where each file's stations are pushed:

```js
      // A reference-only record (slackwater-ios #269) is in the catalogue for
      // a reduction, not as a station; it is never linked, so never slugged.
      stations.push(...readStationsFile(command, path).filter((s) => !s.referenceOnly));
```

- [ ] **Step 4: Run the tests**

Run: `cd ../station-metadata && npm test`
Expected: PASS.

- [ ] **Step 5: Allocate**

```bash
cd ../station-metadata
IOS=../slackwater-ios-wt-bin-references/Slackwater/Resources
node bin/station-metadata.mjs slugs \
  --tides $IOS/stations.json --tides $IOS/chs-stations.json \
  --currents $IOS/currents.json --currents $IOS/chs-current-gates.json --currents $IOS/chs-gates.json
git diff --stat data/
```

Expected: `wrote data/slugs.json - N station(s), 0 tombstoned`; the diff adds exactly 143 lines under `current`, none containing `@`, and `data/slug-tombstones.json` is unchanged. Verify:

```bash
git diff data/slugs.json | grep '^+ ' | wc -l      # 143
git diff data/slugs.json | grep '^+ ' | grep -c '@' # 0
git diff data/slugs.json | grep -c '^- '            # 0 (nothing moved)
```

- [ ] **Step 6: Bump and commit**

Set `"version": "5.3.0"` in `package.json`, run `npm install --package-lock-only`.

```bash
git add bin/station-metadata.mjs bin/station-metadata.test.mjs data/slugs.json package.json package-lock.json
git commit -m "feat: allocate slugs for subordinates of non-primary bins; v5.3.0

slackwater-ios#269 ships the 143 subordinate current stations whose
reference is a non-primary bin. The bin itself ships flagged referenceOnly
and is skipped here: it is not a station and is never linked. Every
existing slug is unchanged; nothing departed."
git push -u origin feat/269-bin-subordinate-slugs
gh pr create --title "feat: slugs for subordinates of non-primary bins; v5.3.0" --body "..."
```

- [ ] **Step 7: Release**

After merge, the user cuts the GitHub release `v5.3.0` (publish.yml runs on release). Confirm with `npm view @openwaters/station-metadata version` → `5.3.0` before Task 4.

---

### Task 4: Bump the dependency and regenerate

**Files:**
- Modify: `tools/package.json`, `tools/package-lock.json`
- Regenerate: `Slackwater/Resources/slugs.json`

- [ ] **Step 1: Bump**

In `tools/package.json`: `"@openwaters/station-metadata": "^5.3.0"`. Then `cd tools && npm install`.

- [ ] **Step 2: Regenerate everything and run the node tests**

Run: `cd tools && npm test`
Expected: `build:data` completes; `slugs.json: N tide + M current` where M is 143 more than before; all `node --test` suites PASS.

- [ ] **Step 3: Commit**

```bash
git add tools/package.json tools/package-lock.json Slackwater/Resources/
git commit -m "data: station-metadata 5.3.0, slugs for the 143 bin-referenced subordinates"
```

---

### Task 5: `CurrentStationRecord.referenceOnly` and the two filters

**Files:**
- Modify: `Slackwater/CurrentStation.swift` (record fields ~line 172; `StationItem.all` ~line 354)
- Modify: `Slackwater/CatalogSnapshot.swift` (`groups` ~line 111)
- Test: `SlackwaterTests/SubordinateCurrentTests.swift`

**Interfaces:**
- Produces: `CurrentStationRecord.referenceOnly: Bool?`; `CurrentStationRecord.all` still holds every record; `StationItem.all` excludes flagged ones.

- [ ] **Step 1: Write the failing tests**

Append to `SubordinateCurrentTests`:

```swift
    // MARK: - Non-primary bin references (#269)

    private var friarRoads: CurrentStationRecord {
        CurrentStationRecord.all.first { $0.id == "noaa/ACT0091" }!
    }

    func testBinReferencedSubordinateDecodesAndResolvesItsReference() {
        XCTAssertEqual(friarRoads.reference, "noaa/EPT0003@11")
        XCTAssertNotNil(friarRoads.referenceRecord)
        XCTAssertEqual(friarRoads.referenceRecord?.referenceOnly, true)
        XCTAssertFalse(friarRoads.referenceRecord!.constituents.isEmpty)
    }

    func testBinReferencedSubordinateCurveIsNotFlat() {
        let speeds = friarRoads.engineStation.speeds(from: day, to: day.addingTimeInterval(86_400), step: 600).map(\.speed)
        XCTAssertGreaterThan(speeds.max()! - speeds.min()!, 0.5)
        XCTAssertNotEqual(currentPinColour(friarRoads, at: day), "unknown")
    }

    func testAReferenceOnlyBinIsInTheCatalogButNotAStation() {
        XCTAssertNotNil(CurrentStationRecord.byId["noaa/EPT0003@11"])
        XCTAssertNil(StationItem.byId["current:noaa/EPT0003@11"])
        XCTAssertFalse(StationItem.all.contains { if case .current(let s) = $0 { s.referenceOnly == true } else { false } })
        let hits = StationItem.search("Estes Head", near: (lat: 44.888, lon: -66.996))
            .filter { if case .current = $0 { true } else { false } }
        XCTAssertEqual(hits.map(\.id), ["current:noaa/EPT0003"])
    }
```

- [ ] **Step 2: Compile-check to verify the failure**

Run:
```sh
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```
Expected: compile error, `referenceOnly` is not a member of `CurrentStationRecord`.

- [ ] **Step 3: Add the field and the filters**

In `CurrentStationRecord`, after `ebbSpeedRatio`:

```swift
    /// A non-primary bin carried only as a subordinate's reference (#269):
    /// harmonic shape, in `all` and `byId`, never in `StationItem.all`.
    var referenceOnly: Bool? = nil
```

In `StationItem.all`:

```swift
        merged += CurrentStationRecord.all.filter { $0.referenceOnly != true }.map { StationItem.current($0) }
```

In `CatalogSnapshot`, the `groups` entry for currents:

```swift
            ("currents", currents.filter { $0.referenceOnly != true }.map(StationItem.current)),
```

Update the file header comment of `CurrentStation.swift`, which still says "harmonic stations only, primary bin": replace that parenthetical with "harmonic and subordinate stations, primary bin plus the bins subordinates reduce from".

- [ ] **Step 4: Run the subordinate tests**

Run:
```sh
lockf -t 0 /tmp/slackwater-test.lock xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:SlackwaterTests/SubordinateCurrentTests 2>&1 | tail -20
```
Expected: all `SubordinateCurrentTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/CurrentStation.swift Slackwater/CatalogSnapshot.swift SlackwaterTests/SubordinateCurrentTests.swift
git commit -m "feat: hide reference-only bins from the station list (#269)"
```

---

### Task 6: Widget resolves a bin reference

**Files:**
- Test: `SlackwaterTests/WidgetStationLoaderTests.swift` (next to the existing subordinate test ~line 160)

No production change is expected; this pins the claim in the spec's Widget section.

- [ ] **Step 1: Write the test**

```swift
    func testWidgetResolvesASubordinateOfANonPrimaryBin() throws {
        let friar = try XCTUnwrap(CurrentStationRecord.all.first { $0.id == "noaa/ACT0091" })
        let loaded = try XCTUnwrap(WidgetStationLoader.load(id: "current:" + friar.id))
        guard case .current(let station, _, _) = loaded else { return XCTFail("not a current") }
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let speeds = station.speeds(from: now, to: now.addingTimeInterval(86_400), step: 600).map(\.speed)
        XCTAssertGreaterThan(speeds.max()! - speeds.min()!, 0.5, "the widget fell back to a flat harmonic with no constituents")
    }
```

Match the `.current(…)` case arity to `WidgetStationLoader.swift:10` (`case current(any CurrentPredicting, tz: TimeZone, name: String)`); adjust the pattern if the existing subordinate test at line 160 destructures differently.

- [ ] **Step 2: Run it**

Run the `xcodebuild test` line from Task 5 with `-only-testing:SlackwaterTests/WidgetStationLoaderTests`.
Expected: PASS. If it FAILS with a flat curve, the scanner missed the bin: check that `currents.json` still has `id` first in each record and that the bin record is present.

- [ ] **Step 3: Commit**

```bash
git add SlackwaterTests/WidgetStationLoaderTests.swift
git commit -m "test: a widget resolves a subordinate of a non-primary bin"
```

---

### Task 7: National-scale invariants and the pin budget

**Files:**
- Test: `SlackwaterTests/NationalScaleTests.swift` (`testBundleCoversTheUsAndCanada` line 23; `testPinLayerBuildsInsideAFrame` line 175)

- [ ] **Step 1: Assert the list count moved by exactly the subordinates**

In `testBundleCoversTheUsAndCanada`, add after the existing count assertions:

```swift
        let hidden = CurrentStationRecord.all.filter { $0.referenceOnly == true }.count
        XCTAssertEqual(hidden, 13, "reference-only bins")
        XCTAssertEqual(currents, CurrentStationRecord.all.count - hidden, "every non-hidden record is listed once")
```

- [ ] **Step 2: Run the national-scale suite**

Run the `xcodebuild test` line from Task 5 with `-only-testing:SlackwaterTests/NationalScaleTests`.
Expected: PASS, including `testPinLayerBuildsInsideAFrame` under its 1.45 s budget. If the pin test fails on time alone, record the measured cold build in the test's doc comment (the existing comment lists each re-base with its measurement) and raise the budget by the smallest round step that clears it; do not touch the cache.

- [ ] **Step 3: Full fast suite**

Run: `./scripts/test.sh 2>&1 | tail -40`
Expected: all green. Read `build/results-fast-iPhone_17.xcresult` if anything reports a crash rather than an assertion.

- [ ] **Step 4: Commit and open the PR**

```bash
git add SlackwaterTests/NationalScaleTests.swift
git commit -m "test: reference-only bins are counted and never listed"
git push -u origin feat/269-bin-references
gh pr create --title "feat: subordinate current stations referencing a non-primary bin (#269)" \
  --body "Closes #269. …"
```

The PR body names the numbers: 143 subordinates, 13 reference-only bins, 4 direction-less dropped by the existing filter, station-metadata 5.3.0.
