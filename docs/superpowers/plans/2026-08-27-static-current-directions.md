# Static Current Directions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore a responsive current map by removing animation and its user toggle while showing certified speed fill with static, map-aligned direction arrows.

**Architecture:** The existing one-minute off-main field evaluation builds both polygon and centroid-point features into the existing fill and patch GeoJSON sources. MapLibre symbol layers rotate one SDF arrow from each point's bearing and handle zoom/collision natively; no current code runs at animation cadence. Dodd contributes one station-local point without claiming area coverage.

**Tech Stack:** Swift 6, SwiftUI, MapLibre Native 6.x, TideEngine, XCTest/XCUITest, Xcode Instruments

**Spec:** `docs/superpowers/specs/2026-08-27-static-current-directions-design.md`

## Global Constraints

- Work only in the existing `fix/static-current-directions` worktree; never switch the shared checkout.
- Keep `FillField`/`PatchField` certification, speed ramp, polygon geometry, one-minute cadence, and land clipping unchanged.
- Add no dependency, setting, camera callback, animation timer, per-frame source update, or data format.
- Patch direction wins wherever a backdrop centroid falls inside a patch cell.
- Dodd gets one direction point only when its fitted model resolves; it gets no polygon.
- `-currentFillOff` remains a test-only launch override; there is no persisted or user-facing toggle.
- Use TDD and prove each new assertion red before production edits.
- This plan covers the static fallback only. CPU-versus-Metal motion evaluation gets its own plan after the static renderer ships.

---

### Task 1: Remove the interaction-blocking animator and current toggle

**Files:**
- Modify: `Slackwater/CurrentFill.swift:17-173`
- Modify: `Slackwater/MapScreen.swift:600,641,657`
- Modify: `Slackwater/SlackwaterApp.swift:321-343,671-674,1051-1064`
- Modify: `SlackwaterTests/CurrentFillTests.swift:6-84`
- Modify: `SlackwaterUITests/ScreenshotTests.swift:958-1006`

**Interfaces:**
- Produces: `func currentFillEnabled(arguments: [String] = CommandLine.arguments) -> Bool`
- Preserves: `addFillStyle(_:)`, `CurrentFillRenderer.attach(to:map:)`, and `-currentFillOff`
- Removes from shipping flow: `CurrentStreakAnimator`, `currentFillKey`, and `@AppStorage(currentFillKey)`

- [ ] **Step 1: Write failing unit tests for the launch-only gate and static style**

Replace the preference-oriented setup/tests and streak-style assertion in `CurrentFillTests.swift` with:

```swift
func testFillIsOnExceptForTestLaunchOverride() {
    XCTAssertTrue(currentFillEnabled(arguments: []))
    XCTAssertFalse(currentFillEnabled(arguments: ["-currentFillOff"]))

    // A value left by a released build must not remain a hidden user setting.
    UserDefaults.standard.set(false, forKey: "showCurrentFill")
    XCTAssertTrue(currentFillEnabled(arguments: []))
    UserDefaults.standard.removeObject(forKey: "showCurrentFill")
}

func testCurrentStyleContainsNoAnimationSourceOrLayers() {
    var style: [String: Any] = [
        "sources": [String: Any](),
        "layers": [["id": "land-usca"], ["id": "station-clusters"]] as [[String: Any]],
    ]
    addFillStyle(&style)

    let sources = style["sources"] as? [String: Any] ?? [:]
    let ids = (style["layers"] as? [[String: Any]] ?? [])
        .compactMap { $0["id"] as? String }
    XCTAssertNil(sources["current-streaks"])
    XCTAssertFalse(ids.contains("current-streak-tails"))
    XCTAssertFalse(ids.contains("current-streak-heads"))
}
```

