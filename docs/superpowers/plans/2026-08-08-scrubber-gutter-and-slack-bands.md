# Scrubber Gutter and Slack Bands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every exact event time out of the scrubber's track into a label gutter beneath it, draw each slack's sub-0.5 kn window as a green band reaching that gutter, and make all three detail readouts relative-only and positioned above the strip.

**Architecture:** `TimelineGeo` grows a `gutterY` slot below the existing track. `TimelineCanvas` gains one dropline+time helper used by both track drawings, replacing the tide-only inline time labels. The slack window computation moves from a per-view recompute into build-time data on `TimelineData`, so the band drawn on the strip and the duration printed in the readout are the same numbers. The three detail views converge on one readout order. No new files; net deletion in the views.

**Tech Stack:** Swift 6 / SwiftUI, `Canvas`/`GraphicsContext` for the strip, `UIScrollView` via `UIViewRepresentable` for the pan host, XCTest.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-08-scrubber-gutter-and-slack-bands-design.md`. Section references below (§1–§7) are to that file.
- Branch is `detail/scrubber-gutter`, already created and pushed. **Never commit to `main` in this repo, and never merge your own PR** (`CONTRIBUTING.md`).
- Chart labels stay fixed-size `.system(size:)`, never Dynamic Type — see the `TimelineGeo` doc comment at `Slackwater/TimelineStrip.swift:200-221`. Do not "finish the job" on Dynamic Type here.
- Gutter time type is `.system(size: 10)` monospaced, `.white.opacity(0.65)`.
- Dropline is `.white.opacity(0.35)`, `StrokeStyle(lineWidth: 1, dash: [2, 3])`. It must NOT be `SN.leaf` — the leaf dash means *now*, and only *now*.
- Band fill is `SN.go.opacity(0.12)`.
- The slack threshold is always `Timeline.slackThresholdKn`, never a `0.5` literal.
- Times are rendered with `cardTime(_:_:)` and spaces stripped (`8:15PM`), matching the existing sun-time and extreme-time style.
- Run tests with `./scripts/test.sh` (fast plan, both simulators). To iterate one test:
  ```bash
  xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
    -only-testing:SlackwaterTests/TimelineTests/TESTNAME \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
  ```
  No files are created by this plan, so `xcodegen generate` is not needed.

## File Structure

| File | Responsibility | Tasks |
|---|---|---|
| `Slackwater/TimelineStrip.swift` | `TimelineGeo` gutter slot; `TimelineCanvas` droplines, gutter times, slack bands; `TimelineData.slackWindows`; `gutterLabels` | 1, 2, 3, 4 |
| `Slackwater/CurrentDetailView.swift` | Readout above the strip, relative-only, window lookup | 5 |
| `Slackwater/DerivedGateDetailView.swift` | Readout above the strip, relative-only | 5 |
| `SlackwaterTests/TimelineTests.swift` | Geometry invariants, `slackWindows`, `gutterLabels` | 1, 3, 4 |

Task order matters: 1 (geometry) → 2 (droplines) → 3 (window data) → 4 (bands, needs 3) → 5 (readouts, needs 3).

---

## Amendment A — the gutter staggers onto two rows

**2026-08-08, after Task 2 shipped.** The screenshots exposed a case neither
the spec nor this plan anticipated: **adjacent gutter labels overprint**. On
Friday Harbor the 17:02 high and 19:10 low are 2h08m apart — 25pt at 12pt/hour
— against ~46pt labels, and they render as `5:027M10PM`. Unreadable, and not
even legible as two labels.

§4's `pair`/`merged` rule covers only a slack window's own two edges. Merging
is wrong here: two unrelated extremes are not a range.

**Decision (Bryan, 2026-08-08): stagger onto two rows.** A label that would
overprint its neighbour drops to a second gutter row 12pt lower, and its
dropline extends to meet it. Every time stays visible — the alternative
considered and rejected was silently dropping the crowded label.

This supersedes the single-row geometry in Task 1 and the single-row draw in
Task 2, and Task 4's band labels must participate in the same row assignment.
Concretely:

- `TimelineGeo` gains `gutterRowStep: CGFloat = 12` and
  `func gutterY(row: Int) -> CGFloat { gutterY + CGFloat(row) * gutterRowStep }`.
  The existing `gutterY` property stays as row 0's baseline.
- `height` becomes `bodyBottom + 48`: **274** tide-only (226 + 48), **368**
  current-only (320 + 48). Task 1's assertions move with it.
- Row assignment is a pure function, which finally gives Task 2 the unit test
  it could not otherwise have:

  ```swift
  /// Greedy row assignment for gutter labels, left to right: the lowest row
  /// whose last label has cleared. When no row has cleared, the row whose last
  /// label ends earliest — overlap becomes unavoidable, so minimise it rather
  /// than pretend it cannot happen.
  func gutterRows(centers: [CGFloat], widths: [CGFloat], rows: Int = 2) -> [Int]
  ```

  Callers pass labels already sorted by time (both event loops already are).
- `drawDrop` takes a `row: Int` and draws to `geo.gutterY(row: row) - 8`.

Everything else in Tasks 1–5 stands.

---

## Amendment C — the gutter gets a third row

**2026-08-09.** Amendment B left one residual: at dense stations two merged band
labels could still land on the same row and overprint (observed on
`m2-current-scrubbed.png`: `6:57AM–7:17AM` and `1:49PM–2:07PM` running
together). It was parked as a product decision — a third row or a shorter label
format.

**Decision (Bryan, 2026-08-09): a third row.** The label format stays; the
gutter grows.

- `gutterRows`' default becomes `rows: Int = 3`.
- `TimelineGeo.height` becomes `bodyBottom + 60`: **286** tide-only (226 + 60),
  **380** current-only (320 + 60). Row baselines are `gutterY`, `gutterY + 12`,
  `gutterY + 24`.
- The band rect ends at `gutterY(row: 2) - 8` so the fill still reaches a label
  that staggered to the last row.
- `TimelineTests` height assertions move to 286 / 380, and the `gutterY(row:)`
  in-bounds assertions must cover row 2.
- `gutterRows`' doc comment says overlap becomes unavoidable "with a bounded
  number of rows" — still true, just a larger bound. Its existing tests pass
  `rows` explicitly where they mean 2; check none of them silently depend on
  the default being 2, and add a case exercising three rows.

The strip is now 28pt taller than it was before this branch on the tide side
(258 → 286) and 40pt on the current side (340 → 380). That is the cost of
every event time being legible.

## Amendment B — the gutter carries slack windows only

**2026-08-08, after Task 4 shipped.** Task 4's bands rendered correctly and its
review was clean, but the screenshots showed the gutter is oversubscribed at
frequent-slack stations. Deception Pass (Narrows) has slacks roughly every 3h —
36pt at 12pt/hour — and each band contributes a *merged* range label
(`1:49PM–2:07PM`, ~90pt), interleaved with max-flood/max-ebb times (~46pt).
Four labels needing ~270pt inside 72pt. Two rows cannot absorb it; the gutter
rendered as an unreadable ribbon.

Nothing in the test suite can see this — the tests cover the row-assignment
rule, not whether the result is legible — and the task review was clean. It was
caught by reading the screenshot.

**Decision (Bryan, 2026-08-08): drop the max-flood/max-ebb times from the
gutter.** Peaks keep their speed value on the dot, and their exact time stays in
the schedule table below the strip. The gutter belongs to the slack windows —
the question the app is named for.

- `drawCurrent` no longer calls `drawDrop` for `.maxFlood` / `.maxEbb`. The
  peak's speed label on the dot is unchanged.
- Max events no longer enter the `gutterRows` candidate set, so the row
  assignment runs over band labels (and windowless-slack droplines) only.
- **Tide is untouched.** Its extremes stay in the gutter — they are ~6h apart
  with single labels, and the tide strip has never been crowded.

**Known residual, accepted going in.** This halves the label count but does not
fully solve the geometry: ~90pt merged labels at ~36pt slack spacing still
collide on the third label of a run, by roughly 18pt on a hand-trace. Bryan
chose this option with that caveat stated. Measure the real result on a
Deception Pass screenshot after implementing and report what it actually looks
like — do not assume the arithmetic.

---

### Task 1: The gutter slot in `TimelineGeo`

Adds the vertical space every later task draws into. Nothing renders differently yet — the strip just gets taller.

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:238-266` (`TimelineGeo.init` and computed vars)
- Test: `SlackwaterTests/TimelineTests.swift:64-96` (`testSingleTrackGeometries`)

