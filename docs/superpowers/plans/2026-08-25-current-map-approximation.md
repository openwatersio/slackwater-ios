# Current Map Approximation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add locally advected streaks over certified current fields plus a compact speed-and-direction cluster at Dodd Narrows, while leaving passage details and uncertified spatial extent off the map.

**Architecture:** Add exact point sampling to the existing `FillField` and `PatchField`, then graduate the existing MapLibre GeoJSON particle spike into one animator owned by `CurrentFillRenderer`. Certified particles follow sampled local vectors; Dodd particles use one fitted-station vector inside an unrendered local envelope, with ramp-colored heads and foam-white tails.

**Tech Stack:** Swift, CoreLocation, MapLibre Native GeoJSON, TideEngine, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-25-current-map-approximation-design.md`

## Global Constraints

- Create a fresh `slackwater-ios` worktree from current `origin/main`; do not reuse or cherry-pick the unshipped stage-aware commits `e2be51d` or `cdc9dd2`.
- Consume the reviewed Dodd coordinate from `station-corrections` PR #15 after its normal release; do not hard-code a second canonical coordinate in renderer code.
- The map is approximate context; station detail remains authoritative for slack, speed, and passage decisions.
- Dodd gets no fill, outline, polygon, or claimed spatial boundary.
- Reuse MapLibre GeoJSON and existing map/current-field ownership; add no Metal renderer or dependency.
- The existing current-fill toggle owns fill and streaks; add no setting or launch-only shipping path.
- Heads use the existing speed ramp; tails use the existing foam token. Never use `PIN_STATE_COLOUR`.
- Patch sampling wins over backdrop sampling. Missing field coverage returns nil; a missing Dodd fitted model omits its cluster.
- Reduce Motion freezes advancement while leaving direction marks visible.
- Keep deterministic particles, visible-bounds/zoom culling, and one-minute model evaluation.
- Follow TDD and commit only after focused GREEN.

---

### Task 1: Sample exact vectors from certified fields

**Files:**
- Modify: `Slackwater/FillField.swift`
- Modify: `Slackwater/PatchField.swift`
- Modify: `SlackwaterTests/FillFieldTests.swift`
- Modify: `SlackwaterTests/PatchFieldTests.swift`

**Interfaces:**
- Produces: `struct CurrentVector { let speedKn: Double; let bearingDeg: Double }`.
- Produces: `triangleContains(_:vertices:) -> Bool`.
- Produces: `FillField.sample(at:time:) -> CurrentVector?`.
- Produces: `PatchField.sample(at:time:) -> CurrentVector?`.

- [ ] **Step 1: Write failing geometry and FillField tests**

Add inclusive-edge tests and fixture sampling:

```swift
let triangle = [
    CLLocationCoordinate2D(latitude: 0, longitude: 0),
    CLLocationCoordinate2D(latitude: 0, longitude: 1),
    CLLocationCoordinate2D(latitude: 1, longitude: 0),
]
XCTAssertTrue(triangleContains(.init(latitude: 0.25, longitude: 0.25), vertices: triangle))
XCTAssertTrue(triangleContains(triangle[0], vertices: triangle))
XCTAssertFalse(triangleContains(.init(latitude: 1, longitude: 1), vertices: triangle))

let vector = try XCTUnwrap(field.sample(at: triangle[0], time: fixtureDate))
XCTAssertEqual(vector.speedKn, expectedSpeed, accuracy: 1e-9)
XCTAssertEqual(vector.bearingDeg, expectedBearing, accuracy: 1e-9)
XCTAssertNil(field.sample(at: .init(latitude: 10, longitude: 10), time: fixtureDate))
```

- [ ] **Step 2: Run focused tests and observe RED**

```bash
rtk xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SlackwaterTests/FillFieldTests
```

Expected: compile failure because `CurrentVector`, `triangleContains`, and `sample` do not exist.

- [ ] **Step 3: Implement the shared geometry helper and FillField sampler**

Use the existing decoded element loop, test geometry before harmonic evaluation, and return the same speed/bearing formulas as `cells(at:)`:

```swift
struct CurrentVector {
    let speedKn: Double
    let bearingDeg: Double
}

