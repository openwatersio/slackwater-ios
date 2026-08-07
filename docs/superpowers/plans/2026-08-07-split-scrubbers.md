# Split Scrubbers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire the combined tide+current strip — a scrubber only ever scrubs ONE track — and spend the freed space on the current story (taller curve, larger time labels, slack window), per `docs/superpowers/specs/2026-08-07-split-scrubbers-design.md`.

**Architecture:** Delete the combined case in place. `TimelineStrip.swift` keeps the one scrubber implementation (UIScrollView host, magnet, centering — do not fork it); `TimelineGeo` drops the `(true, true)` case; the current/derived details go current-only with a quiet "Tide at \<port\>" link navigating to the port's own `TideDetailView`. Sun moves from schedule rows into the day header. Recents stops collapsing namesakes.

**Tech Stack:** SwiftUI + UIKit scroll host, TideEngine, XcodeGen project, XCTest unit + XCUITest screenshot suites.

## Global Constraints

- Branch: `detail/split-scrubbers`, based off `detail/when-row-polish` (PR #25, CI fix pending — expect a rebase; do NOT merge or rebase yourself, Bryan will say when).
- Never commit `SlackwaterUITests/ScreenshotTests.swift` hunks you didn't write — the working tree carries Bryan's uncommitted PR-25 CI work. Stage files by exact path only; before every commit run `git diff --cached --stat` and confirm only your files are staged.
- Never merge your own PR. Outbound text (the PR body) is drafted for Bryan's review, posted only on his explicit go.
- Canvas labels stay fixed `.system(size:)` — the `TimelineGeo` fixed-point-geometry rule. Larger sizes yes, Dynamic Type no.
- Below the strip in the iPad split detail column, `Button` press tracking goes dead — interactive things there use `.onTapGesture` (see the `MultiDaySchedule` row comment). The new tide link must follow this.
- Frame assertions in UI tests use the `settledFrame` pattern (one layout, not two).
- Unit-test iteration: `xcodegen generate && xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater -testPlan Slackwater -only-testing:SlackwaterTests -destination "platform=iOS Simulator,name=iPhone 17" -clonedSourcePackagesDirPath build/SourcePackages | tail -20`. One test run at a time on this machine (test.sh holds a lockf; don't run anything concurrent with it).
- Full suite: `./scripts/test.sh` (both sims, 40–70 min, outlives the 10-min Bash cap — launch `nohup ./scripts/test.sh > /tmp/split-scrubbers-test.log 2>&1 &` then `disown`, poll the log).
- Commit messages end with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` and the Claude-Session trailer used by earlier commits on this branch.

---

### Task 1: Derived-gate build goes current-only

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:93-99` (`TimelineData.build(gate:)`)
- Test: `SlackwaterTests/DerivedGateTests.swift:85-110`

**Interfaces:**
- Produces: `TimelineData.build(gate:now:)` returning `hasTide == false`, `hasCurrent == true`; `snapTimes` = slacks + sun events only (no port turns). Signature unchanged.

- [ ] **Step 1: Flip the failing assertions**

In `DerivedGateTests.swift` (~line 96), the existing test asserts the retired behavior. Change:

```swift
XCTAssert(d.hasTide, "the reference port's tide track must be present")
```

to:

```swift
XCTAssertFalse(d.hasTide, "a derived gate's strip is single-track — no tide track (split-scrubbers spec §3)")
XCTAssert(d.tideExtremes.isEmpty, "no port turns in the data — they'd re-enter snapTimes and the schedule")
```

Keep every other assertion in the test (slack-only events, ±1 normalisation, snap stops) unchanged.

- [ ] **Step 2: Run to verify it fails**

Run the unit-test iteration command (Global Constraints), narrowed: `-only-testing:SlackwaterTests/DerivedGateTests`.
Expected: FAIL — `hasTide` is true today because `build(gate:)` passes the port as the tide input.

- [ ] **Step 3: Minimal implementation**

In `TimelineStrip.swift`, `build(gate:)` currently forwards the port as a drawn track:

```swift
static func build(gate: DerivedGateRecord, now: Date) -> TimelineData {
    build(tide: gate.port, current: nil, now: now, gate: gate)
}
```

Change to:

```swift
/// A derived gate's strip is single-track: the schematic ±1 half-sine with
/// slack events only. The port is the SOURCE of the slack times (engineGate
/// reads it), never a drawn track (split-scrubbers spec §3).
static func build(gate: DerivedGateRecord, now: Date) -> TimelineData {
    build(tide: nil, current: nil, now: now, gate: gate)
}
```

The `tz`/`lat`/`lon` resolution inside `build` already prefers `gate?.gate` first, so timezone and sun positions are unchanged.

- [ ] **Step 4: Run to verify it passes**

Same command. Expected: PASS (all of DerivedGateTests).

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/DerivedGateTests.swift
git commit  # "split: derived-gate strip builds current-only — the port sources slacks, it is not a track"
```

---

### Task 2: TimelineGeo — delete the combined case, grow the current track, bump the canvas labels

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:186-231` (`TimelineGeo`), `:259-335` (`drawDayChrome`), `:337-433` (`drawTide`/`drawCurrent`), `:590-676` (`TimelineScrubStrip.overlay`)
- Test: `SlackwaterTests/TimelineTests.swift`

**Interfaces:**
- Consumes: Task 1 (`build(gate:)` current-only) so no live caller produces `(hasTide, hasCurrent) == (true, true)` except `CurrentDetailView` (fixed in Task 5 — until then that one view renders the current-only geometry with a stray tide readout; acceptable mid-branch).
- Produces: `TimelineGeo` with two cases — tide-only `height 258` (unchanged), current-only `height 340, curTop 68, curBottom 320`. `sepY` property deleted. Overlay track labels ("Tide"/"Current") deleted.

- [ ] **Step 1: Write the failing geometry test**

Append to `TimelineTests.swift` (the `friday` fixture already exists in the class):

```swift
/// Two single-track geometries, no combined case (split-scrubbers spec §1/§2).
func testSingleTrackGeometries() {
    let tide = TimelineGeo(data: TimelineData.build(tide: friday, current: nil, now: Date()))
    XCTAssert(tide.hasTide && !tide.hasCurrent)
    XCTAssertEqual(tide.height, 258, "tide-only geometry does not change in this pass (spec §4)")

    // Current-only: construct TimelineData directly — the geometry keys only
    // on which point arrays are non-empty.
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let cur = TimelineGeo(data: TimelineData(
        tz: .current, today: t0, start: t0, end: t0.addingTimeInterval(3600),
        days: [], tidePoints: [], tideExtremes: [],
        currentPoints: [CurrentPoint(time: t0, speed: 1)], currentEvents: [],
        snapTimes: []))
    XCTAssert(!cur.hasTide && cur.hasCurrent)
    XCTAssertEqual(cur.height, 340, "the reclaimed vertical space goes to the current curve (spec §2)")
    XCTAssertEqual(cur.curBottom, 320)
    XCTAssertEqual(cur.bodyBottom, 320)
}
```

- [ ] **Step 2: Run to verify it fails**

`-only-testing:SlackwaterTests/TimelineTests`. Expected: FAIL — current-only height is 286 today.

- [ ] **Step 3: Implement the two-case geometry**

In `TimelineGeo`:
- Delete the `sepY` property and the `case (true, true)` switch arm. New switch:

```swift
switch (hasTide, hasCurrent) {
case (true, _):
    height = 258; tideBottom = 226; curTop = 0; curBottom = 0
default:
    // Taller than the old 286: the combined strip's reclaimed space goes to
    // the curve — speed labels and the FLOOD/EBB lines breathe (spec §2).
    height = 340; tideBottom = 0; curTop = 68; curBottom = 320
}
```

- Update the `TimelineGeo` doc comment: remove the hand-packed combined-case numbers it narrates (`tideBottom 170`, `sepY 192`, …) and state the two cases. Keep the fixed-size-labels rationale paragraphs — they still govern.
- In `drawDayChrome`, delete the trailing `if geo.hasTide && geo.hasCurrent { … sep … }` separator block (unreachable, and `sepY` is gone).
- In `TimelineScrubStrip.overlay`, delete both `MonoLabel(text: "Tide", …)` and `MonoLabel(text: "Current", …)` blocks (spec §1: one track per strip — the page title names it). The `Circle()` riding dots stay.

- [ ] **Step 4: Bump the canvas label sizes (same review gate: single-track strip visuals)**

Times get larger everywhere; values grow only where the geometry grew:
- `drawTide`: extreme height label stays `size: 10`; the clock-time label `size: 8` → `size: 10` and its stack offset `y ± 23` → `y ± 26` (keep `± 11` for the height).
- `drawCurrent`: speed labels `size: 10` → `size: 12`, offsets `y - 10` / `y + 12` → `y - 12` / `y + 14`; the `slack` label `size: 8` → `size: 10` and `zeroY + 12` → `zeroY + 14`.
- Day/sun chrome labels (11/10) unchanged — the sun band is untouched (spec §5 keeps strip chrome as-is).

- [ ] **Step 5: Run to verify it passes and everything compiles**

`-only-testing:SlackwaterTests`. Expected: PASS across the unit suite (`ColourAndFormTests`/`HeroChromeTests` touch strip colours — if one pins a deleted label or `sepY`, amend it to the two-case reality in this task).

- [ ] **Step 6: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift  # + any amended unit test file
git commit  # "split: two single-track geometries — combined case deleted, current curve taller, canvas times larger"
```

---

### Task 3: slackWindow — the workable window around a slack

**Files:**
- Modify: `Slackwater/TimelineStrip.swift` (add near `TimelineData`; add `Timeline.slackThresholdKn`)
- Test: `SlackwaterTests/TimelineTests.swift`

**Interfaces:**
- Produces: `Timeline.slackThresholdKn: Double = 0.5` and
  `func slackWindow(_ points: [CurrentPoint], around slack: Date, threshold: Double) -> (start: Date, end: Date)?`
  — free function, knots in/out, clamped to the series, `nil` when the slack isn't inside a sub-threshold run. Task 5 consumes it.

- [ ] **Step 1: Write the failing tests**

Append to `TimelineTests.swift`:

```swift
/// v falls linearly 2 kn → -2 kn over 2 h (slack at +60 min); |v| < 0.5
/// between +45 and +75 min. Samples every 10 min like the drawn series.
func testSlackWindowInterpolatesCrossings() throws {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let pts = (0...12).map { i in
        CurrentPoint(time: t0.addingTimeInterval(Double(i) * 600),
                     speed: 2.0 - Double(i) / 3.0)
    }
    let w = try XCTUnwrap(slackWindow(pts, around: t0.addingTimeInterval(3600),
                                      threshold: Timeline.slackThresholdKn))
    XCTAssertEqual(w.start.timeIntervalSince(t0), 2700, accuracy: 1)
    XCTAssertEqual(w.end.timeIntervalSince(t0), 4500, accuracy: 1)
}

/// A series that never leaves the window clamps to its edges.
func testSlackWindowClampsToSeriesEdges() throws {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let pts = (0...6).map { CurrentPoint(time: t0.addingTimeInterval(Double($0) * 600), speed: 0.1) }
    let w = try XCTUnwrap(slackWindow(pts, around: t0.addingTimeInterval(1800), threshold: 0.5))
    XCTAssertEqual(w.start, pts.first!.time)
    XCTAssertEqual(w.end, pts.last!.time)
}

/// No sub-threshold sample brackets the slack (a violent gate where the
/// 10-min sampling steps over the window) — no window, not a wrong one.
func testSlackWindowNilWhenSamplingStepsOver() {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let pts = (0...4).map { i in
        CurrentPoint(time: t0.addingTimeInterval(Double(i) * 600),
                     speed: i < 2 ? 4.0 : -4.0)
    }
    XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(900), threshold: 0.5))
}
```

- [ ] **Step 2: Run to verify they fail**

Expected: compile FAIL — `slackWindow` and `slackThresholdKn` not defined.

- [ ] **Step 3: Implement**

In `Timeline` (the enum at the top of `TimelineStrip.swift`):

```swift
/// The "weak current" convention: under half a knot a small boat transits.
/// A constant, not a setting, until someone asks (split-scrubbers spec §2).
static let slackThresholdKn = 0.5
```

Near `TimelineData` (file scope, like `scrubbedAway`):

```swift
/// The workable window around a slack: where |v| stays under `threshold`,
/// linearly interpolated at the crossings from the drawn 10-min samples —
/// the same series the strip renders, so the window can never disagree with
/// the curve. Clamped to the series; nil when no sub-threshold sample
/// brackets the slack.
func slackWindow(_ points: [CurrentPoint], around slack: Date,
                 threshold: Double) -> (start: Date, end: Date)? {
    guard !points.isEmpty else { return nil }
    let i = points.lastIndex(where: { $0.time <= slack }) ?? 0
    let k: Int
    if abs(points[i].speed) < threshold { k = i }
    else if i + 1 < points.count, abs(points[i + 1].speed) < threshold { k = i + 1 }
    else { return nil }
    func cross(_ a: CurrentPoint, _ b: CurrentPoint) -> Date {
        let va = abs(a.speed), vb = abs(b.speed)
        let f = (threshold - va) / (vb - va)
        return a.time.addingTimeInterval(b.time.timeIntervalSince(a.time) * f)
    }
    var start = points[0].time
    var a = k
    while a > 0 {
        if abs(points[a - 1].speed) >= threshold { start = cross(points[a - 1], points[a]); break }
        a -= 1
    }
    var end = points[points.count - 1].time
    var b = k
    while b < points.count - 1 {
        if abs(points[b + 1].speed) >= threshold { end = cross(points[b], points[b + 1]); break }
        b += 1
    }
    return (start, end)
}
```

- [ ] **Step 4: Run to verify they pass**

`-only-testing:SlackwaterTests/TimelineTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift
git commit  # "split: slackWindow — the workable under-0.5kn span, interpolated from the drawn series"
```

---

### Task 4: Sun moves into the schedule day header

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:692-828` (`SchedulePill`, `MultiDaySchedule`, `pillView`), `Slackwater/Theme.swift:291-300` (delete `SunPill`), `Slackwater/TideDetailView.swift:109-132`, `Slackwater/CurrentDetailView.swift:201-240`, `Slackwater/DerivedGateDetailView.swift:153-180`

