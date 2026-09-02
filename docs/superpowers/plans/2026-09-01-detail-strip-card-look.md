# Detail Strip Card Look Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the detail scrubber's canvas draw the same picture the station cards draw (PR #252), on both tracks, and fix the night band's top edge (#246).

**Architecture:** `TimelineCanvas` in `Slackwater/TimelineStrip.swift` is the one drawing routine for tide and current detail strips; `StationCardGraph` in `Slackwater/StationCardGraph.swift` is the card's. This plan moves the card's curve style into shared constants, adds two pure window helpers both surfaces call, then rewrites `drawTide` and `drawCurrent` to the card look while leaving the scrubber, day chrome, axis column and `TimelineData` untouched.

**Tech Stack:** Swift 6, SwiftUI `Canvas`/`GraphicsContext`, XCTest, XcodeGen, iOS 26 simulator (iPhone 17).

**Spec:** `docs/superpowers/specs/2026-09-01-detail-strip-card-look-design.md`

## Global Constraints

- Branch `feat/detail-strip-card-look`, stacked on `feat/station-card-graphs` (PR #252). Never commit to `feat/station-card-graphs`.
- The repo is a worktree at `/Users/clarkbw/src/openwaters/slackwater-ios-wt-station-card-graphs`. Run `xcodegen generate` once if `Slackwater.xcodeproj` is missing.
- Every `xcodebuild` needs `-clonedSourcePackagesDirPath build/SourcePackages`.
- Compile check (about a minute), used after every code step below:
  ```sh
  lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
    -project Slackwater.xcodeproj -scheme Slackwater \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
  ```
  If `lockf` fails immediately, another test run holds the machine. Wait; never force it.
- One test class (a few minutes):
  ```sh
  lockf -t 0 /tmp/slackwater-test.lock xcodebuild test \
    -project Slackwater.xcodeproj -scheme Slackwater \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -only-testing:SlackwaterTests/<ClassName> 2>&1 \
    | grep -E "Test Case '.*' (passed|failed)|error:|\*\* TEST"
  ```
- Chart labels keep fixed `.system(size:)` fonts (spec §2). Do not convert them to text styles.
- Green (`SN.go`) means a slack window and nothing else. Never colour anything else with it.
- Inside `drawCurrent` the tokens `SN.flood`, `SN.ebb`, `SN.rising`, `SN.falling`, `SN.leaf` are banned by `ColourAndFormTests.testCurrentTrackDoesNotSpeakDirectionInColour`. Current-track labels use `SN.foam`.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. No session links: the repo is public.
- Shut down any simulator you boot with `xcrun simctl shutdown <udid>`, never `shutdown all`.

---

## File map

| File | Responsibility after this plan |
|---|---|
| `Slackwater/Theme.swift` | Gains `enum CurveStyle`: the five curve constants both surfaces share. |
| `Slackwater/SlackWindow.swift` | Gains `WindowRun`, `mergeWindows`, `currentAxisMoments`: pure window helpers. |
| `Slackwater/StationCardGraph.swift` | Card canvas; uses `CurveStyle`, `WindowRun`, `currentAxisMoments`; gains the window-start dot. |
| `Slackwater/TimelineStrip.swift` | `TimelineGeo` (one plot box + one time row), `TimelineCanvas` (card look), `tideRateStops`. Loses `drawBand`, `suppressesSlackLabel`, `slackFillSegments`. |
| `SlackwaterTests/SlackWindowTests.swift` | Tests for the two new helpers. |
| `SlackwaterTests/TimelineTests.swift` | Geometry and tide-track tests updated; two dead tests removed; `tideRateStops` test added. |

---

### Task 1: Shared curve constants

**Files:**
- Modify: `Slackwater/Theme.swift` (after the `SN` enum's `graphLow` line, ~line 60)
- Modify: `Slackwater/StationCardGraph.swift:30-64`

**Interfaces:**
- Produces: `enum CurveStyle { static let lineWidth: CGFloat = 2.5; static let pastLineOpacity = 0.35; static let pastLabelFade = 0.45; static let dotRadius: CGFloat = 2.5; static let haloGap: CGFloat = 2.5; static let nowDotDiameter: CGFloat = 7; static let fillOpacity = 0.5; static let tideFillFloor = 0.05; static let referenceLineOpacity = 0.35; static let referenceLineDash: [CGFloat] = [1, 3]; static let pointerOffset: CGFloat = 18; static let valueFontSize: CGFloat = 15; static let pointerFontSize: CGFloat = 15 }`

- [ ] **Step 1: Add `CurveStyle` to Theme.swift**

Insert after the `SN` enum closes (find `static let graphLow`; add the new enum after the enclosing `enum SN { … }` block, at file scope):

```swift
/// The curve as the station cards draw it, shared with the detail strip so
/// the page a card opens into is the same drawing at larger scale. Every knob
/// both surfaces read lives here; a value only one of them uses stays local.
enum CurveStyle {
    static let lineWidth: CGFloat = 2.5
    /// The line left of now, and the labels of moments already passed.
    static let pastLineOpacity = 0.35
    static let pastLabelFade = 0.45
    /// Extreme and window-start dots; the now dot is its own size.
    static let dotRadius: CGFloat = 2.5
    static let nowDotDiameter: CGFloat = 7
    /// The background-punched ring beyond a dot's or run's edge.
    static let haloGap: CGFloat = 2.5
    /// The area gradient at full intensity, and the tide fill's floor.
    static let fillOpacity = 0.5
    static let tideFillFloor = 0.05
    /// The dotted datum/zero reference line.
    static let referenceLineOpacity = 0.35
    static let referenceLineDash: [CGFloat] = [1, 3]
    /// The pointer glyph's distance from the value on the band.
    static let pointerOffset: CGFloat = 18
    static let valueFontSize: CGFloat = 15
    static let pointerFontSize: CGFloat = 15
}
```

- [ ] **Step 2: Point the card at it**

In `StationCardGraph.swift`, delete these private statics: `lineWidth`, `fillOpacity`, `tideFillFloor`, `referenceLineOpacity`, `referenceLineDash`, `pastLineOpacity`, `pastLabelFade`, `dotRadius`, `nowDotDiameter`, `haloGap`, `pointerOffset`, `valueFontSize`, `pointerFontSize`. Keep `domainPadFraction`, `axisHeight`, `nearDatum`, `labelEdgeMargin`, `axisEdgeMargin`, `timeFontSize`, `timeBaseline`.

Then replace every `Self.<deleted name>` in the file with `CurveStyle.<name>`:

```sh
cd /Users/clarkbw/src/openwaters/slackwater-ios-wt-station-card-graphs
for n in lineWidth fillOpacity tideFillFloor referenceLineOpacity referenceLineDash \
         pastLineOpacity pastLabelFade dotRadius nowDotDiameter haloGap pointerOffset \
         valueFontSize pointerFontSize; do
  sed -i '' "s/Self\.$n\b/CurveStyle.$n/g" Slackwater/StationCardGraph.swift
done
grep -c 'CurveStyle\.' Slackwater/StationCardGraph.swift
```

Expected: a count above 20 and no remaining `Self.lineWidth` etc. (`grep -n 'Self\.\(lineWidth\|haloGap\|dotRadius\)' Slackwater/StationCardGraph.swift` prints nothing).

- [ ] **Step 3: Compile check**

Run the compile check from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```sh
git add Slackwater/Theme.swift Slackwater/StationCardGraph.swift
git commit -m "refactor: share the card's curve constants as CurveStyle

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Window runs and axis moments

**Files:**
- Modify: `Slackwater/SlackWindow.swift` (append at end)
- Modify: `Slackwater/StationCardGraph.swift` (`struct Window`, `var windows`, `cardWindows`, the two current builders)
- Modify: `docs/superpowers/specs/2026-09-01-detail-strip-card-look-design.md` §5 Axis bullet
- Test: `SlackwaterTests/SlackWindowTests.swift`

**Interfaces:**
- Produces:
  - `struct WindowRun: Equatable { let start: Date; let end: Date }`
  - `func mergeWindows(_ windows: [(start: Date, end: Date)]) -> [WindowRun]` — chronological input; touching or overlapping windows become one run.
  - `func currentAxisMoments(runs: [WindowRun], slacks: [Date]) -> [Date]` — each run's start, plus every slack no run contains; sorted.
  - `StationCardGraph.windows: [WindowRun]`, `StationCardGraph.slacks: [Date]`.
  - `cardWindows(points:slacks:threshold:) -> [WindowRun]`.

- [ ] **Step 1: Write the failing tests**

Append inside the class in `SlackwaterTests/SlackWindowTests.swift`, before the final `}`:

```swift
    // MARK: - Runs and axis moments (shared by the card and the strip)

    /// Touching or overlapping windows are one run (current-charts spec §4.3);
    /// a gap keeps two runs apart.
    func testMergeWindowsJoinsTouchingAndOverlappingRuns() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let s = { (m: Double) in t0.addingTimeInterval(m * 60) }
        let runs = mergeWindows([(start: s(50), end: s(120)),
                                 (start: s(110), end: s(220)),   // overlaps
                                 (start: s(220), end: s(340)),   // touches
                                 (start: s(500), end: s(700))])  // gap
        XCTAssertEqual(runs, [WindowRun(start: s(50), end: s(340)),
                              WindowRun(start: s(500), end: s(700))])
    }

    /// The axis prints one time per run, at the run's opening, and the bare
    /// slack instant only where no run covers a slack (the hairline case).
    func testCurrentAxisMomentsNameRunStartsAndBareSlacks() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let s = { (m: Double) in t0.addingTimeInterval(m * 60) }
        let runs = [WindowRun(start: s(50), end: s(340)), WindowRun(start: s(500), end: s(700))]
        let moments = currentAxisMoments(runs: runs, slacks: [s(76), s(188), s(600), s(999)])
        XCTAssertEqual(moments, [s(50), s(500), s(999)])
    }
