# Week Range Bar & Date Picker — Plan B

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A range bar heading the schedule card that states the span on screen and, when tapped, presents a date picker that moves the window's anchor.

**Architecture:** A `WeekRangeBar` view sits at the top of the schedule card, above the first day group. Tapping it presents a sheet holding a native graphical `DatePicker` bound to the anchor. Opening the sheet on an online gate speculatively fetches the next 30-day block, on the assumption the user is heading forward; landing on a week the merged window still does not cover reuses the existing refetch-or-honesty-card path.

**Tech Stack:** Swift 6 / SwiftUI, XCTest, XcodeGen, `scripts/test.sh`.

**Spec:** `docs/superpowers/specs/2026-08-11-week-window-and-date-anchor-design.md` §5

**Depends on:** Plan A (`2026-08-11-week-window-anchor.md`) — complete and merged. This plan assumes `TimelineData.anchor`, `Timeline.window`, `TimelineData.scheduleRange`, `ChsOnlineWindow.covers(anchor:today:)`, `merging(_:prunedBefore:)`, `fetchOnlineWindow(for:from:)`, and each detail view's `@State anchor` all exist. Note `rebuild()` exists on **three** of the four views — `TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView`, which store `timeline` in `@State`. `OnlineGateDetailView` computes its `timeline`, so it has no `rebuild()` and needs none; setting `anchor` is sufficient there.

## Known before you start

Plan A shipped with `anchor = today` on every path, so a whole class of bug is currently unreachable. These five were found by Plan A's reviews and deliberately left, because the anchor never moves until *this* plan moves it. Each becomes live the day the picker lands. None is speculative — every one has a named site.

1. **`fetchOnlineWindow` returns the freshly-fetched block, not the merged-on-disk window.** `saveOnline` merges and persists the union, but the function hands its caller only what it just fetched, and `OnlineGateDetailView.fetchNow` assigns that to `@State`. So immediately after a fetch the view holds a *narrower* window than the one on disk, and `covers` can answer false for a week the app actually has. One line to fix — return the merged window, or reload it — but decide it deliberately.

2. **"Newest fetch wins" when two blocks are disjoint.** `merging` discards the stored block and keeps the incoming one, because `ChsOnlineWindow` carries a single `start`/`end` and cannot represent a hole. On a far-forward page that discards *today's* block — the one the user is most likely to page back to — so returning refetches ~30 days. Whether that is the right survivor is this plan's decision, not Plan A's.

3. **The strip does not re-center when the anchor moves.** `TimelineScrubber.Coordinator.didInitialCenter` is one-shot. On an anchor change, `updateUIView` sets `contentOffset` from a `scrubTime` that is off the new window, UIScrollView clamps to 0, and `scrollViewDidScroll` overwrites `scrubTime` with the left-edge time. It self-corrects to something sane rather than breaking, but "the picker sets `scrubTime` too" is a decision this plan owns and does not currently state.

4. **`scheduleRange` counts 168 *absolute* hours**, so a week containing a spring-forward ends at 01:00 of day 7 and the schedule renders an **8th partial day-group**. That breaks the "seven days" promise twice a year, and it will be more visible once a picker lets someone land on such a week deliberately. Making it calendar-correct ripples through the range's semantics, four view filters and two tests — which is why Plan A left it, not because it is fine.

5. **A past anchor still refetches on a return visit.** `saveOnline`'s prune cut is `min(Timeline.window(anchor: today, today: today).start, window.start)`, which protects the window being saved but not one saved earlier. Page back → today → back again, and the first past block has been pruned. Bounded backward retention is the fix, and Plan A's own `ponytail:` note declined to bound it forward, so the decision is open in both directions.

Two more, cheap and worth doing while you are in these files: the **UI-test seed is no longer hermetic** (`seedOnlineWindow` writes through the now-merging `saveOnline`, and the seeded test launches without `-chsResetModels` while the live-fetch test leaves a real window for the same gate — passing today by test ordering, not by design), and **`OnlineGateDetailView.onAppear` still reads a second clock** for its fetch-or-not question while `timeline` uses `tl.today`; different question, worst case is an honesty card rather than a hole, but it is the last split clock in the file.

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

### Task 2: `WeekRangeBar`, inside the scaffold's schedule card