**Interfaces:**
- Produces: `MultiDaySchedule` gains `let days: [TimelineDay]` (pass `tl.days`); `SchedulePill` loses `.sunrise`/`.sunset`; `SunPill` deleted. Day header sun times carry `accessibilityIdentifier("day-sun-d\(offset)")` — Task 7's UI tests key on it.

- [ ] **Step 1: Add sun times to the day header and drop the sun rows**

In `MultiDaySchedule`:
- Add `let days: [TimelineDay]` after `today`.
- Replace the bare day-label `Text` in the header column with:

```swift
VStack(alignment: .leading, spacing: 3) {
    Text(relativeDayLabel(group.offset, group.start, tz))
        .font(.caption.weight(.semibold))
        .foregroundStyle(SN.foam.opacity(0.9))
    if let day = days.first(where: { $0.offset == group.offset }) {
        VStack(alignment: .leading, spacing: 1) {
            if let rise = day.sunrise {
                Text("↑\(clockTime(rise, tz))").foregroundStyle(SN.sunrise)
            }
            if let set = day.sunset {
                Text("↓\(clockTime(set, tz))").foregroundStyle(SN.sunset)
            }
        }
        .font(.caption2.monospaced())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("day-sun-d\(group.offset)")
    }
}
.frame(width: 74, alignment: .leading)
.padding(.leading, 14)
.padding(.top, 12)
```