```

- [ ] **Step 2: Run to verify they fail**

Run the one-class command with `-only-testing:SlackwaterTests/SlackWindowTests`.
Expected: compile error, `cannot find 'mergeWindows' in scope`.

- [ ] **Step 3: Implement the helpers**

Append to `Slackwater/SlackWindow.swift`:

```swift
/// One usable run of slack water. Touching or overlapping windows merge into
/// one run and carry one label (current-charts spec §4.3); the predicate that
/// produced each window is unchanged, only the drawing joins them.
struct WindowRun: Equatable {
    let start: Date
    let end: Date
    func contains(_ t: Date) -> Bool { start <= t && t <= end }
}

/// Windows in chronological order → runs. Two windows join when the later
/// one starts at or before the earlier one ends.
func mergeWindows(_ windows: [(start: Date, end: Date)]) -> [WindowRun] {
    var runs: [WindowRun] = []
    for w in windows {
        if let last = runs.last, w.start <= last.end {
            runs[runs.count - 1] = WindowRun(start: last.start, end: max(last.end, w.end))
        } else {
            runs.append(WindowRun(start: w.start, end: w.end))
        }
    }
    return runs
}

/// The moments a current axis prints: each run's opening (the time a planner
/// is aiming at — spec §4.6), plus the bare instant of any slack no run
/// covers, which is the hairline case (§5.3). Sorted.
func currentAxisMoments(runs: [WindowRun], slacks: [Date]) -> [Date] {
    let bare = slacks.filter { t in !runs.contains { $0.contains(t) } }
    return (runs.map(\.start) + bare).sorted()
}
```

- [ ] **Step 4: Move the card onto `WindowRun`**

In `Slackwater/StationCardGraph.swift`:

Replace
```swift
    struct Window {
        let start: Date
        let end: Date
    }
    var windows: [Window] = []
```
with
```swift
    var windows: [WindowRun] = []
    /// Every slack instant on the curve, so the axis can print the bare
    /// instant where no run covers a slack. Only signed current curves.
    var slacks: [Date] = []
```

Replace the whole `cardWindows` function with:
```swift
/// The card's runs: one window per slack from the SHARED `slackWindow`
/// predicate against the effective threshold, merged where they touch.
func cardWindows(points: [CurrentPoint], slacks: [Date], threshold: Double = slackThresholdKn) -> [WindowRun] {
    mergeWindows(slacks.compactMap { slackWindow(points, around: $0, threshold: threshold) })
}
```

In both current builders (`extension CurrentStationRecord` and `extension ChsOnlineWindow`), the `windows:` argument stays; add a `slacks:` argument right after it. In `CurrentStationRecord.cardGraph`:
```swift
            windows: cardWindows(points: raw,
                                 slacks: events.filter { $0.kind == .slack }.map(\.time)),
            slacks: events.filter { $0.kind == .slack }.map(\.time))
