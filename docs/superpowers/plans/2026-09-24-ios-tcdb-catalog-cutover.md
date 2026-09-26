# iOS TCDB catalog cutover implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Slackwater's tide/current/index/slug runtime JSON with one mapped TCDB while preserving station identity, unavailable explanations, stored state, widgets, and links.

**Architecture:** Node classifies the unified station database once and builds an app-specific `slackwater.tcdb` containing every identity and only approved prediction payloads. A focused Swift adapter maps the public `SlackwaterDatabase` API into existing app record types; the app scans identity while detail and widget paths perform binary record lookups.

**Tech Stack:** Node.js 24, `@slackwater/database@1.0.0-beta.0`, Swift 5, `SlackwaterDatabase`, Neaps/Slackwater engine, XCTest, XcodeGen

**Spec:** `docs/superpowers/specs/2026-09-24-unified-tcdb-catalog-design.md`

## Global constraints

- Start only after the upstream reader plan publishes the exact `1.0.0-beta.0` contract.
- Pin Swift and Node to exactly `1.0.0-beta.0`; do not use a range. Keep that beta pin until the Slackwater app releases.
- Bundle every upstream identity and strip every prediction field from non-renderable records.
- Keep CHS observations, downloaded windows, and fitted models local.
- Preserve station IDs and the existing `current:` UI prefix.
- Do not enable remote TCDB activation.
- No Slackwater source may import `FlatBuffers` or name a generated `Slackwater_*` type.

## Review focus

- A subordinate whose reference is hidden or missing must never become renderable.
- A restricted station must retain identity/license/source while exposing no prediction values.
- A current missing a required subordinate offset must be non-renderable; a real zero must remain zero and convert to zero seconds.
- A former route must resolve only to its original station, including unavailable or departed targets.
- A chosen namesake whose display name changed must retain the stored station ID and get a new local key.

---

### Task 1: Pin the renamed database release

**Files:**
- Modify: `project.yml`
- Modify: `tools/package.json`
- Modify: `tools/package-lock.json`
- Test: `SlackwaterTests/DatabaseDependencyTests.swift`

**Interfaces:**
- Consumes: `SlackwaterDatabase` and `@slackwater/database` version `1.0.0-beta.0`.
- Produces: both app targets can import `SlackwaterDatabase`; Node generators import `@slackwater/database`.

- [ ] **Step 1: Add a compile-time dependency test**

```swift
import SlackwaterDatabase
import XCTest

final class DatabaseDependencyTests: XCTestCase {
    func testReaderUsesTheRenamedPublicAPI() {
        XCTAssertTrue(StationDatabase.self is Any.Type)
    }
}
```

- [ ] **Step 2: Generate the project and verify the test fails to compile**

Run: `rtk xcodegen generate && SLACKWATER_ONLY=SlackwaterTests/DatabaseDependencyTests rtk test ./scripts/test.sh --unit`

Expected: FAIL because `SlackwaterDatabase` is not a target dependency.

- [ ] **Step 3: Pin both package consumers**

Add the Swift package with `exactVersion: 1.0.0-beta.0` and add its product to both `Slackwater` and `SlackwaterWidgets`. Replace `@neaps/tide-database` and the temporary route alias with exact `@slackwater/database: "1.0.0-beta.0"`.

- [ ] **Step 4: Install and regenerate**

Run: `rtk npm install --ignore-scripts`

Run: `rtk xcodegen generate`

- [ ] **Step 5: Run the focused dependency test**

Run: `SLACKWATER_ONLY=SlackwaterTests/DatabaseDependencyTests rtk test ./scripts/test.sh --unit`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add project.yml tools/package.json tools/package-lock.json SlackwaterTests/DatabaseDependencyTests.swift
rtk git commit -m "Pin the unified station database"
```

### Task 2: Classify the unified catalog once

**Files:**
- Create: `tools/catalog-selection.mjs`
- Create: `tools/catalog-selection.test.mjs`
- Modify: `tools/gen-tides.mjs`
- Modify: `tools/gen-noaa-currents.mjs`
- Modify: `tools/bundle.mjs`

**Interfaces:**
- Consumes: upstream `allStations`, existing CHS coverage inputs, datum checks, and existing selection constants.
- Produces: `selectCatalog(allStations, chs): { stations, byId, renderableIds, unavailableIds, hiddenReasons }`.

- [ ] **Step 1: Write failing classification tests against the real pinned input**

```javascript
test("keeps every upstream identity but only selected records renderable", () => {
  const result = selectCatalog(allStations, chs);
  assert.equal(result.stations.length, allStations.length);
  assert(result.renderableIds.has("noaa/9447130"));
  assert(result.unavailableIds.has("ticon/gijontg-gij-esp-cmems"));
  assert(!result.renderableIds.has("ticon/gijontg-gij-esp-cmems"));
});