(The `frame`/`padding` moves from the old `Text` onto this VStack — same slot, same 74pt column.)
- Delete `case sunrise, sunset` from `SchedulePill` and their two `pillView` arms.
- Delete `struct SunPill` from `Theme.swift` (its only consumers were those two arms — verified 2026-08-07).

- [ ] **Step 2: Prune the three scheduleEntries and pass days**

In each of `TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView`:
- Delete the `for day in tl.days { … SchedulePill.sunrise/.sunset … }` loop from `scheduleEntries`.
- Add `days: tl.days` to the `MultiDaySchedule(entries:tz:today:…)` call (after `today:`).

- [ ] **Step 3: Build + unit suite**

`-only-testing:SlackwaterTests`. Expected: PASS (no unit test reads the sun pills; `SunMoonTests` tests `SunMoon` itself, untouched).

- [ ] **Step 4: Commit**

```bash
git add Slackwater/TimelineStrip.swift Slackwater/Theme.swift Slackwater/TideDetailView.swift Slackwater/CurrentDetailView.swift Slackwater/DerivedGateDetailView.swift
git commit  # "split: sun times move to the schedule day header — rows are purely tide/current events"
```

---

### Task 5: CurrentDetailView goes single-track (+ slack window, + tide link)

**Files:**
- Modify: `Slackwater/CurrentDetailView.swift`, `Slackwater/SlackwaterApp.swift:287-290,324-327` (environment wiring), `Slackwater/Theme.swift` (add `TideAtPortLink` + environment key)