func triangleContains(_ point: CLLocationCoordinate2D,
                      vertices: [CLLocationCoordinate2D]) -> Bool {
    guard vertices.count == 3 else { return false }
    func cross(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D,
               _ c: CLLocationCoordinate2D) -> Double {
        (a.longitude - c.longitude) * (b.latitude - c.latitude)
          - (b.longitude - c.longitude) * (a.latitude - c.latitude)
    }
    let d = vertices.indices.map { cross(point, vertices[$0], vertices[($0 + 1) % 3]) }
    return !(d.contains { $0 < 0 } && d.contains { $0 > 0 })
}
```

Do not call `cells(at:)`; evaluating every cell for one point defeats the seam.

- [ ] **Step 4: Write PatchField match/absence tests, observe RED, and implement**

Pin inside, outside, missing-anchor, and reciprocal ebb bearing. Walk raw cells, test containment first, then evaluate only the matched patch anchor and scale. Preserve any format supported by current `origin/main`; do not restore unused stage-v2 code.

- [ ] **Step 5: Verify and commit**

```bash
rtk xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SlackwaterTests/FillFieldTests \
  -only-testing:SlackwaterTests/PatchFieldTests
rtk git diff --check
rtk git add Slackwater/FillField.swift Slackwater/PatchField.swift \
  SlackwaterTests/FillFieldTests.swift SlackwaterTests/PatchFieldTests.swift
rtk git commit -m "feat: sample current vectors at map coordinates"
```

---

### Task 2: Model the Dodd station-local approximation

**Files:**
- Create: `Slackwater/CurrentStreaks.swift`
- Create: `SlackwaterTests/CurrentStreakTests.swift`
- Modify: `project.yml` only if XcodeGen source discovery requires it.

**Interfaces:**
- Produces: `struct StationMapFlow { center, speedKn, bearingDeg }`.
- Produces: `DoddMapFlowProvider.flow(at:) -> StationMapFlow?`.
- Produces: `advanceCurrentCoordinate(_:vector:dt:speedScale:)`.
- Produces: deterministic local-envelope seed/recycle helpers used by Task 3.

- [ ] **Step 1: Write failing provider tests**

Inject a loader/evaluator so tests do not touch the model store:

```swift
var evaluations = 0
let provider = DoddMapFlowProvider(
    gate: fixtureGate,
    signedSpeed: { _ in evaluations += 1; return -6.0 })
let flow = try XCTUnwrap(provider.flow(at: fixtureDate))
XCTAssertEqual(evaluations, 1)
XCTAssertEqual(flow.center.latitude, fixtureGate.latitude, accuracy: 1e-12)
XCTAssertEqual(flow.speedKn, 6.0)
XCTAssertEqual(flow.bearingDeg,
               (fixtureGate.floodDirection + 180).truncatingRemainder(dividingBy: 360),
               accuracy: 1e-9)
XCTAssertNil(DoddMapFlowProvider(gate: fixtureGate, signedSpeed: { _ in nil })
    .flow(at: fixtureDate))
```

- [ ] **Step 2: Run focused tests and observe RED**

Use the Task 1 focused command with `-only-testing:SlackwaterTests/CurrentStreakTests`.

- [ ] **Step 3: Implement the minimum provider**

Resolve only `chs-dodd-narrows` from `ChsCurrentGateInfo.all`, load its fitted model through `ChsModelStore.loadCurrent`, and use the existing one-second `speeds(from:to:step:)` idiom. Return nil for any missing identity/model/speed.

- [ ] **Step 4: Write failing motion and envelope tests**

```swift
let east = CurrentVector(speedKn: 2, bearingDeg: 90)
let next = advanceCurrentCoordinate(origin, vector: east, dt: 1, speedScale: 40)
XCTAssertEqual(next.latitude, origin.latitude, accuracy: 1e-7)
XCTAssertGreaterThan(next.longitude, origin.longitude)
XCTAssertTrue(doddEnvelopeContains(doddCenter, center: doddCenter))
XCTAssertFalse(doddEnvelopeContains(
    particleCoordinate(doddCenter, bearingDeg: 0, alongM: DODD_AXIS_M, acrossM: 0),
    center: doddCenter))
