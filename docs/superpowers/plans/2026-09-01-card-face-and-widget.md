# Card Face and Medium Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The list card's readings hang off the turn without units, its current header always shows speed and set, the window's closing gets its minor dot on both surfaces, and the medium widget renders the list card itself with an in-window countdown.

**Architecture:** Move the palette and the card face (shell + reading) into files the widget extension compiles, so the widget is `StationCard { ConditionsItem }` with the same `StationCardGraph`. One new pure helper decides the two window-dot opacities for the card and the strip. The medium widget's own sparkline canvas is deleted.

**Tech Stack:** Swift 6, SwiftUI `Canvas`, WidgetKit, XcodeGen (`project.yml` source lists), XCTest.

**Spec:** `docs/superpowers/specs/2026-09-01-card-face-and-widget-design.md`, with `docs/current-charts.md` §5.4, §5.4.1 and §15 as the normative rules.

## Global Constraints

- Branch `feat/detail-strip-card-look`, worktree `/Users/clarkbw/src/openwaters/slackwater-ios-wt-station-card-graphs`. Do not push.
- After any `project.yml` change run `xcodegen generate` before building.
- Every `xcodebuild` needs `-clonedSourcePackagesDirPath build/SourcePackages` and is wrapped `lockf /tmp/slackwater-test.lock xcodebuild …` (waits for the lock). Compile check builds the app AND the embedded `SlackwaterWidgets` target:
  ```sh
  lockf /tmp/slackwater-test.lock xcodebuild build-for-testing \
    -project Slackwater.xcodeproj -scheme Slackwater \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
  ```
- One or more test classes:
  ```sh
  lockf /tmp/slackwater-test.lock xcodebuild test \
    -project Slackwater.xcodeproj -scheme Slackwater \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -only-testing:SlackwaterTests/<Class> … 2>&1 \
    | grep -E "Test Case '.*' (passed|failed)|error:|\*\* TEST"
  ```
- The full suite runs on the clean device: `SLACKWATER_SIMS='SW Clean iPhone 17' SHOT_DIR=<dir> ./scripts/test.sh` (the controller runs it).
- Chart labels keep fixed `.system(size:)` fonts. Green (`SN.go`) means a slack window and nothing else. `.monospacedDigit()` within four lines of every `formatHeight(`/`formatSpeed(` call (TypeScaleTests), or a `knownIndirections` entry.
- Source-text tripwires that name files: `ColourAndFormTests` (hex-literal file allowlist `["Theme.swift", "TimelineStrip.swift"]`; `drawCurrent` direction-token ban), `PhaseGlossTests` (`StationCard.swift` must contain `compass16(` and `struct ConditionsItem`), `ScrubWhenTests` (reads `Theme.swift`), `WidgetSnapshotTests` (reads `MiniScrubberView.swift`). Each task below says which it retargets.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. No `Claude-Session` trailer, no links: the repo is public. Check `git log -1 --format=%B | grep -c claude.ai` prints 0 after each commit.

---

## File map

| File | After this plan |
|---|---|
| `Slackwater/Palette.swift` (new, widget + app) | `extension Color`, `enum SN`, `enum CurveStyle`, `CanvasBackground`, `MonoLabel`, the app clock (`appNow`, `todayLocal`), the formatter cache and `cardTime`/`clockTime`/`chartTime`/`shortWeekday`, `CompassArrow`. |
| `Slackwater/Theme.swift` (app) | Everything else it holds today. |
| `Slackwater/Units.swift` (widget + app) | Gains `formatNm`. |
| `Slackwater/SlackWindow.swift` (widget + app) | Gains `sampleEvents` and `windowDotOpacities`. |
| `Slackwater/CardStatus.swift` (widget + app) | Loses the two helpers that touch `ChsFitService`/`Connectivity`; they move to `StationCard.swift`. |
| `Slackwater/StationCardFace.swift` (new, widget + app) | `StationCard` (with `chrome` and `minHeight`), `ConditionsItem` (with `countdownTo`). |
| `Slackwater/StationCard.swift` (app) | The list-only card views, previews, and the two moved status helpers. |
| `Slackwater/StationCardGraph.swift` (widget + app) | Hang-off labels, no unit, closing dot. |
| `Slackwater/TimelineStrip.swift` (app) | Closing dot in `drawCurrent`. |
| `Slackwater/WidgetStationLoader.swift` (widget + app) | `WidgetRecord` + `loadRecord(id:)`; `load(id:)` maps from it. |
| `Slackwater/MiniScrubberView.swift` (widget + app) | `DayCurveContentView` = the card; the sparkline `MiniScrubberView` deleted; ramp helpers kept. |
| `SlackwaterWidgets/SlackwaterWidgetsBundle.swift`, `HomeWidgets.swift` | Entry carries the card model; medium widget uses `containerBackground(SN.cardFill)`. |
| `project.yml` | Widget sources gain `Palette.swift`, `CardStatus.swift`, `StationCardFace.swift`, `StationCardGraph.swift`. |

