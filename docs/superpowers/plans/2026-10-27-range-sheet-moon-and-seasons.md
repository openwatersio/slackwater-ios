# Range Sheet: Sliding Bars, Moon Strip, Season Marks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Range and Next max sheets' fortnight bars slide-to-a-day, draw the moon phases under them, and mark the real solstices and equinoxes on the year figure with a caption that says which pair the station follows.

**Architecture:** Three pure-geometry additions on two existing `Canvas` figures (`SwingFigure`, `YearFigure`), each new static function unit-tested on its own; the sheets and their builders (`TideDetailView.rangeDetail`, `CurrentDetailView.maxDetail`) compute moon phases and seasons with Almanac and pass them down as plain arrays. Gesture state lives in `SwingFigure` with `@State` and `@Environment(\.dismiss)`.

**Tech Stack:** Swift 6 / SwiftUI `Canvas`, Almanac (`searchMoonPhases`, `seasons`), XCTest unit + XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-27-range-sheet-moon-and-seasons-design.md`

## Global Constraints

- No "scrub", "scrubber" or "scrubbable" in any user-facing string. Internal names (`scrubTime`, `ScrubDetailScaffold`) untouched.
- Station-local calendar everywhere: `Calendar(identifier: .gregorian)` with `cal.timeZone = tz`, as `dailyPeaks` and `months` do.
- Use Almanac's `searchMoonPhases(from:to:)` and `seasons(from:to:)`; never reimplement.
- Every `xcodebuild` needs `-clonedSourcePackagesDirPath build/SourcePackages`. Compile-check first; run shards, never the suite.
- New localised strings carry a `comment:` like their neighbours. `formatHeight(`/`formatSpeed(` calls must sit near a `monospacedDigit()` (TypeScaleTests).
- Commits: subject in sentence case, no trailing period; end the body with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. A drag that starts on a bar and ends with the finger outside the canvas (above, or past either edge) must still jump to the last lit bar, not crash on an out-of-range index — pinned in Task 1 (clamping) and Task 2 (gesture reads the clamped index).
2. Two bars with no `onJump` (a sheet opened without a jump target) must not light or dismiss on touch — Task 2 test `testWithoutAJumpTheBarsIgnoreTouches`.
3. A moon phase instant falling on the dropped fragment day at the window's end draws nothing and does not shift the other glyphs — Task 3 test.
4. A phase on a bar at either edge of the window draws its glyph inside the canvas (the glyph is centred on `bar.x`, which already has half a step of margin) — covered by Task 3's x assertion.
5. `follows` with fewer than two standout months (a station whose year has only one month with span, or all equal spans) returns nil and the caption keeps today's wording — Task 4 test `testFollowsNeedsTwoStandoutMonths`.

---

### Task 1: Bars carry their peak; hit-testing an x

**Files:**
- Modify: `Slackwater/SwingFigure.swift:16-23, 66-83`
- Test: `SlackwaterTests/SwingFigureTests.swift`

**Interfaces:**
- Produces: `SwingFigure.Bar` gains `let peak: Peak` (its day is `cal.startOfDay(for: peak.time)`). `static func barIndex(atX x: CGFloat, count: Int, width: CGFloat) -> Int?` — nil when `count == 0`; otherwise `Int(x / (width / count))` clamped to `0...count-1`.

- [ ] **Step 1: Write the failing tests** (append to `SwingFigureTests`, using the existing `standing()`, `station`, `size` helpers)

```swift
func testEachBarCarriesItsDaysBiggestSwing() {
    let s = standing()
    let bars = SwingFigure.bars(s, tz: station.tz, size: size)
    let peaks = SwingFigure.dailyPeaks(s, tz: station.tz)
    XCTAssertEqual(bars.map(\.peak), peaks)
}

func testTheBarUnderAnXIsFoundAndClampedAtBothEdges() {
    XCTAssertEqual(SwingFigure.barIndex(atX: 0, count: 30, width: 300), 0)
    XCTAssertEqual(SwingFigure.barIndex(atX: 15, count: 30, width: 300), 1)   // step 10, 15 is in bar 1
    XCTAssertEqual(SwingFigure.barIndex(atX: 299, count: 30, width: 300), 29)
    XCTAssertEqual(SwingFigure.barIndex(atX: -40, count: 30, width: 300), 0)
    XCTAssertEqual(SwingFigure.barIndex(atX: 900, count: 30, width: 300), 29)
    XCTAssertNil(SwingFigure.barIndex(atX: 10, count: 0, width: 300))
}
```

- [ ] **Step 2: Compile-check to see them fail**

Run: `mkdir -p build && lockf -t 0 build/xcodebuild.lock xcodebuild build-for-testing -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20`
Expected: error, `Bar` has no member `peak`, no member `barIndex`.

- [ ] **Step 3: Add `peak` to `Bar` and implement `barIndex`** in `SwingFigure.swift`. `bars()` fills `peak: peaks[i]`.

- [ ] **Step 4: Run the shard**

Run: `SLACKWATER_ONLY=SlackwaterTests/SwingFigureTests ./scripts/test.sh --unit 2>&1 | tail -15`
Expected: all SwingFigureTests pass.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/SwingFigure.swift SlackwaterTests/SwingFigureTests.swift
git commit -m "Swing bars carry their peak and find the bar under an x"
```

---

### Task 2: Slide along the bars, lift to jump

**Files:**
- Modify: `Slackwater/SwingFigure.swift` (body, new state), `Slackwater/RangeDetailSheet.swift:69`, `Slackwater/MaxDetailSheet.swift:41` and its stored properties, `Slackwater/CurrentDetailView.swift:286-301`
- Test: `SlackwaterUITests/RangeSheetTests.swift`, `SlackwaterUITests/MaxSheetTests.swift`

**Interfaces:**
- Consumes: `Bar.peak`, `SwingFigure.barIndex` (Task 1); `monthDay(_:_:)` (DetailPieces.swift:711); `formatHeight(_:imperial:)`, `formatSpeed(_:unit:)` (Units.swift).
- Produces: `SwingFigure` gains `var format: ((Double) -> String)? = nil` (magnitude → "10.6 ft" / "3.2 kn", unit included) and `@State private var lit: Int?`. `MaxDetailSheet` gains `var speedUnit = "kn"`, passed from `CurrentDetailView.maxDetail` (`speedUnit` is already an `@AppStorage` there, line 39). Accessibility identifier on the figure canvas stays the sheet's (`range-section-swings` / `max-section-peaks`).

- [ ] **Step 1: Write the failing UI tests**

In `RangeSheetTests`, after `testTappingTheNextBiggerSwingMovesTheScrubber`:

```swift
/// Spec §1: a finger on the bars lights the bar under it; lifting goes to that
/// day's swing and closes the sheet.
func testSlidingAlongTheBarsAndLiftingMovesTheTimeline() throws {
    let app = launch()
    openFridayHarbor(app)
    let lead = leadReading(app)
    XCTAssert(lead.appears(within: 10), "no lead reading")
    let before = lead.label
    let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Range,'")).firstMatch
    XCTAssert(tile.appears(within: 10), "no Range tile")
    tile.tap()
    let figure = app.descendants(matching: .any)["range-section-swings"].firstMatch
    XCTAssert(figure.appears(within: 10), "no swing figure")
    // From the centre bar to the right-hand edge: a day other than the selected one.
    figure.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        .press(forDuration: 0.2, thenDragTo: figure.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
    XCTAssert(app.navigationBars["Range"].disappears(within: 2), "lifting should close the sheet")
    XCTAssert(lead.appears(within: 10), "the detail did not come back")
    XCTAssertNotEqual(lead.label, before, "the timeline did not move to the bar's day")
    save(app, "range-sheet-slid.png")
}
```

In `MaxSheetTests`, the same shape opening Deception Pass (Narrows) as `testTheNextMaxTileOpensASheetWithBothSections` does, on `max-section-peaks`, navigation bar "Next max", named `testSlidingAlongThePeaksAndLiftingMovesTheTimeline`, saving `max-sheet-slid.png`.

- [ ] **Step 2: Write the failing unit test** for the no-jump case in `SwingFigureTests`:

```swift
func testWithoutAJumpTheBarsIgnoreTouches() {
    XCTAssertFalse(SwingFigure(standing: standing(), tz: station.tz).respondsToTouch)
    XCTAssertTrue(SwingFigure(standing: standing(), tz: station.tz, onJump: { _ in }).respondsToTouch)
}
```

- [ ] **Step 3: Compile-check**: fails on `respondsToTouch`.

- [ ] **Step 4: Implement in `SwingFigure.swift`**
  - `var respondsToTouch: Bool { onJump != nil }`.
  - `@State private var lit: Int? = nil`; `@Environment(\.dismiss) private var dismiss`.
  - Wrap the `Canvas` in a `GeometryReader`-free gesture: `.gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { … }.onEnded { … }, including: respondsToTouch ? .all : .none)` — or `.gesture` applied only `if respondsToTouch`; the implementer picks one. On change: `barIndex(atX: value.location.x, count: bars.count, width: size.width)`; when it differs from `lit`, set `lit` and `UISelectionFeedbackGenerator().selectionChanged()`. On end: `if let i = lit { onJump?(bars[i].peak.time); dismiss() }`; `lit = nil`. The canvas size is known inside `Canvas`, so compute `bars` once per draw and store the count/width needed by the gesture in `@State` or recompute from the view's frame via `.onGeometryChange`; keep it simple.
  - Drawing: a bar at index `lit` strokes at opacity 1 and width 3.2 with `CurveDrawing.dot` at its top. Above it, when `format != nil`, a resolved `Text("\(monthDay(bar.peak.time, tz)) · \(format(bar.peak.magnitude))").font(.caption2.monospacedDigit())` in `SN.foam`, drawn with `anchor: .bottom` at `y = baseline - bar.height - 12`, x clamped to `[label.width/2, size.width - label.width/2]`. Raise `boxHeight` from 108 to 124 and the bar area's reserved headroom from 12 to 28 so the label never clips.
- Sheets: `RangeDetailSheet` passes `format: { "\(formatHeight($0, imperial: imperial)) \(unit)" }`; `MaxDetailSheet` passes `format: { "\(formatSpeed($0, unit: speedUnit)) \(speedUnitLabel(speedUnit))" }`; `CurrentDetailView.maxDetail` passes `speedUnit: speedUnit`. Put the closures next to a `.monospacedDigit()` use or list them in TypeScaleTests' known indirections, whichever the test wants (run it and read the failure).

- [ ] **Step 5: Run unit shards**

Run: `SLACKWATER_ONLY=SlackwaterTests/SwingFigureTests ./scripts/test.sh --unit 2>&1 | tail -15` and `SLACKWATER_ONLY=SlackwaterTests/TypeScaleTests ./scripts/test.sh --unit 2>&1 | tail -15`
Expected: pass.

- [ ] **Step 6: Run UI shards**

Run: `SLACKWATER_ONLY=SlackwaterUITests/RangeSheetTests ./scripts/test.sh 2>&1 | tail -15`, then the same for `SlackwaterUITests/MaxSheetTests`.
Expected: both new tests pass; existing ones unchanged. The saved screenshot is taken after the sheet has closed, so it cannot show the lit bar: add a `save(app, "range-sheet-lit.png")` between the press and the drag's end is not possible with `press(forDuration:thenDragTo:)`, so instead run the app (`./scripts/first-run.sh`), open the Range sheet, hold a finger on the bars and check the lit bar and its label by eye. Note what you saw in the commit body.

- [ ] **Step 7: Commit**

```bash
git add Slackwater/SwingFigure.swift Slackwater/RangeDetailSheet.swift Slackwater/MaxDetailSheet.swift Slackwater/CurrentDetailView.swift SlackwaterTests SlackwaterUITests
git commit -m "Slide along the fortnight's bars and lift to go to that day"
```

---

### Task 3: Moon phases under the bars

**Files:**
- Modify: `Slackwater/SwingFigure.swift`, `Slackwater/RangeDetailSheet.swift:69-78`, `Slackwater/MaxDetailSheet.swift:41-46`, `Slackwater/TideDetailView.swift:316-330`, `Slackwater/CurrentDetailView.swift:286-301`
- Test: `SlackwaterTests/SwingFigureTests.swift`

**Interfaces:**
- Consumes: Almanac `MoonPhaseEvent { time: Date; phase: MoonPhaseName }`, `MoonPhaseName.new/.firstQuarter/.full/.lastQuarter`, `searchMoonPhases(from:to:) throws`; `PeakStanding.window`.
- Produces: `SwingFigure` gains `var phases: [MoonPhaseEvent] = []`. `struct PhaseMark: Equatable { let index: Int; let phase: MoonPhaseName }`. `static func phaseMarks(_ phases: [MoonPhaseEvent], peaks: [Peak], tz: TimeZone) -> [PhaseMark]` — one per phase whose station-local day equals a peak's day; others dropped. `static func moonPhases(in window: (start: Date, end: Date)) -> [MoonPhaseEvent]` (wraps the `try?`, returns `[]` on throw) — lives on `SwingFigure` so both builders share it.

- [ ] **Step 1: Write the failing tests**

```swift
func testEachPhaseLandsOnItsDaysBar() throws {
    let s = standing()
    let peaks = SwingFigure.dailyPeaks(s, tz: station.tz)
    let phases = SwingFigure.moonPhases(in: s.window)
    XCTAssertGreaterThanOrEqual(phases.count, 3, "a 30-day window holds four phases, three at the least")
    let marks = SwingFigure.phaseMarks(phases, peaks: peaks, tz: station.tz)
    var cal = Calendar(identifier: .gregorian); cal.timeZone = station.tz
    for mark in marks {
        let phase = try XCTUnwrap(phases.first { $0.phase == mark.phase })
        XCTAssertEqual(cal.startOfDay(for: peaks[mark.index].time), cal.startOfDay(for: phase.time))
    }
}

func testAPhaseOnADroppedDayDrawsNothing() {
    let s = standing()
    let peaks = SwingFigure.dailyPeaks(s, tz: station.tz)
    // A phase one hour before the window's end: that day is a fragment and has no bar.
    let stray = MoonPhaseEvent(time: s.window.end.addingTimeInterval(-3600), phase: .full)
    XCTAssertEqual(SwingFigure.phaseMarks([stray], peaks: peaks, tz: station.tz), [])
}
```

(`MoonPhaseEvent`'s memberwise init may be internal to Almanac; if so, build the stray through `searchMoonPhases` over a window that ends on a phase day, or add a tiny test-only initialiser via an extension in the test target.)

- [ ] **Step 2: Compile-check**: fails on `phaseMarks` / `moonPhases`.

- [ ] **Step 3: Implement** in `SwingFigure.swift` (`import Almanac`). Draw in `body`: for each mark, a 9 pt glyph centred at `(bars[mark.index].x, baseline + 8)` in `SN.foam.opacity(0.35)`: full = filled circle; new = 1 pt stroked circle; firstQuarter = stroked circle with the right half filled; lastQuarter = left half filled. Reserve 16 pt below the baseline (raise `boxHeight` by 16 and offset `baseline` up by 16).

- [ ] **Step 4: Thread phases through**. `TideDetailView.rangeDetail`: `let phases = swing.map { SwingFigure.moonPhases(in: $0.window) } ?? []` and pass `phases:` into `RangeDetailSheet` (new `var phases: [MoonPhaseEvent] = []`) → `SwingFigure(... phases: phases ...)`. `CurrentDetailView.maxDetail` likewise from `standing.window` into `MaxDetailSheet`.

- [ ] **Step 5: Captions and VoiceOver**. Under the Range figure: `Text("Each bar is one day's biggest swing. Springs follow the new and full moon.", comment: "Explains the unit of the swing figure's bars and why they beat with the moon.")`. Max: `Text("Each bar is one day's hardest \(direction.lowercased()). Springs follow the new and full moon.", comment: "Explains the unit of the current figure's bars and why they beat with the moon. The value is 'flood' or 'ebb'.")`. `spoken` appends, for each mark in time order, `String(localized: "Full moon on \(day)", …)` / "New moon on …" / "First quarter on …" / "Last quarter on …" with `day = monthDay(phase.time, tz)`, joined with ", " and ending with ".".

- [ ] **Step 6: Run shards**: `SwingFigureTests`, `TypeScaleTests`, `TimelineTests`, then `SlackwaterUITests/RangeSheetTests` (the screenshot `range-sheet-sections.png` or similar from `testTheRangeTileOpensASheetWithAllThreeSections` — open it and confirm glyphs sit under the bars, not clipped).

- [ ] **Step 7: Commit**: `git commit -m "Draw the moon's phases under the fortnight's bars"`.

---

### Task 4: Solstices and equinoxes on the year figure

**Files:**
- Modify: `Slackwater/YearFigure.swift` (replace the standout rules, lines 55-60 comment and 89-100), `Slackwater/RangeDetailSheet.swift:92-106`, `Slackwater/MaxDetailSheet.swift:50-62`, `Slackwater/TideDetailView.swift:316-330`, `Slackwater/CurrentDetailView.swift:286-301`
- Test: `SlackwaterTests/YearFigureTests.swift`

**Interfaces:**
- Consumes: Almanac `SeasonEvent { time: Date; kind: SeasonKind }`, `SeasonKind.marchEquinox/.juneSolstice/.septemberEquinox/.decemberSolstice`, `seasons(from:to:) throws`; `YearFigure.Month`, `YearFigure.standout`; `TideStanding.yearWindow`.
- Produces on `YearFigure`: `var seasons: [SeasonEvent] = []`; `enum SeasonPair { case solstices, equinoxes }`; `nonisolated static func follows(months: [Month], seasons: [SeasonEvent], tz: TimeZone) -> SeasonPair?`; `nonisolated static func seasonX(_ event: SeasonEvent, months: [Month], tz: TimeZone, step: CGFloat) -> CGFloat?` (nil when the event's month is not in `months`; else `step * (i + fraction)` where `fraction` = days elapsed in the month / days in the month); `static func seasonsAround(_ window: (start: Date, end: Date), tz: TimeZone) -> [SeasonEvent]` — `seasons(from:to:)` over the window widened by 6 calendar months each end, `[]` on throw.

- [ ] **Step 1: Write the failing tests** (in `YearFigureTests`; build synthetic months with a helper `func synthetic(_ spans: [Double], from: Date) -> [YearFigure.Month]` giving twelve months starting at `from`, `highest: span, lowest: 0`; real seasons from `YearFigure.seasonsAround`)

```swift
func testAStationPeakingAtTheSolsticesFollowsThem()   // spans peak in June and December → .solstices
func testAStationPeakingAtTheEquinoxesFollowsThem()   // March and September → .equinoxes
func testAStationPeakingBetweenMakesNoClaim()         // May/November → nil; April/October → nil
func testFollowsNeedsTwoStandoutMonths()              // one month only → nil
func testAnEdgeMonthIsScoredAgainstTheSeasonOutsideTheWindow() {
    // Window starts April 2026; April and October peak. April's nearest equinox is 20 March 2026, outside the window.
    // With seasonsAround the sums are equinoxes ≈ 80, solstices ≈ 102 → nil (22 apart) rather than a wrong .solstices.
}
func testTheJuneSolsticeSitsTwoThirdsAcrossJune() {
    // step 30: x ≈ 30 * (i + 20/30) for a 21 June 2026 solstice (UTC 08:24 → still 21 June in Pacific). Use accuracy 1.
}
func testTheWindowHoldsFourSeasonsAndTheClassifierSeesMore() {
    // seasonsAround over a 12-month window returns 8 events; those inside the window number 4.
}
```

Each assertion uses `YearFigure.follows(months:seasons:tz:)` / `seasonX` with the station's tz. Distances: from the month's 16th at local noon to the event instant, in days.

- [ ] **Step 2: Compile-check**: fails.

- [ ] **Step 3: Implement** in `YearFigure.swift` (`import Almanac`). `follows`: `standout(months)`; `guard count == 2 else nil`; for each, nearest solstice distance and nearest equinox distance in days; `sumS`, `sumE`; `abs(sumS - sumE) <= 45 ? nil : (sumS < sumE ? .solstices : .equinoxes)`. Replace the standout rules in `body` with one dotted rule per `seasons` event that has a `seasonX`, from `y(months[i].highest) - 6` to `y(months[i].lowest) + 6`, same stroke. Delete the "the equinoxes" sentence from `standout`'s doc comment (it still picks the two widest; say only that).

- [ ] **Step 4: Thread seasons through**. `TideDetailView.rangeDetail`: `let seasons = YearFigure.seasonsAround(TideStanding.yearWindow(around: live, tz: record.tz), tz: record.tz)`; `RangeDetailSheet` gains `var seasons: [SeasonEvent] = []` → `YearFigure(... seasons: seasons)`. Same in `CurrentDetailView.maxDetail` → `MaxDetailSheet`.

- [ ] **Step 5: Captions**. In both sheets, `let pair = YearFigure.follows(months: months, seasons: seasons, tz: tz)`. Range:
  - `.solstices`: `"Widest around \(month), near the solstice."` comment "Caption under the year figure. The value is a month name."
  - `.equinoxes`: `"Widest around \(month), near the equinox."`
  - nil: existing `"Widest around \(month)."`
  Max: `"Hardest around \(month), near the solstice."` / `"…, near the equinox."` / existing. `YearFigure.spoken` appends `" Near the solstices."` / `" Near the equinoxes."` when known.

- [ ] **Step 6: Run shards**: `YearFigureTests`, `TypeScaleTests`, then `SlackwaterUITests/RangeSheetTests` and `MaxSheetTests`. In the Range test `testTheRangeTileOpensASheetWithAllThreeSections`, add an assertion that a static text beginning "Widest around" exists; read its label from the result and, if it says "near the solstice" at Friday Harbor (expected: Friday Harbor is mixed-diurnal, widest near the solstices), pin that with `XCTAssert(label.hasSuffix("near the solstice."))`. If it comes out nil, pin the plain form and note it in the commit body.

- [ ] **Step 7: Commit**: `git commit -m "Mark the solstices and equinoxes on the year figure"`.

---

### Task 5: Docs and the whole-branch check

**Files:**
- Modify: `docs/detail.md:146, 150, 167, 171`

- [ ] **Step 1: Update §6.4 and §6.5** in `docs/detail.md`:
  - §6.4 bars paragraph: after "the next bigger day is flagged ahead of it", add that a finger on the bars lights the bar under it with its day and height, and lifting moves the timeline to that day's swing and closes the sheet; and that the new, quarter and full moons are drawn under the days they fall on, because the beat the bars show is the spring/neap cycle. Caption now ends "Springs follow the new and full moon."
  - §6.4 year paragraph: "with the widest months marked" → "with the solstices and equinoxes ruled at their dates"; add that the caption says "near the solstice" where the two widest months sit nearer the solstices than the equinoxes (summed mid-month distances, decided only when the sums differ by more than 45 days, so a station between kinds keeps the plain caption), and that seasons are searched six months past the window so an edge month is scored against its true nearest.
  - §6.5: mirror both on the Next max sheet in one sentence each.

- [ ] **Step 2: Source-wide checks**

Run: `SLACKWATER_ONLY=SlackwaterTests/TimelineTests ./scripts/test.sh --unit 2>&1 | tail -8`, then `TypeScaleTests`, `ColourAndFormTests`, `HeroChromeTests`.
Expected: pass.

- [ ] **Step 3: Website screenshot**

Run: `SLACKWATER_ONLY=SlackwaterUITests/WebsiteScreenshots ./scripts/test.sh 2>&1 | tail -8`; open the Range sheet screenshot it writes and check the moon glyphs and season rules read cleanly.

- [ ] **Step 4: Grep for banned copy**

Run: `grep -rn -i "scrub" Slackwater/*.swift | grep -i "localized\|Text(\"" | grep -v "// "`
Expected: no user-facing string.

- [ ] **Step 5: Commit**: `git commit -m "Document the Range sheet's sliding bars, moon strip and season marks"`.
