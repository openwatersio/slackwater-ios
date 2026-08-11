# Week Range Bar & Date Picker — Plan B

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A range bar heading the schedule card that states the span on screen and, when tapped, presents a date picker that moves the window's anchor.

**Architecture:** A `WeekRangeBar` view sits at the top of the schedule card, above the first day group. Tapping it presents a sheet holding a native graphical `DatePicker` bound to the anchor. Opening the sheet on an online gate speculatively fetches the next 30-day block, on the assumption the user is heading forward; landing on a week the merged window still does not cover reuses the existing refetch-or-honesty-card path.

**Tech Stack:** Swift 6 / SwiftUI, XCTest, XcodeGen, `scripts/test.sh`.

**Spec:** `docs/superpowers/specs/2026-08-11-week-window-and-date-anchor-design.md` §5

**Depends on:** Plan A (`2026-08-11-week-window-anchor.md`) — complete and merged. This plan assumes `TimelineData.anchor`, `Timeline.window`, `TimelineData.scheduleRange`, `ChsOnlineWindow.covers(anchor:today:)`, `merging(_:prunedBefore:)`, `fetchOnlineWindow(for:from:)`, and each detail view's `@State anchor` + `rebuild()` all exist.

## Global Constraints

- **Never commit to `main` in this repo.** Branch, push, PR, never merge your own.
- **`pph` is not to be touched.**
- **Chart labels stay fixed-size.** The range bar is chrome *outside* the canvas, so it uses Dynamic Type fonts normally (`.caption`, `.subheadline`) — the fixed-size rule applies only to labels drawn inside `TimelineCanvas`.
- **Minimum font size 14px** except `.eyebrow` at 12 — mirrors the web's `tokens.test.ts` rule. `MonoLabel` already complies.
- **Colour is state, form is kind.** The range bar carries no direction colour.
- **Run tests with `./scripts/test.sh`.** Never run a bare `xcodebuild` while tests are in flight.
- Commit after every task.

---

### Task 1: The range label

The string the bar prints. Pure function, fully unit-testable, no UI — worth its own task because every boundary case (month, year) is a place to get it silently wrong.

**Files:**
- Modify: `Slackwater/Theme.swift` (beside `monthDay`, `clockTime`, the other formatters)
- Test: `SlackwaterTests/TimelineTests.swift`

**Interfaces:**
- Consumes: `Timeline.scheduleDays` (Plan A)
- Produces: `func weekRangeLabel(anchor: Date, tz: TimeZone) -> String`

**The inclusive-last-day rule.** `scheduleRange` runs `anchor … anchor + 168h`, so the seven day-groups on screen are `anchor` through `anchor + 6 days`. The label names the **last day shown**, not the exclusive upper bound: anchoring on Aug 11 shows Aug 11–17 and the bar says `Aug 11 – 17`. Printing `Aug 11 – 18` would name a day that is not on screen, which is the exact failure the spec rejected "Week of Aug 9 – 16" for.

- [ ] **Step 1: Write the failing test**

```swift
// MARK: - The range bar label (spec §5)

func testWeekRangeLabelNamesTheLastDayShown() {
    let tz = TimeZone(identifier: "America/Vancouver")!
    // Anchor Aug 11 → groups Aug 11…Aug 17. The label names Aug 17, the last
    // day ON SCREEN, never the exclusive Aug 18 boundary.
    XCTAssertEqual(weekRangeLabel(anchor: vancouverMidnight(2026, 8, 11), tz: tz),
                   "Aug 11 – 17")
}

func testWeekRangeLabelSpellsTheMonthWhenItChanges() {
    let tz = TimeZone(identifier: "America/Vancouver")!
    XCTAssertEqual(weekRangeLabel(anchor: vancouverMidnight(2026, 8, 28), tz: tz),
                   "Aug 28 – Sep 3")
}

func testWeekRangeLabelShowsTheYearOnlyWhenItChanges() {
    let tz = TimeZone(identifier: "America/Vancouver")!
    XCTAssertEqual(weekRangeLabel(anchor: vancouverMidnight(2026, 12, 29), tz: tz),
                   "Dec 29 – Jan 4, 2027")
    XCTAssertEqual(weekRangeLabel(anchor: vancouverMidnight(2026, 6, 1), tz: tz),
                   "Jun 1 – 7", "a same-year range never prints a year")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./scripts/test.sh
```