test("never renders a subordinate without its reference", () => {
  const result = selectCatalog(allStations, chs);
  for (const station of result.stations.filter(s => result.renderableIds.has(s.id))) {
    const reference = station.offsets?.reference ?? station.current?.offsets?.reference;
    if (reference) assert(result.renderableIds.has(reference), `${station.id} -> ${reference}`);
  }
});

test("does not collapse missing current offsets into zero", () => {
  const result = selectCatalog(allStations, chs);
  const missing = allStations.filter(s =>
    s.kind === "current" && s.current?.offsets &&
    ["slack_before_flood", "slack_before_ebb", "flood_time", "ebb_time",
     "flood_speed_ratio", "ebb_speed_ratio"].some(k => s.current.offsets[k] === undefined));
  for (const station of missing) assert(!result.renderableIds.has(station.id), station.id);
});
```

- [ ] **Step 2: Run the test and verify the import failure**

Run: `rtk test node --test catalog-selection.test.mjs`

Expected: FAIL because `catalog-selection.mjs` does not exist.

- [ ] **Step 3: Move the existing selection rules behind one function**

Extract the tide and current filtering logic without changing thresholds. Replace current input from `data/noaa-currents.json` with `allStations.filter(s => s.kind === "current")`. Use TCDB `name`, `context`, `region`, `country`, and `aliases`; remove `placesResolver` calls from selected station construction.

Return classifications instead of writing files. Keep direct script entry points temporarily so parity tests can still emit baseline JSON during Tasks 2-4.

- [ ] **Step 4: Run selection and existing generator tests**

Run: `rtk test node --test catalog-selection.test.mjs gen-tides.test.mjs gen-noaa-currents.test.mjs datum-check.test.mjs`

Expected: PASS. Any count/name/current difference must be printed by the parity report introduced in Task 4, not silently accepted here.

- [ ] **Step 5: Commit**

```bash
rtk git add tools/catalog-selection.mjs tools/catalog-selection.test.mjs tools/gen-tides.mjs tools/gen-noaa-currents.mjs tools/bundle.mjs
rtk git commit -m "Select tide and current stations from one database"
```

### Task 3: Build one app-specific TCDB

**Files:**
- Create: `tools/gen-catalog.mjs`
- Create: `tools/gen-catalog.test.mjs`
- Create: `Slackwater/Resources/slackwater.tcdb` (generated)
- Modify: `tools/package.json`
- Modify: `Slackwater/Resources/README.md`

**Interfaces:**
- Consumes: `selectCatalog`, `buildDatabase`, `stationRoutes`.
- Produces: `buildSlackwaterDatabase(selection): Uint8Array` and generated `Slackwater/Resources/slackwater.tcdb`.

- [ ] **Step 1: Write failing binary and payload-boundary tests**

```javascript
test("writes a TCDB containing every identity", () => {
  const { bytes, manifest } = generateCatalog();
  assert.equal(Buffer.from(bytes.subarray(4, 8)).toString(), "TCDB");
  assert.equal(manifest.identityIds.length, allStations.length);
  assert.deepEqual(manifest.predictionIds, [...selection.renderableIds].sort());
});