---

### Task 1: Palette.swift, the widget-safe half of Theme.swift

**Files:**
- Create: `Slackwater/Palette.swift`
- Modify: `Slackwater/Theme.swift`, `Slackwater/Units.swift`, `Slackwater/LocationService.swift`, `project.yml`
- Test: `SlackwaterTests/ColourAndFormTests.swift` (the file allowlist near line 212)

**Interfaces:**
- Produces: the same symbols, unchanged, in a file the widget target compiles. `formatNm(_:)` in `Units.swift`.

- [ ] **Step 1: Move the blocks**

Cut from `Theme.swift` and paste, in this order, into a new `Slackwater/Palette.swift` that begins with the GPL header line and `import SwiftUI` / `import WidgetKit` (WidgetKit only if a moved symbol needs it; today `Theme.swift` imports it — keep the import in whichever file uses it, drop it from the other):
1. `extension Color { init(hex:opacity:) … static func hex(_:lightenedBy:) }`
2. `enum SN { … }` whole
3. `enum CurveStyle { … }` whole
4. `struct CanvasBackground` and `struct MonoLabel`
5. `// MARK: - App clock` through `func todayLocal(_:)`
6. `// MARK: - Station-local time formatting`: the `formatterCache`, `formatter(_:_:)`, `cardTime`, `clockTime`, `chartTime`, `shortWeekday`
7. `struct CompassArrow`

Leave `countdown`, `slackWindowTiming`, `moonLimbShift`, `MoonGlyph`, `monthDay`, `weekRangeLabel`, `ScrubWhen` and everything after in `Theme.swift`. Move the file's opening doc comment (design tokens) to `Palette.swift` and give `Theme.swift` a one-line header: `// Slackwater — GPL v3. Detail-view chrome and list state; the palette and formatters live in Palette.swift so the widget can share them.`

Move `func formatNm(_:)` from `LocationService.swift` to `Units.swift` unchanged.

- [ ] **Step 2: Widget sources**

In `project.yml`, under `SlackwaterWidgets: sources:`, add `- Slackwater/Palette.swift` directly after `- Slackwater/Units.swift`. Run `xcodegen generate`.

- [ ] **Step 3: Retarget the tripwire**

`SlackwaterTests/ColourAndFormTests.swift`: the line `let allowed: Set<String> = ["Theme.swift", "TimelineStrip.swift"]` becomes `["Palette.swift", "Theme.swift", "TimelineStrip.swift"]`. Read the test's comment above it and the doc at ~186 and ~264; if either names `Theme.swift` as the home of `SN`, reword to `Palette.swift`. `ScrubWhenTests` reads `Theme.swift` for `ScrubWhen`, which stays there: no change.

- [ ] **Step 4: Compile and test**

Compile check: `** TEST BUILD SUCCEEDED **` (this builds the widget target too). Run `ColourAndFormTests`, `ScrubWhenTests`, `TypeScaleTests`. All pass.

- [ ] **Step 5: Commit**