Expected: compile failure — `cannot find 'weekRangeLabel' in scope`.

- [ ] **Step 3: Implement**

In `Slackwater/Theme.swift`, beside the other formatters:

```swift
/// The schedule's span, as the range bar prints it: `Aug 11 – 17`,
/// `Aug 28 – Sep 3`, `Dec 29 – Jan 4, 2027`.
///
/// The second date is the LAST DAY SHOWN — `anchor + 6` — not the exclusive
/// `scheduleRange` upper bound. The window is rolling rather than a calendar
/// week, so this bar is the only thing on screen that says what span you are
/// looking at; naming a day that is not in the list below it would be the
/// same defect as calling a Tue→Mon window "Week of Aug 9 – 16".
///
/// The month repeats only when it changes, and the year appears only when the
/// range crosses one — a bar that printed "2026" every week would be teaching
/// the user to stop reading it.
func weekRangeLabel(anchor: Date, tz: TimeZone) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let last = cal.date(byAdding: .day, value: Int(Timeline.scheduleDays) - 1, to: anchor)!

    let f = DateFormatter()
    f.timeZone = tz
    f.locale = Locale(identifier: "en_US_POSIX")

    f.dateFormat = "MMM d"
    let head = f.string(from: anchor)

    let sameMonth = cal.isDate(anchor, equalTo: last, toGranularity: .month)
    let sameYear = cal.isDate(anchor, equalTo: last, toGranularity: .year)
    f.dateFormat = sameYear ? (sameMonth ? "d" : "MMM d") : "MMM d, yyyy"
    return "\(head) – \(f.string(from: last))"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
./scripts/test.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/Theme.swift SlackwaterTests/TimelineTests.swift
git commit -m "feat: the week range label"
```

---

### Task 2: `ScheduleCard` — one card container, four callers

All four detail views wrap `MultiDaySchedule` in an identical `.background` / `.clipShape` / `.overlay` / `.padding` stack. The bar goes inside that card, so the container becomes shared first — otherwise the bar gets pasted four times.

**Files:**
- Create: `Slackwater/ScheduleCard.swift`
- Modify: `Slackwater/TideDetailView.swift`, `Slackwater/CurrentDetailView.swift`, `Slackwater/DerivedGateDetailView.swift`, `Slackwater/OnlineGateDetailView.swift` (each `scheduleCard`)
- Modify: `project.yml` is **not** touched — XcodeGen globs `Slackwater/**`, so a new file in that directory is picked up by `xcodegen generate`, which `scripts/test.sh` runs.

**Interfaces:**
- Consumes: `MultiDaySchedule`, `ScheduleEntry`, `TimelineDay`, `TimelineData`
- Produces:

```swift
struct ScheduleCard: View {
    let entries: [ScheduleEntry]
    let data: TimelineData
    let tz: TimeZone
    let scrubTime: Date
    let onTap: (Date) -> Void
    let onPickDate: () -> Void
}
```

- [ ] **Step 1: Write the failing UI test**

Add to `SlackwaterUITests/ScreenshotTests.swift`. This file has no `launch()` helper — every test builds `XCUIApplication()` itself — and element lookups by identifier go through `app.descendants(matching: .any)[...].firstMatch`, not `app.buttons[...]`. `openFridayHarbor(_:)` is a real private helper at `:147`.

