# Week Window & Date Anchor — Plan A

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Widen the schedule list and the scrubber strip to a rolling 7-day window, and make the date that window hangs from a parameter (`anchor`) rather than an internally-computed `today`.

**Architecture:** `TimelineData.build` gains an `anchor:` parameter and carries both `anchor` (geometry) and `today` (language and liveness). One function, `Timeline.window(anchor:today:)`, replaces the four sites that independently re-derive `today ± hours`. The 48h look-back becomes conditional on the current week. The seven online gates go to a 30-day fetch whose stored window merges rather than replaces. Ships with `anchor = todayLocal(tz)` everywhere and no new UI — the visible change is a week in the list instead of 54 hours.

**Tech Stack:** Swift 6 / SwiftUI, XCTest, XcodeGen, `scripts/test.sh` (two simulators, lockf-serialized).

**Spec:** `docs/superpowers/specs/2026-08-11-week-window-and-date-anchor-design.md`

## Global Constraints

- **Never commit to `main` in this repo.** Branch, push the branch, open a PR, never merge your own. (`CONTRIBUTING.md`; workspace `CLAUDE.md`.) Work this plan on a branch off `origin/main`.
- **`pph` is not to be touched.** `Timeline.pph` stays 18. See spec §2 and the comment at `TimelineStrip.swift:17-22`.
- **Chart labels stay fixed-size**, never `.caption2` or any Dynamic Type font. See the `TimelineGeo` doc comment (`TimelineStrip.swift:376-399`).
- **Run tests with `./scripts/test.sh`** (fast plan). Never run a bare `xcodebuild` in this worktree while tests are in flight — it swaps `Slackwater.app` out from under the live run and every UI test fails with a fake "no file found" error. Wait for the lock.
- **Colour is state, form is kind.** Nothing added here derives colour from station kind.
- Commit after every task. Conventional-commit subject lines, lowercase after the type.

---

### Task 1: `Timeline.window` and the new constants

The one definition of the window, and the `todayLocal` helper the rest of the plan leans on. Pure functions, no UI — this task is entirely unit-testable.

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:16-41` (the `Timeline` enum)
- Modify: `Slackwater/Theme.swift:112` (add `todayLocal` beside `appNow`)
- Test: `SlackwaterTests/TimelineTests.swift`

**Interfaces:**
- Consumes: `appNow() -> Date` (`Theme.swift:112`)
- Produces:
  - `func todayLocal(_ tz: TimeZone) -> Date`
  - `Timeline.scheduleDays: Double` (7), `Timeline.scheduleHours: Double` (168), `Timeline.centerPad: Double` (12), `Timeline.forwardHours: Double` (180), `Timeline.backHours: Double` (48, unchanged)
  - `static func Timeline.window(anchor: Date, today: Date) -> (start: Date, end: Date)`

- [ ] **Step 1: Write the failing tests**

Add to `SlackwaterTests/TimelineTests.swift`:

```swift
// MARK: - The window (spec §1, §2)

private func vancouverMidnight(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/Vancouver")!
    return cal.date(from: DateComponents(year: y, month: m, day: d))!
}

/// The 48h look-back exists to answer "what did the water just do", which is a
/// question about NOW. On a Tuesday in September it is two days of the previous
/// week scrolled in behind you for no reason.
func testWindowBackPadOnlyOnTheCurrentWeek() {
    let today = vancouverMidnight(2026, 8, 11)

    let current = Timeline.window(anchor: today, today: today)
    XCTAssertEqual(current.start, today.addingTimeInterval(-48 * 3600))
    XCTAssertEqual(current.end, today.addingTimeInterval(180 * 3600))

    let future = vancouverMidnight(2026, 9, 14)
    let ahead = Timeline.window(anchor: future, today: today)
    XCTAssertEqual(ahead.start, future, "a future week starts clean at its own midnight")
    XCTAssertEqual(ahead.end, future.addingTimeInterval(180 * 3600))

    let past = vancouverMidnight(2026, 7, 6)
    let behind = Timeline.window(anchor: past, today: today)
    XCTAssertEqual(behind.start, past, "a past week gets no pad either")
}

/// The strip must stay WIDER than the list, or tapping the last schedule row
/// lands the centerline short of the event it names (UIScrollView clamps
/// contentOffset). The pad is what guarantees it.
func testStripOutrunsTheScheduleByTheCenterPad() {
    XCTAssertEqual(Timeline.scheduleHours, 168, "a week in the list")
    XCTAssertEqual(Timeline.forwardHours, Timeline.scheduleHours + Timeline.centerPad)
    XCTAssertGreaterThan(Timeline.centerPad * Timeline.pph, 200,
                         "the pad must exceed half a phone's width in points")
}

func testTodayLocalIsMidnightInTheGivenZone() {
    let tz = TimeZone(identifier: "America/Vancouver")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let t = todayLocal(tz)
    XCTAssertEqual(t, cal.startOfDay(for: appNow()))
    XCTAssertEqual(cal.component(.hour, from: t), 0)
}
```

In the same edit, update the two assertions in the **existing** `testWindowAndMapping` that pin the old width — widening `forwardHours` changes the total from 180h to 228h, and this task must commit green:

```swift
        // -48h … +180h around today's local midnight (spec §2).
        XCTAssertEqual(d.end.timeIntervalSince(d.start), 228 * 3600, accuracy: 3601)
        XCTAssertEqual(d.totalWidth, 228 * Timeline.pph, accuracy: 13)