```
Same two lines in `ChsOnlineWindow.cardGraph`.

Check `slackWindow`'s return type in `SlackWindow.swift:38`: if it returns a named tuple `(start: Date, end: Date)` the `compactMap` above compiles as written; if it returns something else, map it to `(start:end:)` inside the closure.

- [ ] **Step 5: Correct the spec**

In `docs/superpowers/specs/2026-09-01-detail-strip-card-look-design.md`, §5 **Axis** bullet, replace
`Touching windows are already one run from `TimelineData`, so one label per run falls out.`
with
`Touching or overlapping windows are merged into one run by the shared `mergeWindows` before drawing or labelling; `TimelineData.slackWindows` itself stays one window per slack.`

- [ ] **Step 6: Run the tests**

Run `-only-testing:SlackwaterTests/SlackWindowTests`.
Expected: every test in the class `passed`, including the two `testCardWindows…` tests that now go through `mergeWindows`.

- [ ] **Step 7: Commit**

```sh
git add Slackwater/SlackWindow.swift Slackwater/StationCardGraph.swift \
        SlackwaterTests/SlackWindowTests.swift docs/superpowers/specs/2026-09-01-detail-strip-card-look-design.md
git commit -m "feat: shared window runs and axis moments for current curves

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Card gets the window-start dot and axis time

**Files:**
- Modify: `Slackwater/StationCardGraph.swift` (the `for w in windows` loop and the `if includesZero` crossing-time loop that follows it)

**Interfaces:**
- Consumes: `CurveStyle`, `WindowRun`, `currentAxisMoments`, `StationCardGraph.slacks`.

- [ ] **Step 1: Draw the start dot**

Inside the `for w in windows` loop, after the two `strokeGo(...)` calls, add:

```swift
                // The run's opening gets the only dot on a current curve: it
                // is the moment the axis time below names (spec §4.6).
                let fade = w.start < now ? CurveStyle.pastLabelFade : 1.0
                dot(at: CGPoint(x: x0, y: y(valueAt(w.start))), color: SN.go.opacity(fade))
```

- [ ] **Step 2: Replace the crossing scan with the shared moments**

Replace the entire block that begins `// Each crossing's time still joins the bottom axis.` and its `if includesZero { for i in 1..<points.count { … } }` with:

```swift
            // The axis names each run's opening, and a bare slack only where
            // no run covers it — the same moments the detail strip prints.
            if includesZero {
                for when in currentAxisMoments(runs: windows, slacks: slacks) {
                    let cx = x(when)
                    let fade = when < now ? CurveStyle.pastLabelFade : 1.0
                    guard cx >= Self.axisEdgeMargin,
                          cx <= size.width - Self.axisEdgeMargin else { continue }
                    context.draw(Text(cardTime(when, tz))
                                    .font(.system(size: Self.timeFontSize).monospacedDigit())
                                    .fontWeight(.medium)
                                    .foregroundStyle(SN.foam.opacity(fade)),
                                 at: CGPoint(x: cx, y: size.height - Self.timeBaseline))
                }
            }
```

Update the doc comment on `var tz` from "Formats the slack-crossing times computed inside the canvas" to "Formats the axis times computed inside the canvas".

- [ ] **Step 3: Compile check, then look at it**

Run the compile check. Expected `** BUILD SUCCEEDED **`.

Build and launch the app on the iPhone 17 simulator, open the station list, and confirm on a current card (Seymour Narrows in Favorites, or Patos Island Light): a green dot at the left end of each green run, and the time under it is the run's opening, earlier than the old zero-crossing time. Screenshot with `xcrun simctl io <udid> screenshot <scratchpad>/card.png` and open it.

```sh
xcodebuild build -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | grep -E 'error:|BUILD'
APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphonesimulator/Slackwater.app' -maxdepth 6 | head -1)
UDID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for v in d["devices"].values() for x in v if x["name"]=="iPhone 17"))')
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" org.openwaters.slackwater
```

- [ ] **Step 4: Run the card tests and commit**

Run `-only-testing:SlackwaterTests/SlackWindowTests` and `-only-testing:SlackwaterTests/TypeScaleTests`. Expected: all `passed`.

```sh
git add Slackwater/StationCardGraph.swift
git commit -m "feat: card marks each slack run's opening with a dot and its time

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Night bands reach the strip top (#246)

**Files:**
- Modify: `Slackwater/TimelineStrip.swift` `drawDayChrome`, the line `let top = geo.dayY + 4`

- [ ] **Step 1: Change the band's top**

Replace
```swift
            let top = geo.dayY + 4
```
with
```swift
            // From the very top: the reading line spans y=8…bodyBottom and
            // the moon's glow already reaches y=0, so a band starting at
            // dayY+4 drew a crisp edge two points above the moon disc with
            // the day row on unshaded ground (#246). The labels sit inside
            // the night now, the way the moon does.
            let top: CGFloat = 0
```

- [ ] **Step 2: Compile check and rendered-strip tests**

Run the compile check. Then run `-only-testing:SlackwaterTests/RenderedStripTests`. Expected: all `passed`. The blank-strip floor is measured live inside each test, so more night area does not move the thresholds.

- [ ] **Step 3: Commit**

```sh
git add Slackwater/TimelineStrip.swift
git commit -m "fix: night bands reach the strip top instead of stopping under the moon

Closes #246.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: One plot box and one time row (`TimelineGeo`)

**Files:**
- Modify: `Slackwater/TimelineStrip.swift` — `struct TimelineGeo` (~lines 702-747), `floatingNowButton` (`.position(x: 52, y: geo.hasTide ? geo.bottomTimeY : geo.maxTimeY)`), `drawBand` (delete), the `drawBand(` call in `drawTide`, the `geo.slackRangeY` and `geo.maxTimeY` uses in `drawCurrent`
- Test: `SlackwaterTests/TimelineTests.swift` — `assertBandsAreReadable` (delete), `testSingleTrackGeometries`

**Interfaces:**
- Produces: `TimelineGeo.timeY: CGFloat` (the bottom axis row). Removes `topGlyphY`, `topValueY`, `topTimeY`, `bottomGlyphY`, `bottomValueY`, `bottomTimeY`, `slackRangeY`, `maxTimeY`, `drawBand`.
- Both tracks: `bodyTop = 60`, `bodyBottom = 250`, `height = 284`, `timeY = bodyBottom + 18`.

- [ ] **Step 1: Update the geometry test first**

In `SlackwaterTests/TimelineTests.swift`, delete the whole `private func assertBandsAreReadable(...)`.

In `testSingleTrackGeometries`, replace everything from `// NEAPS bands above and below the track, no gutter.` through the `XCTAssertLessThan(cur.maxTimeY, cur.height - 8, "and inside the canvas")` line with:

