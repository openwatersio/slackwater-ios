# Catalog Storage and Widget Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist validated catalog generations atomically, let widgets read one pinned generation with bundle fallback, and stop bundled catalog failures from silently becoming zero stations.

**Architecture:** Add one synchronous Foundation-backed `CatalogStorage` value that owns the App Group directory, immutable generation folders, metadata, and the atomic `current` pointer. A small `CatalogFileLocator` pins one directory for an entire widget lookup and retries once only when reading that directory fails; app-wide live activation and networking remain later slices.

**Tech Stack:** Swift 6, Foundation file APIs, `os.Logger`, XCTest, existing App Group and catalog decoders; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-05-catalog-refresh-design.md`

## Global Constraints

- Base this stacked slice on `feat/catalog-validation` / commit `d3b61c6` from draft PR #285.
- Store catalogs only below `AppGroup.container/Catalogs`; never mutate bundled resources.
- A generation directory is immutable after its `current` pointer is published.
- Validate all six files before moving staging into a generation or replacing `current`.
- A missing record is a valid result and must not fall back to an older bundled record; only lookup, read, or decode failure triggers retry/fallback.
- Widget code never instantiates the future main-actor `CatalogStore`, performs network work, or decodes complete NOAA catalogs.
- Use the existing compact scanner for `stations.json` and `currents.json`; decode the four small CHS files whole.
- Log corrupt active/downloaded data without catalog contents or user data. A bundled catalog failure also asserts in debug and terminates instead of returning `[]`.
- Do not add network refresh, observable generation publication, cache invalidation, generator changes, or Worker deployment in this slice.

---

### Task 1: Immutable generation storage

**Files:**
- Create: `Slackwater/CatalogStorage.swift`
- Create: `SlackwaterTests/CatalogStorageTests.swift`

**Interfaces:**
- Consumes: `CatalogSnapshot.init(directory:active:)`, `CatalogSnapshot.resources`, and `AppGroup.container`.
- Produces: `CatalogMetadata`, `StoredCatalogGeneration`, and `CatalogStorage` with the exact API below.

- [ ] **Step 1: Write failing storage tests**

Create `CatalogStorageTests` with a fresh temporary root and bundled-resource directory. Copy the six bundled files into `storage.stagingDirectory(for:)` and cover these outcomes:

```swift
func testCommitPublishesValidatedGenerationAndMetadata() throws {
    let batch = UUID()
    let staging = try storage.prepareStaging(for: batch)
    try copyCatalogs(to: staging)
    let etags = Dictionary(uniqueKeysWithValues: CatalogSnapshot.resources.map { ($0, "etag-\($0)") })

    let committed = try storage.commit(batch: batch, etags: etags, active: nil)

    XCTAssertEqual(try String(contentsOf: storage.currentURL, encoding: .utf8), committed.name)
    XCTAssertEqual(try storage.loadActive(active: nil)?.metadata.etags, etags)
    XCTAssertEqual(try storage.loadActive(active: nil)?.snapshot.byID.count,
                   committed.snapshot.byID.count)
}

func testInvalidStagingNeverReplacesCurrent() throws {
    let original = try commitBundle(batch: UUID())
    let badBatch = UUID()
    let staging = try storage.prepareStaging(for: badBatch)
    try copyCatalogs(to: staging)
    try Data("broken".utf8).write(to: staging.appendingPathComponent("stations.json"))

    XCTAssertThrowsError(try storage.commit(batch: badBatch, etags: [:], active: original.snapshot))
    XCTAssertEqual(try String(contentsOf: storage.currentURL, encoding: .utf8), original.name)
}

func testOrphanGenerationDoesNotChangeCurrent() throws {
    let original = try commitBundle(batch: UUID())
    let orphan = storage.root.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)

    XCTAssertEqual(try storage.loadActive(active: nil)?.name, original.name)
}

func testCorruptPointerIsNamedError() throws {
    try FileManager.default.createDirectory(at: storage.root, withIntermediateDirectories: true)
    try Data("../outside".utf8).write(to: storage.currentURL)
    XCTAssertThrowsError(try storage.activeDirectory()) { error in
        XCTAssertEqual(error as? CatalogStorageError, .invalidCurrentPointer)
    }
}