Keep the fill colour and fill/patch ordering tests. Remove assertions that name `CurrentStreakAnimator`.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
rtk proxy lockf -t 0 /tmp/slackwater-test.lock xcodebuild test \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SlackwaterTests/CurrentFillTests
```

Expected: compilation fails because `currentFillEnabled(arguments:)` does not exist; after adding only that signature, the static-style test fails because the streak source/layers still exist.

- [ ] **Step 3: Make the current layer launch-only and remove animator ownership**

In `CurrentFill.swift`, replace `currentFillKey` and the computed property with:

```swift
func currentFillEnabled(arguments: [String] = CommandLine.arguments) -> Bool {
    !arguments.contains("-currentFillOff")
}
```

In `addFillStyle(_:)`, delete the `current-streaks` source and both streak layer dictionaries. Insert only `[layer, patch]` before land.

In `CurrentFillRenderer`, delete the `streaks` property, `streaks.stop()` call, and `streaks.attach(...)` call. Keep the 60-second timer and off-main `refresh()` unchanged.

In both style builders and `MapStyler`, call the function form:

```swift
if currentFillEnabled() { addFillStyle(&style) }
private let fill = currentFillEnabled() ? CurrentFillRenderer() : nil
```

- [ ] **Step 4: Remove the user-facing toggle without disturbing map focus remounts**

In `StationListView`, delete:

```swift
@AppStorage(currentFillKey) private var showFill = true
```

Change the map identity to retain its two remaining inputs:

```swift
.id("\(mapFocusToken)-\(slackWindowSpeed)")
```

Delete the `if showMap { ... currents-toggle ... }` block from `fabBar`; leave Search on the left and List/Map on the right. Update the nearby comments so they describe only the search and list/map controls.

- [ ] **Step 5: Add the UI regression assertion**

In `testM45SearchFabAndMapToggle`, immediately after the map canvas appears, add:

```swift
XCTAssertFalse(app.buttons["currents-toggle"].exists)
XCTAssertFalse(app.buttons["Hide currents"].exists)
XCTAssertFalse(app.buttons["Show currents"].exists)
```

This reuses the existing map launch and adds no UI-test runtime.

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run the unit command from Step 2, then:

```bash
rtk proxy lockf -t 0 /tmp/slackwater-test.lock xcodebuild test \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SlackwaterUITests/ScreenshotTests/testM45SearchFabAndMapToggle
```

Expected: both commands pass; opening the map exposes Search and List but no current toggle.

- [ ] **Step 7: Commit the containment change**

```bash
rtk git add Slackwater/CurrentFill.swift Slackwater/MapScreen.swift \
  Slackwater/SlackwaterApp.swift SlackwaterTests/CurrentFillTests.swift \
  SlackwaterUITests/ScreenshotTests.swift
rtk git commit -m "fix: remove current animation and map toggle"
```

---

### Task 2: Render static direction arrows from the minute-stamped field

**Files:**
- Create: `Slackwater/CurrentDirections.swift`
- Create: `SlackwaterTests/CurrentDirectionTests.swift`
- Modify: `Slackwater/CurrentFill.swift:45-188`
- Modify: `Slackwater/MapScreen.swift:712-737`
- Modify: `Slackwater.xcodeproj/project.pbxproj`
- Modify: `SlackwaterTests/CurrentFillTests.swift:43-112`
- Delete: `Slackwater/CurrentStreaks.swift`
- Delete: `SlackwaterTests/CurrentStreakTests.swift`

**Interfaces:**
- Produces: `CURRENT_DIRECTION_MIN_ZOOM`, `StationMapFlow`, `DoddMapFlowProvider`
- Produces: `currentDirectionFeature(at:bearingDeg:) -> MLNPointFeature`
- Produces: `currentCellFeatures(_:excludingDirectionsIn:) -> [MLNShape & MLNFeature]`
- Produces: `currentDirectionImage() -> UIImage`
- Consumes: `FillCell`, `triangleContains`, `fillColourHex`, `ChsCurrentGateInfo`, `ChsModelStore`

- [ ] **Step 1: Write failing feature-construction and Dodd tests**

Create `SlackwaterTests/CurrentDirectionTests.swift`:

```swift
import CoreLocation
import MapLibre
import XCTest
@testable import Slackwater