```swift
        // One plot box for either track (card-look spec §2): the readings
        // live on the curve and one time row under it, so there is nothing
        // left to size differently. Asserted as structure, not pixels.
        XCTAssertEqual(tide.bodyTop, tide.tideTop)
        XCTAssertEqual(tide.bodyBottom, tide.tideBottom)
        XCTAssertGreaterThan(tide.bodyTop, tide.sunY + 8 + 8, "the plot clears the moon disc")
        XCTAssertGreaterThan(tide.timeY, tide.bodyBottom + 8, "the time row sits under the plot")
        XCTAssertLessThan(tide.timeY, tide.height - 8, "and inside the canvas")

        // Current-only: construct TimelineData directly — the geometry keys only
        // on which point arrays are non-empty.
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let cur = TimelineGeo(data: TimelineData(
            tz: .current, anchor: t0, today: t0, start: t0, end: t0.addingTimeInterval(3600),
            days: [], tidePoints: [], tideRates: [], tideExtremes: [],
            currentPoints: [CurrentPoint(time: t0, speed: 1)], currentEvents: [],
            snapTimes: [], slackWindows: []))
        XCTAssert(!cur.hasTide && cur.hasCurrent)
        XCTAssertEqual(cur.bodyTop, cur.curTop)
        XCTAssertEqual(cur.bodyBottom, cur.curBottom)
        XCTAssertEqual(cur.height, tide.height, "same canvas for both tracks")
        XCTAssertEqual(cur.curTop, tide.tideTop, "same plot box for both tracks")
        XCTAssertEqual(cur.curBottom, tide.tideBottom)
        XCTAssertEqual(cur.timeY, tide.timeY)
```

Keep the `both` block that follows unchanged.

- [ ] **Step 2: Run to verify it fails**

Run `-only-testing:SlackwaterTests/TimelineTests`. Expected: compile error, `value of type 'TimelineGeo' has no member 'timeY'`.

- [ ] **Step 3: Rewrite `TimelineGeo`**

Replace the doc comment and struct from `/// Every number in here is a literal point` through the closing `}` of `TimelineGeo` (just before `// MARK: - The strip content`) with:

```swift
/// Every number in here is a literal point, and that is why the chart's own
/// labels are the one place in this branch that keeps a fixed `.system(size:)`
/// — text scaled inside fixed-point geometry degrades by OVERPRINTING the
/// chart, not by wrapping (measured at AX5). Making the labels scale means
/// making this geometry scale with them — a real chart-layout change, not a
/// font swap. Until then the labels stay fixed; don't "finish the job" here.
///
/// The card look (spec §2): day chrome on top, one plot box, one time row
/// under it. Readings annotate the curve itself, so both tracks share the
/// same box; `tideY`/`curY` map data onto it.
struct TimelineGeo {
    let hasTide: Bool
    let hasCurrent: Bool
    let height: CGFloat = 284
    let dayY: CGFloat = 20
    let sunY: CGFloat = 34   // also the night moons' centre line
    let tideTop: CGFloat
    let tideBottom: CGFloat
    let bodyTop: CGFloat
    let curTop: CGFloat
    let curBottom: CGFloat
    let bodyBottom: CGFloat
    let tideMid: Double
    let tideSpan: Double     // half-range, padded (prototype amp*1.18)
    let maxAbsCur: Double    // prototype mxv = cur.mx*1.05

    /// The plot box. 60 clears the moon disc (sunY 34 + radius 8) with room
    /// for a dot's halo; 250 leaves the time row and a margin under it.
    private static let plotTop: CGFloat = 60
    private static let plotBottom: CGFloat = 250

    init(data: TimelineData) {
        hasTide = data.hasTide
        hasCurrent = data.hasCurrent
        // ONE track box, whichever track fills it. The switch resolves a
        // hypothetical both-tracks input tide-first instead of drawing two
        // curves through each other.
        switch (hasTide, hasCurrent) {
        case (true, _):
            tideTop = Self.plotTop; tideBottom = Self.plotBottom
            curTop = 0; curBottom = 0
        default:
            tideTop = 0; tideBottom = 0
            curTop = Self.plotTop; curBottom = Self.plotBottom
        }
        bodyTop = hasTide ? tideTop : curTop
        bodyBottom = hasCurrent ? curBottom : tideBottom
        let heights = data.tidePoints.map(\.height)
        let mn = heights.min() ?? 0, mx = heights.max() ?? 1
        tideMid = (mn + mx) / 2
        // 1.06: the padding only has to clear a dot and its halo now that the
        // readings sit on a band across the middle rather than at the turns.
        tideSpan = max((mx - mn) / 2, 0.01) * 1.06
        maxAbsCur = max(data.currentPoints.map { abs($0.speed) }.max() ?? 1, 0.01) * 1.05
    }

    var zeroY: CGFloat { (curTop + curBottom) / 2 }
    var curHalf: CGFloat { (curBottom - curTop) / 2 - 3 }
    /// The one row of absolute times, under the plot (current spec §5.5:
    /// one home per surface).
    var timeY: CGFloat { bodyBottom + 18 }

    func tideY(_ h: Double) -> CGFloat {
        tideTop + (1 - CGFloat((h - (tideMid - tideSpan)) / (2 * tideSpan))) * (tideBottom - tideTop)
    }
    func curY(_ v: Double) -> CGFloat {
        zeroY - CGFloat(max(-1, min(1, v / maxAbsCur))) * curHalf
    }
}
```

- [ ] **Step 4: Make the canvas compile against it (mechanical only)**

These edits keep the old drawing working on the new rows; Tasks 6 and 7 replace the drawing.

1. In `TimelineScrubStrip.floatingNowButton`, replace `.position(x: 52, y: geo.hasTide ? geo.bottomTimeY : geo.maxTimeY)` with `.position(x: 52, y: geo.timeY)`.
2. Delete the whole `private func drawBand(...)` and its doc comment.
3. In `drawTide`, replace
   ```swift
            drawBand(ctx, x: x, top: high, glyph: high ? "⤒" : "⤓",
                     primary: formatHeight(e.height, imperial: imperial),
                     secondary: chartTime(e.time, data.tz), tint: tint)
   ```
   with
   ```swift
            ctx.draw(Text(chartTime(e.time, data.tz))
                        .font(.system(size: 12).monospaced())
                        .foregroundStyle(.white.opacity(0.6)),
                     at: CGPoint(x: x, y: geo.timeY), anchor: .center)
   ```