func testCorruptMetadataIsNamedError() throws {
    let committed = try commitBundle(batch: UUID())
    try Data("broken".utf8).write(to: committed.directory.appendingPathComponent("metadata.json"))
    XCTAssertThrowsError(try storage.loadActive(active: nil)) { error in
        XCTAssertEqual(error as? CatalogStorageError, .invalidMetadata)
    }
}
```

The helper `copyCatalogs(to:)` must copy `CatalogSnapshot.resources` from `Bundle.main`; `commitBundle(batch:)` prepares staging, copies those files, and calls `commit`.

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
rtk xcodegen generate
rtk proxy lockf /tmp/slackwater-test.lock xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages -only-testing:SlackwaterTests/CatalogStorageTests
```

Expected: FAIL because `CatalogStorage`, `CatalogMetadata`, and `StoredCatalogGeneration` do not exist.

- [ ] **Step 3: Implement the minimal storage types**

Create `Slackwater/CatalogStorage.swift` with these concrete types and operations:

```swift
import Foundation
import os

struct CatalogMetadata: Codable, Equatable {
    let etags: [String: String]
}

struct StoredCatalogGeneration {
    let name: String
    let directory: URL
    let metadata: CatalogMetadata
    let snapshot: CatalogSnapshot
}

enum CatalogStorageError: Error, Equatable {
    case invalidCurrentPointer
    case missingGeneration(String)
    case invalidMetadata
}

struct CatalogStorage {
    static let shared = CatalogStorage(
        root: AppGroup.container.appendingPathComponent("Catalogs", isDirectory: true),
        bundleDirectory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)

    let root: URL
    let bundleDirectory: URL
    private let files = FileManager.default

    init(root: URL, bundleDirectory: URL) {
        self.root = root
        self.bundleDirectory = bundleDirectory
    }

    var currentURL: URL { root.appendingPathComponent("current") }

    func stagingDirectory(for batch: UUID) -> URL {
        root.appendingPathComponent("staging-\(batch.uuidString.lowercased())", isDirectory: true)
    }

    func prepareStaging(for batch: UUID) throws -> URL {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = stagingDirectory(for: batch)
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    func activeDirectory() throws -> URL? {
        guard files.fileExists(atPath: currentURL.path) else { return nil }
        let name = try String(contentsOf: currentURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: name) != nil else { throw CatalogStorageError.invalidCurrentPointer }
        let directory = root.appendingPathComponent(name, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CatalogStorageError.missingGeneration(name)
        }
        return directory
    }

    func loadActive(active: CatalogSnapshot?) throws -> StoredCatalogGeneration? {
        guard let directory = try activeDirectory() else { return nil }
        let metadataURL = directory.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(CatalogMetadata.self, from: data) else {
            throw CatalogStorageError.invalidMetadata
        }
        return StoredCatalogGeneration(
            name: directory.lastPathComponent,
            directory: directory,
            metadata: metadata,
            snapshot: try CatalogSnapshot(directory: directory, active: active))
    }

    func commit(batch: UUID, etags: [String: String], active: CatalogSnapshot?) throws -> StoredCatalogGeneration {
        let staging = stagingDirectory(for: batch)
        let snapshot = try CatalogSnapshot(directory: staging, active: active)
        let metadata = CatalogMetadata(etags: etags)
        try JSONEncoder().encode(metadata).write(
            to: staging.appendingPathComponent("metadata.json"), options: .atomic)
        let name = batch.uuidString.lowercased()
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try files.moveItem(at: staging, to: directory)
        try Data(name.utf8).write(to: currentURL, options: .atomic)
        return StoredCatalogGeneration(name: name, directory: directory,
                                       metadata: metadata, snapshot: snapshot)
    }
}
```

Keep cleanup out of this task. Activation can leave small immutable orphans safely; a later refresh task can delete them only after the widget retry semantics exist.

- [ ] **Step 4: Run the focused storage tests**

Run the Step 2 command again.

Expected: PASS for every `CatalogStorageTests` case.

- [ ] **Step 5: Commit the storage boundary**