final class CurrentDirectionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_787_000_000)
    private let gate = CurrentStationRecord(
        id: "chs-dodd-narrows", name: "Dodd Narrows", region: "Nanaimo", aliases: [],
        latitude: 49.1344, longitude: -123.8171, timezone: "America/Vancouver",
        floodDirection: 21, ebbDirection: 201, meanFlow: 0, tideReference: nil, constituents: [])

    private func cell(_ bearing: Double = 73) -> FillCell {
        FillCell(polygon: [
            .init(latitude: 48.0, longitude: -123.0),
            .init(latitude: 48.0, longitude: -122.7),
            .init(latitude: 48.3, longitude: -123.0),
        ], speedKn: 2.5, bearingDeg: bearing)
    }

    func testCellProducesPolygonAndCentroidDirection() throws {
        let features = currentCellFeatures([cell()])
        XCTAssertEqual(features.count, 2)
        XCTAssertTrue(features[0] is MLNPolygonFeature)
        let point = try XCTUnwrap(features[1] as? MLNPointFeature)
        XCTAssertEqual(point.coordinate.latitude, 48.1, accuracy: 1e-12)
        XCTAssertEqual(point.coordinate.longitude, -122.9, accuracy: 1e-12)
        let bearing = try XCTUnwrap(point.attribute(forKey: "bearing") as? NSNumber)
        XCTAssertEqual(bearing.doubleValue, 73)
    }

    func testPatchCoverageSuppressesBackdropDirectionButNotPolygon() {
        let features = currentCellFeatures([cell()], excludingDirectionsIn: [cell(201)])
        XCTAssertEqual(features.count, 1)
        XCTAssertTrue(features[0] is MLNPolygonFeature)
    }

    func testDoddUsesAbsoluteSpeedAndReciprocalEbbBearing() throws {
        var evaluations = 0
        let provider = DoddMapFlowProvider(gate: gate, signedSpeed: { _ in
            evaluations += 1
            return -6
        })
        let flow = try XCTUnwrap(provider.flow(at: date))
        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(flow.speedKn, 6)
        XCTAssertEqual(flow.bearingDeg, 201)
        XCTAssertEqual(flow.center.latitude, gate.latitude, accuracy: 1e-12)
        XCTAssertEqual(flow.center.longitude, gate.longitude, accuracy: 1e-12)
    }

    func testDoddOmitsMissingModel() {
        XCTAssertNil(DoddMapFlowProvider(gate: gate, signedSpeed: { _ in nil }).flow(at: date))
    }
}
```

- [ ] **Step 2: Write failing style tests for native arrows**

Replace `testStreakStyleSitsAbovePatchesWithFoamTailsAndRampHeads` in `CurrentFillTests.swift` with:

```swift
func testDirectionLayersAreNativeMapAlignedSymbolsBelowLand() throws {
    var style: [String: Any] = [
        "sources": [String: Any](),
        "layers": [["id": "land-usca"], ["id": "station-clusters"]] as [[String: Any]],
    ]
    addFillStyle(&style)
    let layers = style["layers"] as? [[String: Any]] ?? []
    let ids = layers.compactMap { $0["id"] as? String }
    let fill = try XCTUnwrap(ids.firstIndex(of: CurrentFillRenderer.sourceID))
    let patch = try XCTUnwrap(ids.firstIndex(of: CurrentFillRenderer.patchSourceID))
    let direction = try XCTUnwrap(ids.firstIndex(of: CurrentFillRenderer.directionLayerID))
    let patchDirection = try XCTUnwrap(ids.firstIndex(of: CurrentFillRenderer.patchDirectionLayerID))
    let land = try XCTUnwrap(ids.firstIndex(of: "land-usca"))
    XCTAssertEqual([fill, patch, direction, patchDirection], [0, 1, 2, 3])
    XCTAssertLessThan(patchDirection, land)

    for index in [direction, patchDirection] {
        XCTAssertEqual(layers[index]["type"] as? String, "symbol")
        XCTAssertEqual(layers[index]["minzoom"] as? Double, CURRENT_DIRECTION_MIN_ZOOM)
        let filter = try XCTUnwrap(layers[index]["filter"] as? NSArray)
        XCTAssertEqual(filter, ["==", ["geometry-type"], "Point"] as NSArray)
        let layout = try XCTUnwrap(layers[index]["layout"] as? [String: Any])
        XCTAssertEqual(layout["icon-image"] as? String, CurrentFillRenderer.directionImageID)
        XCTAssertEqual(layout["icon-rotate"] as? NSArray, ["get", "bearing"] as NSArray)
        XCTAssertEqual(layout["icon-rotation-alignment"] as? String, "map")
        XCTAssertEqual(layout["icon-pitch-alignment"] as? String, "map")
        XCTAssertEqual(layout["icon-allow-overlap"] as? Bool, false)
    }
}
```

- [ ] **Step 3: Run the focused tests and verify RED**

```bash
rtk xcodegen generate
rtk proxy lockf -t 0 /tmp/slackwater-test.lock xcodebuild test \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SlackwaterTests/CurrentDirectionTests \
  -only-testing:SlackwaterTests/CurrentFillTests
```

Expected: compilation fails because the direction helpers, identifiers, and layers do not exist.

- [ ] **Step 4: Implement the pure static-direction seam**

Create `Slackwater/CurrentDirections.swift`. Move only `StationMapFlow` and `DoddMapFlowProvider` from `CurrentStreaks.swift`, then add:

```swift
import CoreLocation
import Foundation
import MapLibre
import UIKit

let CURRENT_DIRECTION_MIN_ZOOM = 9.0