```

Leave the rest of that test body alone. `testScheduleWindowSpansMultipleDays` needs no change — it asserts `days.count >= 2`, which a 7-day window still satisfies.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./scripts/test.sh
```

Expected: compile failure — `cannot find 'todayLocal' in scope`, `type 'Timeline' has no member 'window'`, `no member 'scheduleDays'`.

- [ ] **Step 3: Add `todayLocal`**

In `Slackwater/Theme.swift`, directly below `func appNow()`:

```swift
/// Today's local midnight in `tz`, on the app clock. The anchor every detail
/// view starts on, and the `today` half of every `Timeline.window` call.
func todayLocal(_ tz: TimeZone) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.startOfDay(for: appNow())
}
```

- [ ] **Step 4: Rewrite the `Timeline` constants and add `window`**

In `Slackwater/TimelineStrip.swift`, replace the `backHours` / `forwardHours` / `scheduleHours` declarations (lines 24-26) with:

```swift
    /// The look-back, and it applies ONLY to the current week — see `window`.
    static let backHours = 48.0
    /// A week in the list. The product decision this whole spec is about; the
    /// 54 it replaced was the HTML prototype's `tableEl` TOP, never a decision.
    static let scheduleDays = 7.0
    static let scheduleHours = scheduleDays * 24          // 168
    /// Half a viewport, so the LAST listed event can still sit under the
    /// centerline instead of jamming against UIScrollView's contentOffset
    /// clamp. Tapping a schedule row scrubs the strip, and a row exactly at
    /// the strip's edge would park the centerline short of the event it names
    /// — the readout disagreeing with the row you just tapped. The old
    /// 132-vs-54 mismatch kept this property by accident; this keeps it on
    /// purpose, at the smallest width that still clears half a phone.
    static let centerPad = 12.0
    static let forwardHours = scheduleHours + centerPad   // 180
```

Then add, after `scrubbedSeconds`:

```swift
    /// THE window definition. Four sites used to re-derive `today ± hours`
    /// independently — day chrome, the online-gate coverage check, the
    /// UI-test seed, and the online fetch — and with a conditional back-pad
    /// they would drift. The failure mode is a coverage check that passes on
    /// a window with a hole in it, which renders as a strip with a dead zone.
    ///
    /// The back-pad is the whole reason this takes two dates: it answers a
    /// question about NOW, so it exists only when the anchor IS now.
    static func window(anchor: Date, today: Date) -> (start: Date, end: Date) {
        let back = anchor == today ? backHours : 0
        return (anchor.addingTimeInterval(-back * 3600),
                anchor.addingTimeInterval(forwardHours * 3600))
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./scripts/test.sh
```

Expected: **the whole suite green.** The four new tests pass, and `testWindowAndMapping` passes on its updated 228h assertions. This task commits green — no red intermediate state is handed to Task 2.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/TimelineStrip.swift Slackwater/Theme.swift SlackwaterTests/TimelineTests.swift
git commit -m "feat: one window definition, and a week in the schedule constants"
```

---

### Task 2: `TimelineData` takes an anchor

`build` stops computing `today` internally. The struct carries both dates, and `dayChrome` derives its window from `Timeline.window`.

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:170-369` (`TimelineDay`, `TimelineData`, `dayChrome`, all three `build` overloads)
- Test: `SlackwaterTests/TimelineTests.swift`

**Interfaces:**
- Consumes: `Timeline.window(anchor:today:)`, `todayLocal(_:)` from Task 1
- Produces:
  - `TimelineData.anchor: Date` and `TimelineData.today: Date` (both stored)
  - `TimelineData.build(tide:current:now:anchor:gate:)`
  - `TimelineData.build(gate:now:anchor:)`
  - `TimelineData.build(onlinePoints:tz:lat:lon:now:anchor:)`
  - In all three, `anchor` has **no default** — every call site states it.

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/TimelineTests.swift`:

```swift
/// The anchor drives geometry; `today` stays the real day. A September strip
/// must be built around September and still know what day it actually is.
func testFutureAnchorMovesTheWindowButNotToday() {
    let now = Date()
    let tz = friday.tz
    let today = todayLocal(tz)
    let future = today.addingTimeInterval(34 * 86_400)

    let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: future)
    XCTAssertEqual(d.anchor, future)
    XCTAssertEqual(d.today, today, "today is the real day, not the anchor")
    XCTAssertEqual(d.start, future, "no back-pad off the current week")
    XCTAssertEqual(d.end.timeIntervalSince(d.start), 180 * 3600, accuracy: 3601)
    XCTAssert(d.tidePoints.allSatisfy { $0.time >= d.start && $0.time <= d.end })
}

/// Day chrome must reach far enough that the LAST night on the strip still
/// finds the following sunrise — `drawDayChrome` reads day+1 to place the moon
/// mid-night. Window ends at anchor+7.5d, so offset 8 has to exist.
func testDayChromeCoversTheLastNightsMoon() {
    let today = todayLocal(friday.tz)
    let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: today)
    XCTAssertEqual(d.days.first?.offset, -2)
    XCTAssertEqual(d.days.last?.offset, 8)
    let lastVisible = d.days.first { $0.offset == 7 }
    XCTAssertNotNil(lastVisible?.sunset)
    XCTAssertNotNil(d.days.first { $0.offset == 8 }?.sunrise,
                    "the last visible night needs the next day's sunrise for its moon")
}
```

Task 1 already fixed the width assertions, so the only change to existing tests here is threading the new argument: add `anchor: todayLocal(friday.tz)` to every `TimelineData.build` call in `testWindowAndMapping`, `testScheduleWindowSpansMultipleDays`, `testNowReadoutEquivalence` and `testNightContinuityAcrossMidnight`.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./scripts/test.sh
```