**Interfaces:**
- Consumes: nothing.
- Produces: `TimelineGeo.gutterY: CGFloat` — the baseline y at which gutter text is centred. `height` becomes 262 (tide-only) and 356 (current-only).

- [ ] **Step 1: Write the failing test**

In `SlackwaterTests/TimelineTests.swift`, replace the three `XCTAssertEqual(…height…)` lines inside `testSingleTrackGeometries` and add gutter assertions. The full edited test body assertions:

```swift
        XCTAssert(tide.hasTide && !tide.hasCurrent)
        XCTAssertEqual(tide.height, 262, "the event-time gutter adds 24+12 below the track (gutter spec §1)")
        XCTAssertEqual(tide.gutterY, 250)
        XCTAssert(tide.gutterY > tide.bodyBottom && tide.gutterY < tide.height,
                  "gutter text sits below the track and inside the canvas")
```

```swift
        XCTAssert(!cur.hasTide && cur.hasCurrent)
        XCTAssertEqual(cur.height, 356, "the event-time gutter adds 24+12 below the track (gutter spec §1)")
        XCTAssertEqual(cur.gutterY, 344)
        XCTAssertEqual(cur.curBottom, 320)
        XCTAssertEqual(cur.bodyBottom, 320)
        XCTAssert(cur.gutterY > cur.bodyBottom && cur.gutterY < cur.height,
                  "gutter text sits below the track and inside the canvas")
        // The 24pt clearance is set by the max-ebb speed label, not by the
        // gutter text: that label draws at `curY + 14` and curY clamps to
        // `zeroY + curHalf`, so it reaches ~331 (gutter spec §1).
        XCTAssertGreaterThan(cur.gutterY, cur.curY(-999) + 14,
                             "the gutter must clear a clamped max-ebb speed label")
```

