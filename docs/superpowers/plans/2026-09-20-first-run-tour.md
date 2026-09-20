# First-Run Tour Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach the station detail view with five coach marks drawn over the real thing on first run — the reading, the swipe (demonstrated by gliding to tonight's stars and then to the moon), the moon tile, and the favourite star.

**Architecture:** One `@Observable` `TourCoach` singleton holds the step and a glide token. `ScrubDetailScaffold` gains a single `.overlayPreferenceValue` layer that positions a glass capsule against anchors published by four existing views. The scrub demo reuses the strip's existing animated-magnet path by bumping a token the strip observes. Nothing in the feature reads download state, the network, or (except for picking a station) location.

**Tech Stack:** SwiftUI, iOS 26 deployment floor, XCTest + XCUITest, `xcodebuild` via `scripts/test.sh`.

**Spec:** `docs/superpowers/specs/2026-09-20-first-run-tour-design.md`

## Global Constraints

- **Deployment floor is iOS 26.0** (`project.yml:8`). No `#available` fences.
- **Never run two `xcodebuild` invocations on this machine at once.** `scripts/test.sh` self-serializes on `/tmp/slackwater-test.lock`. For a compile check use `lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20`. `lockf -t 0` fails immediately if a run holds the machine — wait, never force it.
- **Compile-check before, and usually instead of, the suite** — a minute versus fifteen.
- **Do not add a parameter to `TimelineScrubStrip`.** Four detail views construct one (`TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView`, `OnlineGateDetailView`) and CLAUDE.md requires reviewing all four for any scrubber presentation change. Every hook in this plan goes through the `TourCoach` observable singleton instead, the way `ScrubDetailScaffold` already reads `LinkedInstant.shared.pending` (`Theme.swift:954`).
- **No new dependency, no new general-purpose component.** The capsule is `.buttonStyle(.glass)` + `.buttonBorderShape(.capsule)`, the `nowPill` idiom at `TimelineStrip.swift:1683`. There is no tooltip/TipKit/popover anywhere in the app target and this does not add the first one as an abstraction.
- **Copy is sentence case, no exclamation marks, no "Welcome".** Follow the `pr-writing` skill's voice for any user-facing string.
- **Branch is `first-run-tour`.** Commit after every task. Do not open a PR unless asked.
- **A subagent's backgrounded `xcodebuild` dies when its turn ends.** Implementers compile-check only; the coordinator runs `scripts/test.sh` and relays results.

---

### Task 1: `TourCoach` — the state machine

**Files:**
- Create: `Slackwater/TourCoach.swift`
- Test: `SlackwaterTests/TourCoachTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `TourCoach.Step` (`.read`, `.stars`, `.moon`, `.moonCard`, `.star`), `TourCoach.shared`, `var step: Step?`, `var station: String?`, `var glideToken: Int`, `func arm()`, `func begin(on station: String, skySteps: Bool)`, `func advance()`, `func finish()`, and `let seenTourKey: String`.

- [ ] **Step 1: Write the failing test**

Create `SlackwaterTests/TourCoachTests.swift`:

```swift
// Slackwater — GPL v3. The first-run tour's step machine: ordering, the
// arctic skip, and the one-way seen flag.
import XCTest
@testable import Slackwater