**Interfaces:**
- Consumes: `slackWindow`/`Timeline.slackThresholdKn` (Task 3); the current-only geometry (Task 2).
- Produces: `EnvironmentValues.openTideDetail: (TideStationRecord) -> Void` and `struct TideAtPortLink { let port: TideStationRecord }` with `accessibilityIdentifier("tide-at-port")` — Task 6 reuses both; Task 7's UI tests key on the identifier.

- [ ] **Step 1: Environment key + link view (Theme.swift)**

```swift
// MARK: - Detail-to-detail navigation

/// Detail views push the paired port's own detail through this, not a
/// NavigationLink: NavigationLink is a Button, and Button press tracking
/// goes dead below the strip in the iPad split detail column while tap
/// gestures keep working (see MultiDaySchedule's row comment).
private struct OpenTideDetailKey: EnvironmentKey {
    static let defaultValue: (TideStationRecord) -> Void = { _ in }
}

extension EnvironmentValues {
    var openTideDetail: (TideStationRecord) -> Void {
        get { self[OpenTideDetailKey.self] }
        set { self[OpenTideDetailKey.self] = newValue }
    }
}

/// The one tide affordance on a current/gate detail (split-scrubbers spec
/// §2): a quiet link in the list's matching-stations convention, navigating
/// to the port's own TideDetailView. No tide numbers live here anymore.
struct TideAtPortLink: View {
    let port: TideStationRecord
    @Environment(\.openTideDetail) private var openTide

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2.weight(.semibold))
            Text("Tide at \(port.name)")
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(SN.leaf)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { openTide(port) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("tide-at-port")
    }
}
```