Expected: compile failure — `extra argument 'anchor' in call`.

- [ ] **Step 3: Add the stored properties**

In `Slackwater/TimelineStrip.swift`, in `struct TimelineData`, replace the `let today: Date` line with:

```swift
    /// The local midnight this window is built around. Geometry only.
    let anchor: Date
    /// The REAL local midnight. Language and liveness only — the
    /// Today/Tomorrow labels, the now-marker, return-to-now. Never geometry.
    let today: Date
```

- [ ] **Step 4: Rewrite `dayChrome`**

Replace `TimelineData.DayChrome` and `dayChrome` (lines 235-257) with:

```swift
    private struct DayChrome {
        let tz: TimeZone
        let anchor: Date
        let today: Date
        let start: Date
        let end: Date
        let days: [TimelineDay]
    }

    private static func dayChrome(tz: TimeZone, lat: Double, lon: Double,
                                  anchor: Date, today: Date) -> DayChrome {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let w = Timeline.window(anchor: anchor, today: today)
        // -2 covers the back-pad on the current week; 8 exists so the last
        // visible night (offset 7) can find the following sunrise for its moon.
        let days: [TimelineDay] = (-2...8).map { off in
            let d0 = cal.date(byAdding: .day, value: off, to: anchor)!
            let sun = SunMoon.sunEvents(lat: lat, lon: lon, tz: tz, day: d0)
            return TimelineDay(offset: off, start: d0,
                               sunrise: sun.first { $0.kind == .sunrise }?.time,
                               sunset: sun.first { $0.kind == .sunset }?.time)
        }
        return DayChrome(tz: tz, anchor: anchor, today: today,
                         start: w.start, end: w.end, days: days)
    }
```

- [ ] **Step 5: Thread `anchor` through the three `build` overloads**

In each of the three `build` functions:

- add `anchor: Date` to the signature (after `now:`, before any defaulted parameter),
- replace the `let chrome = dayChrome(tz:lat:lon:now:)` call with `dayChrome(tz: tz, lat: lat, lon: lon, anchor: anchor, today: todayLocal(tz))`,
- delete the local `let today = chrome.today` binding where it exists and pass both through to the initializer.

The signatures become:

```swift
    static func build(gate: DerivedGateRecord, now: Date, anchor: Date) -> TimelineData {
        build(tide: nil, current: nil, now: now, anchor: anchor, gate: gate)
    }

    static func build(onlinePoints: [CurrentPoint], tz: TimeZone, lat: Double, lon: Double,
                      now: Date, anchor: Date) -> TimelineData

    static func build(tide: TideStationRecord?, current: CurrentStationRecord?,
                      now: Date, anchor: Date, gate: DerivedGateRecord? = nil) -> TimelineData
```

Each `TimelineData(...)` initializer call gains `anchor: chrome.anchor, today: chrome.today` in place of `today: chrome.today`.

- [ ] **Step 6: Widen the two `offset <= 5` sun filters**

Both `build` overloads compute `sunTimes` with `days.filter { $0.offset <= 5 }` (lines 298 and 358). Both become:

```swift
        let sunTimes = chrome.days.filter { $0.offset <= 7 }
            .flatMap { [$0.sunrise, $0.sunset].compactMap { $0 } }
```

(in the `tide:current:` overload the local is `days`, not `chrome.days` — keep whichever that function already uses).

- [ ] **Step 7: Fix the call sites so the app compiles**

Four detail views call `build` and will now fail to compile. Give each the interim inline anchor — Task 6 replaces these with `@State`:

- `Slackwater/TideDetailView.swift` — both `build` calls in `.onAppear` / `.onChange`
- `Slackwater/CurrentDetailView.swift:84` and `:91`
- `Slackwater/DerivedGateDetailView.swift` — its `build(gate:now:)` call
- `Slackwater/OnlineGateDetailView.swift` — its `build(onlinePoints:...)` call

In each, add `anchor: todayLocal(tz)` to the call.

- [ ] **Step 8: Run the tests to verify they pass**

```bash
./scripts/test.sh
```

Expected: all of `TimelineTests` PASS, including the two updated width assertions.

- [ ] **Step 9: Commit**

```bash
git add Slackwater/TimelineStrip.swift Slackwater/TideDetailView.swift \
        Slackwater/CurrentDetailView.swift Slackwater/DerivedGateDetailView.swift \
        Slackwater/OnlineGateDetailView.swift SlackwaterTests/TimelineTests.swift
git commit -m "feat: TimelineData hangs from an anchor, not from today"
```

---

### Task 3: Day offsets become anchor-relative