```swift
        XCTAssert(both.hasTide && both.hasCurrent)
        XCTAssertEqual(both.height, 262, "combined input resolves tide-first — no combined case exists (spec §1/§2)")
        XCTAssertEqual(both.curTop, 0)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
  -only-testing:SlackwaterTests/TimelineTests/testSingleTrackGeometries \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```

Expected: compile error — `value of type 'TimelineGeo' has no member 'gutterY'`.

- [ ] **Step 3: Add the gutter to `TimelineGeo`**

In `Slackwater/TimelineStrip.swift`, change the two `height` literals in `init`:

```swift
        switch (hasTide, hasCurrent) {
        case (true, _):
            height = 262; tideBottom = 226; curTop = 0; curBottom = 0
        default:
            // Taller than the old 286: the combined strip's reclaimed space goes to
            // the curve — speed labels and the FLOOD/EBB lines breathe (spec §2).
            height = 356; tideBottom = 0; curTop = 68; curBottom = 320
        }
```

Then add `gutterY` beside the existing computed vars (after `var curHalf`):

```swift
    /// The event-time gutter (gutter spec §1): dotted droplines land here and
    /// the exact times print, so the track itself carries only values and the
    /// readouts above it can stay relative.
    ///
    /// 24pt of clearance, and the number is set by the max-EBB speed label, not
    /// by the gutter text: that label draws at `curY(e.speed) + 14`, and `curY`
    /// clamps to `zeroY + curHalf` = 317, so it can reach ~331. Shrink this and
    /// the strongest ebb of the week prints on top of its own time.
    var gutterY: CGFloat { bodyBottom + 24 }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
  -only-testing:SlackwaterTests/TimelineTests/testSingleTrackGeometries \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift
git commit -m "gutter: TimelineGeo gains a label slot below the track

24pt of clearance below bodyBottom, set by the max-ebb speed label rather
than the gutter text — curY clamps at 317 and that label draws at +14.

Gutter spec §1."
```

---

### Task 2: Droplines and gutter times

Replaces the tide's inline `y ± 26` time with a dotted line down to the gutter, and gives current maxima the same treatment (they have no time label today at all).

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:366-462` (`drawTide`, `drawCurrent`, new private helpers on `TimelineCanvas`)

**Interfaces:**
- Consumes: `TimelineGeo.gutterY` (Task 1).
- Produces, all `private` on `TimelineCanvas`:
  - `func compactTime(_ t: Date) -> String`
  - `func gutterText(_ time: Date) -> Text`
  - `func drawDrop(_ ctx: GraphicsContext, x: CGFloat, from y: CGFloat, time: Date)`

Task 4 reuses `compactTime` and `gutterText`.

- [ ] **Step 1: Add the helpers to `TimelineCanvas`**

There is no unit test for this task — `Canvas` drawing is not queryable from XCTest, and the pure part of the rule (label collision) arrives in Task 4 with its own test. Verification here is the simulator screenshot in Step 4.

Add these three private methods to `TimelineCanvas`, immediately after the `body` property and before `drawDayChrome`:

```swift
    /// "8:15PM" — the chart's compact clock, spaces stripped. Same style the
    /// day header's sun labels use, so the gutter reads as one family with them.
    private func compactTime(_ t: Date) -> String {
        cardTime(t, data.tz).replacingOccurrences(of: " ", with: "")
    }

    private func gutterText(_ time: Date) -> Text {
        Text(compactTime(time))
            .font(.system(size: 10).monospaced())
            .foregroundStyle(.white.opacity(0.65))
    }

    /// The dotted dropline and its gutter time (gutter spec §2). An event's
    /// exact time lives BELOW the track, reached by a line from the event's own
    /// dot — that is what lets every readout above the strip stay relative.
    ///
    /// White, not `SN.leaf`: the leaf dash on this canvas means *now*, and it
    /// has to keep meaning only that. Same dash pattern, different colour, so
    /// the two read as the same family without competing.
    private func drawDrop(_ ctx: GraphicsContext, x: CGFloat, from y: CGFloat, time: Date) {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x, y: geo.gutterY - 8))
        ctx.stroke(p, with: .color(.white.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        ctx.draw(gutterText(time), at: CGPoint(x: x, y: geo.gutterY), anchor: .center)
    }
```

- [ ] **Step 2: Move the tide's extreme time into the gutter**

In `drawTide`, delete the trailing `ctx.draw(Text(cardTime(...)))` block (currently `TimelineStrip.swift:399-402`) and call the helper instead. The extremes loop body becomes:

```swift
            let x = data.x(e.time), y = geo.tideY(e.height)
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                     with: .color(.white))
            ctx.draw(Text(formatHeight(e.height, imperial: imperial))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white),
                     at: CGPoint(x: x, y: e.kind == .high ? y - 11 : y + 11), anchor: .center)
            drawDrop(ctx, x: x, from: y, time: e.time)