test("strips every prediction field from unavailable records", () => {
  const row = manifest.rows.get("ticon/gijontg-gij-esp-cmems");
  assert.equal(row.reason, "unavailable");
  assert.equal(row.hasPrediction, false);
  assert.equal(row.licenseCommercialUse, false);
});
```

- [ ] **Step 2: Run the test and verify the missing-module failure**

Run: `rtk test node --test gen-catalog.test.mjs`

Expected: FAIL because `gen-catalog.mjs` does not exist.

- [ ] **Step 3: Implement the builder**

For each upstream station, preserve identity, location, provenance, attribution, and license. For renderable IDs, preserve prediction fields and set quality `accepted: true`. For every other ID, omit `harmonic_constituents`, `datums`, `astronomical_bounds`, `offsets`, and prediction-bearing current fields, set `accepted: false`, and set a deterministic reason from `hiddenReasons`.

Pass complete tide/current routes to `buildDatabase`:

```javascript
const bytes = buildDatabase(records, {
  version: `${packageJSON.version}+slackwater-ios.1`,
  routes: {
    tide: stationRoutes("tide"),
    current: stationRoutes("current"),
  },
});
```

- [ ] **Step 4: Generate and test the artifact**

Run: `rtk test node gen-catalog.mjs`

Run: `rtk test node --test gen-catalog.test.mjs`

Expected: PASS; the artifact identifier is `TCDB`, identity count equals upstream, and unavailable records have no prediction payload.

- [ ] **Step 5: Commit**

```bash
rtk git add tools/gen-catalog.mjs tools/gen-catalog.test.mjs tools/package.json Slackwater/Resources/slackwater.tcdb Slackwater/Resources/README.md
rtk git commit -m "Build the app catalog as TCDB"
```

### Task 4: Record catalog parity and remove legacy data sources

**Files:**
- Create: `tools/catalog-parity.test.mjs`
- Modify: `tools/gen-chs-stations.mjs`
- Modify: `tools/gen-chs-gates.mjs`
- Modify: `tools/gen-slugs.mjs`
- Modify: `tools/gen-station-index.mjs`
- Modify: `tools/package.json`
- Modify: `tools/package-lock.json`
- Delete: `data/noaa-currents.json`

**Interfaces:**
- Consumes: committed JSON baseline, `selectCatalog`, upstream routes and structured identity.
- Produces: explicit parity report and TCDB-derived CHS policy/tombstone outputs.

- [ ] **Step 1: Write the parity test before deleting sources**

The test must compare sets and values, not snapshot a giant JSON string:

```javascript
test("reports every catalog difference", () => {
  const report = compareCatalogs(readBaselineResources(), generateCatalog().manifest);
  assert.deepEqual(report.unexplainedIds, []);
  assert.deepEqual(report.brokenRoutes, []);
  assert.deepEqual(report.missingReferences, []);
  assert.deepEqual(report.collapsedMissingCurrentValues, []);
  assert(report.predictionError.maxTideMeters <= 1e-5);
  assert(report.predictionError.maxCurrentKnots <= 1e-5);
});
```

- [ ] **Step 2: Run the parity test and verify it reports current differences**

Run: `rtk test node --test catalog-parity.test.mjs`

Expected: FAIL with named ID, route, metadata, or prediction differences; no generic snapshot mismatch.

- [ ] **Step 3: Move remaining generators to unified inputs**

Generate CHS identity, gate rules, aliases, nearby metadata, routes, and tombstones from `selectCatalog` and upstream route tables. Retain only app-specific CHS fitting policy fields in JSON. Stop invoking `gen-slugs.mjs` and `gen-station-index.mjs`; retain them and their baseline artifacts until Tasks 7 and 9 remove the corresponding runtime paths.

Remove `@openwaters/station-metadata`, `tz-lookup` if no remaining caller needs it, the NOAA current vendored file, and the temporary route alias.

- [ ] **Step 4: Resolve only intentional parity differences**

Encode reviewed ID arrivals/departures, the 183 name changes, region changes, current count changes, and Float32 tolerances as explicit assertions or checked report fixtures. Do not loosen set equality or numeric tolerances to make the test green.

- [ ] **Step 5: Run all Node data tests**

Run: `rtk npm test`

Expected: PASS with no access to the removed NOAA current bundle or station-metadata package.

- [ ] **Step 6: Commit**

```bash
rtk git add tools data Slackwater/Resources tools/package.json tools/package-lock.json
rtk git commit -m "Derive every station artifact from TCDB"
```

### Task 5: Add the Swift TCDB adapter

**Files:**
- Create: `Slackwater/TCDBCatalog.swift`
- Create: `SlackwaterTests/TCDBCatalogTests.swift`
- Modify: `Slackwater/TideStation.swift`
- Modify: `Slackwater/CurrentStation.swift`
- Modify: `Slackwater/StationIndex.swift`

**Interfaces:**
- Consumes: public `StationDatabase`, `Station`, `StationRoute`, existing `TideStationRecord`, `CurrentStationRecord`, and `StationItem`.
- Produces: `TCDBCatalog.init(directory:)`, `identityItems`, `tideRecord(id:)`, `currentRecord(id:)`, `stationItem(id:)`, and route methods.

- [ ] **Step 1: Write failing adapter tests**

```swift
func testScansIdentityWithoutMaterializingPredictionRecords() throws {
    let catalog = try TCDBCatalog(directory: Bundle.main.resourceURL!)
    XCTAssertGreaterThan(catalog.identityItems.count, 2_500)
    XCTAssertEqual(catalog.stationItem(id: TideStationRecord.fridayHarborID)?.name, "Friday Harbor")
}