```swift
/// The range bar heads the schedule card on every scrubable detail, and it
/// says what span the list below it covers.
func testWeekRangeBarHeadsTheSchedule() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-seedGate"]
    app.launch()
    XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

    openFridayHarbor(app)
    let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
    XCTAssert(bar.waitForExistence(timeout: 10), "no range bar above the schedule")
    XCTAssert(bar.label.contains("–"), "the bar states a span, got '\(bar.label)'")
}
```

Note `openFridayHarbor` already asserts `app.staticTexts["Today"]` appears — that stays true, since the first day group is still today's.

- [ ] **Step 2: Run the test to verify it fails**

```bash
./scripts/test.sh
```

Expected: FAIL — `week-range-bar` never exists.

- [ ] **Step 3: Create `ScheduleCard`**

```swift
// Slackwater — GPL v3. The schedule card: a range bar naming the span, and the
// day-grouped event list under it. Extracted from the four detail views, which
// each carried a byte-identical copy of the card chrome — the bar had to land
// in one place, not four.
import SwiftUI

struct ScheduleCard: View {
    let entries: [ScheduleEntry]
    let data: TimelineData
    let tz: TimeZone
    let scrubTime: Date
    let onTap: (Date) -> Void
    let onPickDate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WeekRangeBar(anchor: data.anchor, today: data.today, tz: tz, onTap: onPickDate)
            Divider().overlay(Color.white.opacity(0.08))
            MultiDaySchedule(entries: entries, tz: tz, anchor: data.anchor,
                             today: data.today, days: data.days,
                             scrubTime: scrubTime, onTap: onTap)
        }
        .background(SN.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
        .padding(.horizontal, 16)
    }
}

/// The span on screen, and the way to change it.
///
/// It heads the SCHEDULE card rather than sitting in the scrub card: it names
/// the list's range, and putting it in the scrub card would land it below the
/// swipe hint, the readout and the tide-at-port link — much further down the
/// page than "just under the scrubber" suggests — while reopening the
/// 2026-08-03 rule that the `when` row is always last in that card.
struct WeekRangeBar: View {
    let anchor: Date
    let today: Date
    let tz: TimeZone
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.7))
                Text(weekRangeLabel(anchor: anchor, tz: tz))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                if anchor != today {
                    // The bar is the clearest statement on screen that you are
                    // not looking at this week, so it carries the way back.
                    Text("not this week")
                        .font(.caption2)
                        .foregroundStyle(SN.amber)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SN.foam.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("week-range-bar")
        .accessibilityLabel("Showing \(weekRangeLabel(anchor: anchor, tz: tz)). Tap to choose a date.")
    }
}
```

- [ ] **Step 4: Collapse the four `scheduleCard` bodies onto it**

`CurrentDetailView` (and the same shape in the other three, each with its own `scheduleEntries` call and, in `OnlineGateDetailView`, its extra `window` argument):

```swift
    private func scheduleCard(_ tl: TimelineData) -> some View {
        ScheduleCard(entries: scheduleEntries(tl), data: tl, tz: tz,
                     scrubTime: scrubTime,
                     onTap: { scrubTime = $0 },
                     onPickDate: { showPicker = true })
    }
```

Add `@State private var showPicker = false` to each of the four views. The sheet itself lands in Task 3 — for now the flag is set and nothing reads it.

- [ ] **Step 5: Run the test to verify it passes**

```bash
./scripts/test.sh
```

Expected: PASS. Screenshot tests that capture a detail view will show the new bar; review the images in `$SHOT_DIR` and re-baseline if the suite pins them.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/ScheduleCard.swift Slackwater/TideDetailView.swift \
        Slackwater/CurrentDetailView.swift Slackwater/DerivedGateDetailView.swift \
        Slackwater/OnlineGateDetailView.swift SlackwaterUITests/ScreenshotTests.swift