```

Also update the comment above that loop — it currently claims the absolute time lives on the event. Replace it with:

```swift
        // Extreme dots + height labels (prototype fmtH at each turn). The VALUE
        // stays on the dot; the exact TIME drops to the gutter (gutter spec §2),
        // reversing the 2026-08-07 call that kept it stacked on the event.
```

- [ ] **Step 3: Give current maxima a dropline**

In `drawCurrent`'s events loop, the `.maxFlood, .maxEbb` arm becomes:

```swift
            case .maxFlood, .maxEbb:
                let y = geo.curY(e.speed)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                         with: .color(.white))
                ctx.draw(Text(formatSpeed(abs(e.speed), unit: speedUnit))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(e.kind == .maxFlood ? SN.floodLabel : SN.ebbLabel),
                         at: CGPoint(x: x, y: e.kind == .maxFlood ? y - 12 : y + 14),
                         anchor: .center)
                drawDrop(ctx, x: x, from: y, time: e.time)
```

Leave the `.slack` arm alone — its band and its no-window fallback arrive in Task 4.

- [ ] **Step 4: Build, run the suite, and look at it**

```bash
./scripts/test.sh 2>&1 | tail -30
```

Expected: PASS. Then confirm visually — the UI tests write screenshots, so open the tide detail shot and check that every high and low has a dotted line reaching a time under the curve, and that no time is still printed beside a dot:

```bash
ls -t /tmp/slackwater-shots | head
```

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TimelineStrip.swift
git commit -m "gutter: exact event times drop out of the track

One drawDrop helper serves both tracks — a dotted white line from the event
dot to a time in the gutter. Tide loses its inline y±26 label; current maxima
gain a time they never had.

White, not SN.leaf: the leaf dash means now, and only now.

Gutter spec §2."
```

---

### Task 3: `slackWindows` as build-time data