```bash
rtk git add Slackwater/CatalogStorage.swift SlackwaterTests/CatalogStorageTests.swift Slackwater.xcodeproj/project.pbxproj
rtk git commit -m "feat: persist validated catalog generations"
```

---

### Task 2: Pinned lookup and retry policy

**Files:**
- Modify: `Slackwater/CatalogStorage.swift`
- Modify: `SlackwaterTests/CatalogStorageTests.swift`

**Interfaces:**
- Consumes: `CatalogStorage.activeDirectory()` and `CatalogStorage.bundleDirectory` from Task 1.
- Produces: `CatalogFileLocator.shared` and `CatalogFileLocator.load(_:) -> T?`.

- [ ] **Step 1: Write failing locator tests**

Add tests that pass a closure recording each attempted directory:

```swift
func testLocatorPinsOneDirectoryForAllReads() throws {
    let active = try commitBundle(batch: UUID())
    var directories: [URL] = []
    let result: String? = CatalogFileLocator(storage: storage).load { directory in
        directories += [directory, directory]
        _ = try Data(contentsOf: directory.appendingPathComponent("stations.json"))
        _ = try Data(contentsOf: directory.appendingPathComponent("currents.json"))
        return "ok"
    }
    XCTAssertEqual(result, "ok")
    XCTAssertEqual(Set(directories), [active.directory])
}

func testMissingRecordDoesNotResurrectBundledRecord() throws {
    _ = try commitBundle(batch: UUID())
    var attempts = 0
    let result: String? = CatalogFileLocator(storage: storage).load { _ in
        attempts += 1
        return nil
    }
    XCTAssertNil(result)
    XCTAssertEqual(attempts, 1)
}

func testFailedPinnedReadRetriesNewGenerationThenBundle() throws {
    let old = try commitBundle(batch: UUID())
    var attempted: [URL] = []
    let locator = CatalogFileLocator(storage: storage)
    let result: String? = locator.load { directory in
        attempted.append(directory)
        if directory == old.directory {
            _ = try self.commitBundle(batch: UUID())
            try FileManager.default.removeItem(at: old.directory)
            throw CatalogStorageError.missingGeneration(old.name)
        }
        return directory.lastPathComponent
    }
    XCTAssertEqual(result, try storage.activeDirectory()?.lastPathComponent)
    XCTAssertEqual(attempted.count, 2)
}

func testFailedActiveAndRetryReadsFallBackToBundle() throws {
    let active = try commitBundle(batch: UUID())
    var activeAttempts = 0
    let result: URL? = CatalogFileLocator(storage: storage).load { directory in
        if directory == storage.bundleDirectory { return directory }
        activeAttempts += 1
        if directory == active.directory { _ = try self.commitBundle(batch: UUID()) }
        throw CatalogStorageError.missingGeneration(active.name)
    }
    XCTAssertEqual(result, storage.bundleDirectory)
    XCTAssertEqual(activeAttempts, 2)
}

func testInvalidInitialPointerFallsBackToBundle() throws {
    try FileManager.default.createDirectory(at: storage.root, withIntermediateDirectories: true)
    try Data("invalid".utf8).write(to: storage.currentURL)
    let result: URL? = CatalogFileLocator(storage: storage).load { $0 }
    XCTAssertEqual(result, storage.bundleDirectory)
}

func testInvalidRetryPointerFallsBackToBundle() throws {
    let active = try commitBundle(batch: UUID())
    let result: URL? = CatalogFileLocator(storage: storage).load { directory in
        if directory == storage.bundleDirectory { return directory }
        try Data("invalid".utf8).write(to: storage.currentURL)
        throw CatalogStorageError.missingGeneration(active.name)
    }
    XCTAssertEqual(result, storage.bundleDirectory)
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run the focused command from Task 1.

Expected: FAIL because `CatalogFileLocator` does not exist.

- [ ] **Step 3: Implement one pinned attempt, one changed-generation retry, then bundle fallback**

Add this value to `CatalogStorage.swift`:

```swift
struct CatalogFileLocator {
    static let shared = CatalogFileLocator(storage: .shared)
    let storage: CatalogStorage