- [ ] **Step 2: Wire the environment on BOTH NavigationStacks (SlackwaterApp.swift)**

At each of the two `.navigationDestination(for: TideStationRecord.self)` clusters (~:287 compact, ~:324 regular), attach to the same view those modifiers hang off, using the same `path` binding the cluster's `open(_:)`/destinations use:

```swift
.environment(\.openTideDetail) { path.append($0) }
```

(Match the local path variable name in each scope — it's whatever `open(_:)` appends `TideStationRecord`s to. `ChsDetailView` needs no wiring: environment flows through to the detail views it hosts.)

- [ ] **Step 3: The split in CurrentDetailView**

- `onAppear`/`onChange`: `TimelineData.build(tide: nil, current: record, now: live)` (both call sites). Delete the `pairedTide:` forwarding into build ONLY — the `pairedTide` computed property stays (the link needs it).
- Delete the whole `if let port = pairedTide { … }` tide readout block at the top of `scrubCard` (the "Tide at \<port\>" MonoLabel, height text, Next High/Low column) and the now-unused `portHeight(_:at:)` helper.
- Delete the `out += tl.tideExtremes…` block in `scheduleEntries` (port turns leave with the track; `tl.tideExtremes` is empty now anyway).
- Delete the `if let port = pairedTide { Text("Tide shown is …") }` honesty block in `footer` (spec §1: nothing tide-shaped is shown).
- Update the file-header comment: the combined-station anatomy paragraph is retired; one track, tide one tap away.
- Add the slack window under the "Next slack" column, between the time line and the `then …` line:

```swift
private var slackWin: (start: Date, end: Date)? {
    guard let slack = nextSlack, let tl = timeline else { return nil }
    return slackWindow(tl.currentPoints, around: slack.time,
                       threshold: Timeline.slackThresholdKn)
}
```

and in the trailing VStack after the `Text("\(provisionalGate == nil ? "" : "~")in …")` line:

```swift
if let win = slackWin {
    Text("\(provisionalGate == nil ? "" : "~")under \(formatSpeed(Timeline.slackThresholdKn, unit: speedUnit)) \(speedUnitLabel(speedUnit)) · \(cardTime(win.start, tz))–\(cardTime(win.end, tz)) · \(countdown(from: win.start, to: win.end))")
        .font(.caption.monospacedDigit())
        .foregroundStyle(provisionalGate == nil ? SN.foam.opacity(0.7) : SN.amber.opacity(0.7))
        .accessibilityIdentifier("slack-window")
}
```

- Add the link at the bottom of `scrubCard`, after the `ScrubWhen` row:

```swift
if let port = pairedTide {
    TideAtPortLink(port: port)
        .padding(.top, 12)
}
```

- [ ] **Step 4: Build + unit suite**

`-only-testing:SlackwaterTests`. Expected: PASS. Also build for the iPad destination once (`xcodebuild build … -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M5)"`) since the wiring touched both layout branches.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/CurrentDetailView.swift Slackwater/SlackwaterApp.swift Slackwater/Theme.swift
git commit  # "split: current detail scrubs one track — slack window under next slack, tide one tap away"
```

---

### Task 6: DerivedGateDetailView goes single-track

**Files:**
- Modify: `Slackwater/DerivedGateDetailView.swift`

**Interfaces:**
- Consumes: `TideAtPortLink` (Task 5); current-only `build(gate:)` (Task 1). No slack window here — no speeds exist to threshold (spec §3).

- [ ] **Step 1: The split**

- Delete the "Tide at \(port.name)" readout HStack at the top of `scrubCard` and the `portHeight(at:)` helper.
- Delete the `out += tl.tideExtremes…` block in `scheduleEntries` (slack rows + header sun only).
- In `footer`, delete the `Text("Tide shown is \(port.name) — the reference port, not this station")` block; KEEP the derived-provenance sentence ("Slack times for … are derived on this device from … cruising-community rule of thumb …").
- KEEP unchanged: the phase readout, "speeds not predicted for this pass", the "at high/low water" line, and the "Shape only — slack times are derived from high and low water at \(port.name) …" note — the derivation explanation lives entirely in text now (spec §3).
- Update the file-header comment likewise.
- Add after the `ScrubWhen` row:

```swift
TideAtPortLink(port: port)
    .padding(.top, 12)
```

(unconditional — a derived gate always has its reference port).

- [ ] **Step 2: Build + unit suite**

`-only-testing:SlackwaterTests`. Expected: PASS (DerivedGateTests already amended in Task 1).

- [ ] **Step 3: Commit**

```bash
git add Slackwater/DerivedGateDetailView.swift
git commit  # "split: derived gate scrubs the schematic alone — derivation stays in text, tide one tap away"
```

---

### Task 7: Recents stops collapsing namesakes

**Files:**
- Modify: `Slackwater/SlackwaterApp.swift:466`

**Interfaces:**
- Consumes: `StationGroups` unchanged (`Theme.swift:466-493`) — the change is the call site only.

- [ ] **Step 1: The one-line change**

```swift
recentIds: places.collapse(recents.ids),
```

becomes:

```swift
// Uncollapsed on purpose: a station opened via the chooser is an explicit
// pick, same principle StationGroups grants Favorites — collapsing it made
// Recents silently show and reopen the nearest namesake instead
// (split-scrubbers spec §6). Near Me stays collapsed: distance ranking is
// not user choice.
recentIds: recents.ids,
```

ListGroups' dedupe-by-id against the sections above still works — ids are exact now, so a recent that already renders in Near Me still dedupes.

- [ ] **Step 2: Build**

`xcodegen generate && xcodebuild build …` (iPhone destination). Expected: builds. The behavioral guard is the UI test in Task 8.

- [ ] **Step 3: Commit**

```bash
git add Slackwater/SlackwaterApp.swift
git commit  # "split: Recents keeps the station you actually chose — no namesake collapse for explicit picks"
```

---

### Task 8: UI test amendments

**Files:**
- Modify: `SlackwaterUITests/ScreenshotTests.swift`

**CRITICAL:** This file carries Bryan's uncommitted PR-25 hunks. Before editing, run `git diff SlackwaterUITests/ScreenshotTests.swift > /tmp/pr25-pending.diff` to snapshot them; when committing, `git add -p` ONLY your hunks (or verify with `git diff --cached` that every staged hunk is yours). If a pending hunk overlaps a test you must amend, STOP and ask Bryan rather than stacking edits on his in-flight fix.

**Interfaces:**
- Consumes: `"tide-at-port"` (Task 5), `"day-sun-d0"` (Task 4), `"slack-window"` (Task 5), uncollapsed Recents (Task 7).

- [ ] **Step 1: Grep the full pin surface**

```bash
grep -n "TIDE AT\|reference port\|☀\|hasTide\|sepY\|matching stations" SlackwaterUITests/ScreenshotTests.swift
```

Every hit must end up amended by the steps below or affirmatively left alone with a reason.

- [ ] **Step 2: `testM4PairedTide` → `testM4TideAtPortLink` (~line 349)**

The paired pane is gone; the contract is now the link. Rewrite the gate-side half (keep the launch/search scaffolding):

```swift
// M4 (split-scrubbers): a gate detail shows no tide — the port's numbers
// live on the port's own detail, one tap through the quiet link.
func testM4TideAtPortLink() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-seedGate"]
    app.launch()
    XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

    openSearch(app, "deception")
    let gate = app.staticTexts["Deception Pass (Narrows)"].firstMatch
    XCTAssert(gate.waitForExistence(timeout: 5))
    gate.tap()
    XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))

    // Nothing tide-shaped on the gate detail.
    XCTAssertFalse(app.staticTexts["TIDE AT DECEPTION PASS STATE PARK"].exists,
                   "the paired tide readout is retired")
    XCTAssertFalse(app.staticTexts["↑ HIGH"].firstMatch.exists
                   && app.staticTexts["↓ LOW"].firstMatch.exists,
                   "port tide rows must not appear in a gate schedule")
    // The slack window is the new next-slack detail.
    XCTAssert(app.descendants(matching: .any).matching(identifier: "slack-window")
        .firstMatch.waitForExistence(timeout: 5),
              "slack window missing under Next slack")
    sleep(1)
    save(app, "m4-gate-detail.png")

    // The link opens the port's own detail with its schedule.
    let link = app.descendants(matching: .any).matching(identifier: "tide-at-port").firstMatch
    XCTAssert(link.waitForExistence(timeout: 5), "tide-at-port link missing")
    link.tap()
    XCTAssert(app.staticTexts["Deception Pass State Park"].firstMatch.waitForExistence(timeout: 8),
              "the link did not open the reference port's detail")
    XCTAssert(app.staticTexts["↑ HIGH"].firstMatch.waitForExistence(timeout: 5)
              || app.staticTexts["↓ LOW"].firstMatch.waitForExistence(timeout: 5),
              "port detail shows its own tide schedule")
}
```

Delete the now-unused port-side scrape half and the `minutes(_:)` helper inside it. `clockLabels`/`heightLabels` stay — other tests use them.

- [ ] **Step 3: `testM41DetailMapHeaderSunMoon` (~line 475)**

Replace the four `☀ RISE`/`☀ SET` assertions (two on the tide detail, one on the current detail) with the day-header identifier, and pin the rows' purity:

```swift
XCTAssert(app.descendants(matching: .any).matching(identifier: "day-sun-d0")
    .firstMatch.waitForExistence(timeout: 5),
          "sun times missing from the schedule day header")