Moves the window computation out of `CurrentDetailView`'s computed property and into `TimelineData`, so Task 4's band and Task 5's readout read the same array.

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:85-96` (`TimelineData` properties), `:137-197` (`build`)
- Modify: `SlackwaterTests/TimelineTests.swift:73-96` (two direct `TimelineData(...)` constructions)
- Test: `SlackwaterTests/TimelineTests.swift` (new tests)

**Interfaces:**
- Consumes: the existing free function `slackWindow(_ points: [CurrentPoint], around: Date, threshold: Double) -> (start: Date, end: Date)?` (`TimelineStrip.swift:48`), unchanged.
- Produces: `TimelineData.slackWindows: [(slack: Date, start: Date, end: Date)]`, one entry per slack that has a window, ordered as `currentEvents` is. Empty for a derived gate.

- [ ] **Step 1: Write the failing tests**

Add to `SlackwaterTests/TimelineTests.swift`, before the closing brace:

```swift
    /// The window computation is build-time data now, not a per-view recompute
    /// (gutter spec §3) — so the band on the strip and the duration in the
    /// readout are the same numbers by construction.
    func testSlackWindowsBracketTheirSlacks() throws {
        let station = try XCTUnwrap(CurrentStationRecord.all.first)
        let d = TimelineData.build(tide: nil, current: station, now: Date())
        let slacks = d.currentEvents.filter { $0.kind == .slack }
        XCTAssertGreaterThan(slacks.count, 10, "a week of slacks must exist to window")
        XCTAssertFalse(d.slackWindows.isEmpty)
        for w in d.slackWindows {
            XCTAssert(w.start <= w.slack && w.slack <= w.end,
                      "a window must bracket its own slack: \(w)")
            XCTAssert(slacks.contains { $0.time == w.slack },
                      "every window belongs to a drawn slack event")
        }
    }

    /// A derived gate's curve is a schematic ±1 SHAPE, not a velocity, so a
    /// 0.5 kn window measured off it would be fiction (gutter spec §3). Its
    /// slacks fall back to a plain dropline instead.
    func testDerivedGateHasNoSlackWindows() throws {
        let port = TideStationRecord(
            id: "chs-point-atkinson", name: "Point Atkinson", region: "West Vancouver",
            aliases: [], latitude: 49.337, longitude: -123.254,
            timezone: "America/Vancouver", chartDatum: "Chart", datumOffset: 3.0,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 0)])
        let gate = DerivedGateRecord(gate: ChsGateInfo.all.first { $0.id == "chs-malibu-rapids" }!,
                                     port: port)
        let d = TimelineData.build(gate: gate, now: Date())
        XCTAssert(d.hasCurrent, "the schematic track exists")
        XCTAssertFalse(d.currentEvents.isEmpty, "the gate has slack events")
        XCTAssert(d.slackWindows.isEmpty, "but no windows — the curve is a shape (gutter spec §3)")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
  -only-testing:SlackwaterTests/TimelineTests/testSlackWindowsBracketTheirSlacks \
  -only-testing:SlackwaterTests/TimelineTests/testDerivedGateHasNoSlackWindows \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```

Expected: compile error — `value of type 'TimelineData' has no member 'slackWindows'`.

- [ ] **Step 3: Add the property and compute it in `build`**

In `TimelineData`, add after `let snapTimes: [Date]`:

```swift
    /// The workable sub-threshold window around each slack, computed ONCE here
    /// off the same `currentPoints` the strip draws (gutter spec §3). The green
    /// band on the strip and the duration in the readout are therefore the same
    /// numbers by construction, not by two call sites agreeing.
    ///
    /// Empty for a derived gate: `build(gate:)` synthesises a schematic ±1
    /// shape, and a 0.5 kn window measured off a shape would be fiction.
    let slackWindows: [(slack: Date, start: Date, end: Date)]
```

In `build`, insert after the `if let gate { … }` block and before the `sunTimes` line:

```swift
        // Only a real current station gets windows — the gate branch above
        // leaves `current` nil, which is exactly the fiction guard.
        var windows: [(slack: Date, start: Date, end: Date)] = []
        if current != nil {
            windows = currentEvents.filter { $0.kind == .slack }.compactMap { e in
                slackWindow(currentPoints, around: e.time,
                            threshold: Timeline.slackThresholdKn)
                    .map { (slack: e.time, start: $0.start, end: $0.end) }
            }
        }
```

And pass it in the return:

```swift
        return TimelineData(tz: tz, today: today, start: start, end: end, days: days,
                            tidePoints: tidePoints, tideExtremes: tideExtremes,
                            currentPoints: currentPoints, currentEvents: currentEvents,
                            snapTimes: snaps, slackWindows: windows)
```

- [ ] **Step 4: Fix the two direct constructions in the tests**

`testSingleTrackGeometries` builds `TimelineData` by memberwise init twice. Add `slackWindows: []` as the last argument to both — the `cur` construction and the `both` construction:

```swift
            currentPoints: [CurrentPoint(time: t0, speed: 1)], currentEvents: [],
            snapTimes: [], slackWindows: []))
```

```swift
            currentPoints: [CurrentPoint(time: tideData.start, speed: 1)], currentEvents: [],
            snapTimes: tideData.snapTimes, slackWindows: []))
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
./scripts/test.sh 2>&1 | tail -30
```

Expected: PASS, including the existing `testSlackWindow*` tests, which are untouched.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift
git commit -m "gutter: slack windows become build-time data

One computation on TimelineData instead of a per-view recompute, so the band
and the readout duration cannot disagree. Empty for a derived gate — its curve
is a shape, and a 0.5 kn window off a shape would be fiction.

Gutter spec §3."
```

---

### Task 4: Slack bands and their edge labels

**Files:**
- Modify: `Slackwater/TimelineStrip.swift` (new free function `gutterLabels`, `drawCurrent` band block and `.slack` arm)
- Test: `SlackwaterTests/TimelineTests.swift` (new test)