func testConvertsCurrentOffsetUnitsWithoutChangingZero() throws {
    let catalog = try TCDBCatalog(directory: Bundle.main.resourceURL!)
    let subordinate = try XCTUnwrap(catalog.currentRecord(id: knownSubordinateCurrentID))
    XCTAssertEqual(subordinate.floodTimeOffset, expectedFloodMinutes * 60)
    XCTAssertEqual(subordinate.slackBeforeEbbOffset, 0)
}

func testUnavailableIdentityHasNoPredictionRecord() throws {
    let catalog = try TCDBCatalog(directory: Bundle.main.resourceURL!)
    XCTAssertNotNil(catalog.unavailableByID["ticon/gijontg-gij-esp-cmems"])
    XCTAssertNil(catalog.tideRecord(id: "ticon/gijontg-gij-esp-cmems"))
}
```

Use IDs and expected values read from the generated manifest, not invented constants.

- [ ] **Step 2: Run the focused test and verify the compile failure**

Run: `SLACKWATER_ONLY=SlackwaterTests/TCDBCatalogTests rtk test ./scripts/test.sh --unit`

Expected: FAIL because `TCDBCatalog` does not exist.

- [ ] **Step 3: Implement the minimum adapter**

```swift
struct TCDBCatalog {
    let database: StationDatabase

    static let bundled: TCDBCatalog = {
        do { return try TCDBCatalog(directory: Bundle.main.resourceURL ?? Bundle.main.bundleURL) }
        catch { preconditionFailure("Bundled station database is missing or invalid: \(error)") }
    }()

    init(directory: URL) throws {
        database = try StationDatabase(contentsOf: directory.appendingPathComponent("slackwater.tcdb"))
    }

    func tideRecord(id: String) -> TideStationRecord? {
        guard let station = database.station(id: id), station.accepted,
              station.kind == .tide, let timezone = station.timezone,
              let chartDatum = station.chartDatum, let shift = station.chartDatumShift else { return nil }
        var record = TideStationRecord(
            id: station.id, name: station.name, region: displayRegion(station),
            aliases: station.aliases, latitude: station.latitude, longitude: station.longitude,
            timezone: timezone, chartDatum: chartDatum, datumOffset: shift,
            constituents: station.constituents.map {
                Con(name: $0.name, amplitude: $0.amplitude, phase: $0.phase)
            })
        if let source = station.tideOffsets {
            record.reference = source.reference
            record.offsets = TideOffsets(
                time: .init(high: Double(source.timeHigh), low: Double(source.timeLow)),
                height: .init(type: source.heightType == .fixed ? "fixed" : "ratio",
                              high: source.heightHigh, low: source.heightLow))
        }
        return record
    }