> **Amended 2026-08-13.** This task originally created a `ScheduleCard` container by extracting identical card chrome from four detail views. **PR #60 ("ponytail-cuts") already did that** — `ScrubDetailScaffold.scheduleCard` in `Theme.swift` is the shared container and there is exactly one `MultiDaySchedule` call site. What remains is adding the bar to it, in one place. Task 3 is amended alongside: the scaffold owns the bar *and* the picker sheet, taking `@Binding var anchor` plus an `onPick` closure — mirroring how PR #60 already handles `onReturn`, which is caller-owned precisely because only the view can reset the anchor.

The bar heads the schedule card: above the first day group, below the scrub card. It names the span the list covers and, tapped, presents the picker.

That position is deliberate. Putting it *inside* the scrub card would land it below the swipe hint, `ScrubWhen` and the tide-at-port link — further down the page than "just under the scrubber" suggests — and would reopen `2026-08-03-detail-hero-and-scrub-order-design.md`'s rule that the `when` row is always last in that card. The bar is semantically the *list's* range, so it belongs to the list's card.

**Files:**
- Modify: `Slackwater/Theme.swift` — add `WeekRangeBar`, and render it at the top of `ScrubDetailScaffold.scheduleCard`
- No new file, and no detail-view changes in this task. The four views gain their `@State showPicker` / `$anchor` wiring in Task 3.

**Interfaces:**
- Consumes: `weekRangeLabel(anchor:tz:)` (Task 1), `TimelineData.anchor`, `TimelineData.today`
- Produces:

```swift
struct WeekRangeBar: View {
    let anchor: Date
    let today: Date
    let tz: TimeZone
    let onTap: () -> Void
}
```

`ScrubDetailScaffold` gains `let onPickDate: () -> Void`, passed straight through to the bar's `onTap`. Task 3 replaces that with the sheet the scaffold presents itself; keeping it a plain closure here means Task 2 ships a visible, testable bar without the picker existing yet.

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

- [ ] **Step 3: Render the bar in the scaffold's existing schedule card**

In `Slackwater/Theme.swift`, `ScrubDetailScaffold.scheduleCard(_:)` already wraps `MultiDaySchedule` in the card chrome. Put the bar above it, inside the same card:

```swift
    private func scheduleCard(_ tl: TimelineData) -> some View {
        VStack(spacing: 0) {
            WeekRangeBar(anchor: tl.anchor, today: tl.today, tz: tz, onTap: onPickDate)
            Divider().overlay(Color.white.opacity(0.08))
            // Both dates, never one: `anchor` keys the day groups (it is what
            // `days` offsets are relative to), `today` only says Today/Tomorrow.
            MultiDaySchedule(entries: entries(tl), tz: tz, anchor: tl.anchor,
                             today: tl.today, days: tl.days,
                             scrubTime: scrubTime, onTap: { scrubTime = $0 })
        }
        .background(SN.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
        .padding(.horizontal, 16)
    }
```

and add the closure to the scaffold's stored properties, beside `onReturn`:

```swift
    /// Tapping the range bar. Caller-owned for the same reason `onReturn` is:
    /// the anchor lives in the detail view, not here.
    let onPickDate: () -> Void
```

Then `WeekRangeBar` itself, in the same file below the scaffold:

```swift
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

- [ ] **Step 4: Give the four views a `showPicker` flag to pass in**

Each of `TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView` and `OnlineGateDetailView` already constructs `ScrubDetailScaffold(…)`. Add one argument to each call, beside the existing `onReturn:`:

```swift
                            onPickDate: { showPicker = true },
```

and `@State private var showPicker = false` to each view. The sheet lands in Task 3 — for now the flag is set and nothing reads it, which is deliberate: it lets this task ship a real, tappable, screenshot-testable bar without the picker existing.

Do **not** otherwise touch the views' bodies. PR #60 factored their card content into the scaffold's `card:`/`links:`/`bottom:` builders; this task adds one argument and one `@State`, nothing more.

- [ ] **Step 5: Run the test to verify it passes**

```bash
./scripts/test.sh
```

Expected: PASS. Screenshot tests that capture a detail view will show the new bar; review the images in `$SHOT_DIR` and re-baseline if the suite pins them.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/Theme.swift Slackwater/TideDetailView.swift \
        Slackwater/CurrentDetailView.swift Slackwater/DerivedGateDetailView.swift \
        Slackwater/OnlineGateDetailView.swift SlackwaterUITests/ScreenshotTests.swift
git commit -m "feat: a range bar heads the schedule card"
```

---

### Task 3: The picker sheet