**Interfaces:**
- Consumes: `TimelineData.slackWindows` (Task 3), `TimelineCanvas.compactTime` / `gutterText` / `drawDrop` (Task 2), `TimelineGeo.gutterY` (Task 1).
- Produces: `enum GutterLabels { case pair, merged }` and `func gutterLabels(bandWidth: CGFloat, startWidth: CGFloat, endWidth: CGFloat) -> GutterLabels` — both file-scope in `TimelineStrip.swift`, internal (not `private`) so the test can reach them via `@testable import`.

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/TimelineTests.swift`:

```swift
    /// The window's two edge labels grow INWARD from the band and collapse to
    /// one merged range when they'd overlap (gutter spec §4). At 12pt/hour a
    /// typical 1–3h window is 12–36pt wide and a "12:30PM" label is ~46pt, so
    /// `merged` is the COMMON render — `pair` is the weak-station case.
    func testGutterLabelsCollapseWhenTheyWouldOverlap() {
        XCTAssertEqual(gutterLabels(bandWidth: 200, startWidth: 46, endWidth: 46), .pair)
        XCTAssertEqual(gutterLabels(bandWidth: 30, startWidth: 46, endWidth: 46), .merged)
        // Touching labels are unreadable, so equality merges.
        XCTAssertEqual(gutterLabels(bandWidth: 92, startWidth: 46, endWidth: 46), .merged)
        XCTAssertEqual(gutterLabels(bandWidth: 93, startWidth: 46, endWidth: 46), .pair)
        // A zero-width band (a window shorter than a rendering point) merges.
        XCTAssertEqual(gutterLabels(bandWidth: 0, startWidth: 46, endWidth: 46), .merged)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
  -only-testing:SlackwaterTests/TimelineTests/testGutterLabelsCollapseWhenTheyWouldOverlap \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```

Expected: compile error — `cannot find 'gutterLabels' in scope`.

- [ ] **Step 3: Add the pure rule**

In `Slackwater/TimelineStrip.swift`, add at file scope directly below the `slackWindow(_:around:threshold:)` function:

```swift
/// How a slack window's two edge times fit in the gutter (gutter spec §4).
enum GutterLabels { case pair, merged }

/// Two labels growing inward from the band's edges, or one merged range
/// centred on it. Pure so the rule is testable without a `Canvas` — the widths
/// come from `ctx.resolve(_:).measure(in:)` at the call site, never from a
/// hardcoded point estimate, so this survives a font change.
///
/// Equality merges: labels that exactly touch are unreadable.
func gutterLabels(bandWidth: CGFloat, startWidth: CGFloat, endWidth: CGFloat) -> GutterLabels {
    startWidth + endWidth < bandWidth ? .pair : .merged
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
  -only-testing:SlackwaterTests/TimelineTests/testGutterLabelsCollapseWhenTheyWouldOverlap \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```

Expected: PASS.

- [ ] **Step 5: Add the merged-range text helper**

Add to `TimelineCanvas`, right after `gutterText`:

```swift
    private func mergedGutterText(_ a: Date, _ b: Date) -> Text {
        Text("\(compactTime(a))–\(compactTime(b))")
            .font(.system(size: 10).monospaced())
            .foregroundStyle(.white.opacity(0.65))
    }
```

- [ ] **Step 6: Give windowless slacks a dropline**

In `drawCurrent`'s events loop, the `.slack` arm becomes:

```swift
            case .slack:
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2.6, y: geo.zeroY - 2.6,
                                                width: 5.2, height: 5.2)),
                         with: .color(.white.opacity(0.85)))
                // Slack is the app's "go" colour, not a neutral. It is the moment the
                // app is named for, and it must read the same on every surface.
                ctx.draw(Text("slack").font(.system(size: 10).monospaced())
                            .foregroundStyle(SN.go),
                         at: CGPoint(x: x, y: geo.zeroY + 14), anchor: .center)
                // A slack WITH a window is drawn by its band below — the band
                // already reaches the gutter, so a dropline would be a second
                // mark saying the same thing. Without one (a violent gate the
                // 10-min sampling steps over, and every derived gate) the plain
                // dropline is what's left.
                if !data.slackWindows.contains(where: { $0.slack == e.time }) {
                    drawDrop(ctx, x: x, from: geo.zeroY, time: e.time)
                }