@MainActor
final class TourCoachTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.removeObject(forKey: seenTourKey)
        TourCoach.shared.step = nil
        TourCoach.shared.station = nil
    }

    func testWalksAllFiveStepsThenFinishes() {
        let c = TourCoach.shared
        c.arm()
        c.begin(on: "noaa/9449880", skySteps: true)
        XCTAssertEqual(c.step, .read)
        c.advance(); XCTAssertEqual(c.step, .stars)
        c.advance(); XCTAssertEqual(c.step, .moon)
        c.advance(); XCTAssertEqual(c.step, .moonCard)
        c.advance(); XCTAssertEqual(c.step, .star)
        c.advance()
        XCTAssertNil(c.step, "the last advance ends the tour")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: seenTourKey))
    }

    // Above the Arctic Circle in summer there is no sunset in the window, so
    // there is nothing true to say about stars or the moon in the sky.
    func testSkipsSkyStepsWhenThereIsNoNight() {
        let c = TourCoach.shared
        c.arm()
        c.begin(on: "noaa/9449880", skySteps: false)
        XCTAssertEqual(c.step, .read)
        c.advance()
        XCTAssertEqual(c.step, .moonCard, "stars and moon are skipped, not shown empty")
        c.advance(); XCTAssertEqual(c.step, .star)
    }

    func testFinishIsOneWayAndArmRespectsIt() {
        let c = TourCoach.shared
        c.arm()
        c.begin(on: "noaa/9449880", skySteps: true)
        c.finish()
        XCTAssertNil(c.step)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: seenTourKey))

        c.arm()
        XCTAssertFalse(c.armed, "a seen tour does not re-arm on the next launch")
    }

    // Replay from Settings ignores the flag — that is the whole point of it.
    func testReplayBeginsEvenAfterFinish() {
        let c = TourCoach.shared
        c.arm(); c.begin(on: "noaa/9449880", skySteps: true); c.finish()
        c.replay(on: "noaa/9449880", skySteps: true)
        XCTAssertEqual(c.step, .read)
    }

    func testGlideTokenRisesOnEveryRequest() {
        let c = TourCoach.shared
        let before = c.glideToken
        c.requestGlide()
        c.requestGlide()
        XCTAssertEqual(c.glideToken, before + 2)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```sh
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```
Expected: FAIL to compile — `cannot find 'TourCoach' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Slackwater/TourCoach.swift`:

```swift
// Slackwater — GPL v3. The first-run tour: which coach mark is showing, which
// station it belongs to, and the token the strip watches to animate a glide.
//
// App-level state read directly by the views that need it, the way
// `LinkedInstant` is (GateView.swift) — deliberately NOT a parameter, because
// a parameter on `TimelineScrubStrip` fans out to four detail views.
import SwiftUI

let seenTourKey = "slackwater.seenTour"

@Observable final class TourCoach {
    /// In order. `stars` and `moon` are dropped when the window holds no night
    /// (see `skySteps`), so never advance by `rawValue` — use `next(after:)`.
    enum Step: Int, CaseIterable { case read, stars, moon, moonCard, star }

    static let shared = TourCoach()

    /// nil means no tour is running. Non-nil is the mark on screen.
    var step: Step?
    /// The station id the running tour belongs to. A detail for any other
    /// station must not draw its marks.
    var station: String?
    /// Bumped to ask the strip for an animated ride; see `glide(to:)`.
    var glideToken = 0

    /// First launch has armed the tour but no detail has claimed it yet.
    private(set) var armed = false
    private var skySteps = true

    /// Called once on launch. A tour that has already been seen does not arm.
    func arm() {
        armed = !UserDefaults.standard.bool(forKey: seenTourKey)
    }

    /// A detail with a real timeline claims the armed tour.
    func begin(on station: String, skySteps: Bool) {
        guard armed else { return }
        armed = false
        self.station = station
        self.skySteps = skySteps
        step = .read
    }

    /// Settings' "How to read a station" — the seen flag does not gate this.
    func replay(on station: String, skySteps: Bool) {
        armed = true
        begin(on: station, skySteps: skySteps)
    }

    func advance() {
        guard let step else { return }
        if let next = next(after: step) { self.step = next } else { finish() }
    }

    /// Skip, or leaving the detail. One way: the seen flag is written here and
    /// nowhere else, and there is no resume-later state by design.
    func finish() {
        step = nil
        station = nil
        armed = false
        UserDefaults.standard.set(true, forKey: seenTourKey)
    }

    func requestGlide() { glideToken += 1 }

    private func next(after step: Step) -> Step? {
        Step.allCases
            .filter { skySteps || ($0 != .stars && $0 != .moon) }
            .first { $0.rawValue > step.rawValue }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./scripts/test.sh --only TourCoachTests` (if the script has no `--only`, run the full unit plan and read `build/results-*.xcresult` — never two `xcodebuild`s at once).
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TourCoach.swift SlackwaterTests/TourCoachTests.swift
git commit -m "Add the first-run tour's step machine

Five ordered marks, with the two sky steps droppable for a window that
holds no night. The seen flag is written in finish() and nowhere else,
and there is no resume-later state: a half-finished tour reappearing
days later is worse than one that ended, and Settings carries replay."
```

---

### Task 2: The glide — make the strip actually animate

This is the one task that can fail for reasons the design cannot predict, so it comes before everything that depends on it. If the strip teleports, the scrub demo teaches nothing and the design needs revisiting before more is built on it.

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:1636-1645` (add one `.onChange` beside the existing scene-phase one)
- Modify: `Slackwater/Theme.swift:1011-1022` (add `glide(to:)` beside `jump(to:)`)
- Test: manual, on the simulator, plus a UI assertion in Task 9

**Interfaces:**
- Consumes: `TourCoach.shared.glideToken`, `TourCoach.shared.requestGlide()` from Task 1.
- Produces: `ScrubDetailScaffold.glide(to:)` — `private func glide(to t: Date)`, used only by the overlay added in Task 5.

**Background the implementer needs:** `updateUIView` takes its animated branch only when `jumpToken` differs from `co.seenJump` (`TimelineStrip.swift:1216-1243`); otherwise it falls through to `sv.contentOffset = desired`, an instant landing (`:1245-1252`). `jumpToken` is `@State` private to `TimelineScrubStrip` (`:1613`), bumped today only at `:1642` (scene phase), `:1658` (commentary pill) and `:1684` (Now pill). Travel under `Timeline.snapJumpHours` (`7 * 24`, `:121`) rides the magnet; past it, it snaps. Reduce Motion lands instantly by design (`:1233`) and that is correct behaviour, not a bug to work around.

- [ ] **Step 1: Add the glide observer to the strip**

In `Slackwater/TimelineStrip.swift`, immediately after the existing scene-phase `.onChange` that ends at line 1645, add:

```swift
            // The first-run tour's scrub demo. The animated magnet ride is
            // reachable only through `jumpToken`, which is this view's own
            // @State — so the tour asks for it through the observable rather
            // than through a parameter, which would fan out to all four
            // detail views (CLAUDE.md).
            .onChange(of: TourCoach.shared.glideToken) { _, _ in
                jumpToken += 1
            }
```

- [ ] **Step 2: Add `glide(to:)` to the scaffold**

In `Slackwater/Theme.swift`, directly after `jump(to:)` (which ends at line 1022), add:

```swift
    /// `jump(to:)` with the animated ride the tour's demo depends on. The
    /// token bump comes FIRST so the strip's `jumpToken` is already different
    /// by the time `scrubTime`'s change reaches `updateUIView` — reversed,
    /// the offset write can land in the pass before the token and the strip
    /// teleports.
    private func glide(to t: Date) {
        TourCoach.shared.requestGlide()
        jump(to: t)
    }
```

- [ ] **Step 3: Prove the glide with a temporary probe**

`glide(to:)` has no caller until Task 5, so verify it now rather than discovering it in Task 9. Temporarily add to `ScrubDetailScaffold.body`, just after `.onAppear(perform: applyLinkedInstant)` at `Theme.swift:953`:

```swift
            .onAppear {
                guard CommandLine.arguments.contains("-glideProbe") else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    glide(to: appNow().addingTimeInterval(8 * 3600))
                }
            }
```

- [ ] **Step 4: Run it and watch**

```sh
./scripts/first-run.sh
# then in Xcode, or via simctl, launch with -glideProbe and open any bundled
# tide station, e.g. Friday Harbor
```
Expected: two seconds after the detail opens, the curve **slides** roughly eight hours under the centreline over about 0.3 s and the sky changes as it travels. It must not teleport.

If it teleports: the token and the offset are landing in the same update pass and SwiftUI is coalescing them. Fall back to bumping the token and setting `scrubTime` in two passes (`Task { @MainActor in }` between them) and re-verify. **Report the result before continuing** — a teleport that cannot be fixed here invalidates the spec's scrub demo.

- [ ] **Step 5: Remove the probe and commit**

Delete the `-glideProbe` `.onAppear` block added in Step 3. Keep the observer and `glide(to:)`.

```bash
git add Slackwater/TimelineStrip.swift Slackwater/Theme.swift
git commit -m "Give the scaffold an animated glide the tour can drive

The magnet ride is reachable only through jumpToken, which is
TimelineScrubStrip's own @State — so jump(to:) has always landed
instantly, which is why a shared link arrives without a glide. The strip
now watches TourCoach's token, so no parameter is added and none of the
four detail views that build a strip are touched."
```

---

### Task 3: The two scrub targets

**Files:**
- Modify: `Slackwater/TourCoach.swift` (append)
- Test: `SlackwaterTests/TourTargetTests.swift`

**Interfaces:**
- Consumes: `TimelineDay` (`TimelineStrip.swift:167-175`: `offset: Int`, `start: Date`, `sunrise: Date?`, `sunset: Date?`, `moonrise: Date?`, `moonset: Date?`).
- Produces: `func tourStarsTime(days: [TimelineDay], after now: Date) -> Date?` and `func tourMoonTime(days: [TimelineDay], after now: Date) -> Date?`, both free functions in `TourCoach.swift`.

**Background:** `SkyState` refuses to search for rise/set times because a lookup is ~0.005 ms against ~0.6 ms for an Almanac search, and it runs every scrub frame (`Theme.swift:196-200`). These functions inherit that: `TimelineData.days` already holds the times, spanning offsets −3…8 (`TimelineStrip.swift:199`). Do not call Almanac here.

- [ ] **Step 1: Write the failing test**

Create `SlackwaterTests/TourTargetTests.swift`:

```swift
// Slackwater — GPL v3. The tour's two scrub targets, read off the timeline's
// own rise and set times rather than searched for.
import XCTest
@testable import Slackwater

final class TourTargetTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_758_000_000)  // arbitrary fixed epoch
    private func h(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }

    private func day(_ offset: Int, sunrise: Double?, sunset: Double?,
                     moonrise: Double?, moonset: Double?) -> TimelineDay {
        TimelineDay(offset: offset, start: h(Double(offset) * 24),
                    sunrise: sunrise.map(h), sunset: sunset.map(h),
                    moonrise: moonrise.map(h), moonset: moonset.map(h))
    }

    // Stars: the next sunset after now, plus an hour for real darkness.
    func testStarsTimeIsAnHourAfterTheNextSunset() {
        let days = [day(0, sunrise: 6, sunset: 20, moonrise: 22, moonset: 30)]
        XCTAssertEqual(tourStarsTime(days: days, after: h(12)), h(21))
    }

    func testStarsTimeIgnoresASunsetAlreadyPast() {
        let days = [day(0, sunrise: 6, sunset: 20, moonrise: 22, moonset: 30),
                    day(1, sunrise: 30, sunset: 44, moonrise: 46, moonset: 54)]
        XCTAssertEqual(tourStarsTime(days: days, after: h(21)), h(45))
    }

    // Midnight sun: no sunset in the window at all.
    func testStarsTimeIsNilWhenTheSunNeverSets() {
        let days = [day(0, sunrise: 6, sunset: nil, moonrise: 22, moonset: 30),
                    day(1, sunrise: nil, sunset: nil, moonrise: nil, moonset: nil)]
        XCTAssertNil(tourStarsTime(days: days, after: h(12)))
    }

    // Moon: the midpoint of the first overlap between the moon being up and
    // the sun being down.
    func testMoonTimeIsTheMidpointOfTheFirstDarkMoonSpan() {
        // dark 20→30, moon up 22→30 ⇒ overlap 22→30, midpoint 26.
        let days = [day(0, sunrise: 6, sunset: 20, moonrise: 22, moonset: 30),
                    day(1, sunrise: 30, sunset: 44, moonrise: 46, moonset: 54)]
        XCTAssertEqual(tourMoonTime(days: days, after: h(12)), h(26))
    }

    // A moon only ever up in daylight has no dark span on that day; the
    // search continues into the next one rather than giving up.
    func testMoonTimeSkipsADaytimeOnlyMoon() {
        // day 0: moon up 8→16, all inside daylight 6→20 ⇒ no overlap.
        // day 1: dark 44→54, moon up 46→52 ⇒ overlap 46→52, midpoint 49.
        let days = [day(0, sunrise: 6, sunset: 20, moonrise: 8, moonset: 16),
                    day(1, sunrise: 30, sunset: 44, moonrise: 46, moonset: 52),
                    day(2, sunrise: 54, sunset: 68, moonrise: nil, moonset: nil)]
        XCTAssertEqual(tourMoonTime(days: days, after: h(12)), h(49))
    }

    func testMoonTimeIsNilWhenTheSunNeverSets() {
        let days = [day(0, sunrise: 6, sunset: nil, moonrise: 8, moonset: 16)]
        XCTAssertNil(tourMoonTime(days: days, after: h(12)))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run the compile check from Global Constraints.
Expected: FAIL — `cannot find 'tourStarsTime' in scope`.

- [ ] **Step 3: Write the implementation**

Append to `Slackwater/TourCoach.swift`:

```swift
// MARK: - Where the demo scrubs to

/// An hour past the next sunset: late enough that the backdrop is actually
/// dark and the stars are worth pointing at.
private let darkMargin: TimeInterval = 3600

/// The moment the tour glides to for its stars beat, or nil above the Arctic
/// Circle in summer, where the window holds no sunset at all.
///
/// Read off `TimelineDay`, never searched for: `SkyState` documents why a rise
/// or set search does not belong on this page (Theme.swift), and the timeline
/// build has already paid for these.
func tourStarsTime(days: [TimelineDay], after now: Date) -> Date? {
    days.compactMap(\.sunset)
        .sorted()
        .first { $0.addingTimeInterval(darkMargin) > now }
        .map { $0.addingTimeInterval(darkMargin) }
}

/// The midpoint of the first span where the moon is up AND the sun is down —
/// the only kind of moment where "that is the real moon" is worth showing.
/// Nil when no such span falls in the window.
func tourMoonTime(days: [TimelineDay], after now: Date) -> Date? {
    let sunsets = days.compactMap(\.sunset).sorted()
    let sunrises = days.compactMap(\.sunrise).sorted()
    // A dark span runs from a sunset to the next sunrise after it.
    let dark: [(Date, Date)] = sunsets.compactMap { set in
        sunrises.first { $0 > set }.map { (set, $0) }
    }
    let moonUp: [(Date, Date)] = days.compactMap { d in
        guard let rise = d.moonrise else { return nil }
        // A lunar day is 24h50m, so the set can belong to the next entry.
        guard let set = days.compactMap(\.moonset).sorted().first(where: { $0 > rise })
        else { return nil }
        return (rise, set)
    }
    return dark.flatMap { d in
        moonUp.compactMap { m -> Date? in
            let lo = max(d.0, m.0), hi = min(d.1, m.1)
            guard lo < hi else { return nil }
            return lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
        }
    }
    .sorted()
    .first { $0 > now }
}
```

- [ ] **Step 4: Run the tests**

Run: `./scripts/test.sh` filtered to `TourTargetTests`.
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TourCoach.swift SlackwaterTests/TourTargetTests.swift
git commit -m "Find the tour's two scrub targets without an almanac search

SkyState refuses to search for rise and set times on every scrub frame,
and TimelineDay already carries them, so both targets are pure functions
over days the timeline build has already paid for. A window with no
sunset resolves neither, which is how the arctic case stays honest."
```

---

### Task 4: Picking the station

**Files:**
- Modify: `Slackwater/TourCoach.swift` (append)
- Test: `SlackwaterTests/TourStationTests.swift`

**Interfaces:**
- Consumes: `StationIndex.bundled.tides` → `[StationIndexInfo]` with `id`, `name`, `latitude`, `longitude` (`StationIndex.swift:13-20`).
- Produces: `func tourStationID(near: CLLocationCoordinate2D?) -> String`.

**Background:** `StationIndex.bundled` is the lightweight identity index, not the full catalog — this is exactly the split #317 asks for, so the pick costs nothing at launch. Do not reach for `StationItem.all`, which decodes 7.5 MB of constituents. `noaa/9449880` is Friday Harbor, the station `GateView.swift:12` already shows as its example.

- [ ] **Step 1: Write the failing test**

Create `SlackwaterTests/TourStationTests.swift`:

```swift
// Slackwater — GPL v3. Which station the tour teaches on.
import XCTest
import CoreLocation
@testable import Slackwater

final class TourStationTests: XCTestCase {
    // Victoria BC: Canadian fix, but the nearby bundled NOAA stations need no
    // download, which is what lets the tour run during the CHS wait.
    func testPicksANearbyBundledStationForAVictoriaFix() {
        let id = tourStationID(near: CLLocationCoordinate2D(latitude: 48.42, longitude: -123.37))
        let picked = StationIndex.bundled.tides.first { $0.id == id }
        XCTAssertNotNil(picked, "the pick must name a bundled station")
        let d = CLLocation(latitude: picked!.latitude, longitude: picked!.longitude)
            .distance(from: CLLocation(latitude: 48.42, longitude: -123.37))
        XCTAssertLessThan(d, 60_000, "a Victoria fix should teach on local water")
    }

    // No fix at all — denied location, or the gate's search bypass.
    func testFallsBackToFridayHarborWithNoFix() {
        XCTAssertEqual(tourStationID(near: nil), "noaa/9449880")
    }

    // Mid-Pacific: nothing bundled within range, so the fallback holds rather
    // than teaching on a station thousands of miles away.
    func testFallsBackWhenNothingIsInRange() {
        XCTAssertEqual(tourStationID(near: CLLocationCoordinate2D(latitude: 0, longitude: -150)),
                       "noaa/9449880")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run the compile check. Expected: FAIL — `cannot find 'tourStationID' in scope`.

- [ ] **Step 3: Write the implementation**

Append to `Slackwater/TourCoach.swift`:

```swift
// MARK: - Which station the tour teaches on

/// Friday Harbor — the station the gate already showed as its example
/// (GateView.swift), so the card someone just looked at is the one they now
/// learn to read.
let tourFallbackStationID = "noaa/9449880"

/// Past this there is no "local water" claim worth making, and the fallback
/// is more honest than a station on another coast.
private let tourStationRangeKm = 150.0

/// The nearest bundled tide station to the fix, else Friday Harbor.
///
/// Reads `StationIndex.bundled`, the identity-only index — never
/// `StationItem.all`, whose decode is the launch cost #317 is about. Bundled
/// stations need no download, which is what lets the tour run with no network
/// and no location at all.
func tourStationID(near fix: CLLocationCoordinate2D?) -> String {
    guard let fix else { return tourFallbackStationID }
    let here = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
    let nearest = StationIndex.bundled.tides
        .map { ($0.id, CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)) }
        .min { $0.1 < $1.1 }
    guard let nearest, nearest.1 <= tourStationRangeKm * 1000 else { return tourFallbackStationID }
    return nearest.0
}
```

Add `import CoreLocation` to the top of `TourCoach.swift` if it is not already there.

- [ ] **Step 4: Run the tests**

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TourCoach.swift SlackwaterTests/TourStationTests.swift
git commit -m "Pick the tour's station from the bundled index

Nearest bundled tide station to the fix, else Friday Harbor — the one the
gate already showed. Reads StationIndex.bundled, the identity-only index,
so the pick adds nothing to the launch cost #317 is about, and bundled
stations need no download, which is what lets the tour run offline and
with location denied."
```