XCTAssertEqual(doddSeed(index: 3), doddSeed(index: 3))
```

- [ ] **Step 5: Implement pure local-tangent motion and deterministic seeds**

Use `0.514444` metres/second per knot, `STREAK_SPEED_SCALE = 40`, `DODD_AXIS_M = 360`, `DODD_SPREAD_M = 45`, and `DODD_STREAK_COUNT = 12`. The envelope exists only as a containment/recycle check; it creates no map feature.

- [ ] **Step 6: Verify and commit**

Run `CurrentStreakTests` and `git diff --check`, then stage `CurrentStreaks.swift`, its tests, and `project.yml` only if changed:

```bash
rtk git add Slackwater/CurrentStreaks.swift SlackwaterTests/CurrentStreakTests.swift project.yml
rtk git commit -m "feat: model Dodd map current approximation"
```

---

### Task 3: Animate certified and Dodd streaks in one MapLibre source

**Files:**
- Modify: `Slackwater/CurrentStreaks.swift`
- Modify: `Slackwater/CurrentFill.swift`
- Modify: `Slackwater/Theme.swift`
- Modify: `SlackwaterTests/CurrentStreakTests.swift`
- Modify: `SlackwaterTests/CurrentFillTests.swift`

**Interfaces:**
- Produces: `CurrentStreakAnimator.attach(to:map:fillField:patchField:)` and `stop()`.
- Consumes: patch-first closures returning `CurrentVector?`, plus `DoddMapFlowProvider`.
- Adds: one GeoJSON source, a foam-white rounded tail layer, and ramp-colored head layer.

- [ ] **Step 1: Write failing style-contract tests**

Assert the current-fill style includes one streak source and two layers when enabled, none when disabled, and the layers are ordered fill → patch → streaks → land. Pin tail color to `mapHex(SN.foamHex)` and head color to feature attribute `colour`; assert the serialized layers contain no `PIN_STATE_COLOUR` expression.

- [ ] **Step 2: Observe style RED**

Run only `CurrentFillTests`; expect missing source/layer assertions to fail.

- [ ] **Step 3: Expose the existing foam hex and add empty style layers**

Change the existing theme declaration without changing its value:

```swift
static let foamHex: UInt32 = 0xE4F0E4
static let foam = Color(hex: foamHex)
```

Create rounded line tails and small circle heads at `STREAK_MIN_ZOOM = 9`. Head features carry `colour: fillColourHex(forSpeedKn:)`; tails are constant foam.

- [ ] **Step 4: Write failing animator-state tests**

With injected samplers, prove patch wins over fill, a local bearing change curves history, nil recycles a certified particle, Dodd particles recycle at their envelope, histories never exceed `STREAK_HISTORY_LIMIT`, and `reduceMotion: true` leaves heads unchanged while still emitting features.

- [ ] **Step 5: Implement the animator by trimming the existing spike**

Port strong source retention, `.common` 30 Hz timer, zoom/visible-bounds cull, elapsed-time clamp, and deterministic state from `origin/spike/current-particles`. Exclude its launch flag, state colors, straight 1.2 km gate axes, logging, and analytic tails.

On each tick sample certified particles patch-first:

```swift
let vector = patchField?.sample(at: particle.head, time: fieldTime)
    ?? fillField?.sample(at: particle.head, time: fieldTime)
guard let vector else { recycle(&particle); continue }
particle.head = advanceCurrentCoordinate(
    particle.head, vector: vector, dt: reduceMotion ? 0 : elapsed,
    speedScale: STREAK_SPEED_SCALE)