XCTAssertFalse(app.staticTexts["☀ RISE"].firstMatch.exists,
               "sun rows have moved to the day header — none in the schedule")
```

Update the test's comment ("the schedule carries sunrise/sunset rows" → "the day header carries the sun times").

- [ ] **Step 4: `testM46MalibuDerivedGate` (~line 932)**

- The fill-in signal `app.staticTexts["TIDE AT POINT ATKINSON"].waitForExistence(timeout: 300)` becomes `app.staticTexts["NEXT SLACK"].waitForExistence(timeout: 300)` (same meaning: the fit landed and the readout rendered). Delete the second `TIDE AT POINT ATKINSON` assertion.
- Add: the link exists — `app.descendants(matching: .any).matching(identifier: "tide-at-port").firstMatch.waitForExistence(timeout: 5)` with message "derived gate must link to its reference port".
- Keep: `● SLACK` rows, the shape-only note, the cruising-community footer, the no-knots sweep, both screenshots, the `M46-SCHEDULE-TIMES` print.

- [ ] **Step 5: `testM50DetailSwapsBetweenSameKindStations` (~line 1293)**

The tide-row tell is gone; the staleness tell becomes the schedule contents changing (timeline-derived, which is what `@State` staleness freezes), plus the link (record-derived) as the layout check:

```swift
openSearch(app, "discovery island")
app.staticTexts["3.0 nm NE"].firstMatch.tap()
XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 8))
XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "tide-at-port").firstMatch.exists,
               "an unpaired current station has no reference port to link")