git commit -m "feat: a range bar heads the schedule card"
```

---

### Task 3: The picker sheet

**Files:**
- Modify: `Slackwater/ScheduleCard.swift` (add `WeekPickerSheet`)
- Modify: the four detail views (present the sheet, apply the anchor)
- Test: `SlackwaterUITests/ScreenshotTests.swift`

**Interfaces:**
- Consumes: `todayLocal(_:)`, each view's `anchor` state and `rebuild()`
- Produces:

```swift
struct WeekPickerSheet: View {
    @Binding var anchor: Date
    let tz: TimeZone
    let onOpen: () -> Void      // the prefetch hook — Task 4 fills it
    let onPick: (Date) -> Void
}
```

- [ ] **Step 1: Write the failing UI test**

```swift
/// Tapping the bar opens the picker; picking a date moves the window and the
/// bar says so.
func testPickingADateMovesTheWindow() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-seedGate"]
    app.launch()
    XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

    openFridayHarbor(app)
    let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
    XCTAssert(bar.waitForExistence(timeout: 10))
    let before = bar.label

    bar.tap()
    let picker = app.descendants(matching: .any)["week-picker"].firstMatch
    XCTAssert(picker.waitForExistence(timeout: 5))

    // The graphical DatePicker's forward-month button, then a day cell.
    app.buttons["Next Month"].firstMatch.tap()
    app.collectionViews.buttons.element(boundBy: 10).tap()
    app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()

    XCTAssertNotEqual(bar.label, before, "the bar must follow the anchor")
    XCTAssert(app.staticTexts["not this week"].waitForExistence(timeout: 5))
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./scripts/test.sh
```

Expected: FAIL — `week-picker` never exists.

- [ ] **Step 3: Add `WeekPickerSheet`**

In `Slackwater/ScheduleCard.swift`:

```swift
/// A native graphical `DatePicker`, in a sheet.
///
/// Native rather than a hand-rolled month grid: Dynamic Type, VoiceOver, and
/// localization arrive for nothing, and this app adds no dependency it can
/// avoid. Unbounded in both directions — the engine is deterministic, so last
/// Saturday costs exactly what next March costs. Online gates get the SAME
/// unbounded picker rather than a greyed-out range: two classes of station that
/// visibly disagree about how far the future goes would leave the user to work
/// out why, where an honest failure at the moment of asking says it in words.
struct WeekPickerSheet: View {
    @Binding var anchor: Date
    let tz: TimeZone
    let onOpen: () -> Void
    let onPick: (Date) -> Void

    @State private var draft = Date()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("Week starting", selection: $draft,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(SN.go)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("week-picker")
                Spacer()
            }
            .background(SN.page.ignoresSafeArea())
            .navigationTitle("Choose a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") {
                        var cal = Calendar(identifier: .gregorian)
                        cal.timeZone = tz
                        let picked = cal.startOfDay(for: draft)
                        anchor = picked
                        onPick(picked)
                        dismiss()
                    }
                    .accessibilityIdentifier("week-picker-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            draft = anchor
            // Fire the speculative fetch as the sheet appears, not when a date
            // is chosen: by the time the user has picked, the round trip has
            // had the whole browsing interaction to land.
            onOpen()
        }
    }
}
```

- [ ] **Step 4: Present it from the four views**

In each, alongside the existing sheets:

```swift
        .sheet(isPresented: $showPicker) {
            WeekPickerSheet(anchor: $anchor, tz: tz,
                            onOpen: prefetchNextBlock,
                            onPick: { _ in rebuild() })
        }
```

For the three non-online views, `prefetchNextBlock` is a no-op — add it as such so the four call sites read identically:

```swift
    /// Bundled and fitted stations are constituents: every date is already
    /// local. Only an online gate has anything to fetch.
    private func prefetchNextBlock() {}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