**Files:**
- Modify: `Slackwater/Theme.swift` (add `WeekPickerSheet`; the scaffold gains `@Binding anchor`, `onPickerOpen`, `onPicked`, and owns `showPicker` + the `.sheet`)
- Modify: the four detail views (present the sheet, apply the anchor)
- Test: `SlackwaterUITests/ScreenshotTests.swift`

**Interfaces:**
- Consumes: `todayLocal(_:)`, each view's `anchor` state, and `rebuild()` on the three views that have one (not `OnlineGateDetailView` — see Depends on)
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

In `Slackwater/Theme.swift`, below `WeekRangeBar`:

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

- [ ] **Step 4: The scaffold presents it; the views supply the anchor and the consequences**

> **Amended 2026-08-13.** Originally each of the four views presented its own sheet. Since PR #60 the scaffold owns the schedule card and the bar, so it owns the sheet too — one `.sheet`, one `showPicker`, one binding. The views keep exactly what only they can know: the anchor itself, and what must happen when it moves.

`ScrubDetailScaffold` replaces Task 2's `onPickDate: () -> Void` with:

```swift
    /// The window's anchor. The scaffold moves it (via the picker) but does not
    /// own it — it lives in the detail view, which is also what makes
    /// `onReturn` caller-owned.
    @Binding var anchor: Date
    /// Fired when the picker OPENS, before a date is chosen. Only an online
    /// gate has anything to do here (speculatively fetch the next block); the
    /// other three are constituents and pass a no-op.
    var onPickerOpen: () -> Void = {}
    /// Fired after the anchor moves, with the picked date. The three
    /// `@State`-backed views rebuild here; the online gate re-checks coverage.
    var onPicked: (Date) -> Void = { _ in }
```

and holds the sheet itself:

```swift
    @State private var showPicker = false
```

with `.sheet(isPresented: $showPicker) { WeekPickerSheet(anchor: $anchor, tz: tz, onOpen: onPickerOpen, onPick: onPicked) }` on its body, and the bar's `onTap` set to `{ showPicker = true }`.

Task 2's `showPicker` in the four views is removed — it was scaffolding for a bar that had no sheet yet, and now it has one.

Each view then passes `anchor: $anchor` plus its own consequence:

| view | `onPicked` |
|---|---|
| `TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView` | `{ _ in rebuild() }` — they store `timeline` in `@State` |
| `OnlineGateDetailView` | `{ _ in }` here; Task 4 replaces it with `applyAnchor()` |

`onPickerOpen` is omitted by the three constituent views (it defaults to a no-op) and supplied only by `OnlineGateDetailView` in Task 4. That is the difference from the original plan's no-op-in-every-view approach: a defaulted parameter says "most callers have nothing to do here" once, rather than four identical empty functions saying it four times.

- [ ] **Step 5: Run the test to verify it passes**

```bash
./scripts/test.sh
```

Expected: PASS. If the `Next Month` button's accessibility label differs on the CI simulator's iOS version, read the real label from the failure's element tree and fix the test — do not weaken the assertion.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/Theme.swift Slackwater/TideDetailView.swift \
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

> **Amended 2026-08-13.** The sheet lives in `ScrubDetailScaffold` now (Task 3), not in this view. So this is two arguments on the existing `ScrubDetailScaffold(…)` call rather than a `.sheet` modifier.

Supply both hooks where this view constructs the scaffold:

```swift
                            onPickerOpen: prefetchNextBlock,
                            onPicked: { _ in applyAnchor() },
```

`OnlineGateDetailView` is the only view that passes `onPickerOpen` — the other three are constituents with nothing to fetch and take its default no-op.

and add:

```swift
    /// The anchor moved. If the merged window covers it we are done; if not,
    /// this is the same situation `.onAppear` already handles — fetch when
    /// online, show the amber honesty card when that throws.
    ///
    /// No `rebuild()` call, and deliberately: this view's `timeline` is a
    /// COMPUTED property (unlike the other three details, which store theirs in
    /// `@State`), so setting `anchor` is already enough — SwiftUI re-evaluates
    /// it on the next render. Plan A briefly had a `rebuild()` here with an
    /// empty body for symmetry with the other views; it was deleted, because a
    /// function named for an action it does not perform is how the next person
    /// gets fooled.
    private func applyAnchor() {
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
                // Assigning `window` is the whole update: `timeline` is computed
                // off it, so there is no stored data to rebuild.
                window = fresh
                fetching = false
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