---

### Task 5: The coach mark overlay

**Files:**
- Create: `Slackwater/TourOverlay.swift`
- Modify: `Slackwater/Theme.swift` (anchor on the moon tile and `tile-moon` id; overlay on the scaffold)
- Modify: `Slackwater/DetailHeader.swift:85-96` (anchor on the star)
- Modify: `Slackwater/TimelineStrip.swift:1632-1635` (anchor on the strip)
- Test: covered by Task 9's UI walk

**Interfaces:**
- Consumes: `TourCoach.Step`, `TourCoach.shared` (Task 1), `glide(to:)` (Task 2), `tourStarsTime`/`tourMoonTime` (Task 3).
- Produces: `TourAnchorKey: PreferenceKey` with `Value == [TourCoach.Step: Anchor<CGRect>]`, `extension View { func tourAnchor(_ step: TourCoach.Step) -> some View }`, and `struct TourMarkLayer: View`.

- [ ] **Step 1: Write the anchor plumbing and the mark**

Create `Slackwater/TourOverlay.swift`:

```swift
// Slackwater — GPL v3. The first-run tour's coach marks: one preference-fed
// overlay over the real detail, so nothing here is a second copy of the UI.
import SwiftUI

struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourCoach.Step: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [TourCoach.Step: Anchor<CGRect>],
                       nextValue: () -> [TourCoach.Step: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's bounds as the anchor for one tour step.
    func tourAnchor(_ step: TourCoach.Step) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [step: $0] }
    }
}

/// What each mark says. The copy is deliberately about what the thing IS, not
/// about the app: the backdrop being the real sky is the fact nobody guesses.
func tourCopy(_ step: TourCoach.Step, station: String, arrived: Bool) -> String {
    switch step {
    case .read:
        return "The reading is whatever sits on the centre line."
    case .stars:
        return arrived
            ? "Those are the actual stars over \(station) right now."
            : "Swipe the curve to move through time."
    case .moon:
        return "And that is the real moon, at tonight's phase."
    case .moonCard:
        return "Tap the moon for its rise, set and phase."
    case .star:
        return "Star a station to keep it at the top of your list."
    }
}

/// The mark itself: a ring around the thing, and a glass capsule beside it.
struct TourMarkLayer: View {
    let anchors: [TourCoach.Step: Anchor<CGRect>]
    let proxy: GeometryProxy
    let stationName: String
    /// True once the glide for this step has settled, which swaps the stars
    /// copy from the instruction to the payoff.
    let arrived: Bool
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var coach = TourCoach.shared

    var body: some View {
        if let step = coach.step, let anchor = anchors[step] {
            let rect = proxy[anchor]
            let below = rect.midY < proxy.size.height / 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SN.leaf, lineWidth: 2)
                    .frame(width: rect.width + 8, height: rect.height + 8)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)

                capsule(step: step)
                    .frame(maxWidth: 320)
                    .position(x: proxy.size.width / 2,
                              y: below ? rect.maxY + 56 : max(rect.minY - 56, 60))
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: step)
        }
    }

    private func capsule(step: TourCoach.Step) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if step == .stars {
                    // The platform's own swipe glyph. `.symbolEffect` stills
                    // itself under Reduce Motion without being asked.
                    Image(systemName: "hand.draw.fill")
                        .symbolEffect(.wiggle.left)
                }
                Text(tourCopy(step, station: stationName, arrived: arrived))
                    .font(.callout)
                    .foregroundStyle(SN.paper)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 16) {
                Button("Skip", action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(SN.foam.opacity(0.8))
                    .accessibilityIdentifier("tour-skip")
                Spacer()
                Button(step == .star ? "Done" : "Next", action: onNext)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SN.paper)
                    .accessibilityIdentifier("tour-next")
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("tour-mark")
    }
}
```