    func currentRecord(id: String) -> CurrentStationRecord? {
        guard let station = database.station(id: id), station.accepted,
              station.kind == .current, let timezone = station.timezone,
              let current = station.current, let flood = current.floodDirection,
              let ebb = current.ebbDirection else { return nil }
        var record = CurrentStationRecord(
            id: station.id, name: station.name, region: displayRegion(station),
            aliases: station.aliases, latitude: station.latitude, longitude: station.longitude,
            timezone: timezone, floodDirection: flood, ebbDirection: ebb,
            meanFlow: current.meanFlow ?? 0, tideReference: current.tideReference,
            constituents: station.constituents.map {
                Con(name: $0.name, amplitude: $0.amplitude, phase: $0.phase)
            })
        if let source = current.offsets {
            guard let beforeFlood = source.slackBeforeFlood, let beforeEbb = source.slackBeforeEbb,
                  let floodTime = source.floodTime, let ebbTime = source.ebbTime,
                  let floodRatio = source.floodSpeedRatio, let ebbRatio = source.ebbSpeedRatio else { return nil }
            record.reference = source.reference
            record.slackBeforeFloodOffset = Double(beforeFlood * 60)
            record.slackBeforeEbbOffset = Double(beforeEbb * 60)
            record.floodTimeOffset = Double(floodTime * 60)
            record.ebbTimeOffset = Double(ebbTime * 60)
            record.floodSpeedRatio = floodRatio
            record.ebbSpeedRatio = ebbRatio
        }
        return record
    }
}
```

Implement `displayRegion(_:)` as `station.context ?? station.region ?? station.country ?? ""`. Reject non-accepted records from prediction conversion. Build identity and unavailable values from typed station metadata and quality reason. Map CHS cases by typed source/derived-current fields, then join current-gate fitting policy by ID.

- [ ] **Step 4: Run focused and model tests**

Run: `SLACKWATER_ONLY=SlackwaterTests/TCDBCatalogTests rtk test ./scripts/test.sh --unit`

Run: `SLACKWATER_ONLY=SlackwaterTests/WorldDefaultsTests rtk test ./scripts/test.sh --unit`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
rtk git add Slackwater/TCDBCatalog.swift Slackwater/TideStation.swift Slackwater/CurrentStation.swift Slackwater/StationIndex.swift SlackwaterTests/TCDBCatalogTests.swift
rtk git commit -m "Read tide and current records from TCDB"
```

### Task 6: Switch app and widget catalog lookup

**Files:**
- Modify: `Slackwater/CatalogSnapshot.swift`
- Modify: `Slackwater/CatalogStorage.swift`
- Modify: `Slackwater/WidgetStationLoader.swift`
- Modify: `Slackwater/StationIntent.swift`
- Modify: `project.yml`
- Modify: `SlackwaterTests/CatalogSnapshotTests.swift`
- Modify: `SlackwaterTests/CatalogStorageTests.swift`
- Modify: `SlackwaterTests/WidgetStationLoaderTests.swift`

**Interfaces:**
- Consumes: `TCDBCatalog` from Task 5.
- Produces: app and widget lookup through the bundle-only `slackwater.tcdb`; remaining generation loading is CHS policy/tombstones only.

- [ ] **Step 1: Change tests to treat TCDB as bundle-only**

Update snapshot/storage fixtures so active generations contain only remaining JSON policy/tombstone resources. Add these cases:

```swift
func testActiveGenerationDoesNotShadowBundledDatabase() throws {
    let active = try commitBundle(batch: UUID())
    XCTAssertFalse(FileManager.default.fileExists(
        atPath: active.directory.appendingPathComponent("slackwater.tcdb").path))
    XCTAssertNotNil(try TCDBCatalog(directory: storage.bundleDirectory).tideRecord(
        id: TideStationRecord.fridayHarborID))
}

func testWidgetReadsTideAndCurrentFromMappedDatabase() throws {
    let tide = try XCTUnwrap(StationItem.all.first { $0.series == .tide })
    let current = try XCTUnwrap(StationItem.all.first { $0.series == .current })
    XCTAssertNotNil(WidgetStationLoader.loadRecord(id: tide.id))
    XCTAssertNotNil(WidgetStationLoader.loadRecord(id: current.id))
}
```

- [ ] **Step 2: Run focused tests and verify failures use JSON paths**

Run: `SLACKWATER_ONLY=SlackwaterTests/CatalogStorageTests,SlackwaterTests/WidgetStationLoaderTests rtk test ./scripts/test.sh --unit`

Expected: FAIL because loaders still request `stations.json` and `currents.json` and active generations still list them.

- [ ] **Step 3: Route all tide/current lookup through `TCDBCatalog`**

