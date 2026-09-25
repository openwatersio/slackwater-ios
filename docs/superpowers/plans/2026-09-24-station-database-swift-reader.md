# Station database Swift reader implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a brand-neutral Swift API that reads tide/current records, structured identity, licensing, and stable routes from one mapped TCDB.

**Architecture:** Extend the existing zero-copy Swift wrapper in `openwatersio/slackwater-database`; generated FlatBuffers accessors remain private implementation detail. `StationDatabase` owns the mapped root, `Station` exposes typed values, and route lookups use the generated key lookup without materializing the route vector.

**Tech Stack:** Swift 5.9, Swift Package Manager, FlatBuffers 25.9.23, XCTest

**Spec:** `../slackwater-ios/.worktrees/issue-469-flatbuffers/docs/superpowers/specs/2026-09-24-unified-tcdb-catalog-design.md`

## Global constraints

- Implement in a linked worktree based on PR #192's rename branch, never in the local `tide-database` checkout.
- Keep `TCDB` and `.tcdb` as format names.
- Public API must not expose generated `Slackwater_*` types.
- Preserve memory mapping and lazy per-field reads; do not cache prediction arrays.
- Keep FlatBuffers and generated-code versions pinned together at `25.9.23`.

## Review focus

- Missing scalar flags must produce `nil`; a real zero must remain `0`.
- A route lookup for an unknown slug must return `nil` without scanning or trapping.
- Empty route vectors and optional former paths must return empty Swift arrays.
- A current subordinate must preserve every offset independently, including missing values.
- A short or wrong-identifier buffer must throw `InvalidStationDatabase` before FlatBuffers access.

---

### Task 1: Rename the public database root

**Files:**
- Modify: `Package.swift`
- Rename: `packages/swift/Sources/SlackwaterDatabase/TideDatabase.swift` to `packages/swift/Sources/SlackwaterDatabase/StationDatabase.swift`
- Rename: `packages/swift/Tests/SlackwaterDatabaseTests/TideDatabaseTests.swift` to `packages/swift/Tests/SlackwaterDatabaseTests/StationDatabaseTests.swift`
- Modify: `packages/swift/Tests/SlackwaterDatabaseTests/AttributionTests.swift`
- Modify: `packages/swift/README.md`

**Interfaces:**
- Consumes: `Slackwater_Root` generated accessor.
- Produces: `public struct StationDatabase: RandomAccessCollection`, `public struct InvalidStationDatabase: Error`.

- [ ] **Step 1: Rename the test API first**

Change the fixture helper and invalid-file assertions to compile only with the desired API:

```swift
func open() throws -> StationDatabase {
  try StationDatabase(contentsOf: Self.url)
}

XCTAssertThrowsError(try StationDatabase(data: Data())) {
  XCTAssert($0 is InvalidStationDatabase)
}
```

- [ ] **Step 2: Run the Swift tests and verify the compile failure**

Run: `rtk swift test`

Expected: FAIL because `StationDatabase` and `InvalidStationDatabase` do not exist.

- [ ] **Step 3: Rename the public types without compatibility aliases**

Rename `TideDatabase` to `StationDatabase` and `NotATideDatabase` to `InvalidStationDatabase` in the implementation, tests, package README, root README examples, and docs. Keep the generated root and file identifier unchanged.

- [ ] **Step 4: Run the Swift tests**

Run: `rtk swift test`

Expected: all existing Swift reader tests PASS.

- [ ] **Step 5: Commit**

```bash
rtk git add Package.swift README.md packages/swift docs
rtk git commit -m "Name the Swift reader for the full station database"
```

### Task 2: Add typed station metadata and current records

**Files:**
- Modify: `packages/swift/Sources/SlackwaterDatabase/StationDatabase.swift`
- Modify: `packages/swift/Tests/SlackwaterDatabaseTests/StationDatabaseTests.swift`
- Modify: `packages/swift/scripts/generate-fixture.ts`
- Modify: `packages/swift/README.md`

**Interfaces:**
- Consumes: `Station.raw`, `Slackwater_Current`, `Slackwater_CurrentOffsets`, `Slackwater_TideOffsets`, `Slackwater_Source`, `Slackwater_License`, and missing-value booleans.
- Produces: `StationKind`, `StationType`, `Station.source`, `Station.license`, `Station.tideOffsets`, `Station.current`, structured location properties, and `Station.qualityReason`.

- [ ] **Step 1: Add failing fixture assertions for typed fields**

Add assertions that never mention generated types:

```swift
let reference = try XCTUnwrap(open().station(id: "test/reference"))
XCTAssertEqual(reference.locality, "Seattle")
XCTAssertEqual(reference.regionCode, "US-WA")
XCTAssertEqual(reference.countryCode, "US")
XCTAssertEqual(reference.context, "Seattle, WA")
XCTAssertEqual(reference.cities, ["Seattle"])
XCTAssertEqual(reference.source?.name, "Test Source")
XCTAssertEqual(reference.license?.commercialUse, true)

let current = try XCTUnwrap(open().station(id: "test/current")?.current)
XCTAssertEqual(current.floodDirection, 90)
XCTAssertEqual(current.ebbDirection, 270)
XCTAssertEqual(current.meanFlow, 0.4, accuracy: 1e-6)
XCTAssertEqual(current.tideReference, "test/reference")
XCTAssertEqual(current.offsets?.slackBeforeFlood, -30)
XCTAssertNil(current.offsets?.slackBeforeEbb)
```

Add a fixture current whose encoded scalar is zero with its missing flag false, and assert `0`, not `nil`.

- [ ] **Step 2: Run the focused test and verify the compile failure**

Run: `rtk swift test --filter StationDatabaseTests.testReadsTypedMetadataAndCurrent`