- [ ] **Step 2: Compile-check**

Run the compile check from Global Constraints.
Expected: PASS. If `.symbolEffect(.wiggle.left)` does not resolve, substitute `.symbolEffect(.pulse)` and note the substitution in the commit message — the glyph matters more than the motion.

- [ ] **Step 3: Attach the four anchors**

`Slackwater/TimelineStrip.swift`, on the strip, immediately after `.accessibilityIdentifier("timeline-strip")` at line 1635:

```swift
            .tourAnchor(.stars)
```

(One anchor serves both `.stars` and `.moon`; the layer falls back to the `.stars` anchor when the step is `.moon` — see Step 4.)

`Slackwater/DetailHeader.swift`, after `.accessibilityIdentifier("detail-favorite")` at line 95:

```swift
                        .tourAnchor(.star)
```

`Slackwater/Theme.swift`, on the `LeadCard`, after `.accessibilityIdentifier("detail-reading")` at line 626:

```swift
        .tourAnchor(.read)
```

`Slackwater/Theme.swift`, on the Moon `ReadoutTile` in `SummaryTiles` — the tile built at lines 742-751 gets both a new identifier and the anchor:

```swift
                .accessibilityIdentifier("tile-moon")
                .tourAnchor(.moonCard)
```

- [ ] **Step 4: Hang the layer on the scaffold**