4. In `drawCurrent`, replace `y: geo.slackRangeY` with `y: geo.timeY` and `y: geo.maxTimeY` with `y: geo.timeY`.

- [ ] **Step 5: Run the geometry tests**

Run `-only-testing:SlackwaterTests/TimelineTests`. Expected: `testSingleTrackGeometries` and `testFloatingReadoutMovesAwayFromTheCurve` pass. `testTideTrackUsesBlueFillAndCurveFollowingChevrons` still passes (drawTide is not yet rewritten). Everything else in the class passes.

- [ ] **Step 6: Commit**

```sh
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift
git commit -m "refactor: one plot box and one time row for the detail strip

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Tide track takes the card look

**Files:**
- Modify: `Slackwater/TimelineStrip.swift` — add `tideRateStops` next to `currentFillStops`; add shared drawing helpers to `TimelineCanvas`; rewrite `drawTide`; the `draw(_:)` now-line block
- Test: `SlackwaterTests/TimelineTests.swift` — replace `testTideTrackUsesBlueFillAndCurveFollowingChevrons`; add `testTideRateStopsColourOnlyFastWater`

**Interfaces:**
- Produces:
  - `func tideRateStops(_ rates: [(time: Date, rate: Double)], x: (Date) -> CGFloat, width: CGFloat) -> [Gradient.Stop]` — plain tuples, not `TideRatePoint`, because that struct has no public initializer for a test to call.
  - On `TimelineCanvas`: `nowX: CGFloat`, `fade(_ t: Date) -> Double`, `strokeSplitAtNow(_:_:with:lineWidth:)`, `punchHalo(_:at:dotRadius:)`, `dot(_:at:color:)`, `referenceLine(_:at:)`, `drawNowDot(_:at:)`. Task 7 reuses all of them.

- [ ] **Step 1: Write the failing tests**

In `SlackwaterTests/TimelineTests.swift`, replace the whole `testTideTrackUsesBlueFillAndCurveFollowingChevrons` with:

```swift
    /// The tide track draws the card's curve: the card's blue fill, no
    /// speed palette in the fill, and the tide-rate ramp carried by the
    /// LINE COLOUR rather than by chevron glyphs (card-look spec §4).
    func testTideTrackUsesCardFillAndRateColouredLine() throws {
        let source = try repoSource("Slackwater/TimelineStrip.swift")
        let lines = source.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains("private func drawTide(") }),
              let end = lines[(start + 1)...].firstIndex(where: { $0.contains("private func deg(") })
        else { return XCTFail("drawTide body not found") }
        let body = lines[start..<end].joined(separator: "\n")

        XCTAssertFalse(body.contains("currentFillStops"), "tide fill must not use the current speed palette")
        XCTAssertTrue(body.contains("SN.graphLine.opacity(CurveStyle.fillOpacity)"), "tide fill is the card's blue gradient")
        XCTAssertFalse(body.contains("››››"), "chevrons are gone; the line carries the rate")
        XCTAssertTrue(body.contains("tideRateStops("), "the stroke takes its colour from the tide-rate ramp")
    }

    /// Below the ramp floor the line is the base colour; above it the stroke
    /// follows the absolute tide-rate ramp, so a lazy tide never leaves blue
    /// and a Fundy run reaches red.
    func testTideRateStopsColourOnlyFastWater() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let x = { (t: Date) -> CGFloat in CGFloat(t.timeIntervalSince(t0)) }
        let lazy = [(time: t0, rate: 0.2), (time: t0.addingTimeInterval(100), rate: -0.5)]
        XCTAssertTrue(tideRateStops(lazy, x: x, width: 100).allSatisfy { $0.color == SN.graphLine })

        let fundy = [(time: t0, rate: 0.2),
                     (time: t0.addingTimeInterval(50), rate: 1.8),
                     (time: t0.addingTimeInterval(100), rate: 0.2)]
        let stops = tideRateStops(fundy, x: x, width: 100)
        XCTAssertEqual(stops[0].color, SN.graphLine)
        XCTAssertEqual(stops[1].color, SN.speedColour(1), "1.8 m/hr is the red ceiling")
        XCTAssertEqual(stops[2].color, SN.graphLine)
        XCTAssertEqual(stops[1].location, 0.5, accuracy: 0.001)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run `-only-testing:SlackwaterTests/TimelineTests`. Expected: compile error, `cannot find 'tideRateStops' in scope`.

- [ ] **Step 3: Add `tideRateStops`**

In `TimelineStrip.swift`, directly after `currentFillStops` ends, add:

```swift
/// Stroke stops for the tide line (card-look spec §4). Under the ramp floor
/// the line is the base colour; from the floor up it takes the absolute
/// tide-rate ramp, so a fast run climbs yellow to red toward its fastest
/// point and back. Locations are strip fractions, so the gradient stays put
/// under `TimelineCanvas`'s per-tile translate.
func tideRateStops(_ rates: [(time: Date, rate: Double)], x: (Date) -> CGFloat, width: CGFloat) -> [Gradient.Stop] {
    guard width > 0, !rates.isEmpty else { return [] }
    let stops = rates.map { p -> Gradient.Stop in
        let r = abs(p.rate)
        let colour = r < tideMovementRampAnchorsMHr[0]
            ? SN.graphLine
            : SN.speedColour(Timeline.rampT(forTideRateMHr: r))
        return Gradient.Stop(color: colour, location: min(max(x(p.time) / width, 0), 1))
    }
    return stops.count == 1 ? [stops[0], Gradient.Stop(color: stops[0].color, location: 1)] : stops
}
```

- [ ] **Step 4: Add the shared drawing helpers to `TimelineCanvas`**

Inside `struct TimelineCanvas`, after `private func draw(_ ctx: GraphicsContext)`, add:

