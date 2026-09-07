# Lunar Eclipse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A lunar eclipse gets an umbral shadow on the sky dome's moon, a row in the schedule, a snap target at every contact, and a Moon tile that opens a detail sheet naming the last and next eclipse — both jumpable.

**Architecture:** One Almanac search per timeline *build* (never per scrub frame), cached on `TimelineData.eclipses`. That single array feeds the schedule row (merged in `ScrubDetailScaffold`, so all four detail views get it without four edits), the strip mark, the snap times, and the sky glyph. The Moon sheet computes its own longer-range answers in a `.task`, off the scrub path.

**Tech Stack:** Swift 6 / SwiftUI, iOS 26, `Almanac` SwiftPM package (already a dependency), XCTest.

**Spec:** `docs/superpowers/specs/2026-09-07-lunar-eclipse-design.md`

## Global Constraints

- **`SkyState.init` runs on every scrub frame.** It may never call an Almanac *search* (`nextLunarEclipse`, `searchMoonPhases`, `moonEvents`). It is handed answers; position lookups only.
- **A scrubber presentation change has four consumers:** `TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView`, `OnlineGateDetailView`. Prefer a change in `ScrubDetailScaffold` or `TimelineData` over four edits.
- **`anchor` drives geometry, `today` drives language.** Never geometry off `today`.
- **Calendar days are not 86,400 seconds.** Anything meaning *a day* goes through `Calendar` with its `timeZone` set.
- **Almanac throws** outside 1950–2101. Every call site degrades to "no eclipse" rather than propagating — the tile drops, never the row.
- **Compile-check, don't run the suite, between tasks:**
  ```sh
  lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
    -project Slackwater.xcodeproj -scheme Slackwater \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
  ```
  `lockf -t 0` fails immediately if another run holds the machine — wait, never force it. The full `./scripts/test.sh` runs once, at Task 9.
- **Run a single test** with `-only-testing:SlackwaterTests/EclipseTests/<name>` on `xcodebuild test` with the same lock and flags.
- **Commits:** `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. No session links — this repo is public.

---

## File Structure

| File | Responsibility |
|---|---|
| `Slackwater/Eclipse.swift` (new) | `WindowEclipse` and `lunarEclipses(from:to:observer:)` — windowing and shadow interpolation over Almanac's answers. Nothing else knows Almanac's eclipse types. |
| `Slackwater/TimelineStrip.swift` | `TimelineData.eclipses`, contacts into `snapTimes`, `SchedulePill.eclipse` + its row, the strip's copper mark. |
| `Slackwater/Theme.swift` | `MoonGlyph.umbra`, `SkyState.eclipse`, the glow's dimming, the Moon tile's eclipse text, `ReadoutTile.detail`, the scaffold's row merge and `jump(to:)`. |
| `Slackwater/MoonDetailSheet.swift` (new) | The sheet: its content, its own `.task` computation, and its jump rows. |
| `Slackwater/Palette.swift` | `SN.umbra`, `SN.umbraLabel`. |
| `SlackwaterTests/EclipseTests.swift` (new) | Windowing, filtering, shadow interpolation, snap times, the row merge, the glyph geometry and its render probe. |
| `SlackwaterUITests/…` | One test: Moon tile → sheet → jump. |

---

### Task 1: `WindowEclipse` and the window search

**Files:**
- Create: `Slackwater/Eclipse.swift`
- Test: `SlackwaterTests/EclipseTests.swift`

**Interfaces:**
- Consumes: `Almanac.nextLunarEclipse(after:)`, `Almanac.lunarEclipseVisibility(_:observer:)`, `Almanac.searchMoonPhases(from:to:)`, `Almanac.Observer`.
- Produces:
  ```swift
  struct WindowEclipse: Identifiable {
      let eclipse: LunarEclipse
      let visibility: LunarEclipseVisibility
      var id: Date { get }              // the peak
      var kind: LunarEclipseKind { get }
      var peak: Date { get }
      var start: Date { get }           // u1 ?? p1
      var contacts: [Date] { get }      // p1, u1, peak, u4, p4 — nils dropped, chronological
      var anyContactVisible: Bool { get }
      func underway(at t: Date) -> Bool
      func shadow(at t: Date) -> Double
  }
  func lunarEclipses(from: Date, to: Date, observer: Observer) -> [WindowEclipse]
  ```

- [ ] **Step 1: Write the failing test**

Create `SlackwaterTests/EclipseTests.swift`:

```swift
// Slackwater — GPL v3.
import Almanac
import XCTest
@testable import Slackwater

final class EclipseTests: XCTestCase {
    // Almanac's own pinned regression case: the 2026-08-28 partial, umbral
    // magnitude ~0.93, visible at peak from Victoria and not from Athens.
    static let victoria = try! Observer(latitudeDeg: 48.42, longitudeDeg: -123.37)
    // Perth is the not-visible fixture and it is not a coin flip: the whole
    // event falls in Perth's daylight on the day of the full moon, and a full
    // moon is below the horizon while the sun is up.
    static let perth = try! Observer(latitudeDeg: -31.95, longitudeDeg: 115.86)