In `Slackwater/Theme.swift`, on `ScrubDetailScaffold.body`'s `ScrollView`, after `.ignoresSafeArea(edges: .top)` at line 944, add:

```swift
            .overlayPreferenceValue(TourAnchorKey.self) { anchors in
                // `.stars` and `.moon` both point at the strip; only the copy
                // and the glide target differ.
                let resolved = TourCoach.shared.step == .moon
                    ? anchors.merging([.moon: anchors[.stars]].compactMapValues { $0 }) { _, n in n }
                    : anchors
                TourMarkLayer(anchors: resolved, proxy: geo,
                              stationName: name, arrived: tourArrived,
                              onNext: tourNext, onSkip: { TourCoach.shared.finish() })
                    .opacity(TourCoach.shared.station == favoriteId ? 1 : 0)
                    .allowsHitTesting(TourCoach.shared.station == favoriteId)
            }
```

Add to `ScrubDetailScaffold`'s stored properties, beside `@State private var topHeight`:

```swift
    /// The tour's glide has settled, which swaps the stars copy from the
    /// instruction to the payoff.
    @State private var tourArrived = false
```

And add, beside `glide(to:)`:

```swift
    /// Advance the tour, gliding first where the next mark needs the strip
    /// somewhere else. The glide targets are read off the timeline the page is
    /// already drawing — no almanac search (see `tourStarsTime`).
    private func tourNext() {
        tourArrived = false
        TourCoach.shared.advance()
        guard let step = TourCoach.shared.step, let days = timeline?.days else { return }
        let target: Date? = switch step {
        case .stars: tourStarsTime(days: days, after: appNow())
        case .moon: tourMoonTime(days: days, after: appNow())
        default: nil
        }
        guard let target else { return }
        glide(to: target)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            tourArrived = true
        }
    }
```