```sh
git add -A Slackwater/Palette.swift Slackwater/Theme.swift Slackwater/Units.swift Slackwater/LocationService.swift project.yml SlackwaterTests/ColourAndFormTests.swift
git commit -m "refactor: Palette.swift, the widget-safe palette and formatters

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: The card face compiles in the widget

**Files:**
- Create: `Slackwater/StationCardFace.swift`
- Modify: `Slackwater/StationCard.swift`, `Slackwater/CardStatus.swift`, `Slackwater/SlackWindow.swift`, `Slackwater/TimelineStrip.swift` (remove `sampleEvents`), `project.yml`
- Test: `SlackwaterTests/PhaseGlossTests.swift`

**Interfaces:**
- Produces: `StationCard(name:region:km:status:opacity:graph:chrome:minHeight:trailing:)` with `var chrome = true` and `var minHeight: CGFloat? = nil` (nil → today's `graph == nil ? 96 : 168`); `ConditionsItem` unchanged in this task; `sampleEvents(_:)` in `SlackWindow.swift`.

- [ ] **Step 1: Move `sampleEvents`**

Cut `func sampleEvents(_ points: [CurrentPoint]) -> [CurrentEvent]` with its doc comment from `TimelineStrip.swift` and append it to `SlackWindow.swift`. `TimelineData.build(onlinePoints:…)` still calls it by name.

- [ ] **Step 2: Move the two app-only status helpers**

In `CardStatus.swift`, the function containing `ChsFitService.shared.isQueued(id)` / `Connectivity.shared.online` (around lines 95-103; read it to get its exact signature) and `func onlineGateStatus(_ window: ChsOnlineWindow?, online: Bool) -> CardStatus` move, unchanged, to the end of `StationCard.swift`. `onlineDownloadValidity(end:now:calendar:)` stays (it needs only `appNow`, now in `Palette.swift`). `CardStatus.swift` must then reference nothing outside SwiftUI, TideEngine, `Palette.swift`, `Units.swift`: check with `grep -n 'ChsFitService\|Connectivity\|RecentsStore\|appNow' Slackwater/CardStatus.swift` → only `appNow` may remain.

- [ ] **Step 3: Extract the face**

Create `Slackwater/StationCardFace.swift` (GPL header, `import SwiftUI`, `import TideEngine`) and move into it, unchanged: `struct StationCard<Trailing: View>` with its doc comment, and `struct ConditionsItem` with its doc comment. Everything else stays in `StationCard.swift`.

In the moved `StationCard`, add two properties after `var graph: StationCardGraph? = nil`:

```swift
    /// The list's rounded clip and shadow. The widget passes false: its own
    /// container clips, and a shadow inside a widget is a smear.
    var chrome = true
    /// The list's card heights by default; the widget lets the card fill
    /// its family instead.
    var minHeight: CGFloat? = nil
```

and change the end of `body`:

```swift
        .frame(maxWidth: .infinity, minHeight: minHeight ?? (graph == nil ? 96 : 168), alignment: .topLeading)
        .background { … unchanged … }
        .clipShape(RoundedRectangle(cornerRadius: chrome ? 24 : 0, style: .continuous))
        .shadow(color: chrome ? SN.shadow.opacity(0.24) : .clear, radius: chrome ? 12 : 0, y: chrome ? 10 : 0)
```

- [ ] **Step 4: Widget sources**

`project.yml`, widget `sources:`, add after `Slackwater/SlackWindow.swift`:
```yaml
      - Slackwater/CardStatus.swift
      - Slackwater/StationCardFace.swift
      - Slackwater/StationCardGraph.swift