func currentDirectionFeature(at coordinate: CLLocationCoordinate2D,
                             bearingDeg: Double) -> MLNPointFeature {
    let feature = MLNPointFeature()
    feature.coordinate = coordinate
    feature.attributes = ["bearing": bearingDeg]
    return feature
}

func currentCellFeatures(_ cells: [FillCell],
                         excludingDirectionsIn exclusions: [FillCell] = [])
    -> [MLNShape & MLNFeature] {
    cells.flatMap { cell -> [MLNShape & MLNFeature] in
        var coordinates = cell.polygon
        let polygon = MLNPolygonFeature(coordinates: &coordinates,
                                        count: UInt(coordinates.count))
        polygon.attributes = [
            "colour": fillColourHex(forSpeedKn: cell.speedKn),
            "kn": cell.speedKn,
        ]
        let count = Double(cell.polygon.count)
        guard count > 0 else { return [polygon] }
        let center = CLLocationCoordinate2D(
            latitude: cell.polygon.reduce(0) { $0 + $1.latitude } / count,
            longitude: cell.polygon.reduce(0) { $0 + $1.longitude } / count)
        guard !exclusions.contains(where: {
            triangleContains(center, vertices: $0.polygon)
        }) else { return [polygon] }
        return [polygon, currentDirectionFeature(at: center, bearingDeg: cell.bearingDeg)]
    }
}

func currentDirectionImage() -> UIImage {
    let configuration = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
    return UIImage(systemName: "arrow.up", withConfiguration: configuration)!
        .withRenderingMode(.alwaysTemplate)
}
```

Keep `DoddMapFlowProvider`'s production initializer cache-only: resolve `chs-dodd-narrows`, load `ChsModelStore`, evaluate one signed speed, and return flood bearing for positive flow or its reciprocal for negative flow. Keep its injected initializer exactly as exercised above.

Delete `CurrentStreaks.swift` and `CurrentStreakTests.swift`; none of the particle, advection, envelope, seed, timer, or GeoJSON animation code has a shipping caller.

- [ ] **Step 5: Add native symbol layers to the existing sources**

In `CurrentFillRenderer`, add:

```swift
static let directionLayerID = "current-directions"
static let patchDirectionLayerID = "current-directions-patches"
static let directionImageID = "current-direction-arrow"
```

In `addFillStyle(_:)`, build one direction layer and its patch copy:

```swift
let direction: [String: Any] = [
    "id": CurrentFillRenderer.directionLayerID,
    "type": "symbol",
    "source": CurrentFillRenderer.sourceID,
    "minzoom": CURRENT_DIRECTION_MIN_ZOOM,
    "filter": ["==", ["geometry-type"], "Point"],
    "layout": [
        "icon-image": CurrentFillRenderer.directionImageID,
        "icon-rotate": ["get", "bearing"],
        "icon-rotation-alignment": "map",
        "icon-pitch-alignment": "map",
        "icon-allow-overlap": false,
        "icon-ignore-placement": false,
        "icon-padding": 8,
    ],
    "paint": [
        "icon-color": mapHex(SN.foamHex),
    ],
]
var patchDirection = direction
patchDirection["id"] = CurrentFillRenderer.patchDirectionLayerID
patchDirection["source"] = CurrentFillRenderer.patchSourceID
```

Insert `[layer, patch, direction, patchDirection]` before land. Do not add a new source.

- [ ] **Step 6: Build polygon and direction features once per minute**

Give `CurrentFillRenderer` a single Dodd provider:

```swift
private let dodd = DoddMapFlowProvider()
```

Replace the local polygon-only `features` function in `refresh()` with this off-main work:

```swift
let dodd = self.dodd
DispatchQueue.global(qos: .utility).async { [weak self] in
    let fillCells = field?.cells(at: when) ?? []
    let patchCells = patches?.cells(at: when) ?? []
    let fillFeatures = currentCellFeatures(
        fillCells, excludingDirectionsIn: patchCells)
    var patchFeatures = currentCellFeatures(patchCells)
    if let flow = dodd.flow(at: when) {
        patchFeatures.append(currentDirectionFeature(
            at: flow.center, bearingDeg: flow.bearingDeg))
    }
    DispatchQueue.main.async {
        guard let self else { return }
        self.evaluating = false
        self.source?.shape = MLNShapeCollectionFeature(shapes: fillFeatures)
        self.patchSource?.shape = MLNShapeCollectionFeature(shapes: patchFeatures)
    }
}
```

This evaluates each provider once per refresh, performs feature construction off-main, and assigns each source once on main.

- [ ] **Step 7: Register the SDF arrow for every style load**

In `MapStyler.mapView(_:didFinishLoading:)`, alongside the two pin images, add:

```swift
style.setImage(currentDirectionImage(),
               forName: CurrentFillRenderer.directionImageID)