- [ ] **Step 5: Compile-check and commit**

Run the compile check. Expected: PASS.

```bash
git add Slackwater/TourOverlay.swift Slackwater/Theme.swift \
        Slackwater/DetailHeader.swift Slackwater/TimelineStrip.swift
git commit -m "Draw the tour's coach marks over the real detail

One preference-fed overlay on the shared scaffold, so all four detail
views carry it and CLAUDE.md's four-consumer rule is satisfied by
construction rather than by review. The capsule is the nowPill glass
idiom; no tooltip component is introduced as an abstraction."
```

---

### Task 6: The drag passes through, and each target scrolls into view

Two properties that are easy to get wrong and that nothing above proves.

**Files:**
- Modify: `Slackwater/TourOverlay.swift` (hit testing)
- Modify: `Slackwater/Theme.swift` (`ScrollViewReader`, `.id(step)` tags, the scrub-through advance)

**Interfaces:**
- Consumes: everything from Task 5.
- Produces: no new names.

- [ ] **Step 1: Make the layer transparent to touches except the capsule**

In `TourMarkLayer.body`, the ring already carries `.allowsHitTesting(false)`. Confirm the outer `ZStack` has **no** background and no `.contentShape`, so the only hit-testable thing in the layer is the capsule. A real drag on the strip must reach the `UIScrollView` underneath — this is what lets step 2 clear on the user's own swipe rather than only on a Next tap.

- [ ] **Step 2: Advance the stars step on a real drag**

In `Slackwater/Theme.swift`, on the scaffold's `ScrollView`, beside the overlay added in Task 5:

```swift
            // The user's own swipe is as good as Next, which is the whole
            // point of a demo you can interrupt. The tour's own glide writes
            // scrubTime too, so only a change AFTER the glide settled counts.
            .onChange(of: scrubTime) { _, _ in
                guard TourCoach.shared.step == .stars, tourArrived else { return }
                tourNext()
            }
```

- [ ] **Step 3: Bring each target into view before its mark appears**

Wrap the scaffold's `ScrollView` (`Theme.swift:888`) in a `ScrollViewReader`, which hands the body a proxy — the `.onChange` below goes **inside** that closure so it can close over it, not outside where the name does not exist:

```swift
        GeometryReader { geo in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    // …unchanged body…
                }
                // …the existing modifiers, then:
                .onChange(of: TourCoach.shared.step) { _, step in
                    guard let step, TourCoach.shared.station == favoriteId else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scrollProxy.scrollTo(step, anchor: .center)
                    }
                }
            }
        }
```

Then tag each of the four anchored views with its step, beside the `.tourAnchor(...)` added in Task 5 — `.id(TourCoach.Step.read)` on the `LeadCard`, `.id(TourCoach.Step.stars)` on the strip, `.id(TourCoach.Step.moonCard)` on the moon tile, `.id(TourCoach.Step.star)` on the favourite button.

The star is in the header and the moon tile is below the strip, so without this the mark for one of them points off-screen.

**Watch for one trap:** adding `.id(...)` to a view that already carries state resets that state when the id changes. These ids are constant per view, so nothing resets — but do not be tempted to make them vary by step.

- [ ] **Step 4: Compile-check, then verify by hand**

Run the compile check, then `./scripts/first-run.sh` and walk the tour on the simulator. Confirm, and **report each explicitly**:
1. Every mark is on screen, beside its thing.
2. Dragging the strip during the stars mark advances the tour.
3. The moon mark scrolls the page down, and the star mark scrolls it back up.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TourOverlay.swift Slackwater/Theme.swift
git commit -m "Let a real swipe advance the tour, and scroll each mark into view

The overlay hit-tests only on its capsule, so a drag reaches the scroll
view underneath and the user's own swipe clears the stars mark — a demo
worth interrupting. The star sits in the header and the moon tile below
the strip, so each mark scrolls its target to centre first."
```

---

### Task 7: Arming and firing

**Files:**
- Modify: `Slackwater/SlackwaterApp.swift:8-24` (arm in `init`)
- Modify: `Slackwater/Theme.swift` (claim the armed tour on a real timeline; end it on leaving)
- Modify: `Slackwater/StationListView.swift:225-235` (the location-path open)

**Interfaces:**
- Consumes: `TourCoach.arm()`, `.begin(on:skySteps:)`, `.finish()`, `tourStationID(near:)`, `tourStarsTime`.
- Produces: no new names.

- [ ] **Step 1: Arm on launch**

In `Slackwater/SlackwaterApp.swift`'s `init()`, after the existing `AppGroup.migrateIfNeeded` call and the seed hooks:

```swift
        TourCoach.shared.arm()