```swift
    // MARK: Card-look primitives, shared by both tracks

    /// Where `now` falls on the strip: 0 when it is before the window (an
    /// anchored month out — everything is forecast), the full width when it
    /// is after it (everything is past).
    private var nowX: CGFloat {
        now <= data.start ? 0 : now >= data.end ? data.totalWidth : data.x(now)
    }

    /// A label or dot for a moment already passed fades like the past line.
    private func fade(_ t: Date) -> Double { t < now ? CurveStyle.pastLabelFade : 1 }

    /// The past is context, the future is the forecast: the same path drawn
    /// muted left of now and at full strength right of it, split by clip.
    private func strokeSplitAtNow(_ ctx: GraphicsContext, _ path: Path,
                                  with shading: GraphicsContext.Shading,
                                  lineWidth: CGFloat = CurveStyle.lineWidth) {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        var past = ctx
        past.opacity = CurveStyle.pastLineOpacity
        past.clip(to: Path(CGRect(x: 0, y: 0, width: nowX, height: geo.height)))
        past.stroke(path, with: shading, style: style)
        var future = ctx
        future.clip(to: Path(CGRect(x: nowX, y: 0, width: data.totalWidth - nowX, height: geo.height)))
        future.stroke(path, with: shading, style: style)
    }

    /// A halo that truly matches whatever is behind the canvas: erase a ring
    /// around the dot (destinationOut punches through the fill and the night
    /// bands alike) rather than paint a guess at the ground colour.
    private func punchHalo(_ ctx: GraphicsContext, at p: CGPoint, dotRadius: CGFloat) {
        let radius = dotRadius + CurveStyle.haloGap
        var eraser = ctx
        eraser.blendMode = .destinationOut
        eraser.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(.black))
    }

    private func dot(_ ctx: GraphicsContext, at p: CGPoint, color: Color) {
        punchHalo(ctx, at: p, dotRadius: CurveStyle.dotRadius)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - CurveStyle.dotRadius, y: p.y - CurveStyle.dotRadius,
                                        width: CurveStyle.dotRadius * 2, height: CurveStyle.dotRadius * 2)),
                 with: .color(color))
    }

    /// The card's white now dot, riding the curve. Only when now is on the strip.
    private func drawNowDot(_ ctx: GraphicsContext, at p: CGPoint) {
        guard data.contains(now) else { return }
        let r = CurveStyle.nowDotDiameter / 2
        punchHalo(ctx, at: p, dotRadius: r)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .color(SN.paper))
    }

    /// The dotted datum/zero reference line, full strip width.
    private func referenceLine(_ ctx: GraphicsContext, at lineY: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: lineY))
        path.addLine(to: CGPoint(x: data.totalWidth, y: lineY))
        ctx.stroke(path, with: .color(SN.foam.opacity(CurveStyle.referenceLineOpacity)),
                   style: StrokeStyle(lineWidth: 1, dash: CurveStyle.referenceLineDash))
    }

    /// One axis time on the bottom row, faded when passed.
    private func axisTime(_ ctx: GraphicsContext, _ t: Date) {
        ctx.draw(Text(chartTime(t, data.tz))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.7 * fade(t))),
                 at: CGPoint(x: data.x(t), y: geo.timeY), anchor: .center)
    }
```

- [ ] **Step 5: Remove the dashed now line from `draw(_:)`**

In `private func draw(_ ctx: GraphicsContext)`, delete everything from `// Real-now faint marker rides the timeline` to the end of the function body, leaving:

```swift
    private func draw(_ ctx: GraphicsContext) {
        drawDayChrome(ctx)
        if geo.hasTide { drawTide(ctx) }
        if geo.hasCurrent { drawCurrent(ctx) }
    }
```

- [ ] **Step 6: Rewrite `drawTide`**

Replace the entire `private func drawTide(_ ctx: GraphicsContext) { … }` with:

```swift
    private func drawTide(_ ctx: GraphicsContext) {
        var line = Path()
        for (i, p) in data.tidePoints.enumerated() {
            let pt = CGPoint(x: data.x(p.time), y: geo.tideY(p.height))
            i == 0 ? line.move(to: pt) : line.addLine(to: pt)
        }
        var area = line
        area.addLine(to: CGPoint(x: data.totalWidth, y: geo.tideBottom))
        area.addLine(to: CGPoint(x: 0, y: geo.tideBottom))
        area.closeSubpath()
        // A tide's intensity is the water level itself, so the fade is
        // vertical (the card, via Neaps): strongest at the surface, easing
        // toward the bottom of the box.
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [SN.graphLine.opacity(CurveStyle.fillOpacity),
                              SN.graphLine.opacity(CurveStyle.tideFillFloor)]),
            startPoint: CGPoint(x: 0, y: geo.tideTop),
            endPoint: CGPoint(x: 0, y: geo.tideBottom)))

        // Chart datum, the reference every printed height is quoted against.
        // Drawn only when datum is inside the plotted span; a week where the
        // tide never drops near it would otherwise get a rule pinned to an
        // edge it isn't at.
        if 0 > geo.tideMid - geo.tideSpan && 0 < geo.tideMid + geo.tideSpan {
            referenceLine(ctx, at: geo.tideY(0))
        }

        // Rate of rise as line colour (#95, card-look spec §4): base blue
        // under the ramp floor, the absolute tide-rate ramp above it. The
        // past fade applies on top.
        // ponytail: one stop per sample (~1,400 across the strip). Thin to
        // every Nth sample if the canvas ever stalls on an iPad.
        let stops = tideRateStops(data.tideRates.map { (time: $0.time, rate: $0.rate) },
                                  x: data.x, width: data.totalWidth)
        let shading: GraphicsContext.Shading = stops.isEmpty
            ? .color(SN.graphLine)
            : .linearGradient(Gradient(stops: stops),
                              startPoint: .zero, endPoint: CGPoint(x: data.totalWidth, y: 0))
        strokeSplitAtNow(ctx, line, with: shading)

        // Turns: a dot on the curve, the reading on a band across the middle
        // of the box with its pointer on the dot's side, the time on the
        // bottom row. Teal for a high and amber for a low, as on the card.
        let margin = 0.3 * 3600
        let bandY = (geo.tideTop + geo.tideBottom) / 2
        for e in data.tideExtremes where e.time >= data.start.addingTimeInterval(margin)
                                      && e.time <= data.end.addingTimeInterval(-margin) {
            let x = data.x(e.time), y = geo.tideY(e.height)
            let high = e.kind == .high
            let f = fade(e.time)
            let tint = (high ? SN.graphHigh : SN.graphLow).opacity(f)
            dot(ctx, at: CGPoint(x: x, y: y), color: tint)
            // ⤒ / ⤓ — arrow TO BAR: a plain ↑ says "rising", the one thing no
            // longer true at a high.
            ctx.draw(Text(high ? "⤒" : "⤓")
                        .font(.system(size: CurveStyle.pointerFontSize, weight: .bold))
                        .foregroundStyle(tint),
                     at: CGPoint(x: x, y: bandY + (high ? -CurveStyle.pointerOffset : CurveStyle.pointerOffset)),
                     anchor: .center)
            ctx.draw(Text("\(formatHeight(e.height, imperial: imperial)) \(heightUnit(imperial: imperial))")
                        .font(.system(size: CurveStyle.valueFontSize, weight: .bold).monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(f)),
                     at: CGPoint(x: x, y: bandY), anchor: .center)
            axisTime(ctx, e.time)
        }

        drawNowDot(ctx, at: CGPoint(x: data.x(now), y: geo.tideY(data.heightAt(now))))
    }
```