let before = scheduleRowLabels(app)
XCTAssert(!before.isEmpty, "no schedule rows read from the first station")

openSearch(app, "deception pass (n")
app.staticTexts["Deception Pass (Narrows)"].firstMatch.tap()
XCTAssert(app.staticTexts["Deception Pass (Narrows)"].firstMatch.waitForExistence(timeout: 8))
XCTAssert(app.descendants(matching: .any).matching(identifier: "tide-at-port")
    .firstMatch.waitForExistence(timeout: 8),
          "a paired gate links to its reference port")
XCTAssert(scheduleRowLabels(app) != before,
          "the detail kept the previous station's timeline — schedule did not change")
```

Keep the orientation scaffolding and screenshot; update the doc comment (tide rows → schedule contents as the tell).

- [ ] **Step 6: The M50 recents/chooser test (~line 1176)**

Read the test around the `"2 matching stations"` assertion first. Amend/extend for uncollapsed Recents: after opening a NON-nearest namesake from the chooser sheet and returning, assert Recents contains that exact station (its distinguishing region string, e.g. `"6.6 nm SSE"`), not the nearest namesake. If the existing test asserts a collapsed single entry in Recents, that assertion inverts. Any frame comparisons added here use `settledFrame`.

- [ ] **Step 7: Sweep the remaining greps**

For each remaining hit from Step 1 (`M52` tests among them): amend if it pins combined-layout geometry or retired copy; otherwise note in the task report why it stands (e.g. `timeline-strip` existence checks are layout-agnostic). The height change (286→340) moves things DOWN on current details — check any assertion measuring against the strip's bottom on a current detail.

- [ ] **Step 8: Compile the UI test target**

`xcodebuild build-for-testing -project Slackwater.xcodeproj -scheme Slackwater -testPlan Slackwater -destination "platform=iOS Simulator,name=iPhone 17" -clonedSourcePackagesDirPath build/SourcePackages | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 9: Commit (your hunks only)**