```

Order matters: `applySeedHooksIfRequested()` writes `seenTourKey` for `-resetTour`/`-seedTour` (Task 8), so arming must come after it.

- [ ] **Step 2: Claim the armed tour from a detail that has something to teach**

In `Slackwater/Theme.swift`, on `ScrubDetailScaffold.body`, beside the existing `.onAppear(perform: applyLinkedInstant)` at line 953:

```swift
            // A waiting page or an unavailable station has no curve, no sky,
            // no moon tile and no scrubber — nothing to teach — so the tour
            // stays armed and fires on the next detail that does.
            .onChange(of: timeline?.revision, initial: true) { _, _ in
                guard let days = timeline?.days else { return }
                TourCoach.shared.begin(
                    on: favoriteId,
                    skySteps: tourStarsTime(days: days, after: appNow()) != nil)
            }
            .onDisappear {
                if TourCoach.shared.station == favoriteId { TourCoach.shared.finish() }
            }
```

`begin` already no-ops unless the tour is armed, so this is safe on every detail, every time.

- [ ] **Step 3: Open a station on the location path**

In `Slackwater/StationListView.swift`, inside the existing `.onAppear` at lines 225-235, after the `pendingDeepLink` branch:

```swift
            // First run on the location path: the gate has resolved (a fix or
            // a denial) and nothing else has claimed the tour, so bring the
            // user to a detail that can teach. A bundled station needs no
            // download, so this works offline and with location denied.
            if TourCoach.shared.armed, !gateSearchHandoff, pendingDeepLink == nil,
               let item = StationItem.byId[tourStationID(near: loc.location?.coordinate)] {
                open(item)
            }
```

Read the `gateSearchHandoff` and `pendingDeepLink` values **before** the branches above consume them, or hoist this block above them — a search bypass or a deep link must win, because that user asked for something specific.

- [ ] **Step 4: Compile-check, then verify all three entry paths**

Run the compile check, then `./scripts/first-run.sh` three times and confirm, reporting each:
1. **Location path** — grant location, land on the list, get pushed into a nearby station, tour runs.
2. **Search bypass** — tap "Search for a place", open any station yourself, tour runs there and the list did not push you anywhere.
3. **Denied** — deny location; the list shows its amber card, the push still happens, the tour runs on Friday Harbor.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/SlackwaterApp.swift Slackwater/Theme.swift Slackwater/StationListView.swift
git commit -m "Arm the tour on first launch and fire it on a real detail

Arming rather than scripting is what covers the entry paths that skip
the location flow: the gate's search bypass and a widget or shared link
land a first-time user on a detail with no teaching at all. A detail
with no timeline teaches nothing, so the tour stays armed for the next."
```

---

### Task 8: Replay, and the launch hooks

**Files:**
- Modify: `Slackwater/TestSeeds.swift:12-23`
- Modify: `Slackwater/SettingsView.swift` (a row in the existing `section(...)` pattern)

**Interfaces:**
- Consumes: `seenTourKey`, `TourCoach.replay(on:skySteps:)`, `tourStationID(near:)`.
- Produces: launch arguments `-resetTour` and `-seedTour`.

- [ ] **Step 1: Add the launch hooks**

In `Slackwater/TestSeeds.swift`, inside `applySeedHooksIfRequested()`, beside the existing gate hooks:

```swift
    // Same shape as -resetGate/-seedGate: a UI test forces or suppresses the
    // first-run tour by writing the persisted flag, because an
    // arguments-domain value would mask the in-app write.
    if CommandLine.arguments.contains("-resetTour") {
        UserDefaults.standard.removeObject(forKey: seenTourKey)
    }
    if CommandLine.arguments.contains("-seedTour") {
        UserDefaults.standard.set(true, forKey: seenTourKey)
    }
```

Every existing UI test that does not name `-resetTour` must be unaffected. Most tests land on the list via `-seedGate`; because the tour arms whenever `seenTourKey` is unset, **add `-seedTour` to the shared default launch arguments** in `SlackwaterUITests/ScreenshotTestCase.swift`'s `testArguments(_:)` (line 32) alongside the existing defaults, so no existing test suddenly grows a coach mark. This is the single highest-risk regression in the plan.

- [ ] **Step 2: Add the replay row**

In `Slackwater/SettingsView.swift`, following the existing `section("Offline downloads")` pattern at lines 60-72:

```swift
                    section("How to read a station") {
                        Button {
                            TourCoach.shared.replay(
                                on: tourStationID(near: LocationService.shared.location?.coordinate),
                                skySteps: true)
                            dismiss()
                        } label: {
                            HStack {
                                Text("Show the tour again")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                        .accessibilityIdentifier("settings-replay-tour")
                    }
```

`skySteps: true` here is provisional: the scaffold re-derives it from the real timeline when the detail appears, because Settings has no timeline to read.

- [ ] **Step 3: Compile-check**

Run the compile check. Expected: PASS.

- [ ] **Step 4: Run the full suite**

Run: `./scripts/test.sh`
Expected: every existing test still passes. If any UI test now fails on an unexpected coach mark, it is missing `-seedTour` from Step 1 — fix the default, not the test.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TestSeeds.swift Slackwater/SettingsView.swift \
        SlackwaterUITests/ScreenshotTestCase.swift
git commit -m "Add tour replay and the -resetTour/-seedTour launch hooks

The default UI-test arguments gain -seedTour so no existing test grows a
coach mark. Replay exists because a one-shot nobody can find again is
not a fair place to put real explanation."
```

---

### Task 9: The UI walk, and what only a device can answer

**Files:**
- Create: `SlackwaterUITests/TourUITests.swift`

**Interfaces:**
- Consumes: `-resetTour`, `-seedGate`, identifiers `tour-mark`, `tour-next`, `tour-skip`, `tile-moon`, `detail-favorite`, `timeline-strip`.
- Produces: nothing.

- [ ] **Step 1: Write the test**

Create `SlackwaterUITests/TourUITests.swift`:

```swift
// Slackwater — GPL v3. The first-run tour: the walk, the skip, and the
// assertion that earns its keep — a real swipe advances the stars mark.
import XCTest