Keep `private func deg(_ flood: Bool)` immediately after `drawTide`; the source test uses it as the body's end marker.

- [ ] **Step 7: Compile, test, look**

Run the compile check. Expected `** BUILD SUCCEEDED **`. Warnings about `tideFlowArrows` being unused inside the canvas are fine; `tideFlowArrows` is still called by `TimelineData.build` and `TideDetailView`.

Run `-only-testing:SlackwaterTests/TimelineTests`, `-only-testing:SlackwaterTests/RenderedStripTests`, `-only-testing:SlackwaterTests/TypeScaleTests`. Expected: all `passed`. If a `RenderedStripTests` tide case drops under `drawnStripInk` (0.12), report the measured number; do not lower the threshold without saying so in the commit.

Launch the app (Task 3 Step 3 commands), open a tide station (Narvaez Bay under Near Me), screenshot, open the image. Check: past half of the curve faded, a white dot at now, teal/amber dots at turns with the value on the middle band, times only on the bottom row, no chevrons, no dashed now line, the axis column still on the left.

- [ ] **Step 8: Commit**

```sh
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift
git commit -m "feat: tide detail strip takes the card look, rate as line colour

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Current track takes the card look

**Files:**
- Modify: `Slackwater/TimelineStrip.swift` — rewrite `drawCurrent`; delete `slackFillSegments` and `suppressesSlackLabel`
- Test: `SlackwaterTests/TimelineTests.swift` — delete `testTouchingSlackWindowsLabelOnlyTheFirst` and `testSlackFillSegmentsClipToInterpolatedThresholdCrossings`

**Interfaces:**
- Consumes: Task 6's helpers, `mergeWindows`, `currentAxisMoments`, `currentExcessSegments` (unchanged).

- [ ] **Step 1: Delete the two dead tests**

In `SlackwaterTests/TimelineTests.swift`, delete `testTouchingSlackWindowsLabelOnlyTheFirst` (and its doc comment) and `testSlackFillSegmentsClipToInterpolatedThresholdCrossings` (and its doc comment). Leave `testCurrentExcessSegmentsStartAtTheSlackThreshold`.

- [ ] **Step 2: Delete the two dead functions**

In `TimelineStrip.swift`, delete `func suppressesSlackLabel(...)` with its doc comment, and `func slackFillSegments(...)` with its doc comment.

- [ ] **Step 3: Rewrite `drawCurrent`**

Replace the entire `private func drawCurrent(_ ctx: GraphicsContext) { … }` with:

```swift
    private func drawCurrent(_ ctx: GraphicsContext) {
        var line = Path()
        for (i, p) in data.currentPoints.enumerated() {
            let pt = CGPoint(x: data.x(p.time), y: geo.curY(p.speed))
            i == 0 ? line.move(to: pt) : line.addLine(to: pt)
        }
        let runs = mergeWindows(data.slackWindows.map { (start: $0.start, end: $0.end) })

        if !data.speedsAreSchematic {
            // Hot water starts at the comfort limit, never at zero: only the
            // excess above the threshold is inked, on the absolute ramp (#97).
            for segment in currentExcessSegments(data.currentPoints, threshold: data.slackThreshold) {
                let positive = segment[0].speed > 0
                let thresholdY = geo.curY(positive ? data.slackThreshold : -data.slackThreshold)
                var excess = Path()
                for (i, point) in segment.enumerated() {
                    let p = CGPoint(x: data.x(point.time), y: geo.curY(point.speed))
                    i == 0 ? excess.move(to: p) : excess.addLine(to: p)
                }
                excess.addLine(to: CGPoint(x: data.x(segment.last!.time), y: thresholdY))
                excess.addLine(to: CGPoint(x: data.x(segment[0].time), y: thresholdY))
                excess.closeSubpath()
                ctx.fill(excess, with: .linearGradient(
                    Gradient(colors: [SN.speedColour(0), SN.speedColour(0.5), SN.speedColour(1)]),
                    startPoint: CGPoint(x: 0, y: thresholdY),
                    endPoint: CGPoint(x: 0, y: positive ? geo.curTop : geo.curBottom)))
            }
            // The limit made visible everywhere at once (spec §5.2), quiet:
            // two hairlines, and no zero stroke while they are drawn (§7.4).
            for speed in [-data.slackThreshold, data.slackThreshold] {
                var threshold = Path()
                threshold.move(to: CGPoint(x: 0, y: geo.curY(speed)))
                threshold.addLine(to: CGPoint(x: data.totalWidth, y: geo.curY(speed)))
                ctx.stroke(threshold, with: .color(SN.go.opacity(0.35)), lineWidth: 1)
            }
        } else {
            var area = line
            area.addLine(to: CGPoint(x: data.totalWidth, y: geo.zeroY))
            area.addLine(to: CGPoint(x: 0, y: geo.zeroY))
            area.closeSubpath()
            let fillStops = currentFillStops(data.currentPoints, x: data.x,
                                             width: data.totalWidth, schematic: true)
            if !fillStops.isEmpty {
                ctx.fill(area, with: .linearGradient(
                    Gradient(stops: fillStops),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: data.totalWidth, y: 0)))
            }
            referenceLine(ctx, at: geo.zeroY)
        }

        strokeSplitAtNow(ctx, line, with: .color(SN.graphLine))

        // The run is the mark (spec §5.2): the line itself turns the go
        // colour between each run's interpolated edges, over a wider
        // round-capped eraser so the seam at both ends is a clear ring, not
        // a slanted cut. The run's opening gets the track's only dot; its
        // time goes on the bottom row.
        for run in runs {
            var seg = Path()
            seg.move(to: CGPoint(x: data.x(run.start), y: geo.curY(data.velocityAt(run.start))))
            for p in data.currentPoints where p.time > run.start && p.time < run.end {
                seg.addLine(to: CGPoint(x: data.x(p.time), y: geo.curY(p.speed)))
            }
            seg.addLine(to: CGPoint(x: data.x(run.end), y: geo.curY(data.velocityAt(run.end))))
            var eraser = ctx
            eraser.blendMode = .destinationOut
            eraser.stroke(seg, with: .color(.black),
                          style: StrokeStyle(lineWidth: CurveStyle.lineWidth + CurveStyle.haloGap * 2,
                                             lineCap: .round))
            strokeSplitAtNow(ctx, seg, with: .color(SN.go))
            dot(ctx, at: CGPoint(x: data.x(run.start), y: geo.curY(data.velocityAt(run.start))),
                color: SN.go.opacity(fade(run.start)))
        }

        let margin = 0.3 * 3600
        let onStrip = { (t: Date) in
            t >= data.start.addingTimeInterval(margin) && t <= data.end.addingTimeInterval(-margin)
        }
        let slacks = data.currentEvents.filter { $0.kind == .slack }.map(\.time)
        for t in currentAxisMoments(runs: runs, slacks: slacks) where onStrip(t) {
            axisTime(ctx, t)
        }

        for e in data.currentEvents where onStrip(e.time) {
            let x = data.x(e.time)
            switch e.kind {
            case .slack:
                // No window (a violent gate the sampling steps over, every
                // derived gate): a hairline rather than a run — a zero-width
                // window must not look like a window (§5.3). Where a run
                // exists, the run is the mark.
                if !runs.contains(where: { $0.contains(e.time) }) {
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: geo.curTop))
                    tick.addLine(to: CGPoint(x: x, y: geo.curBottom))
                    ctx.stroke(tick, with: .color(SN.go.opacity(0.35 * fade(e.time))), lineWidth: 1)
                }
            case .maxFlood, .maxEbb:
                // Context, not the event (§5.1): no dot. The speed on the
                // band at the zero line, the set arrow on the peak's side —
                // above for flood, below for ebb. Foam ink: the warm fill is
                // a magnitude cue, not a second text-colour system.
                let flood = e.kind == .maxFlood
                let f = fade(e.time)
                let ink = SN.foam.opacity(f)
                let pointerAt = CGPoint(x: x, y: geo.zeroY + (flood ? -CurveStyle.pointerOffset : CurveStyle.pointerOffset))
                if let d = deg(flood) {
                    ctx.drawLayer { l in
                        l.translateBy(x: pointerAt.x, y: pointerAt.y)
                        l.rotate(by: .degrees(d))
                        l.draw(Text(Image(systemName: "arrow.up"))
                                .font(.system(size: CurveStyle.pointerFontSize, weight: .bold))
                                .foregroundStyle(ink),
                               at: .zero, anchor: .center)
                    }
                }
                if !data.speedsAreSchematic {
                    ctx.draw(Text("\(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                                .font(.system(size: CurveStyle.valueFontSize, weight: .bold).monospacedDigit())
                                .foregroundStyle(ink),
                             at: CGPoint(x: x, y: geo.zeroY), anchor: .center)
                }
            }
        }

        drawNowDot(ctx, at: CGPoint(x: data.x(now), y: geo.curY(data.velocityAt(now))))
    }