```
Run `xcodegen generate`. Compile check. Expect the widget target to fail on any symbol the face still needs that is not in its source list; for each, find the symbol's file (`grep -rn 'func <name>\|struct <name>' Slackwater/`) and either add that file to the widget sources if it is widget-safe (no `ChsFitService`, `Connectivity`, `RecentsStore`, MapLibre, CoreLocation) or move the one function into a widget-safe file. Record every such move in the report. Known already: `DerivedPhase` is a TideEngine type; `compass16`, `currentPhase`, `CardState`, `CurrentCardState`, `DerivedGateCardState`, `formatSpeed`, `formatHeight`, `speedUnitLabel`, `heightUnit` are in files already listed.

- [ ] **Step 5: Retarget the tripwire**

`SlackwaterTests/PhaseGlossTests.swift`, `testGlossAndDirectionReachTheirSurfaces`: the two assertions on `repoSource("Slackwater/StationCard.swift")` (`compass16(` and `struct ConditionsItem`) now read `Slackwater/StationCardFace.swift`. Update the comment above them to say the face moved so the widget can share it.

- [ ] **Step 6: Compile, test, commit**

Compile check passes for both targets. Run `PhaseGlossTests`, `ColourAndFormTests`, `TypeScaleTests`, `TimelineTests`. All pass.

```sh
git add -A Slackwater project.yml SlackwaterTests/PhaseGlossTests.swift
git commit -m "refactor: the card face compiles in the widget extension

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Window-edge dots and hang-off readings on the card and the strip

**Files:**
- Modify: `Slackwater/SlackWindow.swift` (add `windowDotOpacities`), `Slackwater/StationCardGraph.swift`, `Slackwater/TimelineStrip.swift` (`drawCurrent`'s second run loop)
- Test: `SlackwaterTests/SlackWindowTests.swift`

**Interfaces:**
- Produces: `func windowDotOpacities(run: WindowRun, now: Date) -> (opening: Double, closing: Double)`.
- `StationCardGraph.Extreme` gains `let spokenText: String` (value with unit, for VoiceOver); `valueText` becomes the bare value.

- [ ] **Step 1: Failing test**

Append inside the class in `SlackWindowTests.swift`:

```swift
    /// The opening is the major point while the run is ahead; once inside
    /// the run the closing is (current-charts §5.4.1). The minor one draws
    /// at half strength; a past run fades both under the past rule.
    func testWindowDotOpacitiesSwapInsideTheRun() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let run = WindowRun(start: t0.addingTimeInterval(600), end: t0.addingTimeInterval(1_800))
        let ahead = windowDotOpacities(run: run, now: t0)
        XCTAssertEqual(ahead.opening, 1); XCTAssertEqual(ahead.closing, 0.5)
        let inside = windowDotOpacities(run: run, now: t0.addingTimeInterval(1_000))
        XCTAssertEqual(inside.opening, 0.5); XCTAssertEqual(inside.closing, 1)
        let past = windowDotOpacities(run: run, now: t0.addingTimeInterval(3_600))
        XCTAssertEqual(past.opening, CurveStyle.pastLabelFade * 0.5)
        XCTAssertEqual(past.closing, CurveStyle.pastLabelFade)
    }
```

Run `SlackWindowTests` → compile error `cannot find 'windowDotOpacities'`.

- [ ] **Step 2: Implement**

Append to `SlackWindow.swift`:

```swift
/// The window's two edges are the points of interest (current-charts
/// §5.4.1): the opening is major while the run is ahead, the closing is
/// major once inside it; the other draws at half strength. A run already
/// passed fades both like any past mark, keeping the same ratio.
func windowDotOpacities(run: WindowRun, now: Date) -> (opening: Double, closing: Double) {
    if now < run.start { return (1, 0.5) }
    if now <= run.end { return (0.5, 1) }
    return (CurveStyle.pastLabelFade * 0.5, CurveStyle.pastLabelFade)
}
```

Run `SlackWindowTests` → passes.

- [ ] **Step 3: Card graph — labels and dots**

In `StationCardGraph.swift`:

1. `struct Extreme`: add `let spokenText: String` after `valueText` and reword `valueText`'s meaning in a comment: `/// The bare number for the curve; the unit prints once in the card's reading.` Update the accessibility line to `.accessibilityValue(extremes.map { "\($0.spokenText) at \($0.timeText)" } …)`.
2. In the three builders, split the existing `valueText:` strings: `valueText` keeps only the number (with the tilde for currents), `spokenText` gets what `valueText` was (number + unit). E.g. tide: `valueText: formatHeight($0.height, imperial: imperial), spokenText: "\(formatHeight($0.height, imperial: imperial)) \(heightUnit(imperial: imperial))"`. Keep `.monospacedDigit()` reachable: the canvas draw applies it and the `knownIndirections` entry `StationCardGraph.swift:cardGraph` already covers the builders.
3. In the `for e in extremes` loop, replace everything from `// The values form one rail across the vertical middle` to the closing `context.draw(Text(e.valueText) … at: CGPoint(x: labelX, y: bandY))` with:

```swift
                // The reading hangs off the turn toward the plot middle with
                // its pointer under it — the same rule the detail strip
                // follows (current-charts §15.1). No unit: the card's
                // reading states it once.
                let toward: CGFloat = e.high ? 1 : -1
                let cy = dotAt.y + toward * CurveStyle.hangOffset
                context.draw(Text(e.valueText)
                                .font(.system(size: CurveStyle.hangValueFontSize, weight: .semibold).monospacedDigit())
                                .foregroundStyle(text),
                             at: CGPoint(x: dotAt.x, y: cy - CurveStyle.hangValueRise))
                if let deg = e.deg {
                    // The SF Symbol, not the "↑" text glyph — a text arrow
                    // at the same point size renders visibly smaller.
                    var rotated = context
                    rotated.translateBy(x: dotAt.x, y: cy + CurveStyle.hangGlyphDrop)
                    rotated.rotate(by: .degrees(deg))
                    rotated.draw(Text(Image(systemName: "arrow.up"))
                                    .font(.system(size: CurveStyle.hangGlyphFontSize, weight: .bold))
                                    .foregroundStyle(tint),
                                 at: .zero)
                } else {
                    context.draw(Text(e.high ? "⤒" : "⤓")
                                    .font(.system(size: CurveStyle.hangGlyphFontSize, weight: .semibold))
                                    .foregroundStyle(tint),
                                 at: CGPoint(x: dotAt.x, y: cy + CurveStyle.hangGlyphDrop))
                }
```

Delete the now-unused private statics `pointerOffset`, `valueFontSize`, `pointerFontSize`.

4. In the `for w in windows` loop, replace the opening-dot block (`let fade = w.start < now …` and the `dot(...)` call) with:

```swift
                // The window's edges are the points of interest (§5.4.1):
                // the opening at full strength while the run is ahead, the
                // closing at half; inside the run they swap.
                let o = windowDotOpacities(run: w, now: now)
                dot(at: CGPoint(x: x0, y: y(valueAt(w.start))), color: SN.go.opacity(o.opening))
                dot(at: CGPoint(x: x1, y: y(valueAt(w.end))), color: SN.go.opacity(o.closing))
```

- [ ] **Step 4: Strip — the closing dot**

In `TimelineStrip.swift`, `drawCurrent`'s second run loop `for (run, seg) in zip(runs, segs) { … }`: replace the single `dot(...)` call with:

```swift
            let o = windowDotOpacities(run: run, now: now)
            dot(ctx, at: CGPoint(x: data.x(run.start), y: geo.curY(data.velocityAt(run.start))),
                color: SN.go.opacity(o.opening))
            dot(ctx, at: CGPoint(x: data.x(run.end), y: geo.curY(data.velocityAt(run.end))),
                color: SN.go.opacity(o.closing))
```

Update the comment above the loops (it says the opening "gets the track's only dot") to say the run's two edges get the dots, opening major while ahead, closing major inside.

- [ ] **Step 5: Compile, test, look, commit**

Compile check. Run `SlackWindowTests`, `TypeScaleTests`, `ColourAndFormTests`, `TimelineTests`, `RenderedStripTests`. All pass. Launch the app on the iPhone 17 simulator (terminate first: `xcrun simctl terminate <udid> org.openwaters.slackwater`), wait 20 s, screenshot the list to `<scratchpad>/card-task3.png`, open it: values without units hanging off the turns and peaks, both run edges dotted with the ahead one brighter.

```sh
git add Slackwater/SlackWindow.swift Slackwater/StationCardGraph.swift Slackwater/TimelineStrip.swift SlackwaterTests/SlackWindowTests.swift
git commit -m "feat: window-edge dots and hang-off readings on the card

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: The current card header shows speed and set, never a pill

**Files:**
- Modify: `Slackwater/StationCardFace.swift` (`ConditionsItem`)

**Interfaces:**
- Produces: `ConditionsItem.Reading.current(signed:deg:unit:tilde:countdownTo:)` with `countdownTo: Date? = nil`; the `.current` case no longer renders a pill.

- [ ] **Step 1: Replace the `.current` case**

In `ConditionsItem`, change the enum case to
`case current(signed: Double, deg: Double, unit: String, tilde: Bool = false, countdownTo: Date? = nil)`
and replace the whole `case .current(...)` branch of `body` with:

```swift
        case .current(let signed, let deg, let unit, let tilde, let countdownTo):
            // Always the speed and the set (current-charts §15.2): a pill
            // states a phase without either. Inside a window a counting
            // surface (the widget) shows the time to the closing instead of
            // the speed (§15.3); the list passes no countdown.
            let phase = currentPhase(signed: signed)
            if let end = countdownTo {
                if end.timeIntervalSinceNow > 7_200 {
                    Text("> 2 hrs")
                        .font(.title3.monospacedDigit()).fontWeight(.bold)
                        .foregroundStyle(.white)
                } else {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.title3.monospacedDigit()).fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            } else {
                (Text((tilde ? "~" : "") + formatSpeed(abs(signed), unit: unit))
                    .font(.title3.monospacedDigit()).fontWeight(.bold)
                 + Text(" \(speedUnitLabel(unit))")
                    .font(.body))
                    .foregroundStyle(.white)
            }
            // Direction-first (#59): a novice reads the arrow + cardinal;
            // the word demotes to a dimmer label. "Slack" wears the go
            // colour — the same meaning it has everywhere else. Under
            // 0.05 kn the set gives way to a neutral mark of the same
            // footprint so the header never resizes.
            let tint = phase == .slack ? SN.go : phase == .flood ? SN.flood : SN.ebb
            HStack(spacing: 4) {
                Text(phase == .slack ? "Slack" : phase.word).font(.caption2)
                    .foregroundStyle(tint.opacity(phase == .slack ? 1 : 0.6))
                if abs(signed) < 0.05 {
                    Text("•").font(.caption2).foregroundStyle(SN.foam.opacity(0.4))
                        .frame(width: 30)
                } else {
                    Text(compass16(deg)).font(.caption2).foregroundStyle(tint)
                    CompassArrow(deg: deg).font(.caption2).foregroundStyle(tint)
                }
            }.foregroundStyle(tint)
```

Check `phase.word` for `.slack` (in `CurrentStation.swift`); if it already returns "Slack", drop the ternary. `Text(timerInterval:countsDown:)` needs iOS 16; the app targets iOS 26.

Update `ConditionsItem`'s doc comment: the `.current` line becomes "signed velocity — speed + set arrow + word, Slack in the go colour inside a window; `countdownTo` swaps the speed for a timer on counting surfaces."

- [ ] **Step 2: Callers**

`grep -rn '\.current(signed:' Slackwater/` — every existing call compiles unchanged (the new parameter defaults to nil). `LiveFetchTests` matches the header by `label == 'Flooding' OR label == 'Ebbing' OR label == 'SLACK'`: read the three sites (lines ~96, ~116, ~326) and add `OR label == 'Slack'` to each predicate so a station in a window still matches.

- [ ] **Step 3: Compile, test, look, commit**

Compile check. Run `TypeScaleTests`, `PhaseGlossTests`, `ColourAndFormTests`. Launch the app, screenshot the list to `<scratchpad>/card-task4.png`: the Patos card (in a window at the time of writing) shows a speed with unit and "Slack" + cardinal + arrow, no pill.

```sh
git add Slackwater/StationCardFace.swift SlackwaterUITests/LiveFetchTests.swift
git commit -m "feat: current card header always shows speed and set

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: The medium widget renders the card

**Files:**
- Modify: `Slackwater/WidgetStationLoader.swift`, `Slackwater/MiniScrubberView.swift`, `SlackwaterWidgets/SlackwaterWidgetsBundle.swift`, `SlackwaterWidgets/HomeWidgets.swift`
- Test: `SlackwaterTests/WidgetSnapshotTests.swift`

**Interfaces:**
- Produces:
  - `enum WidgetRecord { case tide(TideStationRecord), current(CurrentStationRecord), derived(DerivedGateRecord) }` and `WidgetStationLoader.loadRecord(id:) -> WidgetRecord?`; `load(id:)` becomes `loadRecord(id:).map { … }` with the existing name-prefix logic preserved.
  - `struct WidgetCard: Equatable`: `name`, `region`, `reading: ConditionsItem.Reading`, `graph: StationCardGraph?`, `nextSlack: Date?` (derived gates), built by `WidgetCard.build(_ record: WidgetRecord, now: Date, stationNamePrefix: String?) -> WidgetCard` next to `WidgetSnapshot.build` in `WidgetSnapshot.swift`.
  - `SlackwaterEntry` gains `let card: WidgetCard?`.
  - `DayCurveContentView(card: WidgetCard)` renders `StationCard(chrome: false, minHeight: 0)`.

- [ ] **Step 1: Records from the loader**

In `WidgetStationLoader.swift`, refactor `load(id:)`: its switch over `StationItem.byId[id]` currently returns `WidgetStation` cases from records; split it so `loadRecord(id:)` returns the record (`.tide(r)`, `.current(r)`, `.derived(DerivedGateRecord(gate:port:))`, using the same `ChsModelStore` lookups) and `load(id:)` is `loadRecord(id: id).map { switch $0 { case .tide(let r): .tide(r.engineStation, tz: r.tz, name: r.name) … } }`. One switch over the catalog, not two. `WidgetSnapshot.build` is untouched.

- [ ] **Step 2: The card model**

In `WidgetSnapshot.swift` add:

```swift
/// The list card's inputs, built once per timeline entry so the widget is
/// the card (current-charts §15) with no second drawing of the curve.
struct WidgetCard {
    let name: String
    let region: String
    let reading: ConditionsItem.Reading
    let graph: StationCardGraph?
    /// A derived gate's next slack, for its "Slack · time" line.
    let nextSlack: (time: Date, tz: TimeZone)?

    static func build(_ record: WidgetRecord, now: Date, stationNamePrefix: String? = nil) -> WidgetCard {
        let imperial = AppGroup.defaults.string(forKey: unitsKey) != "metric"
        let speedUnit = AppGroup.defaults.string(forKey: speedUnitKey) ?? "kn"
        func named(_ n: String) -> String { [stationNamePrefix, n].compactMap { $0 }.joined(separator: " · ") }
        switch record {
        case .tide(let r):
            let state = r.cardState(at: now)
            return .init(name: named(r.name), region: r.region,
                         reading: .tide(state, imperial: imperial),
                         graph: r.cardGraph(at: now, imperial: imperial), nextSlack: nil)
        case .current(let r):
            let state = r.cardState(at: now)
            let graph = r.cardGraph(at: now, unit: speedUnit)
            // Inside a window the widget counts down to the closing (§15.3).
            let inside = graph.windows.first { $0.contains(now) }
            return .init(name: named(r.name), region: r.region,
                         reading: .current(signed: state.signed, deg: r.setDegrees(signed: state.signed),
                                           unit: speedUnit, countdownTo: inside?.end),
                         graph: graph, nextSlack: nil)
        case .derived(let r):
            let state = r.cardState(at: now)
            return .init(name: named(r.gate.name), region: r.gate.region,
                         reading: .gate(state.phase), graph: nil,
                         nextSlack: state.nextSlack.map { ($0.time, r.gate.tz) })
        }
    }
}
```

Match the real names: read `cardState(at:)` on each record and `CurrentCardState`'s fields (`signed`), `DerivedGateCardState` (`phase`, `nextSlack`), `DerivedGateRecord` (`gate.name`, `gate.region`, `gate.tz`), and the `cardGraph` signatures in `StationCardGraph.swift`; adjust the field names above to what exists, not the other way round.

- [ ] **Step 3: The entry and the view**

`SlackwaterWidgetsBundle.swift`: `SlackwaterEntry` gains `let card: WidgetCard?`; `entry(_:at:)` builds it with `WidgetStationLoader.loadRecord(id: id).map { WidgetCard.build($0, now: date, stationNamePrefix: …same prefix expression…) }` alongside the snapshot (the small widget still reads the snapshot).

`MiniScrubberView.swift`: delete `struct MiniScrubberView` (the sparkline canvas) and everything in `DayCurveContentView` except its shell; keep `widgetStationPresentation`, `tideEventValue` if anything still calls them (grep; delete if not), and keep any ramp helpers defined in the file (`grep -n '^func\|^let' Slackwater/MiniScrubberView.swift` first — `widgetSpeedRampT`/`currentSpeedRampAnchorsKn` may live here and are used by `Timeline.rampT`). The new view:

```swift
/// The medium widget IS the list card (current-charts §15): same shell,
/// same reading, same curve. No chrome — the widget's container clips.
struct DayCurveContentView: View {
    let card: WidgetCard
    var body: some View {
        StationCard(name: card.name, region: card.region, graph: card.graph, chrome: false, minHeight: 0) {
            ConditionsItem(reading: card.reading)
            if let next = card.nextSlack {
                Text("Slack · \(cardTime(next.time, next.tz))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.92))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`HomeWidgets.swift`, `DayCurveView`: `if let card = entry.card { DayCurveContentView(card: card) } else { …unchanged fallback… }`, and the widget's `.containerBackground(.background, for: .widget)` for `DayCurveWidget` becomes `.containerBackground(SN.cardFill, for: .widget)`. `NextEventWidget` unchanged.

Rename the file? No: `project.yml` lists it and a test reads it by path; keep `MiniScrubberView.swift`.

- [ ] **Step 4: Tests**

`WidgetSnapshotTests.swift`:
- Delete `testQuietTideAccessibilityDoesNotAnnounceMovementChevrons` (the widget no longer speaks chevrons; the card graph carries its own accessibility value).
- Replace `testMediumWidgetPresentsSlackWindowBeforeItsCountdown` with a source test on `Slackwater/MiniScrubberView.swift` asserting it contains `StationCard(name: card.name` and `ConditionsItem(reading: card.reading)` and does NOT contain `Canvas {` or `sparkline` — the widget is the card, not a second drawing.
- Replace the two `ImageRenderer` tests with one: build `WidgetCard.build(.current(<a bundled NOAA current record>), now: Date())`, render `DayCurveContentView(card:)` at 338×158 on `SN.cardFill`, assert the PNG is over 1,000 bytes and that at least 100 pixels in the middle rows are the go colour (`SN.go` is 0x… — read `goHex` in `Palette.swift` and match within ±24 per channel) when the card's `graph.windows` is non-empty; if it is empty at `Date()`, pick `now` as the start of the first window of `graph` built one day ahead. Keep the attachment.
- Add `testWidgetCardCountsDownInsideAWindow`: build a current `WidgetCard` at `now = graph.windows.first!.start + 60` (build the graph once to find it) and assert `if case .current(_, _, _, _, let end) = card.reading { XCTAssertEqual(end, window.end) }`.
- `testCurrentSnapshotPreservesMiniScrubberState` stays: the snapshot is untouched.

Run `WidgetSnapshotTests`, `TypeScaleTests` (add `"WidgetSnapshot.swift:build"` for `WidgetCard.build` only if the scan flags it; it formats nothing itself). All pass.

- [ ] **Step 5: Look**

The widget gallery: `WidgetsGalleryView` in the app renders `DayCurveContentView`? `grep -n DayCurveContentView Slackwater/WidgetsGalleryView.swift`; if it does, update its call to pass a `WidgetCard` built from a bundled record. Render `DayCurveContentView(card:)` via `ImageRenderer` at 338×158 to `<scratchpad>/widget-medium.png` in the test (the attachment) and also save it with `pngData()` to that path; open it. It must look like a list card: name, reading with set, curve with dots and times.

- [ ] **Step 6: Commit**

```sh
git add -A Slackwater SlackwaterWidgets SlackwaterTests/WidgetSnapshotTests.swift
git commit -m "feat: the medium widget renders the station card

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Full suite and screenshots (controller)

- [ ] Run `SLACKWATER_SIMS='SW Clean iPhone 17' SHOT_DIR=<scratchpad>/shots-cf ./scripts/test.sh` on the clean device. Expect `** TEST SUCCEEDED **`.
- [ ] Open `m1-list.png`, `m2-list-mixed.png`, `m2-current-scrubbed.png`, the widget render from Task 5, and check against current-charts §15: no units on the curve, readings in the lobes, both run edges dotted, the current header with speed and set and no pill, the widget indistinguishable from the card.
- [ ] Each visual fix is its own commit; re-run the affected class, then the suite once more if canvas code changed.
- [ ] Shut down the clean device (`xcrun simctl shutdown 36401EBC-8538-4973-B3BA-F9603C5BBCBB`). Do not push.