final class TourUITests: ScreenshotTestCase {
    func testTourWalksAndSticks() {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-seedGate", "-resetTour", "-locAuthorizedNoFix"])
            .filter { $0 != "-seedTour" }
        app.launch()

        let mark = app.otherElements["tour-mark"].firstMatch
        XCTAssert(mark.appears(within: 15), "the tour did not fire on the first detail")
        save(app, "tour-read.png")

        // Read → stars → moon → moonCard → star, then done.
        for _ in 0..<4 { app.buttons["tour-next"].tap() }
        XCTAssert(app.buttons["Done"].exists, "the last mark should offer Done")
        app.buttons["tour-next"].tap()
        XCTAssertFalse(mark.exists, "Done must end the tour")

        // One-way: the flag survives a relaunch.
        app.terminate()
        app.launchArguments = testArguments(["-seedGate", "-locAuthorizedNoFix"])
        app.launch()
        XCTAssertFalse(app.otherElements["tour-mark"].firstMatch.appears(within: 5),
                       "a seen tour must not run again")
    }

    // The assertion this whole design rests on: the overlay hit-tests only on
    // its capsule, so the user's own drag reaches the strip underneath. If
    // this regresses the tour still "works" and silently stops teaching.
    func testARealSwipeAdvancesTheStarsMark() {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-seedGate", "-resetTour", "-locAuthorizedNoFix"])
            .filter { $0 != "-seedTour" }
        app.launch()

        XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15))
        app.buttons["tour-next"].tap()   // → .stars

        scrubStrip(app)
        settleScrub(app)
        // Advancing off .stars lands on .moon, whose mark names the moon.
        XCTAssert(app.staticTexts["And that is the real moon, at tonight's phase."]
                    .appears(within: 5),
                  "a real drag must advance the stars mark — the overlay is swallowing touches")
    }

    func testSkipEndsItFromTheFirstMark() {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-seedGate", "-resetTour", "-locAuthorizedNoFix"])
            .filter { $0 != "-seedTour" }
        app.launch()

        XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15))
        app.buttons["tour-skip"].tap()
        XCTAssertFalse(app.otherElements["tour-mark"].firstMatch.exists)
    }
}
```

- [ ] **Step 2: Run it**

Run: `./scripts/test.sh` (UI lane).
Expected: 3 tests pass. If `testARealSwipeAdvancesTheStarsMark` fails, the overlay is capturing the drag — check that nothing in `TourMarkLayer` has a background or `.contentShape`, and that only the capsule is hit-testable.

Read the result bundle, not just the exit code: `build/results-$MODE-$sim.xcresult`. "Test crashed with signal kill" with zero assertion failures means machine contention, not a defect — re-run alone.

- [ ] **Step 3: Verify on a device what the simulator cannot answer**

Three things, each to be stated plainly in the PR:

1. **The glide is not swallowed by XCUITest's quiescence rule.** CLAUDE.md: no UI test can tap during momentum, and the demo glide is momentum. The capsule lives outside the scroll view so taps should not be deferred — confirm on device, and if they are, say so rather than adding a sleep.
2. **Reduce Motion.** Settings → Accessibility → Motion → Reduce Motion on. The glide should land instantly (`TimelineStrip.swift:1233`) and the `hand.draw.fill` symbol should stop wiggling. The tour must still be comprehensible: several hours of sky change is still visible.
3. **VoiceOver.** Steps `.stars` and `.moon` must not run — the strip is an adjustable element there and "swipe the curve" is wrong advice. Confirm the tour goes `.read` → `.moonCard` → `.star`, and that each capsule reads its sentence with Next and Skip as actions.

If VoiceOver is not yet suppressed, add to `TourCoach.begin` and `next(after:)`:

```swift
    private var skipsSky: Bool { !skySteps || UIAccessibility.isVoiceOverRunning }
```

and use `skipsSky` in place of `!skySteps` in `next(after:)`.

- [ ] **Step 4: Run the whole suite one last time**

Run: `./scripts/test.sh`
Expected: all green. Report the actual test count and any failure text — do not claim a pass you have not read.

- [ ] **Step 5: Commit**

```bash
git add SlackwaterUITests/TourUITests.swift Slackwater/TourCoach.swift
git commit -m "Cover the tour with a UI walk, and suppress the sky steps under VoiceOver

The assertion that earns its keep is that a real swipe advances the
stars mark: if the overlay ever starts swallowing touches the tour still
looks fine and silently stops teaching the one gesture it exists for."
```

---

## Self-Review

**Spec coverage.** Five steps (Tasks 1, 5). Scrub demo gliding to stars then moon (Tasks 2, 3, 5). Targets as pure functions over `TimelineDay` with no Almanac search (Task 3). Arctic skip (Tasks 1, 3, 7). Overlay on the shared scaffold with preference anchors (Task 5). `nowPill` glass idiom and `hand.draw.fill` (Task 5). Hit-test pass-through and the drag advancing step 2 (Tasks 6, 9). `ScrollViewReader` (Task 6). Arm-and-fire plus the location-path open (Task 7). Ending on leaving the detail, surviving backgrounding (Task 7 — backgrounding is untouched, which is how it survives). Replay (Task 8). Launch hooks (Task 8). Reduce Motion and VoiceOver (Task 9). Unit and UI tests (Tasks 1, 3, 4, 9). `scripts/first-run.sh` (Tasks 6, 7).

**Not covered, deliberately:** the spec's "Verified, no change needed" section on the queued-station row needs no task — it records that `StationCard.swift:151` already does the right thing.

**Risks named in the plan rather than assumed away:** the glide may not animate (Task 2 Step 4 stops the work and reports); existing UI tests may grow coach marks (Task 8 Step 1 adds `-seedTour` to the default arguments); XCUITest may defer taps during the glide (Task 9 Step 3, device only).