`TimelineDay.offset` is currently days-from-today and does two jobs: label input and lookup key. Once the anchor moves they want different numbers. `offset` keeps the key job; `relativeDayLabel` computes the word from `today`.

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:891-899` (`relativeDayLabel`), `:655` (day-label draw), `:1183` (`MultiDaySchedule`)
- Test: `SlackwaterTests/TimelineTests.swift`

**Interfaces:**
- Consumes: `TimelineData.anchor`, `TimelineData.today`, `TimelineDay.offset` (anchor-relative, from Task 2)
- Produces: `func relativeDayLabel(_ dayStart: Date, _ tz: TimeZone, today: Date) -> String` — note the offset parameter is **gone**; the function derives the relation itself.

- [ ] **Step 1: Write the failing test**

```swift
/// "Today" must mean today, on any strip. The old signature took a
/// days-from-today offset; once the anchor moves, offset is days-from-ANCHOR
/// and passing it here would label a September Monday "Today".
func testRelativeDayLabelTracksTodayNotTheAnchor() {
    let tz = TimeZone(identifier: "America/Vancouver")!
    let today = vancouverMidnight(2026, 8, 11)          // a Tuesday
    let tomorrow = vancouverMidnight(2026, 8, 12)
    let yesterday = vancouverMidnight(2026, 8, 10)
    let september = vancouverMidnight(2026, 9, 14)      // a Monday

    XCTAssertEqual(relativeDayLabel(today, tz, today: today), "Today")
    XCTAssertEqual(relativeDayLabel(tomorrow, tz, today: today), "Tomorrow")
    XCTAssertEqual(relativeDayLabel(yesterday, tz, today: today), "Yesterday")
    XCTAssertEqual(relativeDayLabel(september, tz, today: today), "Mon",
                   "a day 34 days out is a weekday, never Today")
}

/// The first group of a future-anchored schedule is the anchor's own day, and
/// it must NOT be called Today.
func testFutureAnchorFirstDayIsNotLabelledToday() {
    let tz = friday.tz
    let today = todayLocal(tz)
    let future = today.addingTimeInterval(34 * 86_400)
    let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: future)
    let firstDay = d.days.first { $0.offset == 0 }!
    XCTAssertEqual(firstDay.start, future, "offset 0 is the ANCHOR's day")
    XCTAssertNotEqual(relativeDayLabel(firstDay.start, tz, today: today), "Today")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./scripts/test.sh
```

Expected: compile failure — `extra argument 'today' in call` / missing argument for parameter #1.

- [ ] **Step 3: Rewrite `relativeDayLabel`**

Replace `TimelineStrip.swift:891-899`:

```swift
/// "Today" / "Tomorrow" / "Yesterday", short weekday otherwise (prototype
/// dayName). Takes the day itself and the REAL today, never an offset: on an
/// anchored strip `TimelineDay.offset` is days-from-anchor, so feeding it here
/// would label the first day of a September window "Today".
func relativeDayLabel(_ dayStart: Date, _ tz: TimeZone, today: Date) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    switch cal.dateComponents([.day], from: today, to: dayStart).day ?? 0 {
    case 0: "Today"
    case 1: "Tomorrow"
    case -1: "Yesterday"
    default: formatterShortWeekday(dayStart, tz)
    }
}
```

- [ ] **Step 4: Update the two call sites**

`TimelineCanvas.drawDayChrome` (~line 655):

```swift
            ctx.draw(Text(relativeDayLabel(day.start, data.tz, today: data.today))
```

`MultiDaySchedule` (~line 1183):

```swift
                        Text(relativeDayLabel(group.start, tz, today: today))
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./scripts/test.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift
git commit -m "fix: Today means today, not the first day of the window"
```

---

### Task 4: One schedule range, four callers

All four detail views compute `t0 = tl.today; t1 = t0 + scheduleHours` and filter on it. That block moves onto `TimelineData` so the anchor change lands in one place and the four cannot drift.

**Files:**
- Modify: `Slackwater/TimelineStrip.swift` (add `scheduleRange` to `TimelineData`)
- Modify: `Slackwater/TideDetailView.swift:120-128`, `Slackwater/CurrentDetailView.swift:223-243`, `Slackwater/DerivedGateDetailView.swift:142-151`, `Slackwater/OnlineGateDetailView.swift:223-244`
- Test: `SlackwaterTests/TimelineTests.swift`

**Interfaces:**
- Consumes: `TimelineData.anchor`, `Timeline.scheduleHours`
- Produces: `TimelineData.scheduleRange: ClosedRange<Date>`

- [ ] **Step 1: Write the failing test**

```swift
/// The list runs the anchor's 00:00 → +7d, and it is strictly inside the strip
/// — the centerPad is what lets the last row scrub under the centerline.
func testScheduleRangeIsAWeekInsideTheStrip() {
    let today = todayLocal(friday.tz)
    let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: today)
    XCTAssertEqual(d.scheduleRange.lowerBound, today)
    XCTAssertEqual(d.scheduleRange.upperBound, today.addingTimeInterval(168 * 3600))
    XCTAssertLessThan(d.scheduleRange.upperBound, d.end,
                      "the strip must outrun the list by the centerPad")
}

/// Seven day-groups, and the first is the anchor's own day.
func testFutureAnchorSchedulesSevenDays() {
    let tz = friday.tz
    let future = todayLocal(tz).addingTimeInterval(34 * 86_400)
    let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: future)
    let turns = d.tideExtremes.filter { d.scheduleRange.contains($0.time) }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let days = Set(turns.map { cal.startOfDay(for: $0.time) })
    XCTAssertEqual(days.count, 7, "a week of tide turns, got \(days.count)")
    XCTAssertEqual(days.min(), future)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./scripts/test.sh
```

Expected: compile failure — `value of type 'TimelineData' has no member 'scheduleRange'`.

- [ ] **Step 3: Add `scheduleRange`**

In `struct TimelineData`, beside `totalWidth`:

```swift
    /// The list's window: the anchor's own midnight → +7d. Deliberately
    /// NARROWER than `start…end` — the strip carries `Timeline.centerPad` more
    /// so the last listed event can still park under the centerline.
    ///
    /// This lives here rather than in the four detail views because all four
    /// were computing it identically off `today`, and the anchor change would
    /// otherwise have to land correctly in four places.
    var scheduleRange: ClosedRange<Date> {
        anchor...anchor.addingTimeInterval(Timeline.scheduleHours * 3600)
    }