```

- [ ] **Step 7: Draw the bands**

Add at the very end of `drawCurrent`, after the events loop closes:

```swift
        // Bands LAST, over the curve: at 0.12 the fill reads as a highlight
        // column tinting the ebb fill under it rather than an opaque patch
        // fighting it, and the 2pt near-white curve still reads through
        // (gutter spec §3). This opacity is the one number here expected to
        // want a tuning pass against a real screenshot.
        for w in data.slackWindows {
            let x0 = data.x(w.start), x1 = data.x(w.end)
            ctx.fill(Path(CGRect(x: x0, y: geo.zeroY, width: x1 - x0,
                                 height: geo.gutterY - 8 - geo.zeroY)),
                     with: .color(SN.go.opacity(0.12)))
            let a = gutterText(w.start), b = gutterText(w.end)
            let box = CGSize(width: 1000, height: 100)
            let aw = ctx.resolve(a).measure(in: box).width
            let bw = ctx.resolve(b).measure(in: box).width
            switch gutterLabels(bandWidth: x1 - x0, startWidth: aw, endWidth: bw) {
            case .pair:
                ctx.draw(a, at: CGPoint(x: x0, y: geo.gutterY), anchor: .leading)
                ctx.draw(b, at: CGPoint(x: x1, y: geo.gutterY), anchor: .trailing)
            case .merged:
                ctx.draw(mergedGutterText(w.start, w.end),
                         at: CGPoint(x: (x0 + x1) / 2, y: geo.gutterY), anchor: .center)
            }
        }
```

- [ ] **Step 8: Run the suite and look at it**

```bash
./scripts/test.sh 2>&1 | tail -30
ls -t /tmp/slackwater-shots | head
```

Expected: PASS. On a current-detail screenshot, confirm: a green column under each slack reaching the gutter, its start and end times under the column's edges (or one merged range when narrow), and no dotted line duplicating a band. On a derived-gate screenshot: no green columns, a dotted line and time under each slack.

- [ ] **Step 9: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift
git commit -m "gutter: the slack window draws as a band down to its own times

A go-coloured column from the zero line to the gutter, edge times growing
inward and collapsing to a merged range when they'd overlap. Widths come from
resolve().measure(), not a point estimate, so the rule survives a font change.

A slack without a window — a violent gate, and every derived gate — falls back
to the plain dropline.

Gutter spec §3, §4."
```

---

### Task 5: Readouts go relative and move above the strip

**Files:**
- Modify: `Slackwater/CurrentDetailView.swift:32-47` (computed properties), `:102-187` (`scrubCard`)
- Modify: `Slackwater/DerivedGateDetailView.swift:73-129` (`scrubCard`)

**Interfaces:**
- Consumes: `TimelineData.slackWindows` (Task 3).
- Produces: no new API. `CurrentDetailView.following` is deleted.

- [ ] **Step 1: Rewire `slackWin` and delete `following`**

In `CurrentDetailView.swift`, delete the `following` computed property entirely (`:37-42`) and replace `slackWin` (`:43-47`) with a lookup:

```swift
    /// The window around the next slack — looked up, not recomputed. The strip
    /// draws these same numbers as a band (gutter spec §3).
    private var slackWin: (start: Date, end: Date)? {
        guard let slack = nextSlack else { return nil }
        return timeline?.slackWindows.first { $0.slack == slack.time }
            .map { (start: $0.start, end: $0.end) }
    }

    /// The fast answer's marking, on every number this page prints: the tilde
    /// appears when the reading IS provisional. Three call sites inlined this
    /// ternary; the next-slack block below reaches it three more times.
    private var tilde: String { provisionalGate == nil ? "" : "~" }
```

- [ ] **Step 2: Move the readout above the strip and make it relative**

In `CurrentDetailView.scrubCard`, the `TimelineScrubStrip` currently comes first and the readout `HStack` second. Swap them: the `HStack` becomes the first child with no top padding, and the strip keeps `.padding(.top, 12)`. The readout's own `.padding(.top, 8)` is deleted.

The left column (the big number, the phase word, the provisional badge) is unchanged. Replace only the right column — the `if let slack = nextSlack { ... }` block — with:

```swift
                if let slack = nextSlack {
                    VStack(alignment: .trailing, spacing: 1) {
                        MonoLabel(text: "Next slack", color: SN.foam.opacity(0.5), tracking: 1.4)
                        if let win = slackWin {
                            // Counts to the window OPENING, not the slack instant:
                            // this readout answers "when can I be there", and the
                            // window is when the pass is transitable. The window
                            // brackets the slack, so it is often already open —
                            // then it says `now` (gutter spec §5).
                            Text(win.start > scrubTime
                                 ? "\(tilde)in \(countdown(from: scrubTime, to: win.start))"
                                 : "\(tilde)now")
                                .font(.caption.monospacedDigit())
                                // SN.go, not SN.leaf: this line says when slack is.
                                // Same value today, but the token has to name the
                                // meaning or retargeting one of them breaks it.
                                .foregroundStyle(provisionalGate == nil ? SN.go : SN.amber)
                            // Time REMAINING, not the window's original length —
                            // an already-open window must not claim its full run.
                            Text("\(tilde)for \(countdown(from: max(scrubTime, win.start), to: win.end)) @ \(formatSpeed(Timeline.slackThresholdKn, unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(provisionalGate == nil ? SN.foam.opacity(0.7) : SN.amber.opacity(0.7))
                                .accessibilityIdentifier("slack-window")
                        } else {
                            Text("\(tilde)in \(countdown(from: scrubTime, to: slack.time))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(provisionalGate == nil ? SN.go : SN.amber)
                        }
                    }
                }
```