Keep `CatalogFileLocator` directory pinning and fallback behavior for the remaining JSON generation. Open `TCDBCatalog` only from `storage.bundleDirectory` and inject it into snapshot/widget tests. Remove tide/current resources from active generation validation. Production refresh never reads a TCDB from staging or an active directory.

Replace widget JSON resources with `Slackwater/Resources/slackwater.tcdb` in the explicit extension resource list.

- [ ] **Step 4: Run catalog and widget tests**

Run: `SLACKWATER_ONLY=SlackwaterTests/CatalogSnapshotTests,SlackwaterTests/CatalogStorageTests,SlackwaterTests/WidgetStationLoaderTests rtk test ./scripts/test.sh --unit`

Expected: PASS, including missing record, missing reference, active-generation retry, and bundle fallback. Corrupt and wrong-identifier TCDB behavior remains owned by `TCDBCatalogTests` and the upstream reader tests.

- [ ] **Step 5: Commit**

```bash
rtk git add project.yml Slackwater/CatalogSnapshot.swift Slackwater/CatalogStorage.swift Slackwater/WidgetStationLoader.swift Slackwater/StationIntent.swift SlackwaterTests
rtk git commit -m "Use the mapped catalog in the app and widgets"
```

### Task 7: Replace slug JSON with TCDB routes

**Files:**
- Modify: `Slackwater/DeepLink.swift`
- Modify: `SlackwaterTests/StationLinkTests.swift`
- Delete: `Slackwater/Resources/slugs.json`
- Delete: `tools/gen-slugs.mjs`
- Delete: `tools/gen-slugs.test.mjs`

**Interfaces:**
- Consumes: `TCDBCatalog.stationRoute(kind:slug:)`, `stationRoutes(kind:)`.
- Produces: shared-link parsing and sharing without `SlugTable`.

- [ ] **Step 1: Rewrite route tests against the catalog API**

Add coverage for current/tide slug collision, former path, unknown slug, unavailable target, and a departed target. The former route test must assert the original ID and never accept another station sharing a display name.

- [ ] **Step 2: Run station-link tests and verify they fail while `SlugTable` remains**

Run: `SLACKWATER_ONLY=SlackwaterTests/StationLinkTests rtk test ./scripts/test.sh --unit`

Expected: FAIL because tests expect TCDB route behavior that `SlugTable` cannot provide.

- [ ] **Step 3: Implement route resolution**

Resolve incoming routes by key lookup. Build a lazy reverse map only for `shareURL`:

```swift
private static let routeByStationID: [StationRouteKind: [String: String]] = {
    let catalog = TCDBCatalog.bundled
    return Dictionary(uniqueKeysWithValues: [StationRouteKind.tide, .current].map { kind in
        let pairs = catalog.stationRoutes(kind: kind).flatMap { route in
            route.stationIDs.map { ($0, route.slug) }
        }
        return (kind, Dictionary(pairs, uniquingKeysWith: { first, _ in first }))
    })
}()
```

Keep tide/current namespaces separate. For incoming current IDs, apply the existing `current:` UI prefix only when looking up `StationItem`.

- [ ] **Step 4: Run station-link tests**

Run: `SLACKWATER_ONLY=SlackwaterTests/StationLinkTests rtk test ./scripts/test.sh --unit`

Expected: PASS.

- [ ] **Step 5: Delete slug generator and resource, then commit**

```bash
rtk git add Slackwater/DeepLink.swift SlackwaterTests/StationLinkTests.swift Slackwater/Resources tools
rtk git commit -m "Read station routes from TCDB"
```

### Task 8: Normalize persisted namesake choices

**Files:**
- Modify: `Slackwater/Theme.swift`
- Modify: `SlackwaterTests/WorldDefaultsTests.swift`

**Interfaces:**
- Consumes: stored `[placeKey: stationID]`, `StationItem.byId`.
- Produces: `ChosenStationsStore.normalized(_:) -> [String: String]`.

- [ ] **Step 1: Write a failing rename migration test**

```swift
func testChosenStationRekeysFromStoredIDAfterRename() throws {
    let station = try XCTUnwrap(StationItem.all.first)
    let stored = ["tide|Former name": station.id]
    XCTAssertEqual(ChosenStationsStore.normalized(stored), [station.placeKey: station.id])
}
```