```bash
git add -p SlackwaterUITests/ScreenshotTests.swift   # stage ONLY your hunks — verify with git diff --cached
git commit  # "split: UI tests pin the single-track layouts — link flow, header sun, schedule-change tell"
```

---

### Task 9: Full suite, both simulators

- [ ] **Step 1: Launch detached**

```bash
nohup ./scripts/test.sh > /tmp/split-scrubbers-test.log 2>&1 &
disown
```

- [ ] **Step 2: Poll until done**

Poll every ~5 min (until-loop on the log; the run is 40–70 min):

```bash
until grep -qE "^=== Slackwater · iPad.*: [0-9]+s ===$" /tmp/split-scrubbers-test.log; do sleep 300; done
grep -E "Test Suite|TEST|failed|passed" /tmp/split-scrubbers-test.log | tail -20
```

- [ ] **Step 3: Green or fix**

Both sims green → proceed. Failures → superpowers:systematic-debugging per failure; re-run the affected test targeted before another full run. Report actual failure output, never "should pass".

- [ ] **Step 4: Push and draft the PR**

Push the branch. Draft (do NOT post) the PR body for Bryan's review: what split, the four design answers, the Recents fix, the test amendments, and the pending PR-25 rebase note. Bryan posts/merges on his go.

---

## Self-review notes (spec → plan)

- Spec §1 kill-list → Tasks 1, 2, 5, 6 (combined geometry, builds, readouts, honesty lines, track labels), Task 4 (sun rows). §2 → Tasks 2, 3, 5. §3 → Tasks 1, 6. §4 → Task 4 + Task 2's tide-time bump. §5 → Task 4. §6 → Task 7 (+ Task 8 Step 6 guard). §7 → Tasks 8, 9.
- Names used across tasks: `slackWindow`/`Timeline.slackThresholdKn` (T3→T5), `TideAtPortLink`/`openTideDetail`/`"tide-at-port"` (T5→T6→T8), `"day-sun-d\(offset)"` (T4→T8), `"slack-window"` (T5→T8), `days:` param (T4).