Expected: FAIL because the typed properties do not exist.

- [ ] **Step 3: Add immutable wrapper values**

Implement public value types with optional scalar fields:

```swift
public struct StationLicense: Equatable {
  public let type: String?
  public let url: String?
  public let notes: String?
  public let commercialUse: Bool
}

public struct CurrentOffsets: Equatable {
  public let reference: String
  public let slackBeforeFlood: Int?
  public let slackBeforeEbb: Int?
  public let floodTime: Int?
  public let ebbTime: Int?
  public let floodSpeedRatio: Double?
  public let ebbSpeedRatio: Double?
}

public struct CurrentRecord: Equatable {
  public let floodDirection: Double?
  public let ebbDirection: Double?
  public let meanFlow: Double?
  public let tideReference: String?
  public let offsets: CurrentOffsets?
  public let magnitudeNote: String?
  public let derived: TideDerivedCurrent?
}
```

Use each generated `*_missing` flag before reading a scalar. Add equivalent typed `TideOffsets`, `StationSource`, and `TideDerivedCurrent` wrappers. Define public `StationKind { case tide, current }` and `StationType { case reference, subordinate }`, then map generated enums inside `Station.kind` and `Station.type`. Add `locality`, `regionCode`, `countryCode`, `context`, `contextDerived`, `cities`, and `qualityReason` properties directly on `Station`.

- [ ] **Step 4: Run all Swift reader tests**

Run: `rtk swift test`

Expected: PASS with no warnings.

- [ ] **Step 5: Commit**

```bash
rtk git add packages/swift
rtk git commit -m "Expose typed current and station metadata"
```

### Task 3: Add stable route lookup

**Files:**
- Modify: `packages/swift/Sources/SlackwaterDatabase/StationDatabase.swift`
- Modify: `packages/swift/Tests/SlackwaterDatabaseTests/StationDatabaseTests.swift`
- Modify: `packages/swift/README.md`
- Modify: `packages/swift/scripts/generate-fixture.ts` only if the fixture lacks tide/current/former routes.

**Interfaces:**
- Consumes: sorted `tide_routes` and `current_routes` vectors.
- Produces: `StationRouteKind`, `StationRoute`, `StationDatabase.stationRoute(kind:slug:)`, `StationDatabase.stationRoutes(kind:)`.

- [ ] **Step 1: Add failing route tests**

```swift
func testLooksUpStableRoutesWithoutGeneratedTypes() throws {
  let db = try open()
  XCTAssertEqual(
    db.stationRoute(kind: .tide, slug: "reference"),
    StationRoute(slug: "reference", stationIDs: ["test/reference"], formerPaths: ["old-reference"]))
  XCTAssertNil(db.stationRoute(kind: .current, slug: "missing"))
  XCTAssertEqual(db.stationRoutes(kind: .current).map(\.slug), ["a-current"])
}
```

- [ ] **Step 2: Run the focused test and verify the compile failure**

Run: `rtk swift test --filter StationDatabaseTests.testLooksUpStableRoutesWithoutGeneratedTypes`

Expected: FAIL because route API types and methods do not exist.

- [ ] **Step 3: Implement route values and key lookup**

```swift
public enum StationRouteKind: Hashable { case tide, current }

public struct StationRoute: Equatable {
  public let slug: String
  public let stationIDs: [String]
  public let formerPaths: [String]
}

public func stationRoute(kind: StationRouteKind, slug: String) -> StationRoute? {
  let raw = switch kind {
  case .tide: root.tideRoutesBy(key: slug)
  case .current: root.currentRoutesBy(key: slug)
  }
  return raw.map(StationRoute.init)
}
```

Implement `stationRoutes(kind:)` by iterating only the selected route vector. Convert absent `former_paths` to `[]`.

- [ ] **Step 4: Run all Swift reader tests against fixture and shipped TCDB**

Run: `SLACKWATER_TCDB=packages/database/src/generated/slackwater.tcdb rtk swift test`

Expected: PASS, including unknown slug and empty optional-vector cases.

- [ ] **Step 5: Run repository formatting and tests**

Run: `rtk npm test -w swift`

Expected: fixture regeneration, Swift tests, and generated-code drift checks PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add packages/swift
rtk git commit -m "Read stable station routes from Swift"
```

### Task 4: Publish the renamed reader contract

**Files:**
- Modify: PR #192 body/checklist if needed.
- No product file changes unless review finds a missing public symbol.

**Interfaces:**
- Consumes: green Tasks 1-3.
- Produces: exact `1.0.0-beta.0` Swift/Node release contract consumed by Slackwater iOS.

- [ ] **Step 1: Verify public symbol names from a clean consumer**

Create a temporary Swift package outside the repository and compile this import:

```swift
import SlackwaterDatabase

func read(_ url: URL) throws {
  let db = try StationDatabase(contentsOf: url)
  _ = db.station(id: "noaa/9447130")?.license?.commercialUse
  _ = db.stationRoute(kind: .tide, slug: "seattle")
}
```

Run: `rtk swift build`

Expected: PASS without importing `FlatBuffers` or naming a generated type.

- [ ] **Step 2: Run the repository suite**

Run: `rtk npm test`

Expected: all workspaces and Swift tests PASS.

- [ ] **Step 3: Update PR #192**

Add the Swift API changes and exact verification counts to the existing PR body. Keep the do-not-merge-before-flip-day instruction intact.

- [ ] **Step 4: Merge and tag through the scheduled rename workflow**

Confirm the published repository is `openwatersio/slackwater-database`, npm package is `@slackwater/database@1.0.0-beta.0`, Swift product is `SlackwaterDatabase`, and release artifact is `slackwater-<date>.tcdb`. Keep the package at this beta until the Slackwater app releases.