```

- [ ] **Step 4: Collapse the four callers onto it**

In each of the four views' `scheduleEntries`, delete the `let t0` / `let t1` lines and change the filter. `TideDetailView`:

```swift
    private func scheduleEntries(_ tl: TimelineData) -> [ScheduleEntry] {
        tl.tideExtremes
            .filter { tl.scheduleRange.contains($0.time) }
            .map { ScheduleEntry(time: $0.time, pill: $0.kind == .high ? .high : .low,
                                 value: "\(formatHeight($0.height, imperial: imperial)) \(unit)") }
            .sorted { $0.time < $1.time }
    }
```

`DerivedGateDetailView`:

```swift
    private func scheduleEntries(_ tl: TimelineData) -> [ScheduleEntry] {
        tl.currentEvents
            .filter { tl.scheduleRange.contains($0.time) }
            .map { ScheduleEntry(time: $0.time, pill: .slack) }
            .sorted { $0.time < $1.time }
    }
```

`CurrentDetailView` and `OnlineGateDetailView`: keep their existing `switch e.kind` map bodies exactly as they are; only replace the `.filter { $0.time >= t0 && $0.time <= t1 }` line with `.filter { tl.scheduleRange.contains($0.time) }` and delete the two `let` lines above it.

- [ ] **Step 5: Update `MultiDaySchedule`'s day-group offsets**

`MultiDaySchedule.groups` (line 1158) computes `off` from `today`. It must key off the anchor to match `TimelineDay.offset`. Change the parameter and the computation:

```swift
struct MultiDaySchedule: View {
    let entries: [ScheduleEntry]
    let tz: TimeZone
    /// The window's anchor — day-group offsets are anchor-relative, matching
    /// `TimelineDay.offset`, because that is what `days` is keyed on below.
    let anchor: Date
    /// The real today, for the Today/Tomorrow labels only.
    let today: Date
    let days: [TimelineDay]
    let scrubTime: Date
    let onTap: (Date) -> Void
```

and inside `groups`, replace `cal.dateComponents([.day], from: today, to: d0)` with `cal.dateComponents([.day], from: anchor, to: d0)`.

Then in all four views' `scheduleCard`, change `MultiDaySchedule(entries:tz:today:days:...)` to pass both:

```swift
        MultiDaySchedule(entries: scheduleEntries(tl), tz: tz, anchor: tl.anchor,
                         today: tl.today, days: tl.days,
                         scrubTime: scrubTime, onTap: { scrubTime = $0 })
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
./scripts/test.sh
```

Expected: PASS, including the `ScreenshotTests` day-group accessibility identifiers (`schedule-row-d<offset>`, `day-sun-d<offset>`) — these are anchor-relative now but on a today-anchored strip the numbers are unchanged, so existing UI tests keep matching.

- [ ] **Step 7: Commit**

```bash
git add Slackwater/TimelineStrip.swift Slackwater/TideDetailView.swift \
        Slackwater/CurrentDetailView.swift Slackwater/DerivedGateDetailView.swift \
        Slackwater/OnlineGateDetailView.swift SlackwaterTests/TimelineTests.swift
git commit -m "refactor: one schedule range on TimelineData, four callers"
```

---

### Task 5: The now-marker only draws when now is on the strip

`TimelineCanvas.draw` strokes the dashed `now` line unconditionally. On a September strip that line lands off the window entirely.

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:546-556` (`TimelineCanvas.draw`)
- Test: `SlackwaterTests/TimelineTests.swift`

**Interfaces:**
- Consumes: `TimelineData.start`, `TimelineData.end`
- Produces: `TimelineData.contains(_ t: Date) -> Bool`

- [ ] **Step 1: Write the failing test**

The draw call itself is a `Canvas` closure and not directly assertable, so the testable unit is the predicate that guards it.

```swift
func testContainsBoundsTheStripWindow() {
    let today = todayLocal(friday.tz)
    let now = Date()
    let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: today)
    XCTAssert(d.contains(now), "a today-anchored strip contains now")

    let ahead = TimelineData.build(tide: friday, current: nil, now: now,
                                   anchor: today.addingTimeInterval(34 * 86_400))
    XCTAssertFalse(ahead.contains(now),
                   "a September strip must not claim to hold today's now-marker")
    XCTAssert(ahead.contains(ahead.anchor.addingTimeInterval(3 * 86_400)))
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./scripts/test.sh
```

Expected: compile failure — `value of type 'TimelineData' has no member 'contains'`.

- [ ] **Step 3: Add `contains` and guard the draw**

In `struct TimelineData`, beside `scheduleRange`:

```swift
    /// Is `t` inside the drawn window? The guard on anything positioned by
    /// absolute time rather than by the window itself.
    func contains(_ t: Date) -> Bool { t >= start && t <= end }
```

In `TimelineCanvas.draw`, wrap the now-line:

```swift
    private func draw(_ ctx: GraphicsContext) {
        drawDayChrome(ctx)
        if geo.hasTide { drawTide(ctx) }
        if geo.hasCurrent { drawCurrent(ctx) }
        // Real-now faint marker rides the timeline (prototype 'nowt') — but
        // only when now is ON this timeline. An anchored strip a month out has
        // no "now" to mark, and drawing it anyway pins a dashed line to
        // whichever edge the clamp lands on, which reads as a real event.
        guard data.contains(now) else { return }
        var nowLine = Path()
        nowLine.move(to: CGPoint(x: data.x(now), y: geo.hasTide ? geo.tideTop : geo.curTop))
        nowLine.addLine(to: CGPoint(x: data.x(now), y: geo.bodyBottom))
        ctx.stroke(nowLine, with: .color(SN.leaf.opacity(0.55)),
                   style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
./scripts/test.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift
git commit -m "fix: the now-marker draws only when now is on the strip"
```

---

### Task 6: Detail views hold the anchor

The four views get `@State private var anchor`, and `returnToNow` resets it. Nothing moves the anchor yet — Plan B's range bar does — but the plumbing lands here so Plan B is additive.

**Files:**
- Modify: `Slackwater/TideDetailView.swift`, `Slackwater/CurrentDetailView.swift`, `Slackwater/DerivedGateDetailView.swift`, `Slackwater/OnlineGateDetailView.swift`
- Test: `SlackwaterUITests/ScreenshotTests.swift` (existing, no change — this task must not alter any screenshot)

**Interfaces:**
- Consumes: `todayLocal(_:)`, `TimelineData.build(..., anchor:)`
- Produces: in each of the four views, `@State private var anchor: Date` and a `rebuild()` private method that Plan B calls.

- [ ] **Step 1: Add the state and the rebuild seam**

In `CurrentDetailView`, beside the existing `@State private var timeline`:

```swift
    /// The local midnight the window hangs from. Only `returnToNow` and (in
    /// Plan B) the range bar move it; everything else reads it.
    @State private var anchor = Date.distantPast
```

`Date.distantPast` rather than `todayLocal(tz)`: a property initializer cannot reference `self.tz`. `.onAppear` sets the real value.

Replace the `.onAppear` / `.onChange` bodies:

```swift
        .onAppear {
            if timeline == nil {
                anchor = todayLocal(tz)
                rebuild()
            }
            RecentsStore.shared.record(record.itemId)
        }
        .onChange(of: record) { _, _ in rebuild() }
```

and add:

```swift
    /// One place the timeline is rebuilt from, so the anchor and the record
    /// can never be applied by two different code paths.
    private func rebuild() {
        timeline = TimelineData.build(tide: nil, current: record, now: live, anchor: anchor)
    }
```

- [ ] **Step 2: Make `returnToNow` reset the anchor**

```swift
    private func returnToNow() {
        live = appNow()
        scrubTime = live
        // The anchor too: return-to-now from a September window has to bring
        // the whole window back, not just park the centerline at a `now` that
        // isn't on this strip.
        anchor = todayLocal(tz)
        rebuild()
    }
```

- [ ] **Step 3: Repeat for the other three views**

Same four edits in each, with that view's own `build` overload inside `rebuild()`:

- `TideDetailView` — `TimelineData.build(tide: record, current: nil, now: live, anchor: anchor)`
- `DerivedGateDetailView` — `TimelineData.build(gate: record, now: live, anchor: anchor)`
- `OnlineGateDetailView` — `TimelineData.build(onlinePoints: window.points, tz: gate.tz, lat: gate.latitude, lon: gate.longitude, now: live, anchor: anchor)`; this one already rebuilds from `window`, so `rebuild()` takes the window it has and returns early when `window == nil`.

Remove the interim `anchor: todayLocal(tz)` inline arguments added in Task 2 Step 7 — they are replaced by the state.

- [ ] **Step 4: Run the tests**

```bash
./scripts/test.sh
```

Expected: PASS with no screenshot diffs. `anchor` is today on every path in this plan, so every rendered surface is byte-identical to Task 5.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TideDetailView.swift Slackwater/CurrentDetailView.swift \
        Slackwater/DerivedGateDetailView.swift Slackwater/OnlineGateDetailView.swift
git commit -m "feat: detail views hold the window anchor"
```

---

### Task 7: `coversStrip` becomes `covers(anchor:today:)`

The online-gate coverage check re-derives the window. It calls `Timeline.window` instead, and the UI-test seed follows.

**Files:**
- Modify: `Slackwater/ChsCurrentGate.swift:168-179`
- Modify: `Slackwater/SlackwaterApp.swift:60-70` (`seedOnlineWindow`), `:1533`
- Modify: `Slackwater/OnlineGateDetailView.swift:44`, `:103`
- Test: `SlackwaterTests/ChsCurrentGateTests.swift:150-160`

**Interfaces:**
- Consumes: `Timeline.window(anchor:today:)`
- Produces: `ChsOnlineWindow.covers(anchor: Date, today: Date) -> Bool` (replaces `coversStrip(now:)`)

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/ChsCurrentGateTests.swift`:

```swift
/// A 30-day fetched window covers every anchor whose own 7.5-day strip fits
/// inside it — 30 − 7.5 ≈ 22 days out — and honestly fails past that.
func testCoversHoldsForThreeWeeksOfAnchors() {
    let tz = TimeZone(identifier: "America/Vancouver")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let today = cal.startOfDay(for: Date())
    let w = Timeline.window(anchor: today, today: today)
    let window = ChsOnlineWindow(
        stationID: "test", iwlsName: "Test", timezone: tz.identifier,
        fetchedAt: Date(), start: w.start,
        end: today.addingTimeInterval(30 * 86_400),
        floodDirection: 0, ebbDirection: 180, times: [], speeds: [])

    XCTAssert(window.covers(anchor: today, today: today))
    XCTAssert(window.covers(anchor: today.addingTimeInterval(22 * 86_400), today: today),
              "22 days out still fits its 7.5-day strip inside 30 days of samples")
    XCTAssertFalse(window.covers(anchor: today.addingTimeInterval(24 * 86_400), today: today),
                   "past the edge it must fail, not silently render a hole")
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./scripts/test.sh
```

Expected: compile failure — `value of type 'ChsOnlineWindow' has no member 'covers'`.

- [ ] **Step 3: Rewrite the coverage check**

Replace `ChsCurrentGate.swift:168-179`:

```swift
    /// Does the stored window cover the FULL strip `Timeline` would build for
    /// `anchor`? The window is computed by `Timeline.window`, never re-derived
    /// here — with a conditional back-pad, a second derivation drifts, and the
    /// failure mode is this returning true for a window with a hole in it,
    /// which renders as a strip with a dead zone.
    func covers(anchor: Date, today: Date) -> Bool {
        let need = Timeline.window(anchor: anchor, today: today)
        return start <= need.start && end >= need.end
    }
```

- [ ] **Step 4: Update the three callers**

`OnlineGateDetailView.swift:44`:

```swift
        guard let window, window.covers(anchor: anchor, today: todayLocal(tz)) else { return nil }
```

`OnlineGateDetailView.swift:103`:

```swift
            if window?.covers(anchor: anchor, today: todayLocal(tz)) != true, net.online { fetchNow() }
```

`SlackwaterApp.swift:1533`:

```swift
        if let onlineWindow, onlineWindow.covers(anchor: todayLocal(gate.tz), today: todayLocal(gate.tz)) {
```

- [ ] **Step 5: Make `seedOnlineWindow` use the same definition**

`SlackwaterApp.swift:60-70` — replace the two manual `addingTimeInterval` lines:

```swift
    let today = todayLocal(gate.tz)
    let w = Timeline.window(anchor: today, today: today)
    let start = w.start, end = w.end
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
./scripts/test.sh
```

Expected: PASS, including `ChsCurrentGateTests` and the `testOnlineGateLiveFetch` skip in the fast plan.

- [ ] **Step 7: Commit**

```bash
git add Slackwater/ChsCurrentGate.swift Slackwater/SlackwaterApp.swift \
        Slackwater/OnlineGateDetailView.swift SlackwaterTests/ChsCurrentGateTests.swift
git commit -m "refactor: online-gate coverage asks Timeline for the window"
```

---

### Task 8: The 30-day fetch, merged on save

The fetch widens to 30 days and stored windows union rather than replace, so paging back does not refetch what you just had.

**Files:**
- Modify: `Slackwater/ChsFitService.swift:496-547` (`fetchOnlineWindow`)
- Modify: `Slackwater/ChsCurrentGate.swift:135-145` (`ChsModelStore.saveOnline`)
- Test: `SlackwaterTests/ChsCurrentGateTests.swift`

**Interfaces:**
- Consumes: `Timeline.window(anchor:today:)`, `ChsFitService.chunkPlan(days:end:)`
- Produces:
  - `Timeline.onlineFetchDays: Double` (30)
  - `ChsOnlineWindow.merging(_ other: ChsOnlineWindow, prunedBefore: Date) -> ChsOnlineWindow`
  - `ChsFitService.fetchOnlineWindow(for:from:) async throws -> ChsOnlineWindow` — `from` is the anchor the fetch starts at.

- [ ] **Step 1: Write the failing tests**

```swift
/// Merging must union by timestamp, not append — a refetch overlapping the
/// stored window would otherwise duplicate every sample in the overlap and
/// hand `sampleEvents` a doubled series.
func testMergingUnionsByTimestampAndWidensTheWindow() {
    let t0 = Date().timeIntervalSince1970.rounded(.down)
    func win(_ times: [Double], _ speeds: [Double], _ s: Date, _ e: Date) -> ChsOnlineWindow {
        ChsOnlineWindow(stationID: "g", iwlsName: "G", timezone: "America/Vancouver",
                        fetchedAt: Date(), start: s, end: e,
                        floodDirection: 0, ebbDirection: 180, times: times, speeds: speeds)
    }
    let a = win([t0, t0 + 900, t0 + 1800], [1, 2, 3],
                Date(timeIntervalSince1970: t0), Date(timeIntervalSince1970: t0 + 1800))
    let b = win([t0 + 1800, t0 + 2700], [3, 4],
                Date(timeIntervalSince1970: t0 + 1800), Date(timeIntervalSince1970: t0 + 2700))

    let m = a.merging(b, prunedBefore: Date(timeIntervalSince1970: t0 - 1))
    XCTAssertEqual(m.times, [t0, t0 + 900, t0 + 1800, t0 + 2700], "no duplicate at the seam")
    XCTAssertEqual(m.speeds, [1, 2, 3, 4])
    XCTAssertEqual(m.end, Date(timeIntervalSince1970: t0 + 2700), "the window widens")
    XCTAssertEqual(m.start, Date(timeIntervalSince1970: t0))
}

/// Past current has no value once it is past, and pruning is what keeps the
/// file from growing in the direction nobody looks.
func testMergingPrunesTheStalePast() {
    let t0 = Date().timeIntervalSince1970.rounded(.down)
    let a = ChsOnlineWindow(stationID: "g", iwlsName: "G", timezone: "America/Vancouver",
                            fetchedAt: Date(), start: Date(timeIntervalSince1970: t0),
                            end: Date(timeIntervalSince1970: t0 + 2700),
                            floodDirection: 0, ebbDirection: 180,
                            times: [t0, t0 + 900, t0 + 1800, t0 + 2700], speeds: [1, 2, 3, 4])
    let m = a.merging(a, prunedBefore: Date(timeIntervalSince1970: t0 + 1800))
    XCTAssertEqual(m.times, [t0 + 1800, t0 + 2700])
    XCTAssertEqual(m.speeds, [3, 4])
    XCTAssertEqual(m.start, Date(timeIntervalSince1970: t0 + 1800),
                   "start follows the prune, or coverage would lie")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./scripts/test.sh
```

Expected: compile failure — `value of type 'ChsOnlineWindow' has no member 'merging'`.

- [ ] **Step 3: Add `merging`**

In `Slackwater/ChsCurrentGate.swift`, in `extension ChsOnlineWindow` (beside `points`):

```swift
    /// Union `other`'s samples into this window by timestamp and widen the
    /// bounds, dropping everything before `prunedBefore`.
    ///
    /// Union, not append: the fetch chunks land on an absolute 7-day grid, so
    /// a refetch routinely overlaps what is already stored, and appending
    /// would hand `sampleEvents` a series with every overlapped sample twice.
    ///
    /// `start` follows the prune. If it did not, `covers` would keep claiming
    /// a range whose samples had just been deleted.
    func merging(_ other: ChsOnlineWindow, prunedBefore: Date) -> ChsOnlineWindow {
        let cut = prunedBefore.timeIntervalSince1970
        var byTime = Dictionary(zip(times, speeds), uniquingKeysWith: { _, b in b })
        for (t, v) in zip(other.times, other.speeds) { byTime[t] = v }
        let kept = byTime.filter { $0.key >= cut }.sorted { $0.key < $1.key }
        return ChsOnlineWindow(
            stationID: stationID, iwlsName: other.iwlsName, timezone: timezone,
            fetchedAt: other.fetchedAt,
            start: max(min(start, other.start), prunedBefore),
            end: max(end, other.end),
            floodDirection: other.floodDirection, ebbDirection: other.ebbDirection,
            times: kept.map(\.key), speeds: kept.map(\.value))
    }
```

- [ ] **Step 4: Merge inside `saveOnline`**

`ChsModelStore.saveOnline` (`ChsCurrentGate.swift:135`) becomes:

```swift
    /// Merges into whatever is already on disk rather than replacing it.
    /// Replacing would make the Plan B prefetch destructive: fetching the next
    /// block would discard the current one, and paging back would refetch what
    /// the user just had.
    ///
    // ponytail: no forward cap. A 30-day block is ~2880 samples (~90KB JSON);
    // someone who pages a year out accumulates ~1MB on a gate they evidently
    // care about, and -chsResetModels already clears it. Add a cap when a real
    // file gets big.
    static func saveOnline(_ window: ChsOnlineWindow) throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: window.timezone) ?? .current
        let cut = cal.startOfDay(for: appNow())
            .addingTimeInterval(-Timeline.backHours * 3600)
        let merged = loadOnline(window.stationID)?.merging(window, prunedBefore: cut) ?? window
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(merged).write(to: onlineUrl(window.stationID), options: .atomic)
    }
```

Keep whatever directory/URL expressions the existing body uses — only the merge and the encode target change.

- [ ] **Step 5: Widen the fetch to 30 days**

In `Slackwater/TimelineStrip.swift`, add to `enum Timeline`:

```swift
    /// How much an online gate fetches in one go. Four times the strip it
    /// needs, so ordinary paging lands in cache instead of on the network —
    /// the gates people plan a passage around are exactly the ones that must
    /// not need a signal to look at next month.
    static let onlineFetchDays = 30.0
```

In `ChsFitService.fetchOnlineWindow` (line 496), change the signature and the window computation:

```swift
    nonisolated static func fetchOnlineWindow(for gate: ChsCurrentGateInfo,
                                             from anchor: Date? = nil) async throws -> ChsOnlineWindow {
```

and replace the `today` / `start` / `end` / `plan` block (lines ~517-524):

```swift
        let today = todayLocal(gate.tz)
        let from = anchor ?? today
        let start = Timeline.window(anchor: from, today: today).start
        let end = from.addingTimeInterval(Timeline.onlineFetchDays * 86_400)
        // Same absolute 7-day grid the fit path uses, so chunk identity (and
        // the cache file behind it) is stable and an overlapping refetch is free.
        let plan = Self.chunkPlan(days: end.timeIntervalSince(start) / 86_400, end: end)
```

Leave the sample clamping, the `emptySeries` guard, and the `saveOnline` + `onlineFetchStamp` block below it exactly as they are.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
./scripts/test.sh
```

Then the live-network check, which the fast plan skips:

```bash
./scripts/test.sh --full
```

Expected: PASS, including `ScreenshotTests/testOnlineGateLiveFetch()`. That test hits IWLS for real and is the only thing that proves a 30-day chunk plan actually comes back populated.

- [ ] **Step 7: Commit**

```bash
git add Slackwater/ChsFitService.swift Slackwater/ChsCurrentGate.swift \
        Slackwater/TimelineStrip.swift SlackwaterTests/ChsCurrentGateTests.swift
git commit -m "feat: online gates fetch 30 days and merge on save"
```

---

## Done when

- The schedule list on every detail view shows seven day-groups.
- The strip pans a week forward from today, with the 48h look-back intact.
- `./scripts/test.sh` and `./scripts/test.sh --full` both green.
- No visual change other than the longer list and strip — the anchor is today on every path in this plan.

Then open a PR (branch-and-PR, never merge your own) and pick up Plan B:
`docs/superpowers/plans/2026-08-11-week-range-bar-and-picker.md`.