    func load<T>(_ body: (URL) throws -> T?) -> T? {
        let first: URL?
        do { first = try storage.activeDirectory() }
        catch {
            CatalogDiagnostics.log(error)
            first = nil
        }
        if let first {
            do { return try body(first) }
            catch {
                CatalogDiagnostics.log(error)
                do {
                    if let retry = try storage.activeDirectory(), retry != first {
                        do { return try body(retry) }
                        catch { CatalogDiagnostics.log(error) }
                    }
                } catch {
                    CatalogDiagnostics.log(error)
                }
            }
        }
        do { return try body(storage.bundleDirectory) }
        catch {
            CatalogDiagnostics.log(error)
            return nil
        }
    }
}

enum CatalogDiagnostics {
    private static let logger = Logger(subsystem: "org.openwaters.slackwater", category: "Catalog")

    static func log(_ error: Error) {
        logger.error("Catalog load failed: \(String(describing: error), privacy: .public)")
    }
}
```

Do not retry when `body` returns `nil`; that means the pinned generation validly does not contain the requested station.

- [ ] **Step 4: Run the focused storage tests**

Run the Task 1 focused command.

Expected: PASS, including exactly one retry only when `current` changes.

- [ ] **Step 5: Commit the locator**

```bash
rtk git add Slackwater/CatalogStorage.swift SlackwaterTests/CatalogStorageTests.swift
rtk git commit -m "feat: pin widget catalog lookups to one generation"
```

---

### Task 3: Widget reads active generations without mixing references

**Files:**
- Modify: `Slackwater/CurrentStation.swift`
- Modify: `Slackwater/StationIntent.swift`
- Modify: `Slackwater/WidgetStationLoader.swift`
- Modify: `SlackwaterTests/WidgetStationLoaderTests.swift`
- Modify: `project.yml`
- Modify: `Slackwater.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CatalogFileLocator.load(_:)` from Task 2 and `readCatalog(_:directory:)` / `decodeCatalogRecord(_:id:)` from PR #285.
- Produces: `catalogRecord(_:id:directory:)`, `StationItem.widgetItem(id:directory:)`, and `WidgetStationLoader.loadRecord(id:locator:)`.

- [ ] **Step 1: Write failing widget-generation tests**

Add test helpers that commit a copy of the shipped files under a temporary `CatalogStorage`. Add these cases:

```swift
func testWidgetReadsCorrectedActiveStation() throws {
    let storage = try makeStorage { directory in
        try editStation(TideStationRecord.fridayHarborID, in: directory) { $0["name"] = "Remote Friday Harbor" }
    }
    let record = try XCTUnwrap(WidgetStationLoader.loadRecord(
        id: TideStationRecord.fridayHarborID,
        locator: CatalogFileLocator(storage: storage)))
    guard case .tide(let tide, _) = record else { return XCTFail("Expected tide") }
    XCTAssertEqual(tide.name, "Remote Friday Harbor")
}