```

Note for the derived-gate case: `deg(flood)` is nil there, so no arrow; `speedsAreSchematic` is true, so no speed. The gate draws its schematic curve, hairlines, and the past fade only, as the spec's §1 requires.

- [ ] **Step 4: Compile and run the guard tests**

Run the compile check. Expected `** BUILD SUCCEEDED **` with no warning about `slackFillSegments`.

Run these classes: `TimelineTests`, `ColourAndFormTests`, `RenderedStripTests`, `TypeScaleTests`, `PhaseGlossTests`, `SlackWindowTests`. Expected: all `passed`. In particular:
- `ColourAndFormTests.testCurrentTrackDoesNotSpeakDirectionInColour` finds `drawCurrent`'s body (the first line equal to four spaces and `}` after the signature) and finds no banned token.
- `RenderedStripTests` online-gate and derived-gate ink stays above `drawnStripInk`. If it does not, report the measured fraction in the commit and stop; do not lower the threshold.

- [ ] **Step 5: Look at all four detail kinds**

Launch the app (Task 3 Step 3 commands). Open, screenshot, and open the image for:
1. Patos Island Light (harmonic current): green runs with a green dot at each opening, one time under each dot, no dot at peaks, speed + rotated set arrow on the zero band, threshold hairlines, ramp fill above them, past half faded, white now dot, no dashed now line.
2. A derived gate (a CHS gate in the list; `DerivedGateDetailView`): neutral schematic curve, dotted zero line, hairlines at slack with their times on the bottom row, no speeds, no arrows.
3. An online gate if one is cached (`OnlineGateDetailView`): same as 1.
4. Scrub Patos a day forward and back: the readout pill over the band value. If the pill hides a peak value at rest, note it in the final report; do not redesign here.

- [ ] **Step 6: Commit**

```sh
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift
git commit -m "feat: current detail strip takes the card look, run and opening dot

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Full suite and screenshots

**Files:**
- None new. Screenshots land in the directory you pass.

- [ ] **Step 1: Run the fast suite with screenshots**

```sh
cd /Users/clarkbw/src/openwaters/slackwater-ios-wt-station-card-graphs
SHOT_DIR=/tmp/slackwater-shots \
  ./scripts/test.sh 2>&1 | tail -40
```

Expected: `** TEST SUCCEEDED **`. About fifteen minutes. Read the result bundle if anything reports "Test crashed with signal kill" with zero assertion failures: that is contention, not a regression. Re-run.

- [ ] **Step 2: Open the screenshots**

Open each of these from the shot directory and check against the spec:
- `m2-current-scrubbed.png` — current track, scrubbed: past fade, run + opening dot, times only at openings, pill not hiding a band value.
- `m4-gate-detail.png`, `m46-derived-gate-seeded.png` — derived gate: schematic, hairlines, no speeds.
- `online-gate-seeded.png`, `online-gate-far-block.png` — online gate.
- The tide walkthrough shot from `testM1Walkthrough` — tide track: gradient fill, turn dots, band values, bottom times, rate-coloured line on a fast station if one appears.
- Any night in view: the band reaches the strip top; the `Sep N` sub-label is readable on it.

- [ ] **Step 3: Fix what the screenshots show, if anything**

Each visual fix is its own small commit on this branch, with the screenshot named in the message. Re-run only the affected test class, then the full suite once more if any canvas code changed.

- [ ] **Step 4: Shut down the simulator and report**

```sh
xcrun simctl shutdown "$UDID"
git log --oneline feat/station-card-graphs..HEAD
```

Report: the commit list, the test result line, the measured ink fractions if any moved, and what each screenshot showed. Do not push or open a PR; the user merges from mobile and will ask.