Also assert missing IDs are discarded and two stale keys resolving to one current place produce one deterministic value.

- [ ] **Step 2: Run the focused test and verify failure**

Run: `SLACKWATER_ONLY=SlackwaterTests/WorldDefaultsTests/testChosenStationRekeysFromStoredIDAfterRename rtk test ./scripts/test.sh --unit`

Expected: FAIL because `normalized` does not exist.

- [ ] **Step 3: Implement normalization at load and cloud adoption**

```swift
static func normalized(_ stored: [String: String]) -> [String: String] {
    Dictionary(stored.values.compactMap { id in
        StationItem.byId[id].map { ($0.placeKey, id) }
    }, uniquingKeysWith: { first, _ in first })
}
```

Use the function for local initialization and cloud picks. Persist the normalized local dictionary once when it differs.

- [ ] **Step 4: Run world-default and favorites tests**

Run: `SLACKWATER_ONLY=SlackwaterTests/WorldDefaultsTests rtk test ./scripts/test.sh --unit`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
rtk git add Slackwater/Theme.swift SlackwaterTests/WorldDefaultsTests.swift
rtk git commit -m "Keep namesake choices across station renames"
```

### Task 9: Remove runtime JSON paths and verify the cutover

**Files:**
- Delete: `Slackwater/Resources/stations.json`
- Delete: `Slackwater/Resources/currents.json`
- Delete: `Slackwater/Resources/station-index.json`
- Delete: `Slackwater/Resources/unavailable-stations.json`
- Delete: obsolete JSON tests and scanner code from `Slackwater/CatalogSnapshot.swift`, `Slackwater/CurrentStation.swift`, and `Slackwater/StationIndex.swift`
- Modify: `Slackwater/Resources/README.md`
- Modify: `scripts/test.sh`
- Modify: affected catalog tests.

**Interfaces:**
- Consumes: green Tasks 1-8.
- Produces: one runtime station database with no tide/current/index/slug JSON fallback.

- [ ] **Step 1: Add a resource-completeness test**

```swift
func testRuntimeCatalogResourcesAreTCDBOnly() throws {
    XCTAssertNotNil(Bundle.main.url(forResource: "slackwater", withExtension: "tcdb"))
    for name in ["stations", "currents", "station-index", "slugs", "unavailable-stations"] {
        XCTAssertNil(Bundle.main.url(forResource: name, withExtension: "json"))
    }
}
```

- [ ] **Step 2: Run it and verify the legacy resources are still found**

Run: `SLACKWATER_ONLY=SlackwaterTests/DatabaseDependencyTests/testRuntimeCatalogResourcesAreTCDBOnly rtk test ./scripts/test.sh --unit`

Expected: FAIL because JSON resources still exist.

- [ ] **Step 3: Delete JSON resources and dead decoding paths**

Remove `readCatalog` use for tide/current records, `decodeCatalogRecord`, `catalogRecord`, `StationIndex.bundled`, and resource-list references that exist only for the four deleted files. Keep generic JSON decoding for CHS policy, tombstones, saved fits, and unrelated resources.

- [ ] **Step 4: Run all data and unit tests offline**

Run: `rtk npm test`

Run: `rtk test ./scripts/test.sh --unit`

Expected: PASS. Report every skipped live-network test by name.

- [ ] **Step 5: Build app and widget**

Run: `rtk xcodebuild build -scheme Slackwater -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`

Expected: BUILD SUCCEEDED for app and embedded widget extension.

- [ ] **Step 6: Record release measurements**

Measure the same Release build and simulator/device for cold database open, identity scan, first/repeated tide lookup, first/repeated current lookup, widget lookup, and resident memory. Add the numbers to issue #469 without attributing distance-sort or unrelated launch work.

- [ ] **Step 7: Commit**

```bash
rtk git add Slackwater SlackwaterTests scripts project.yml
rtk git commit -m "Remove the JSON station catalogs"
```

- [ ] **Step 8: Request whole-branch review**

Review against issue #469 and the design spec. Block completion on ID loss, restricted prediction leakage, route reassignment, current missing-value collapse, widget regression, or unreported parity differences.