    private func utc(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    func testTheWindowFindsThe2026PartialAndDescribesIt() {
        let found = lunarEclipses(from: utc("2026-08-25T00:00:00Z"),
                                  to: utc("2026-08-31T00:00:00Z"),
                                  observer: Self.victoria)
        XCTAssertEqual(found.count, 1)
        let e = try! XCTUnwrap(found.first)
        XCTAssertEqual(e.kind, .partial)
        XCTAssertEqual(e.start, e.eclipse.u1)
        XCTAssertEqual(e.contacts, [e.eclipse.p1, e.eclipse.u1!, e.peak, e.eclipse.u4!, e.eclipse.p4])
        XCTAssertEqual(e.contacts, e.contacts.sorted())
        XCTAssertTrue(e.anyContactVisible)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run:
```sh
lockf -t 0 /tmp/slackwater-test.lock xcodebuild test \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:SlackwaterTests/EclipseTests 2>&1 | tail -20
```
Expected: compile failure — `cannot find 'lunarEclipses' in scope`.

- [ ] **Step 3: Write `Slackwater/Eclipse.swift`**

```swift
// Slackwater — GPL v3. Lunar eclipses for the strip, the schedule and the
// Moon sheet. The astronomy is Almanac's; everything here is windowing and
// presentation.
import Almanac
import Foundation

/// One eclipse paired with what this observer can see of it. Built once per
/// timeline build — never on a scrub frame — and carried on `TimelineData`.
struct WindowEclipse: Identifiable {
    let eclipse: LunarEclipse
    let visibility: LunarEclipseVisibility

    var id: Date { eclipse.peak }
    var kind: LunarEclipseKind { eclipse.kind }
    var peak: Date { eclipse.peak }

    /// The instant the shadow first bites — U1, or P1 for a penumbral eclipse,
    /// which has no umbral contact at all. What the list row and the strip
    /// mark point at, and what "scrub to the start" means.
    var start: Date { eclipse.u1 ?? eclipse.p1 }

    /// The snap targets, chronological, nils dropped: P1, U1, greatest, U4, P4.
    var contacts: [Date] {
        [eclipse.p1, eclipse.u1, eclipse.peak, eclipse.u4, eclipse.p4].compactMap { $0 }
    }

    /// Any contact with the moon above this observer's horizon. The test for
    /// whether the event is worth a row here — deliberately weaker than
    /// `visibility.visibleAtPeak`, so an eclipse already underway at moonrise
    /// still counts. That is the one worth walking outside for.
    var anyContactVisible: Bool {
        let v = visibility.contactsVisible
        return [v.p1, v.u1, v.u2, v.u3, v.u4, v.p4].contains { $0 == true }
            || visibility.visibleAtPeak
    }

    /// Anywhere in the event, first to last penumbral contact. Dims the dome's
    /// glow and renames the Moon tile.
    func underway(at t: Date) -> Bool { t >= eclipse.p1 && t <= eclipse.p4 }

    /// Fraction of the moon's diameter inside the UMBRA at `t`, 0 outside the
    /// umbral phase — including for the whole of a penumbral eclipse, which
    /// has no umbral contact. That is not a gap: a penumbral eclipse is a
    /// dimming, not a bite, and the glow carries it.
    ///
    /// ponytail: linear between contacts. Almanac reports contact instants and
    /// the magnitude at greatest eclipse, not a coverage curve; the shape
    /// between them is this app's drawing. Endpoints and the peak are exact,
    /// the middle is within a few percent of the real chord geometry, and no
    /// number here is ever printed — it only moves a shadow. Upgrade path if
    /// it ever is printed: chord geometry from the shadow radii, which means
    /// an Almanac API for them.
    func shadow(at t: Date) -> Double {
        guard let u1 = eclipse.u1, let u4 = eclipse.u4, t >= u1, t <= u4 else { return 0 }
        let mag = max(eclipse.magUmbral, 0)
        if t <= peak {
            let span = peak.timeIntervalSince(u1)
            return span > 0 ? mag * t.timeIntervalSince(u1) / span : mag
        }
        let span = u4.timeIntervalSince(peak)
        return span > 0 ? mag * u4.timeIntervalSince(t) / span : mag
    }
}

/// Every lunar eclipse whose peak falls in `from...to` and that this observer
/// can see any contact of.
///
/// Walks `nextLunarEclipse(after:)` forward — Almanac has no range or backward
/// search (openwatersio/almanac#6). Almanac throws outside 1950–2101; that
/// ends the walk and returns what was found, the way `SummaryTiles` drops its
/// tile rather than the row.
func lunarEclipses(from: Date, to: Date, observer: Observer) -> [WindowEclipse] {
    var out: [WindowEclipse] = []
    var cursor = from
    while cursor < to {
        guard let e = try? nextLunarEclipse(after: cursor), e.peak <= to else { break }
        cursor = e.peak
        guard let v = try? lunarEclipseVisibility(e, observer: observer) else { continue }
        let windowed = WindowEclipse(eclipse: e, visibility: v)
        if windowed.anyContactVisible { out.append(windowed) }
    }
    return out
}
```

- [ ] **Step 4: Run the test, watch it pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Add the filter, interpolation and empty-window tests**

Append to `EclipseTests`:

```swift
    func testAnEclipseNobodyHereCanSeeIsDropped() {
        let found = lunarEclipses(from: utc("2026-08-25T00:00:00Z"),
                                  to: utc("2026-08-31T00:00:00Z"),
                                  observer: Self.perth)
        XCTAssertTrue(found.isEmpty, "Perth is in daylight for the whole event")
    }

    func testShadowIsZeroOutsideAndPeaksAtTheUmbralMagnitude() {
        let e = lunarEclipses(from: utc("2026-08-25T00:00:00Z"),
                              to: utc("2026-08-31T00:00:00Z"),
                              observer: Self.victoria).first!
        XCTAssertEqual(e.shadow(at: e.eclipse.p1.addingTimeInterval(-60)), 0)
        XCTAssertEqual(e.shadow(at: e.eclipse.p4.addingTimeInterval(60)), 0)
        // Penumbral legs are a dimming, not a bite.
        XCTAssertEqual(e.shadow(at: e.eclipse.p1.addingTimeInterval(60)), 0)
        XCTAssertEqual(e.shadow(at: e.peak), e.eclipse.magUmbral, accuracy: 0.001)
        XCTAssertEqual(e.shadow(at: e.eclipse.u1!), 0, accuracy: 0.001)
        XCTAssertEqual(e.shadow(at: e.eclipse.u4!), 0, accuracy: 0.001)
        // Monotone into the peak.
        let quarter = e.eclipse.u1!.addingTimeInterval(
            e.peak.timeIntervalSince(e.eclipse.u1!) / 2)
        XCTAssertGreaterThan(e.shadow(at: quarter), 0)
        XCTAssertLessThan(e.shadow(at: quarter), e.eclipse.magUmbral)
        XCTAssertTrue(e.underway(at: e.peak))
        XCTAssertFalse(e.underway(at: e.eclipse.p4.addingTimeInterval(60)))
    }

    func testAQuietMonthHasNoEclipse() {
        // October 2026 carries a full moon and no lunar eclipse; the next one
        // after 2026-08-28 is in 2027.
        XCTAssertTrue(lunarEclipses(from: utc("2026-10-01T00:00:00Z"),
                                    to: utc("2026-10-31T00:00:00Z"),
                                    observer: Self.victoria).isEmpty)
    }
```

- [ ] **Step 6: Run all four tests**

Same command as Step 2. Expected: 4 passing. If `testAQuietMonthHasNoEclipse` fails, an eclipse really is in that window — check the printed peak against the Espenak catalog and move the window, do not weaken the assertion.

- [ ] **Step 7: Commit**

```bash
git add Slackwater/Eclipse.swift SlackwaterTests/EclipseTests.swift
git commit -m "feat: window lunar eclipses against an observer (#222)"
```

---

### Task 2: `TimelineData.eclipses` and the snap targets

**Files:**
- Modify: `Slackwater/TimelineStrip.swift` — `TimelineData` (fields ~`:164-200`), `build(tide:current:...)` (~`:446-462`), `build(onlinePoints:...)` (~`:383-393`)
- Test: `SlackwaterTests/EclipseTests.swift`

**Interfaces:**
- Consumes: `lunarEclipses(from:to:observer:)`, `WindowEclipse` (Task 1).
- Produces: `TimelineData.eclipses: [WindowEclipse]`, and every contact inside the window present in `TimelineData.snapTimes`.

- [ ] **Step 1: Write the failing test**

Append to `EclipseTests`:

```swift
    func testTheTimelineCarriesTheEclipseAndSnapsToEveryContact() throws {
        let station = try XCTUnwrap(TideStationRecord.seed(id: seedTideStationId))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        // The anchor is the eclipse's local day; the window covers it.
        let anchor = cal.startOfDay(for: utc("2026-08-28T12:00:00Z"))
        let tl = TimelineData.build(tide: station, current: nil,
                                    now: anchor, anchor: anchor)
        let e = try XCTUnwrap(tl.eclipses.first)
        XCTAssertEqual(e.kind, .partial)
        for c in e.contacts where tl.contains(c) {
            XCTAssertTrue(tl.snapTimes.contains(c), "contact \(c) is not magnetic")
        }
    }

    func testAWindowWithNoFullMoonCostsNoEclipseSearch() throws {
        let station = try XCTUnwrap(TideStationRecord.seed(id: seedTideStationId))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        let anchor = cal.startOfDay(for: utc("2026-10-08T12:00:00Z"))
        let tl = TimelineData.build(tide: station, current: nil, now: anchor, anchor: anchor)
        XCTAssertTrue(tl.eclipses.isEmpty)
    }
```

Before writing this, confirm the seed helper's real name and signature — `SlackwaterTests` already builds timelines this way in `SlackWindowTests.swift` and `DetailLeadTests.swift`. Use whatever those use verbatim rather than the placeholder names above; `TestSeeds.swift` is the source.

- [ ] **Step 2: Run it, watch it fail**

Run the `-only-testing:SlackwaterTests/EclipseTests` command from Task 1 Step 2. Expected: `value of type 'TimelineData' has no member 'eclipses'`.

- [ ] **Step 3: Add the field**

In `TimelineData`, after `snapTimes`:

```swift
    /// Lunar eclipses with a peak inside the window and at least one contact
    /// above this station's horizon. Built ONCE here — `SkyState.init` runs on
    /// every scrub frame and must never search — and read by the dome's moon,
    /// the schedule row and the strip's mark.
    var eclipses: [WindowEclipse] = []
```

Defaulted, so the memberwise initialiser's existing call sites keep compiling.

- [ ] **Step 4: Add the shared search helper**

In `TimelineData`, next to `eventPad`:

```swift
    /// The window's eclipses, or nothing — the shared tail of both builders.
    ///
    /// The full-moon gate is the whole performance story: `nextLunarEclipse`
    /// scans lunation by lunation and will happily walk months past the window
    /// before it finds one, on every rebuild. An eclipse is a full moon, so a
    /// window with no full moon in it cannot hold one, and `searchMoonPhases`
    /// answers that far more cheaply than the eclipse scan does.
    private static func windowEclipses(lat: Double, lon: Double,
                                       start: Date, end: Date) -> [WindowEclipse] {
        guard let observer = try? Observer(latitudeDeg: lat, longitudeDeg: lon),
              let phases = try? searchMoonPhases(from: start, to: end),
              phases.contains(where: { $0.phase == .full })
        else { return [] }
        return lunarEclipses(from: start, to: end, observer: observer)
    }
```

`TimelineStrip.swift` already imports `Almanac`; confirm at the top of the file and add the import if it does not.

- [ ] **Step 5: Wire both builders**

In `build(tide:current:now:anchor:gate:threshold:)`, replace the `snaps` construction and the return with:

```swift
        let eclipses = windowEclipses(lat: lat, lon: lon, start: start, end: end)
        let snaps = Array(Set(tideExtremes.map(\.time) + tideFlowArrows(tideRates).map(\.time)
                              + currentEvents.map(\.time) + sunTimes
                              + eclipses.flatMap(\.contacts)
                              + windows.flatMap { [$0.start, $0.end] }))
            .filter { $0 >= start && $0 <= end }.sorted()
```

and add `eclipses: eclipses` to the `TimelineData(...)` call.

In `build(onlinePoints:tz:lat:lon:now:anchor:threshold:)`, make the same two changes — that builder has `lat`/`lon` as parameters already.

- [ ] **Step 6: Run the tests**

Run the `EclipseTests` command. Expected: 6 passing.

- [ ] **Step 7: Measure the build cost and record it**

Add, and keep, a timing test:

```swift
    func testBuildingAnEclipseWindowStaysUnderTheFrameBudget() throws {
        let station = try XCTUnwrap(TideStationRecord.seed(id: seedTideStationId))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        let anchor = cal.startOfDay(for: utc("2026-08-28T12:00:00Z"))
        let t0 = Date()
        _ = TimelineData.build(tide: station, current: nil, now: anchor, anchor: anchor)
        let eclipseWeek = Date().timeIntervalSince(t0)
        let quiet = cal.startOfDay(for: utc("2026-10-08T12:00:00Z"))
        let t1 = Date()
        _ = TimelineData.build(tide: station, current: nil, now: quiet, anchor: quiet)
        let quietWeek = Date().timeIntervalSince(t1)
        print("eclipse-week build \(eclipseWeek * 1000) ms, quiet week \(quietWeek * 1000) ms")
        // A rebuild is a user action (open a detail, pick a week), not a frame.
        // 250 ms is the ceiling where it stops feeling instant.
        XCTAssertLessThan(eclipseWeek, 0.25)
        XCTAssertLessThan(quietWeek, 0.25)
    }
```

Run it, read the printed milliseconds, and put both numbers in the commit message. If the eclipse week exceeds 250 ms, stop and report — the spec's fallback is moving the search to a `Task` that merges its result in, which is a plan change, not a silent one.

- [ ] **Step 8: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/EclipseTests.swift
git commit -m "feat: carry the window's eclipses on the timeline (#222)"
```

---

### Task 3: The shadow on `MoonGlyph`

**Files:**
- Modify: `Slackwater/Palette.swift` (~`:71`), `Slackwater/Theme.swift` — `moonLimbShift` neighbourhood (~`:203-250`)
- Test: `SlackwaterTests/EclipseTests.swift`

**Interfaces:**
- Produces:
  ```swift
  func moonUmbraShift(coverage: Double, radius: CGFloat) -> CGFloat
  MoonGlyph(fraction:waxing:size:umbra:)   // umbra defaults to 0
  SN.umbra: Color
  ```

- [ ] **Step 1: Write the failing geometry test**

Append to `EclipseTests`:

```swift
    func testTheUmbraDiscSlidesFromTouchingToCovering() {
        // Same shape as moonLimbShift: an equal-radius disc offset across the
        // moon. At zero coverage it is exactly tangent (2r away), at full
        // coverage it is concentric.
        XCTAssertEqual(moonUmbraShift(coverage: 0, radius: 10), 20, accuracy: 0.001)
        XCTAssertEqual(moonUmbraShift(coverage: 1, radius: 10), 0, accuracy: 0.001)
        XCTAssertEqual(moonUmbraShift(coverage: 0.5, radius: 10), 10, accuracy: 0.001)
        // A total eclipse reports magUmbral above 1; the disc stops at covered.
        XCTAssertEqual(moonUmbraShift(coverage: 1.4, radius: 10), 0, accuracy: 0.001)
    }
```

- [ ] **Step 2: Run it, watch it fail**

`-only-testing:SlackwaterTests/EclipseTests/testTheUmbraDiscSlidesFromTouchingToCovering`. Expected: `cannot find 'moonUmbraShift' in scope`.

- [ ] **Step 3: Implement the geometry and the glyph**

In `Slackwater/Palette.swift`, beside `moonLimb`:

```swift
    static let umbra = Color(hex: 0x6B2A18, opacity: 0.94)   // the eclipse shadow — copper, not black
    static let umbraLabel = Color(hex: 0xD98A66)             // its text and strip mark
```

In `Slackwater/Theme.swift`, directly under `moonLimbShift`:

```swift
/// The umbral shadow's offset for a disc of radius `r`: tangent at zero
/// coverage (2r), concentric when the moon is covered. `coverage` is a
/// fraction of the moon's DIAMETER, which is what Almanac's `magUmbral` means,
/// and above 1 for a total eclipse — clamped, since there is nowhere further
/// to slide.
func moonUmbraShift(coverage: Double, radius: CGFloat) -> CGFloat {
    (1 - CGFloat(min(max(coverage, 0), 1))) * 2 * radius
}
```

and in `MoonGlyph`:

```swift
struct MoonGlyph: View {
    let fraction: Double
    let waxing: Bool
    var size: CGFloat = 20
    /// Fraction of the moon's diameter inside the umbra — `WindowEclipse.shadow(at:)`.
    /// Zero draws exactly what this glyph has always drawn.
    var umbra: Double = 0

    var body: some View {
        let r = size / 2 - 1
        let shift = moonLimbShift(fraction: fraction, waxing: waxing, radius: r)
        ZStack {
            Circle().fill(SN.foam)
            Circle().fill(SN.moonLimb).offset(x: shift)
            if umbra > 0 {
                // A THIRD element, entering from the side the phase limb is
                // leaving, so the eclipse can never be read as a phase: an
                // eclipse happens at full, where the limb shift is off the
                // disc entirely, and the two never share a pixel in practice.
                Circle().fill(SN.umbra)
                    .offset(x: (waxing ? 1 : -1) * moonUmbraShift(coverage: umbra, radius: r))
            }
        }
        .frame(width: 2 * r, height: 2 * r)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 4: Run the geometry test**

Expected: PASS.

- [ ] **Step 5: Add the render probe**

Append to `EclipseTests` (`RenderProbes.swift` supplies `inkFraction`; `import SwiftUI` and `import UIKit` at the top of the file):

```swift
    @MainActor
    func testTheEclipsedGlyphDrawsSomethingTheCleanOneDoesNot() {
        func shot(_ umbra: Double) -> UIImage {
            let r = ImageRenderer(content:
                MoonGlyph(fraction: 1, waxing: false, size: 44, umbra: umbra)
                    .frame(width: 60, height: 60)
                    .background(SN.canvas))
            r.scale = 2
            return r.uiImage!
        }
        // A full moon with no shadow is a near-uniform disc; at peak coverage
        // the copper is most of it.
        XCTAssertGreaterThan(inkFraction(shot(0.93)), inkFraction(shot(0)) + 0.05)
    }
```

- [ ] **Step 6: Run it**

Expected: PASS. If the two ink fractions land within 0.05, print both and pick the threshold off the measured floor the way `drawnStripInk` documents — do not delete the assertion.

- [ ] **Step 7: Commit**

```bash
git add Slackwater/Palette.swift Slackwater/Theme.swift SlackwaterTests/EclipseTests.swift
git commit -m "feat: draw the umbral shadow on the moon glyph (#222)"
```

---

### Task 4: The dome's moon takes the shadow

**Files:**
- Modify: `Slackwater/Theme.swift` — `SkyState` (~`:85-120`), `SkyBackdrop`'s moon block (~`:177-190`)
- Modify: `Slackwater/TideDetailView.swift:73`, `Slackwater/CurrentDetailView.swift:71`, `Slackwater/DerivedGateDetailView.swift:31`, `Slackwater/OnlineGateDetailView.swift:77`
- Test: `SlackwaterTests/EclipseTests.swift`

**Interfaces:**
- Consumes: `TimelineData.eclipses` (Task 2), `MoonGlyph.umbra` (Task 3).
- Produces: `SkyState.init(time:latitude:longitude:days:eclipses:)` and `SkyState.eclipse: WindowEclipse?` — the eclipse underway at `time`, or nil.

- [ ] **Step 1: Write the failing test**

```swift
    func testTheSkyStateCarriesOnlyTheEclipseUnderwayAtItsTime() throws {
        let station = try XCTUnwrap(TideStationRecord.seed(id: seedTideStationId))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        let anchor = cal.startOfDay(for: utc("2026-08-28T12:00:00Z"))
        let tl = TimelineData.build(tide: station, current: nil, now: anchor, anchor: anchor)
        let e = try XCTUnwrap(tl.eclipses.first)
        let at = SkyState(time: e.peak, latitude: station.latitude, longitude: station.longitude,
                          days: tl.days, eclipses: tl.eclipses)
        XCTAssertNotNil(at.eclipse)
        XCTAssertEqual(at.shadow, e.eclipse.magUmbral, accuracy: 0.001)
        let after = SkyState(time: e.eclipse.p4.addingTimeInterval(3600),
                             latitude: station.latitude, longitude: station.longitude,
                             days: tl.days, eclipses: tl.eclipses)
        XCTAssertNil(after.eclipse)
        XCTAssertEqual(after.shadow, 0)
    }
```

- [ ] **Step 2: Run it, watch it fail**

Expected: `extra argument 'eclipses' in call`.

- [ ] **Step 3: Extend `SkyState`**

Add the stored property and the initialiser parameter:

```swift
    /// The eclipse underway at `time`, if any. Chosen from an array the
    /// timeline already built: this initialiser runs on every scrub frame, and
    /// an eclipse SEARCH here would cost orders of magnitude more than the
    /// position lookups above it — the same reason the sun's arc reads its
    /// endpoints from `days`.
    let eclipse: WindowEclipse?
    /// Fraction of the moon's diameter in the umbra right now, 0 when clear.
    var shadow: Double { eclipse?.shadow(at: time) ?? 0 }
```

`SkyState` does not currently keep `time`; add `let time: Date` alongside `latitude` and set it in the initialiser. Extend the signature:

```swift
    init(time: Date, latitude: Double, longitude: Double, days: [TimelineDay] = [],
         eclipses: [WindowEclipse] = []) {
        self.time = time
        …
        eclipse = eclipses.first { $0.underway(at: time) }
    }
```

- [ ] **Step 4: Draw it**

In `SkyBackdrop`, the moon block becomes:

```swift
                if let moon = sky.moon, let illumination = sky.illumination, moon.altDeg >= 0 {
                    let point = skyPoint(azimuth: moon.azDeg, altitude: moon.altDeg,
                                         latitude: sky.latitude, size: proxy.size)
                    let glowRadius = moonGlowRadius(fraction: illumination.fraction)
                    // The eclipsed moon dims and warms: the umbra is copper,
                    // and the whole sky goes quieter with it. Two changes to
                    // one gradient, not a second element.
                    let eclipsed = sky.eclipse?.underway(at: sky.time) ?? false
                    let dim = 1 - 0.75 * sky.shadow
                    let core = eclipsed ? 0xE8B08C : 0xE6EEFF
                    let halo = eclipsed ? 0xD79A78 : 0xCFE0FF
                    Circle()
                        .fill(RadialGradient(
                            stops: [
                                .init(color: Color(hex: core,
                                                   opacity: 0.95 * (0.1 + illumination.fraction * 0.66) * dim),
                                      location: 0),
                                .init(color: Color(hex: halo,
                                                   opacity: 0.28 * (0.1 + illumination.fraction * 0.66) * dim),
                                      location: 0.45),
                                .init(color: Color(hex: halo, opacity: 0), location: 1),
                            ], center: .center, startRadius: 0, endRadius: glowRadius))
                        .frame(width: glowRadius * 2, height: glowRadius * 2)
                        .position(point)
                    MoonGlyph(fraction: illumination.fraction, waxing: illumination.waxing,
                              size: 22, umbra: sky.shadow)
                        .position(point)
                }
```

- [ ] **Step 5: Hand each detail view its eclipses**

Four identical edits — `TideDetailView.swift:73`, `CurrentDetailView.swift:71`, `DerivedGateDetailView.swift:31`, `OnlineGateDetailView.swift:77`:

```swift
        let sky = SkyState(time: scrubTime, latitude: record.latitude, longitude: record.longitude,
                           days: timeline?.days ?? [], eclipses: timeline?.eclipses ?? [])
```

(`gate.latitude` / `gate.longitude` in the two gate views, as they already read.)

- [ ] **Step 6: Guard the four with a source test**

Append, in the style of `SkyBackdropTests.testEveryScrubDetailUsesTheSkyBackdrop`:

```swift
    func testEveryScrubDetailHandsTheSkyItsEclipses() throws {
        for file in ["Slackwater/TideDetailView.swift", "Slackwater/CurrentDetailView.swift",
                     "Slackwater/OnlineGateDetailView.swift", "Slackwater/DerivedGateDetailView.swift"] {
            XCTAssertTrue(try repoSource(file).contains("eclipses: timeline?.eclipses ?? []"), file)
        }
    }
```

- [ ] **Step 7: Run the eclipse tests, then compile-check**

Expected: all passing, build clean.

- [ ] **Step 8: Commit**

```bash
git add Slackwater/Theme.swift Slackwater/TideDetailView.swift Slackwater/CurrentDetailView.swift \
        Slackwater/DerivedGateDetailView.swift Slackwater/OnlineGateDetailView.swift \
        SlackwaterTests/EclipseTests.swift
git commit -m "feat: eclipse the dome's moon and warm its glow (#222)"
```

---

### Task 5: The schedule row

**Files:**
- Modify: `Slackwater/TimelineStrip.swift` — `SchedulePill` (~`:231`), `pillView` (~`:1476-1519`)
- Modify: `Slackwater/Theme.swift` — `ScrubDetailScaffold.scheduleCard` (~`:653`)
- Test: `SlackwaterTests/EclipseTests.swift`

**Interfaces:**
- Consumes: `TimelineData.eclipses`, `WindowEclipse.start`, `.peak`, `.kind`.
- Produces: `SchedulePill.eclipse`, and `func eclipseEntries(_ tl: TimelineData) -> [ScheduleEntry]` in `TimelineStrip.swift` (file-scope, not private — the scaffold and the tests call it).

- [ ] **Step 1: Write the failing test**

```swift
    func testTheEclipseRowMergesIntoTheScheduleInTimeOrder() throws {
        let station = try XCTUnwrap(TideStationRecord.seed(id: seedTideStationId))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        let anchor = cal.startOfDay(for: utc("2026-08-28T12:00:00Z"))
        let tl = TimelineData.build(tide: station, current: nil, now: anchor, anchor: anchor)
        let e = try XCTUnwrap(tl.eclipses.first)
        let rows = eclipseEntries(tl)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.time, e.start)
        XCTAssertEqual(rows.first?.pill, .eclipse)
        // The value column carries the peak, the one instant worth quoting.
        XCTAssertEqual(rows.first?.value, chartTime(e.peak, tl.tz))
        // Only what the list's own window covers.
        XCTAssertTrue(tl.scheduleRange.contains(e.start))
    }
```

`SchedulePill` needs `Equatable` for `XCTAssertEqual` — it is a plain enum with no associated values, so add the conformance if the compiler asks.

- [ ] **Step 2: Run it, watch it fail**

Expected: `cannot find 'eclipseEntries' in scope`.

- [ ] **Step 3: Add the pill case and the row builder**

In `TimelineStrip.swift`:

```swift
enum SchedulePill {
    case high, low, flood, ebb, slack, eclipse
}
```

Below `ScheduleEntry`:

```swift
/// The window's eclipses as schedule rows: one row each, at the first bite,
/// with the peak in the value column.
///
/// Built here and merged by `ScrubDetailScaffold` rather than by the four
/// detail views: an eclipse is the sky's event, not the station's, so all four
/// kinds of detail get the same row from one place.
func eclipseEntries(_ tl: TimelineData) -> [ScheduleEntry] {
    tl.eclipses
        .filter { tl.scheduleRange.contains($0.start) }
        .map { ScheduleEntry(time: $0.start, pill: .eclipse, value: chartTime($0.peak, tl.tz)) }
}
```

In `pillView`, a case beside `.slack`:

```swift
        case .eclipse:
            // Copper, and the moon glyph rather than a geometric mark: this is
            // the one row in the list that is not about water.
            Text("🌘 ECLIPSE")
                .font(.caption2.monospaced().weight(.medium)).tracking(0.5)
                .foregroundStyle(SN.foam)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.umbra, in: Capsule())
```

The kind (`PARTIAL` / `TOTAL` / `PENUMBRAL`) is deliberately not in the pill: `MultiDaySchedule` caps this column at 100 pt for `WSW FLOOD`, and `🌘 PENUMBRAL ECLIPSE` does not fit. The kind belongs to the sheet, which has room for it.

- [ ] **Step 4: Merge in the scaffold**

In `ScrubDetailScaffold.scheduleCard`, replace `entries: entries(tl)` with:

```swift
            MultiDaySchedule(entries: (entries(tl) + eclipseEntries(tl)).sorted { $0.time < $1.time },
                             tz: tz, anchor: tl.anchor,
                             today: tl.today, days: tl.days,
                             scrubTime: scrubTime, onTap: { scrubTime = $0 })
```

- [ ] **Step 5: Run the test**

Expected: PASS.

- [ ] **Step 6: Compile-check and commit**

```bash
git add Slackwater/TimelineStrip.swift Slackwater/Theme.swift SlackwaterTests/EclipseTests.swift
git commit -m "feat: give the eclipse a schedule row on all four details (#222)"
```

---

### Task 6: The strip's mark

**Files:**
- Modify: `Slackwater/TimelineStrip.swift` — `TimelineCanvas`'s day-chrome loop, the sun dot block (~`:723-733`)
- Test: `SlackwaterTests/EclipseTests.swift`

**Interfaces:**
- Consumes: `TimelineData.eclipses`, `SN.umbra`, `SN.umbraLabel`.
- Produces: nothing new — a drawing change inside `TimelineCanvas`.

- [ ] **Step 1: Draw the mark**

After the sun rise/set loop, still inside `drawDayChrome` but *outside* the per-day loop (an eclipse belongs to an instant, not to a day):

```swift
        // The eclipse's first bite, on the same row as the sun dots: a copper
        // dot and its time. One mark per eclipse even though every contact is
        // magnetic — five labels on one evening is a smear, and the label the
        // user needs is the one they are scrubbing toward.
        for e in data.eclipses where data.contains(e.start) {
            let x = data.x(e.start)
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: geo.sunY - 3.5, width: 7, height: 7)),
                     with: .color(SN.umbra))
            ctx.draw(Text("🌘\(cardTime(e.start, data.tz))")
                        .font(.system(size: 11, weight: .medium).monospaced())
                        .foregroundStyle(SN.umbraLabel),
                     at: CGPoint(x: x, y: geo.dayY), anchor: .center)
        }
```

Check the enclosing function's name and the loop's brace structure before pasting — the sun dots sit inside `for day in …`, and this block must not.

- [ ] **Step 2: Prove it draws**

```swift
    @MainActor
    func testTheStripMarksTheEclipse() throws {
        let station = try XCTUnwrap(TideStationRecord.seed(id: seedTideStationId))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        let anchor = cal.startOfDay(for: utc("2026-08-28T12:00:00Z"))
        let withEclipse = TimelineData.build(tide: station, current: nil, now: anchor, anchor: anchor)
        XCTAssertFalse(withEclipse.eclipses.isEmpty)
        let quiet = cal.startOfDay(for: utc("2026-10-08T12:00:00Z"))
        let without = TimelineData.build(tide: station, current: nil, now: quiet, anchor: quiet)
        XCTAssertTrue(without.eclipses.isEmpty)
        // Ink, not text: this target cannot read rendered text (RenderProbes.swift).
        XCTAssertGreaterThan(strippedInk(withEclipse), strippedInk(without))
    }
```

`strippedInk` here means "render `TimelineCanvas` for this data and return `inkFraction`". `RenderedStripTests.swift` already has that helper under some name — reuse it verbatim rather than adding a second one; if it is private to that file, move it into `RenderProbes.swift` in this step and leave `RenderedStripTests` calling it.

- [ ] **Step 3: Run it**

Expected: PASS. Two different weeks differ in ink for reasons other than the eclipse (different tide curve), so if this passes for the wrong reason it is still a weak test — tighten it by rendering the SAME data with `eclipses` emptied instead, if the helper makes that easy.

- [ ] **Step 4: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/EclipseTests.swift
git commit -m "feat: mark the eclipse's first bite on the strip (#222)"
```

---

### Task 7: A tile that opens, and a tile that says "eclipse"

**Files:**
- Modify: `Slackwater/Theme.swift` — `ReadoutTile` (~`:417-452`), `SummaryTiles` (~`:386-414`)
- Test: `SlackwaterTests/EclipseTests.swift`

**Interfaces:**
- Consumes: `WindowEclipse.underway(at:)`, `WindowEclipse.kind`.
- Produces:
  ```swift
  ReadoutTile(..., detail: (() -> AnyView)? = nil)
  func eclipseTileText(_ kind: LunarEclipseKind) -> String   // "Total Eclipse" etc.
  SummaryTiles(primary:at:eclipse:onJump:latitude:longitude:)
  ```
  `latitude`/`longitude` are the station's, defaulting to nil alongside `onJump`: the sheet needs an `Observer` and `SummaryTiles` is the only thing between the detail view and it. All three new arguments default, so `DerivedGateDetailView`'s no-primary call and the tests keep compiling unchanged.

- [ ] **Step 1: Write the failing test**

```swift
    func testTheTileNamesTheEclipseInsteadOfTheFullMoon() {
        XCTAssertEqual(eclipseTileText(.total), "Total Eclipse")
        XCTAssertEqual(eclipseTileText(.partial), "Partial Eclipse")
        XCTAssertEqual(eclipseTileText(.penumbral), "Penumbral Eclipse")
    }
```

- [ ] **Step 2: Run it, watch it fail**

Expected: `cannot find 'eclipseTileText' in scope`.

- [ ] **Step 3: Implement**

In `Theme.swift`, beside `moonPhaseName`:

```swift
/// The Moon tile's value line while an eclipse is underway. Presentation, like
/// `moonPhaseName`: Almanac reports a kind, and the words are this app's.
func eclipseTileText(_ kind: LunarEclipseKind) -> String {
    switch kind {
    case .total: "Total Eclipse"
    case .partial: "Partial Eclipse"
    case .penumbral: "Penumbral Eclipse"
    }
}
```

Give `ReadoutTile` the optional sheet:

```swift
    /// A tile with somewhere to go: a chevron, a tap, and a sheet. Only the
    /// Moon tile has one so far; `Range` and `Next max` stay inert until they
    /// have something to say.
    var detail: (() -> AnyView)? = nil
    @State private var showDetail = false
```

In its `body`, add the chevron next to the label when `detail != nil`, and after the outer `.overlay(...)`:

```swift
        .contentShape(Rectangle())
        // A tap gesture, not a Button: Button press tracking goes dead in the
        // iPad split layout's detail column, the same reason MultiDaySchedule's
        // rows use a gesture.
        .onTapGesture { if detail != nil { showDetail = true } }
        .accessibilityAddTraits(detail != nil ? .isButton : [])
        .sheet(isPresented: $showDetail) { detail?() }
```

In `SummaryTiles`, add the two parameters and use them:

```swift
struct SummaryTiles: View {
    var primary: (label: String, value: String, caption: String)? = nil
    let at: Date
    /// The eclipse underway at `at`, from the timeline. Renames the value line
    /// and shadows the glyph.
    var eclipse: WindowEclipse? = nil
    /// Handed down from the scaffold; nil leaves the tile inert.
    var onJump: ((Date) -> Void)? = nil
    /// The station's position — the sheet needs an `Observer`, and this view is
    /// the only thing between the detail view and it.
    var latitude: Double? = nil
    var longitude: Double? = nil
```

and inside the moon tile:

```swift
                ReadoutTile(label: "Moon", caption: "\(Int((moon.fraction * 100).rounded()))% lit",
                            accessibility: "Moon",
                            detail: sheet) {
                    MoonGlyph(fraction: moon.fraction, waxing: moon.waxing, size: 14,
                              umbra: eclipse?.shadow(at: at) ?? 0)
                } value: {
                    Text(eclipse.map { eclipseTileText($0.kind) } ?? moonPhaseName(phase: moon.phase))
                        .font(ReadoutType.tileText)
                }
```

with the sheet assembled once, above `body`, so the tile stays inert when a caller has not supplied both a jump and a position:

```swift
    /// Non-nil only when the caller gave both somewhere to go and somewhere to
    /// stand. A detail view that passes neither gets today's inert tile.
    private var sheet: (() -> AnyView)? {
        guard let onJump, let latitude, let longitude else { return nil }
        return { AnyView(MoonDetailSheet(at: at, eclipse: eclipse,
                                         latitude: latitude, longitude: longitude,
                                         onJump: onJump)) }
    }
```

`MoonDetailSheet` does not exist until Task 8, so this task does not compile on its own — Task 8 is its other half and follows immediately. Run Task 8's Step 3 before the compile-check in Step 4 below.

- [ ] **Step 4: Run the test and compile-check**

Expected: PASS, build clean.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/Theme.swift SlackwaterTests/EclipseTests.swift
git commit -m "feat: let a readout tile open a sheet, and name the eclipse (#222)"
```

---

### Task 8: The Moon sheet

**Files:**
- Create: `Slackwater/MoonDetailSheet.swift`
- Test: `SlackwaterTests/EclipseTests.swift`

**Interfaces:**
- Consumes: `lunarEclipses(from:to:observer:)`, `Almanac.moonEvents`, `searchMoonPhases`, `moonPosition`, `moonIllumination`, `MoonGlyph`.
- Produces:
  ```swift
  struct MoonFacts {                                  // pure, testable, no SwiftUI
      let illumination: MoonIllumination
      let rise: Date?
      let set: Date?
      let nextFull: Date?
      let nextNew: Date?
      let distanceKm: Double
      let closest: Date?          // perigee-ish, sampled
      let farthest: Date?         // apogee-ish, sampled
      let last: WindowEclipse?
      let next: WindowEclipse?
  }
  func moonFacts(at: Date, observer: Observer, tz: TimeZone) -> MoonFacts?
  struct MoonDetailSheet: View                        // (at:eclipse:onJump:)
  ```

- [ ] **Step 1: Write the failing test**

```swift
    func testMoonFactsFindTheEclipseOnEitherSideOfTheNight() throws {
        let facts = try XCTUnwrap(moonFacts(at: utc("2026-09-07T12:00:00Z"),
                                            observer: Self.victoria,
                                            tz: TimeZone(identifier: "America/Vancouver")!))
        // Ten days after the partial, it is the one behind us.
        XCTAssertEqual(facts.last?.peak.timeIntervalSince(utc("2026-08-28T04:12:00Z")),
                       0, accuracy: 3600)
        XCTAssertEqual(facts.last?.kind, .partial)
        // And there is one ahead, whatever it is.
        XCTAssertNotNil(facts.next)
        XCTAssertGreaterThan(try XCTUnwrap(facts.next).peak, utc("2026-09-07T12:00:00Z"))
        // The near-month extremes bracket the moment.
        XCTAssertNotNil(facts.closest)
        XCTAssertNotNil(facts.farthest)
        XCTAssertGreaterThan(facts.distanceKm, 350_000)
        XCTAssertLessThan(facts.distanceKm, 410_000)
    }
```

The 04:12 UT peak with an hour of slack is Espenak's greatest-eclipse time for 2026-08-28; Almanac holds it to 60 s, so this only fails if the *wrong eclipse* was found.

- [ ] **Step 2: Run it, watch it fail**

Expected: `cannot find 'moonFacts' in scope`.

- [ ] **Step 3: Write `Slackwater/MoonDetailSheet.swift`**

```swift
// Slackwater — GPL v3. The Moon tile's sheet: everything about the moon this
// app knows, and the two eclipses either side of the scrub time.
//
// Every search in here runs ONCE, in the sheet's `.task` — none of it is on
// the scrub path, which is what lets it be this expensive.
import Almanac
import SwiftUI

struct MoonFacts {
    let illumination: MoonIllumination
    let rise: Date?
    let set: Date?
    let nextFull: Date?
    let nextNew: Date?
    let distanceKm: Double
    let closest: Date?
    let farthest: Date?
    let last: WindowEclipse?
    let next: WindowEclipse?
}

/// 400 days back covers the longest gap between consecutive lunar eclipses
/// (under a year in the 1950–2100 catalog), which is why "the last one" can be
/// a forward walk from there. Almanac has no backward or range search —
/// openwatersio/almanac#6 asks whether it should.
private let eclipseLookBack = 400.0 * 86_400
private let eclipseLookAhead = 800.0 * 86_400

func moonFacts(at: Date, observer: Observer, tz: TimeZone) -> MoonFacts? {
    guard let illumination = try? moonIllumination(at),
          let position = try? moonPosition(at) else { return nil }

    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let dayStart = cal.startOfDay(for: at)
    let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
    let events = (try? moonEvents(from: dayStart, to: dayEnd, observer: observer)) ?? []
    let phases = (try? searchMoonPhases(from: at, to: at.addingTimeInterval(45 * 86_400))) ?? []

    // Almanac has no apogee/perigee search, so sample: 6-hour steps across a
    // synodic month either side, which resolves a perigee to within a few
    // hours — enough to name a date, which is all this line does.
    var closest: (Date, Double)?
    var farthest: (Date, Double)?
    var t = at.addingTimeInterval(-15 * 86_400)
    let last = at.addingTimeInterval(15 * 86_400)
    while t <= last {
        if let km = try? moonPosition(t).distanceKm {
            if closest == nil || km < closest!.1 { closest = (t, km) }
            if farthest == nil || km > farthest!.1 { farthest = (t, km) }
        }
        t = t.addingTimeInterval(6 * 3600)
    }

    return MoonFacts(
        illumination: illumination,
        rise: events.first { $0.kind == .rise }?.time,
        set: events.first { $0.kind == .set }?.time,
        nextFull: phases.first { $0.phase == .full }?.time,
        nextNew: phases.first { $0.phase == .new }?.time,
        distanceKm: position.distanceKm,
        closest: closest?.0,
        farthest: farthest?.0,
        last: lunarEclipses(from: at.addingTimeInterval(-eclipseLookBack), to: at,
                            observer: observer).last,
        next: lunarEclipses(from: at, to: at.addingTimeInterval(eclipseLookAhead),
                            observer: observer).first)
}
```

Note what `last`/`next` mean here: `lunarEclipses` keeps only eclipses with a contact above this observer's horizon, so both lines read "the last/next one you could see from here". That is the honest thing for a sheet that says "visible from here", and it means the sheet never offers a jump to a night with nothing to look at.

- [ ] **Step 4: Run the test**

Expected: PASS. Watch the wall time; if `moonFacts` takes more than ~300 ms, halve the sampling window before the view work — it runs in a `.task`, but a sheet that renders empty for half a second is a bug too.

- [ ] **Step 5: Build the view**

Append to the same file:

```swift
struct MoonDetailSheet: View {
    let at: Date
    var eclipse: WindowEclipse? = nil
    let latitude: Double
    let longitude: Double
    let onJump: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.timeZone) private var tz
    @State private var facts: MoonFacts?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let facts {
                        head(facts)
                        line("RISE", facts.rise.map { chartTime($0, tz) } ?? "—")
                        line("SET", facts.set.map { chartTime($0, tz) } ?? "—")
                        line("NEXT FULL", when(facts.nextFull))
                        line("NEXT NEW", when(facts.nextNew))
                        line("DISTANCE", "\(Int((facts.distanceKm / 100).rounded()) * 100) km",
                             caption: [facts.closest.map { "closest \(monthDay($0, tz))" },
                                       facts.farthest.map { "farthest \(monthDay($0, tz))" }]
                                .compactMap { $0 }.joined(separator: " · "))
                        eclipseRow("LAST ECLIPSE", facts.last, id: "moon-last-eclipse")
                        eclipseRow("NEXT ECLIPSE", facts.next, id: "moon-next-eclipse")
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(20)
            }
            .background(CanvasBackground())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .navigationTitle("Moon")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard let observer = try? Observer(latitudeDeg: latitude, longitudeDeg: longitude)
            else { return }
            facts = moonFacts(at: at, observer: observer, tz: tz)
        }
    }

    private func when(_ d: Date?) -> String {
        guard let d else { return "—" }
        return "\(monthDay(d, tz)) · \(chartTime(d, tz))"
    }

    private func head(_ facts: MoonFacts) -> some View {
        HStack(spacing: 12) {
            MoonGlyph(fraction: facts.illumination.fraction, waxing: facts.illumination.waxing,
                      size: 54, umbra: eclipse?.shadow(at: at) ?? 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(eclipse.map { eclipseTileText($0.kind) }
                        ?? moonPhaseName(phase: facts.illumination.phase))
                    .font(ReadoutType.tileText)
                    .foregroundStyle(.white)
                Text("\(Int((facts.illumination.fraction * 100).rounded()))% lit")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.55))
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func line(_ label: String, _ value: String, caption: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                MonoLabel(text: label, color: SN.foam.opacity(0.55))
                Spacer()
                Text(value).font(.footnote.monospaced()).foregroundStyle(.white)
            }
            if !caption.isEmpty {
                Text(caption).font(.caption2).foregroundStyle(SN.foam.opacity(0.55))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// An eclipse either side of now. Nil reads "none visible from here"
    /// rather than vanishing: a missing row would say the app forgot to look.
    @ViewBuilder
    private func eclipseRow(_ label: String, _ e: WindowEclipse?, id: String) -> some View {
        if let e {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    MonoLabel(text: label, color: SN.umbraLabel)
                    Text(eclipseTileText(e.kind)).font(ReadoutType.tileText).foregroundStyle(.white)
                    Text(when(e.peak)).font(.caption.monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.5))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { onJump(e.start); dismiss() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(id)
        } else {
            line(label, "none visible from here")
        }
    }
}
```

`when(_:)` takes a non-optional in the eclipse row and an optional elsewhere — write the one overload above and let the row call `when(e.peak)`; Swift promotes the argument.

- [ ] **Step 6: Size probe**

`RenderProbes.swift` can host a `UIHostingController` and ask `sizeThatFits`; add a probe that the sheet lays out non-zero at the default dynamic type size and at `accessibility5`, following whatever existing test in this repo already does that (grep for `sizeThatFits`). If none exists, skip this step rather than inventing a harness — the UI test in Task 9 covers presentation.

- [ ] **Step 7: Compile-check and commit**

```bash
git add Slackwater/MoonDetailSheet.swift Slackwater/Theme.swift SlackwaterTests/EclipseTests.swift \
        Slackwater/TideDetailView.swift Slackwater/CurrentDetailView.swift \
        Slackwater/DerivedGateDetailView.swift Slackwater/OnlineGateDetailView.swift
git commit -m "feat: a Moon sheet that names the last and next eclipse (#222)"
```

---

### Task 9: Jumping, and the full suite

**Files:**
- Modify: `Slackwater/Theme.swift` — `ScrubDetailScaffold`'s `linkedInstant` `onChange` (~`:585-600`) and `scrubCard`'s `links(tl)` call (~`:645`)
- Test: `SlackwaterUITests/` (one new test, in the file that already drives a tide detail — grep for an existing `SummaryTiles`/moon assertion first)

**Interfaces:**
- Consumes: `SummaryTiles(onJump:)` (Task 7), `MoonDetailSheet.onJump` (Task 8).
- Produces: `ScrubDetailScaffold.jump(to:)`, used by both the shared-link path and the sheet.

- [ ] **Step 1: Factor the jump out of the link path**

In `ScrubDetailScaffold`:

```swift
    /// Park the centerline on `t`, moving the window when `t` is not on it.
    ///
    /// Shared by the two things that arrive with an instant in hand: a shared
    /// link (#187) and the Moon sheet's eclipse rows. The window test is the
    /// picker's rule inverted — move only when the moment isn't already on the
    /// strip, so a jump to later today doesn't open on a week bar reading
    /// "not this week".
    private func jump(to t: Date) {
        scrubTime = t
        let week = Timeline.window(anchor: anchor)
        if t < week.start || t > week.end {
            anchor = dayLocal(t, tz)
            onPicked(anchor)
        }
    }
```

and the `onChange` that applies `linkedInstant` becomes:

```swift
            .onChange(of: timeline == nil) { _, isNil in
                guard !isNil, let t = linkedInstant else { return }
                linkedInstant = nil
                jump(to: t)
            }
```

Keep the existing comment above the `onChange` — it explains the deferral, which is still true — and move the window-rule comment onto `jump(to:)` as above.

- [ ] **Step 2: Hand it to the links slot**

`links` currently has the signature `(TimelineData) -> Links`. Change it to `(TimelineData, @escaping (Date) -> Void) -> Links` and call it as `links(tl, jump)` in `scrubCard`. Update the four detail views' `links:` closures to take the second parameter and pass it to `SummaryTiles(onJump:)`:

```swift
                            links: { _, jump in SummaryTiles(primary: range, at: scrubTime,
                                                             eclipse: eclipse, onJump: jump,
                                                             latitude: record.latitude,
                                                             longitude: record.longitude) },
```

where `eclipse` is `timeline?.eclipses.first { $0.underway(at: scrubTime) }` — the same expression `SkyState` uses, and small enough to inline. `DerivedGateDetailView` passes `SummaryTiles(at: scrubTime, …)` with no primary, as it does today.

- [ ] **Step 3: Compile-check**

Expected: clean. Four call sites plus the scaffold; if any detail view still passes a one-argument closure the compiler will name it.

- [ ] **Step 4: Widen the phase-name regex in the existing test**

`SlackwaterUITests/DetailAndScrubTests.swift:186` (`testM41DetailHeaderSunMoon`) asserts the readout matches one of the eight phase names. On an eclipse day the tile now reads `Partial Eclipse` and that test fails — a real failure, on a real day, that would land on whoever is running the suite that week. Add the three eclipse names to `phaseNames`:

```swift
        let phaseNames = "New Moon|Waxing Crescent|First Quarter|Waxing Gibbous|Full Moon|Waning Gibbous|Last Quarter|Waning Crescent|Penumbral Eclipse|Partial Eclipse|Total Eclipse"
```

- [ ] **Step 5: Write the UI test**

Append to `SlackwaterUITests/DetailAndScrubTests.swift`, using this file's own helpers (`launch`, `openFridayHarbor`, `save`) exactly as `testM41DetailHeaderSunMoon` does:

```swift
    /// #222: the Moon tile is the way into the moon's own facts, and the
    /// eclipse rows are destinations — tapping one moves the window to it.
    func testTheMoonTileOpensItsSheetAndTheEclipseRowJumps() throws {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        // Case-insensitive, like the Range assertion above: the tile's eyebrow
        // combines an uppercasing MonoLabel with an accessibility label that
        // does not.
        let moon = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'moon'")).firstMatch
        XCTAssert(moon.waitForExistence(timeout: 10), "no Moon tile on the tide detail")
        moon.tap()

        XCTAssert(app.navigationBars["Moon"].waitForExistence(timeout: 5),
                  "the Moon tile did not open its sheet")
        save(app, "moon-sheet.png")

        let next = app.descendants(matching: .any)["moon-next-eclipse"].firstMatch
        XCTAssert(next.waitForExistence(timeout: 10), "no next-eclipse row in the Moon sheet")
        next.tap()

        // The sheet closes and the window has moved: the next eclipse is
        // months out, so the range bar has to be saying so.
        XCTAssertFalse(app.navigationBars["Moon"].exists, "the sheet stayed up after a jump")
        XCTAssert(app.staticTexts["not this week"].waitForExistence(timeout: 10),
                  "the jump did not move the window")
        save(app, "moon-sheet-jumped.png")
    }
```

The wait before the first tap is `waitForExistence`, not a settle helper: the tile is below the strip and is not moving. Do not tap anything *on* the strip in this test — a quiescence wait defers taps until the strip settles, so no UI test can touch it mid-glide.

- [ ] **Step 6: Run the full suite**

```sh
./scripts/test.sh
```
~15 minutes, and it self-serializes against CI on this machine. Read `build/results-*.xcresult`, not just the exit code: a run killed by contention reports "Test crashed with signal kill" with zero assertion failures. A live-network test that fails under load usually passes alone — re-run it in isolation before blaming this branch.

- [ ] **Step 7: Look at it**

Run the app, open a tide detail, use the week picker to reach 2026-08-27, and confirm by eye: the copper mark and time on the strip, the eclipse row in the list, the shadow crossing the dome's moon as you scrub through the contacts, and the Moon tile's sheet. Screenshots land in `/tmp/slackwater-shots` under `scripts/test.sh`; for a hand run, pass `TEST_RUNNER_M1_SHOT_DIR` yourself. Open them.

- [ ] **Step 8: Commit and open the draft PR**

```bash
git add -A
git commit -m "feat: jump to an eclipse from the Moon sheet (#222)"
git push -u origin HEAD
gh pr create --draft --title "A lunar eclipse the app can show, list, scrub to and explain" --body "…closes #222, links the spec and the plan, names the measured build cost…"
```

---

## Notes for the executor

- **The 2026-08-28 partial is the fixture throughout.** It is Almanac's pinned regression case, visible from Victoria, and the app's seed station is in the same sky. If a test needs a different eclipse, take it from Almanac's `EclipseTests` rather than a web search.
- **`shadow(at:)` is drawing, not data.** No number it produces is ever printed. If a future task wants to *print* a magnitude, it comes from `eclipse.magUmbral` at the peak, never from the interpolation.
- **`lunarEclipses` filters on visibility.** Anything asking "when is the next eclipse, anywhere" needs a different call — there isn't one yet, and openwatersio/almanac#6 is where that lands.