func testWidgetDoesNotFallBackWhenStationWasRemoved() throws {
    let bundled = try CatalogSnapshot(directory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
    let referenced = Set(bundled.tides.compactMap(\.reference))
        .union(bundled.currents.compactMap(\.tideReference))
    let removed = try XCTUnwrap(bundled.tides.first { !referenced.contains($0.id) })
    let storage = try makeStorage { directory in
        try removeStation(removed.id, from: directory)
        try appendTombstone(removed.id, to: directory)
    }
    XCTAssertNil(WidgetStationLoader.loadRecord(
        id: removed.id,
        locator: CatalogFileLocator(storage: storage)))
}

func testSubordinateCurrentAndReferenceUseSameGeneration() throws {
    let subordinate = try XCTUnwrap(CurrentStationRecord.all.first(where: \.isSubordinate))
    let storage = try makeStorage { directory in
        try scaleCurrentConstituents(subordinate.reference!, by: 2, in: directory)
    }
    let record = try XCTUnwrap(WidgetStationLoader.loadRecord(
        id: "current:" + subordinate.id,
        locator: CatalogFileLocator(storage: storage)))
    guard case .current(let current, let station) = record else { return XCTFail("Expected current") }
    let directory = try XCTUnwrap(storage.activeDirectory())
    let activeReference: CurrentStationRecord? = try catalogRecord(
        "currents", id: subordinate.reference!, directory: directory)
    let start = Date(timeIntervalSince1970: 1_750_000_000)
    let end = start + 6 * 3600
    let actual = station.speeds(from: start, to: end, step: 60).map(\.speed)
    let expected = current.engineStation(referenceRecord: activeReference)
        .speeds(from: start, to: end, step: 60).map(\.speed)
    let bundled = try XCTUnwrap(CurrentStationRecord.byId[subordinate.reference!])
    let stale = current.engineStation(referenceRecord: bundled)
        .speeds(from: start, to: end, step: 60).map(\.speed)
    XCTAssertEqual(actual.count, expected.count)
    XCTAssertTrue(zip(actual, expected).allSatisfy { abs($0 - $1) < 0.000_001 })
    XCTAssertTrue(zip(actual, stale).contains { abs($0 - $1) > 0.000_001 })
}

func testWidgetReadsEverySmallGeneratedCatalogThroughActiveDirectory() throws {
    let storage = try makeStorage()
    let directory = try XCTUnwrap(storage.activeDirectory())
    for id in [ChsStationInfo.all[0].id, ChsGateInfo.all[0].id, ChsCurrentGateInfo.all[0].id] {
        XCTAssertNotNil(try StationItem.widgetItem(id: id, directory: directory))
    }
    let tombstones: [StationTombstone] = try readCatalog("chs-tombstones", directory: directory)
    XCTAssertFalse(tombstones.isEmpty)
}

func testLocatorBackedWidgetIdentityUsesActiveCatalog() throws {
    let bundled = try CatalogSnapshot(directory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
    let removed = try XCTUnwrap(bundled.tides.first)
    let addedID = "999999999"
    let storage = try makeStorage { directory in
        try appendStation(copying: removed.id, as: addedID, name: "Remote only", in: directory)
        try removeStation(removed.id, from: directory)
        try appendTombstone(removed.id, to: directory)
    }
    let locator = CatalogFileLocator(storage: storage)
    XCTAssertEqual(StationItem.widgetItem(id: addedID, locator: locator)?.name, "Remote only")
    XCTAssertNil(StationItem.widgetItem(id: removed.id, locator: locator))
}

func testCorruptActiveNOAAFileFallsBackToBundle() throws {
    let storage = try makeStorage()
    let directory = try XCTUnwrap(storage.activeDirectory())
    try Data("broken".utf8).write(to: directory.appendingPathComponent("stations.json"))
    let record = try XCTUnwrap(WidgetStationLoader.loadRecord(
        id: TideStationRecord.fridayHarborID,
        locator: CatalogFileLocator(storage: storage)))
    guard case .tide(let tide, _) = record else { return XCTFail("Expected tide") }
    XCTAssertEqual(tide.name, TideStationRecord.byId[TideStationRecord.fridayHarborID]?.name)
}

func testTruncatedActiveNOAAFileEndingAtNestedArrayFallsBackToBundle() throws {
    let storage = try makeStorage()
    let directory = try XCTUnwrap(storage.activeDirectory())
    try Data(#"[{"id":"first","aliases":[]"#.utf8)
        .write(to: directory.appendingPathComponent("stations.json"))
    XCTAssertNotNil(WidgetStationLoader.loadRecord(
        id: TideStationRecord.fridayHarborID,
        locator: CatalogFileLocator(storage: storage)))
}

func testCompactScannerRejectsInvalidOuterGrammar() throws {
    for (bytes, id) in [
        (#"[{"id":"first"}][]"#, "missing"),
        (#"[{"id":"first"},garbage]"#, "missing"),
        (#"{"id":"first"}]"#, "first"),
    ] {
        XCTAssertThrowsError(
            try decodeCatalogRecord(Data(bytes.utf8), id: id) as TideStationRecord?)
    }
}
```

The helper mutations must preserve compact id-first formatting for the two NOAA files, using the existing JSON rewrite helper pattern in `CatalogSnapshotTests`.
`scaleCurrentConstituents(_:by:in:)` rewrites the named reference row and
multiplies each constituent amplitude by the supplied factor.

- [ ] **Step 2: Run the widget tests to verify they fail**

Run:

```bash
rtk xcodegen generate
rtk proxy lockf /tmp/slackwater-test.lock xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages -only-testing:SlackwaterTests/WidgetStationLoaderTests
```

Expected: FAIL because widget lookup has no locator injection and still reads bundle globals.

- [ ] **Step 3: Parameterize record loading by one directory**

In `CurrentStation.swift`, keep the compact decoder and add:

```swift
func catalogRecord<T: Decodable & StationIdentity>(
    _ resource: String, id: String, directory: URL
) throws -> T? {
    let url = directory.appendingPathComponent(resource + ".json")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CatalogError(resource: resource, stage: .lookup, reason: "file missing")
    }
    let data: Data
    do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
    catch { throw CatalogError(resource: resource, stage: .read, reason: "unable to read file") }
    do { return try decodeCatalogRecord(data, id: id) }
    catch { throw CatalogError(resource: resource, stage: .decode, reason: "invalid catalog record") }
}

static func widgetItem(id: String, directory: URL) throws -> StationItem? {
    if id.hasPrefix("current:") {
        let record: CurrentStationRecord? = try catalogRecord(
            "currents", id: String(id.dropFirst("current:".count)), directory: directory)
        return record.map(StationItem.current)
    }
    if id.hasPrefix("chs-") {
        let stations: [ChsStationInfo] = try readCatalog("chs-stations", directory: directory)
        if let record = stations.first(where: { $0.id == id }) { return .chs(record) }
        let gates: [ChsGateInfo] = try readCatalog("chs-gates", directory: directory)
        if let record = gates.first(where: { $0.id == id }) { return .chsGate(record) }
        let currents: [ChsCurrentGateInfo] = try readCatalog("chs-current-gates", directory: directory)
        return currents.first(where: { $0.id == id }).map(StationItem.chsCurrent)
    }
    let record: TideStationRecord? = try catalogRecord("stations", id: id, directory: directory)
    return record.map(StationItem.tide)
}

static func widgetItem(
    id: String, locator: CatalogFileLocator = .shared
) -> StationItem? {
    locator.load { directory in try widgetItem(id: id, directory: directory) }
}
```

Before returning `nil` for a missing compact NOAA record, `decodeCatalogRecord`
must scan the bytes with a small delimiter/string-state check: the outer array,
every nested object/array, and every quoted string must close in the right order,
the outer array must remain open until the final byte, and every non-empty
top-level element must be a comma-separated record beginning with the exact
`{"id":"` prefix. Reject a second root, leading/trailing commas, and unquoted
top-level garbage. This catches truncation that ends at a nested `]` without
materializing the NOAA array. Keep the constant-time first-`[`/last-`]` guard
before marker lookup so malformed marker hits still throw. Run the O(n) state
scan only when the requested marker is absent; successful lookups otherwise keep
the compact scanner's existing cost. Malformed bytes throw so `catalogRecord`
reports `.decode` and the locator can fall back; a structurally complete catalog
without the requested marker remains `nil`.
Replace the old bundle-only `widgetItem(id:)` implementation with the
locator-backed forwarder above.

Do not make the scanner whitespace-independent; PR #285 already validates the generated NOAA format, while the small pretty-printed catalogs use whole decode.

- [ ] **Step 4: Keep current references inside the pinned lookup**

Change `CurrentStationRecord` to mirror the existing tide API:

```swift
var engineStation: any CurrentPredicting {
    engineStation(referenceRecord: referenceRecord)
}

func engineStation(referenceRecord: CurrentStationRecord?) -> any CurrentPredicting {
    guard reference != nil, let ref = referenceRecord else { return harmonicStation }
    return SubordinateStation(
        reference: ref.harmonicStation,
        slackBeforeFloodOffset: slackBeforeFloodOffset ?? 0,
        slackBeforeEbbOffset: slackBeforeEbbOffset ?? 0,
        floodTimeOffset: floodTimeOffset ?? 0,
        ebbTimeOffset: ebbTimeOffset ?? 0,
        floodSpeedRatio: floodSpeedRatio ?? 1,
        ebbSpeedRatio: ebbSpeedRatio ?? 1,
        floodDirection: floodDirection,
        ebbDirection: ebbDirection)
}
```

Change `WidgetRecord.current` to carry the already-resolved predictor:

```swift
case current(CurrentStationRecord, station: any CurrentPredicting)
```

Wrap all of `WidgetStationLoader.loadRecord` in one locator call and pass its directory through tide/current reference and derived-CHS reference reads:

```swift
static func loadRecord(
    id: String, locator: CatalogFileLocator = .shared
) -> WidgetRecord? {
    locator.load { directory in try loadRecord(id: id, directory: directory) }
}

private static func loadRecord(id: String, directory: URL) throws -> WidgetRecord? {
    guard let item = try StationItem.widgetItem(id: id, directory: directory) else { return nil }
    switch item {
    case .tide(let record):
        let reference: TideStationRecord? = try record.reference.flatMap {
            try catalogRecord("stations", id: $0, directory: directory)
        }
        return .tide(record, station: record.engineStation(referenceRecord: reference))
    case .current(let record):
        let reference: CurrentStationRecord? = try record.reference.flatMap {
            try catalogRecord("currents", id: $0, directory: directory)
        }
        return .current(record, station: record.engineStation(referenceRecord: reference))
    case .chs(let info):
        guard let model = ChsModelStore.load(info.id) else { return nil }
        let record = info.record(with: model)
        return .tide(record, station: record.harmonicStation)
    case .chsGate(let gate):
        return try derivedRecord(for: gate, directory: directory)
    case .chsCurrent(let info):
        return fittedCurrentRecord(for: info).map {
            .current($0, station: $0.harmonicStation)
        }
    }
}
```

Update `station(from:)` to return the carried current predictor. Update `derivedRecord` to read `chs-stations.json` from the passed directory rather than `ChsStationInfo.all`.

Add `Slackwater/CatalogSnapshot.swift` and `Slackwater/CatalogStorage.swift` to the widget target's explicit source list in `project.yml`, then regenerate the Xcode project.

Give `StationQuery` a defaulted locator so its favorites/recents suggestions and
entity resolution use the same locator-backed identity lookup and remain
injectable in tests. Give `WidgetStationLoader.resolvedStationID` the same
defaulted locator parameter so an active-only cached station is accepted and a
tombstoned cached station is rejected. Add focused caller tests for both cases.

- [ ] **Step 5: Run widget tests and compile both targets**

Run the Step 2 command, then:

```bash
rtk proxy lockf /tmp/slackwater-test.lock xcodebuild build -project Slackwater.xcodeproj -scheme Slackwater -destination 'generic/platform=iOS Simulator' -clonedSourcePackagesDirPath build/SourcePackages
```

Expected: widget tests PASS and both app/widget targets compile.

- [ ] **Step 6: Commit widget generation loading**

```bash
rtk git add Slackwater/CurrentStation.swift Slackwater/StationIntent.swift Slackwater/WidgetStationLoader.swift SlackwaterTests/WidgetStationLoaderTests.swift project.yml Slackwater.xcodeproj/project.pbxproj
rtk git commit -m "feat: load widget stations from active catalogs"
```

---

### Task 4: Remove silent bundled catalog failure

**Files:**
- Modify: `Slackwater/CurrentStation.swift`
- Modify: `SlackwaterTests/CatalogSnapshotTests.swift`

**Interfaces:**
- Consumes: throwing `readCatalog(_:directory:)` and `CatalogDiagnostics.log(_:)`.
- Produces: `requiredCatalog(_:directory:) throws -> [T]` and a `bundled(_:)` wrapper that cannot return an invented empty array.

- [ ] **Step 1: Add the regression assertion for #234's shared boundary**

Add a named-error test beside the existing malformed-file coverage:

```swift
func testRequiredCatalogNeverConvertsFailureToEmpty() throws {
    let missing = directory.appendingPathComponent("missing", isDirectory: true)
    XCTAssertThrowsError(
        try requiredCatalog("stations", directory: missing) as [TideStationRecord]
    ) { error in
        let catalog = error as? CatalogError
        XCTAssertEqual(catalog?.resource, "stations")
        XCTAssertEqual(catalog?.stage, .lookup)
    }
}
```

- [ ] **Step 2: Run the focused regression test and verify failure**

Run:

```bash
rtk xcodegen generate
rtk proxy lockf /tmp/slackwater-test.lock xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages -only-testing:SlackwaterTests/CatalogSnapshotTests/testRequiredCatalogNeverConvertsFailureToEmpty
```

Expected: FAIL because `requiredCatalog` does not exist.

- [ ] **Step 3: Route bundle loading through the throwing boundary**

In `CurrentStation.swift`:

```swift
func requiredCatalog<T: Decodable & StationIdentity>(
    _ resource: String, directory: URL
) throws -> [T] {
    try readCatalog(resource, directory: directory)
}

func bundled<T: Decodable & StationIdentity>(_ resource: String) -> [T] {
    do {
        return try requiredCatalog(resource, directory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
    } catch {
        CatalogDiagnostics.log(error)
        assertionFailure(String(describing: error))
        preconditionFailure(String(describing: error))
    }
}
```

Keep the throwing helper testable; do not try to unit-test the deliberate process termination. The shipped six-file validation test and CI prevent that terminal path from reaching a release.

- [ ] **Step 4: Run focused catalog and widget tests**

Run:

```bash
rtk proxy lockf /tmp/slackwater-test.lock xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages -only-testing:SlackwaterTests/CatalogSnapshotTests -only-testing:SlackwaterTests/CatalogStorageTests -only-testing:SlackwaterTests/WidgetStationLoaderTests
```

Expected: all focused tests PASS and no catalog loader contains `return []` as an error path.

- [ ] **Step 5: Commit the #234 guard**

```bash
rtk git add Slackwater/CurrentStation.swift SlackwaterTests/CatalogSnapshotTests.swift
rtk git commit -m "fix: surface bundled catalog failures"
```

---

### Task 5: Verify and publish the stacked slice

**Files:**
- Modify: `docs/superpowers/plans/2026-09-05-catalog-storage-widget-loading.md`
- Modify: `docs/superpowers/specs/2026-09-05-catalog-refresh-design.md`

**Interfaces:**
- Consumes: all Task 1–4 commits.
- Produces: one reviewable branch based on `feat/catalog-validation`.

- [ ] **Step 1: Record the reviewed historical-tombstone rule**

Keep the already-prepared spec edit that requires every active tombstone to persist unless its exact ID becomes live again, and keep its regression-test bullet. This matches `CatalogSnapshot`'s existing union of active live IDs and active tombstone IDs.

- [ ] **Step 2: Run the repository fast suite**

Run:

```bash
rtk test ./scripts/test.sh
```

Expected: the fast suite completes with zero failures. The script owns `/tmp/slackwater-test.lock`; wait for the active CI run instead of starting a second `xcodebuild` outside that lock.

- [ ] **Step 3: Verify the final diff**

Run:

```bash
rtk git diff --check feat/catalog-validation..HEAD
rtk git status --short
rtk git log --oneline feat/catalog-validation..HEAD
```

Expected: no whitespace errors, only intended files, and the storage/locator/widget/#234 commits listed.

- [ ] **Step 4: Commit plan/spec bookkeeping if still uncommitted**

```bash
rtk git add docs/superpowers/plans/2026-09-05-catalog-storage-widget-loading.md docs/superpowers/specs/2026-09-05-catalog-refresh-design.md
rtk git commit -m "docs: plan catalog storage and widget loading"
```

- [ ] **Step 5: Push and open a stacked draft PR**

```bash
rtk git push -u origin feat/catalog-storage
rtk gh pr create --repo openwatersio/slackwater-ios --base feat/catalog-validation --head feat/catalog-storage --draft --title "Persist remote catalog generations" --body $'## What and why\n\nPersist validated catalog generations atomically and let widgets read one pinned active generation with bundle fallback. This stacked slice also removes the silent zero-station bundle failure from #234.\n\n## Testing\n\n- [x] Focused catalog storage and widget-loader tests\n- [x] App and widget targets compile\n- [x] ./scripts/test.sh\n\n## Notes for the reviewer\n\nStacked on PR #285. Network refresh, live app generation publication, cache invalidation, generator changes, and Worker deployment remain later slices.'
```

Do not mark ready until PR #285 and this branch's app CI both complete.