Everything the old block printed that is gone: `· \(cardTime(slack.time, tz))`, the `under 0.5 kn · 12:30 PM–10:43 AM · 22h 13m` absolute pair, and the whole `then max flood 0.3 kn` line. Those times now live in the gutter under the band.

- [ ] **Step 3: Do the same to the derived gate**

In `DerivedGateDetailView.scrubCard`, move the readout `HStack` above `TimelineScrubStrip` (deleting its `.padding(.top, 8)`; the strip keeps `.padding(.top, 12)`). Leave the "Shape only —" note, `‹ swipe to scrub ›`, `ScrubWhen` and `TideAtPortLink` below the strip in their current order.

Change one line — drop the absolute time:

```swift
                        Text("in \(countdown(from: scrubTime, to: slack.time))")
                            // SN.go, not SN.leaf: this line says when slack is.
                            .font(.caption.monospacedDigit()).foregroundStyle(SN.go)
```

Keep `at \(slack.highWater ? "high" : "low") water` — that is a derivation fact, not a time.

- [ ] **Step 4: Run the full suite**

```bash
./scripts/test.sh 2>&1 | tail -30
```

Expected: PASS. `ScreenshotTests.swift:369` asserts a `slack-window` element exists under Next slack — it still does, now above the strip rather than below it. If that test fails, the identifier was dropped in Step 2; do not weaken the assertion.

- [ ] **Step 5: Check all three details visually**

```bash
ls -t /tmp/slackwater-shots | head -20
```

Confirm on the screenshots: tide, current and gate all put the readout above the strip; no absolute clock time appears in any readout; the only absolute times on screen are the gutter, the day-header sun labels, the `ScrubWhen` clock, and the schedule table.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/CurrentDetailView.swift Slackwater/DerivedGateDetailView.swift
git commit -m "gutter: readouts go relative, above the strip, on all three details

Current and derived gate join tide's order. The next-slack line counts to the
window OPENING — the question is when you can be there — and says now when the
window is already open; the duration is time remaining, not the window's
original length.

Absolute times, the then-max line and CurrentDetailView.following all go: the
gutter and ScrubWhen carry the clock now.

Gutter spec §5."
```

---

### Task 6: Open the PR

**Files:** none.

- [ ] **Step 1: Confirm the branch is clean and pushed**

```bash
git status --short && git log --oneline main..HEAD
git push
```

- [ ] **Step 2: Draft the PR body and stop**

Outbound text gets Bryan's review before posting. Write the PR title and body into a copy-pasteable block in the session and **do not run `gh pr create`** until he says go. Do not merge it under any circumstance — `CONTRIBUTING.md` forbids merging your own PR in this repo.

---

## Self-Review

**Spec coverage:** §1 → Task 1. §2 → Task 2. §3 → Tasks 3 and 4 (data, then band). §4 → Task 4. §5 → Task 5. §6 (unification) is the sum of Tasks 2–5, not separate work: one time-label implementation (Task 2), one window computation (Task 3), one readout order (Task 5), and four deletions — the inline extreme time (Task 2), `following`, the `then max` line and the per-view `slackWindow` call (Tasks 3 and 5). §7 → the tests in Tasks 1, 3, 4; the "no new UI assertions" note is honoured by Task 5 Step 4, which only verifies the existing ones still pass.

**Type consistency:** `gutterY` (Tasks 1, 2, 4), `slackWindows` with element labels `slack`/`start`/`end` (Tasks 3, 4, 5), `compactTime`/`gutterText`/`drawDrop` (Tasks 2, 4), `gutterLabels`/`GutterLabels` (Task 4) are spelled identically at every use.

**Known gap, deliberate:** Task 2 has no unit test because `Canvas` output is not queryable from XCTest. Its check is the screenshot review in Step 4, plus the geometry invariants from Task 1 and the pure label rule from Task 4 that bound what it can get wrong. Do not invent a snapshot-testing harness to close this — that is a bigger dependency than the thing it would verify.