```

Evaluate Dodd once per minute, advance all 12 particles with that one vector, and recycle only within its unrendered envelope. Keep bounded coordinate histories for curved certified tails.

- [ ] **Step 6: Wire ownership into CurrentFillRenderer**

`CurrentFillRenderer` owns one animator, passes its existing field instances on style attach, and calls `stop()` from `deinit`. Reattachment replaces the strong MapLibre source and clears histories; it does not create a second timer.

- [ ] **Step 7: Verify focused tests and commit**

```bash
rtk xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SlackwaterTests/CurrentStreakTests \
  -only-testing:SlackwaterTests/CurrentFillTests
rtk git diff --check
rtk git add Slackwater/CurrentStreaks.swift Slackwater/CurrentFill.swift Slackwater/Theme.swift \
  SlackwaterTests/CurrentStreakTests.swift SlackwaterTests/CurrentFillTests.swift
rtk git commit -m "feat: animate current speed and direction on the map"
```

---

### Task 4: Pin Dodd, verify the app, and open the internal PR

**Files:**
- Modify: `SlackwaterTests/CurrentStreakTests.swift`
- Modify: `SlackwaterTests/CurrentFillTests.swift` only if acceptance needs a public seam.
- Modify: `tools/package.json`, `tools/package-lock.json`, `Slackwater/Resources/chs-current-gates.json` only after the reviewed station-corrections release.

**Interfaces:**
- Consumes: released Dodd hydraulic-control coordinate and fitted-model fixture.
- Produces: pinned peak color/direction acceptance and recorded simulator behavior.

- [ ] **Step 1: Consume the reviewed station-corrections release**

After PR #15 is reviewed, merged, versioned, and tagged through its normal release process:

```bash
rtk npm install --prefix tools @sailingnaturali/station-corrections@latest
rtk npm run build:data --prefix tools
```

Assert `chs-dodd-narrows` resolves to `[49.13546639419797, -123.81735084108287]`. Do not use a local-path lockfile.

- [ ] **Step 2: Add the pinned Dodd acceptance test**

With an injected `+9.43` knot fixture, assert the cluster center is the regenerated gate coordinate, head color is `#c93a32`, bearing is flood; repeat with `-9.43` and assert reciprocal bearing. Advance one second at scale 40 and assert movement exceeds one metre along the expected set.

- [ ] **Step 3: Run focused and full verification**

```bash
rtk test ./scripts/test.sh
rtk test ./scripts/test.sh --full
rtk git diff --check
rtk git status --short --branch
```

- [ ] **Step 4: Inspect Dodd at peak on iPhone**

Launch centered at `49.13546639419797,-123.81735084108287`, zoom 11, with a pinned app clock/model fixture. Record one screenshot and short video. Confirm: dark-red heads, white tails, correct flood/ebb reversal, no filled Dodd polygon, no overlap obscuring the station label, smooth frame behavior, and Reduce Motion freeze.

Record actual particle count, cadence, and observed frame behavior in the PR body. Tune cadence first, then density, only if measurement shows a problem.

- [ ] **Step 5: Commit, authenticate, push, and open the internal PR**

```bash
rtk git add SlackwaterTests/CurrentStreakTests.swift SlackwaterTests/CurrentFillTests.swift \
  tools/package.json tools/package-lock.json Slackwater/Resources/chs-current-gates.json
rtk git commit -m "test: pin Dodd map current approximation"
rtk gh auth status
rtk git log --oneline origin/main..HEAD
rtk git push -u origin feat/current-map-approximation
rtk gh pr create --repo openwatersio/slackwater-ios \
  --title "Show current speed and direction on the map" \
  --body "Adds locally advected streaks over certified fields and a compact fitted-current approximation at Dodd Narrows. Dodd gets no filled area or passage-planning claim; detailed timing remains in the station view. Includes Reduce Motion and focused/full verification."
```

Do not merge the PR.