./scripts/test.sh
```

Expected: PASS. If the `Next Month` button's accessibility label differs on the CI simulator's iOS version, read the real label from the failure's element tree and fix the test — do not weaken the assertion.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/ScheduleCard.swift Slackwater/TideDetailView.swift \
        Slackwater/CurrentDetailView.swift Slackwater/DerivedGateDetailView.swift \
        Slackwater/OnlineGateDetailView.swift SlackwaterUITests/ScreenshotTests.swift
git commit -m "feat: the date picker moves the window anchor"
```

---

### Task 4: Online gates — prefetch and honest failure

**Files:**
- Modify: `Slackwater/OnlineGateDetailView.swift`
- Test: `SlackwaterTests/ChsCurrentGateTests.swift`, `SlackwaterUITests/ScreenshotTests.swift`

**Interfaces:**
- Consumes: `ChsFitService.fetchOnlineWindow(for:from:)`, `ChsOnlineWindow.covers(anchor:today:)`, `ChsOnlineWindow.merging(_:prunedBefore:)` (all Plan A)
- Produces: `OnlineGateDetailView.prefetchNextBlock()`, and an anchor-change refetch

- [ ] **Step 1: Write the failing test**

```swift
/// The prefetch aims at the block AFTER what is stored — the point is that a
/// user paging forward lands in cache, so re-fetching the stored range would
/// be pure waste.
func testPrefetchAnchorIsTheStoredWindowsEdge() {
    let tz = TimeZone(identifier: "America/Vancouver")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let today = cal.startOfDay(for: Date())
    let end = today.addingTimeInterval(30 * 86_400)
    let w = ChsOnlineWindow(stationID: "g", iwlsName: "G", timezone: tz.identifier,
                            fetchedAt: Date(), start: today, end: end,
                            floodDirection: 0, ebbDirection: 180, times: [], speeds: [])
    XCTAssertEqual(prefetchAnchor(after: w, tz: tz), cal.startOfDay(for: end))
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./scripts/test.sh
```

Expected: compile failure — `cannot find 'prefetchAnchor' in scope`.

- [ ] **Step 3: Add the anchor helper**

In `Slackwater/ChsCurrentGate.swift`, at file scope beside the other online-window helpers:

```swift
/// Where the next speculative fetch starts: the local midnight at the stored
/// window's far edge. Blocks land on `chunkPlan`'s absolute 7-day grid, so
/// the overlap this creates costs nothing and the seam can never leave a gap.
func prefetchAnchor(after window: ChsOnlineWindow, tz: TimeZone) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.startOfDay(for: window.end)
}
```

- [ ] **Step 4: Implement the prefetch in `OnlineGateDetailView`**

Replace the no-op `prefetchNextBlock` stub from Task 3 Step 4 in this view only:

```swift
    /// Fired when the picker OPENS, not when a date is chosen: the assumption
    /// is that someone opening a calendar is heading forward, and giving the
    /// round trip the whole browsing interaction is the difference between a
    /// spinner and no spinner.
    ///
    /// Nothing here touches this view's state on success. `fetchOnlineWindow`
    /// merges, saves, and bumps `ChsFitService.onlineFetchStamp`, which this
    /// view and the list card already observe — the fetch lands and the UI
    /// updates itself. A failure is silent BY DESIGN: the user has not asked
    /// for that week yet, so there is nothing to apologise for. If they do
    /// land there and it is missing, `applyAnchor` below says so properly.
    private func prefetchNextBlock() {
        guard let window, net.online, !fetching else { return }
        let from = prefetchAnchor(after: window, tz: gate.tz)
        Task { try? await ChsFitService.fetchOnlineWindow(for: gate, from: from) }
    }
```

- [ ] **Step 5: Refetch when the anchor lands outside the merged window**

Change this view's `onPick` closure to route through a new method rather than a bare `rebuild()`:

```swift
        .sheet(isPresented: $showPicker) {
            WeekPickerSheet(anchor: $anchor, tz: tz,
                            onOpen: prefetchNextBlock,
                            onPick: { _ in applyAnchor() })
        }
```

and add:

```swift
    /// The anchor moved. If the merged window covers it we are done; if not,
    /// this is the same situation `.onAppear` already handles — fetch when
    /// online, show the amber honesty card when that throws.
    private func applyAnchor() {
        rebuild()
        if window?.covers(anchor: anchor, today: todayLocal(tz)) != true {
            if net.online { fetchNow(from: anchor) } else { fetchFailed = true }
        }
    }
```

Give `fetchNow` the anchor it should fetch from:

```swift
    private func fetchNow(from anchor: Date? = nil) {
        guard !fetching else { return }
        fetching = true
        fetchFailed = false
        Task { @MainActor in
            do {
                let fresh = try await ChsFitService.fetchOnlineWindow(for: gate, from: anchor)
                window = fresh
                fetching = false
                rebuild()
            } catch {
                fetching = false
                fetchFailed = true
            }
        }
    }
```

The existing `.onAppear` call site stays `fetchNow()` — no argument, meaning today.

- [ ] **Step 6: Write the offline-paging UI test**

Model the launch arguments and the navigation on `testOnlineGateFetchedRendersDetail` (`:2355`), which is the existing seeded-online-gate test. The offline flag is `-networkKillSwitch`, the seeded gate id is `chs-sechelt-rapids`, it is reached by searching its alias "skookumchuck", and the honesty card's identifier is `online-honesty-card`.

```swift
/// Paging an online gate to a week nobody has downloaded, with no network, must
/// SAY so — not render an empty strip that reads as slack water all week.
func testOnlineGatePagedBeyondItsWindowOffline() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-seedGate", "-seedOnlineWindow", "chs-sechelt-rapids",
                           "-networkKillSwitch",
                           "-fixLat", "48.4235", "-fixLon", "-123.3705"]
    app.launch()
    XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

    openSearch(app, "skookumchuck")
    let result = app.staticTexts["Sechelt Rapids"].firstMatch
    XCTAssert(result.waitForExistence(timeout: 5))
    result.tap()
    XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
              "the seeded window should render before we page off it")

    app.descendants(matching: .any)["week-range-bar"].firstMatch.tap()
    XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch
        .waitForExistence(timeout: 5))
    app.buttons["Next Month"].firstMatch.tap()
    app.buttons["Next Month"].firstMatch.tap()   // two months out — past the 30-day window
    app.collectionViews.buttons.element(boundBy: 20).tap()
    app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()

    XCTAssert(app.descendants(matching: .any)["online-honesty-card"].firstMatch
        .waitForExistence(timeout: 5),
              "an uncovered week offline must show the honesty card, never a dead strip")
}
```

Add this test to the **skipped** list in `TestPlans/Slackwater.xctestplan` only if it proves slow; it uses no network, so it should stay in the fast plan.

- [ ] **Step 7: Run the tests**

```bash
./scripts/test.sh
./scripts/test.sh --full
```

Expected: both green. The full plan is required here — `testOnlineGateLiveFetch` is the only check that a real 30-day-plus-prefetch fetch comes back populated from IWLS.

- [ ] **Step 8: Commit**

```bash
git add Slackwater/OnlineGateDetailView.swift Slackwater/ChsCurrentGate.swift \
        SlackwaterTests/ChsCurrentGateTests.swift SlackwaterUITests/ScreenshotTests.swift
git commit -m "feat: online gates prefetch on picker open, and say so when a week is missing"
```

---

## Done when

- Every scrubable detail view has a range bar above its schedule saying e.g. `Aug 11 – 17`.
- Tapping it opens a graphical date picker; picking a date moves the window, and the bar and list follow.
- Off the current week the bar marks itself, and return-to-now brings the whole window back.
- On an online gate: opening the picker starts the next block downloading; landing on an uncovered week fetches it, or shows the honesty card when offline.
- `./scripts/test.sh` and `./scripts/test.sh --full` both green.

Then open a PR. Never merge your own.