```

Registration stays in `didFinishLoading` because fallback and Seascape each create a fresh style.

- [ ] **Step 8: Run focused tests and verify GREEN**

Run the command from Step 3.

Expected: all `CurrentDirectionTests` and `CurrentFillTests` pass, including polygon/point construction, overlap suppression, Dodd direction, native layer configuration, and absence of animation layers.

- [ ] **Step 9: Commit the static renderer**

```bash
rtk git add Slackwater/CurrentDirections.swift Slackwater/CurrentFill.swift \
  Slackwater/MapScreen.swift SlackwaterTests/CurrentDirectionTests.swift \
  SlackwaterTests/CurrentFillTests.swift Slackwater/CurrentStreaks.swift \
  SlackwaterTests/CurrentStreakTests.swift Slackwater.xcodeproj/project.pbxproj
rtk git commit -m "feat: show static current direction arrows"
```

---

### Task 3: Verify interaction, visuals, and delivery

**Files:**
- Verify: `Slackwater/CurrentFill.swift`
- Verify: `Slackwater/CurrentDirections.swift`
- Verify: `Slackwater/SlackwaterApp.swift`
- Verify: `SlackwaterTests/CurrentFillTests.swift`
- Verify: `SlackwaterTests/CurrentDirectionTests.swift`
- Verify: `SlackwaterUITests/ScreenshotTests.swift`

**Interfaces:**
- Consumes: the static renderer and launch-only override from Tasks 1–2
- Produces: test output, before/after screenshots, and real-device Instruments evidence for the internal PR

- [ ] **Step 1: Compile-check before booking the full suite**

```bash
rtk proxy lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages
```

Expected: build succeeds with no Swift concurrency warning introduced by the off-main feature construction.

- [ ] **Step 2: Run the fast suite**

```bash
rtk test ./scripts/test.sh
```

Expected: the iPhone fast plan passes. Open the map screenshot in `$SHOT_DIR` and confirm Search/List spacing remains balanced without the current toggle.

- [ ] **Step 3: Inspect the static current layer on the simulator**

Launch the app without `-currentFillOff`, open a current station inside certified Salish coverage, tap its map-header title to focus the map past zoom 9, and capture:

- speed fill with monochrome arrows;
- patch arrows at a grown patch such as Tacoma Narrows;
- Dodd's single arrow with no surrounding filled polygon when a fitted model is present;
- the map FAB row with no current toggle.

Confirm arrows rotate with the map, thin through native collision rather than overlapping, stay below land/station labels, and never show contradictory patch/backdrop directions at one location.

- [ ] **Step 4: Run the physical-phone performance gate**

On the phone that exhibits the regression, use a Release build and record two Instruments runs with Animation Hitches and Time Profiler:

1. static currents disabled via `-currentFillOff`;
2. static currents enabled with no override.

For each run, perform the same 30-second script: cross zoom 9 three times, pinch continuously for ten seconds, pan across a certified field for ten seconds, then rotate and pan together for ten seconds. Leave the enabled run open through one 60-second refresh.

Pass criteria:

- no visible hitch when crossing zoom 9;
- gesture frame behavior within 10% of the disabled baseline;
- no animation-rate timer or shape-source replacement in the trace;
- no severe animation hitch;
- no visible stall at the minute refresh.

If static fill misses this bar, stop and profile its minute refresh/source size. Do not add viewport callbacks or restore animation as a workaround.

- [ ] **Step 5: Run the full suite before upload**

```bash
rtk test ./scripts/test.sh --full
rtk git diff --check
rtk git status --short --branch
rtk git log --oneline origin/main..HEAD
```

Expected: full plan passes; diff check is clean; branch contains only the design commits and the two implementation commits from this plan.

- [ ] **Step 6: Push and open the internal PR**

```bash
rtk gh auth status
rtk git push
rtk gh pr create --repo openwatersio/slackwater-ios \
  --title "Show static current directions without blocking the map" \
  --body-file /tmp/static-current-directions-pr.md
```

Before the command, write `/tmp/static-current-directions-pr.md` with: the user-visible outcome, root cause, focused/fast/full results, device/OS/build and Instruments measurements, and side-by-side uploaded before/after screenshots. The PR is internal; do not merge it.
