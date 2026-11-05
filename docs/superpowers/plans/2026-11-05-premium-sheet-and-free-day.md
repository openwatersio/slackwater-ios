# Premium Sheet and Free Day Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Premium sheet that pitches every Premium feature starting from the one tapped, and a free day of full Premium once a calendar month.

**Architecture:** The free day is pure date logic (`FreeDay.swift`, shared with widgets and watch) plus a small store that records it in iCloud's key-value store and the App Group. `PremiumStore.isPremium` becomes "purchased or free day running", so every existing gate keeps working; the App Group keeps the purchase flag and gains the free day's end, and widgets, complications, the alert scheduler and station calendars each cap Premium at that end. The sheet is rebuilt as carousel, comparison table, plan picker with pinned button, free day button and support note, driven by a `PremiumFeature` enum that each entry point passes in.

**Tech Stack:** Swift, SwiftUI, StoreKit 2, WidgetKit, EventKit, `NSUbiquitousKeyValueStore`, XCTest, XcodeGen (`project.yml`).

**Spec:** `docs/superpowers/specs/2026-11-04-premium-sheet-and-free-day-design.md`

## Global Constraints

- One sheet, `PremiumView`, for every entry point. An entry point with no feature opens on the first card.
- Plans stay yearly (`PremiumStore.yearlyID`) and lifetime (`PremiumStore.lifetimeID`). No monthly plan, no App Store trial or introductory offer.
- Yearly is selected when the sheet opens; yearly says it renews every year until you cancel; Restore purchase, Privacy Policy and Terms of Use stay on the sheet (App Review 3.1.2).
- Free day: anyone with no Premium purchase; once per calendar month in the device's current calendar and time zone; lasts 24 hours from the tap.
- The free day is a "free day", never a "trial", in every string.
- Premium labels, headings and purchase options use the SF Symbol `sparkles`, separate from localized text.
- Never "scrub" in a user-facing string.
- Every new or changed string ships in all 16 locales in `Slackwater/Localizable.xcstrings`, added by hand in Xcode's order (CONTRIBUTING, Localization). `git diff -- '*.xcstrings' | grep '^-'` prints only the header.
- Carousel and table order: Print and PDF (only once #754 ships), Alerts, Calendars, Lock screen (phone only), Watch complications, Sky controls.
- A stored setting, rule or subscription is never deleted when Premium or a free day ends.
- No in-app analytics.
- Code comments follow the `code-comments` skill; commits follow the repo's log style and end with the session's `Co-Authored-By` trailer.

## Review Focus

- **The free day ends while the app is closed.** A lock screen widget, a watch complication and a scheduled notification must all behave as free after the end without the app running. Pinned in Tasks 3 and 4.
- **A month boundary in another time zone.** A free day used on October 31 at 23:00 in Seattle must not block November 1 because UTC already says November; one started on the 1st at 00:30 local must count for that month. Pinned in Task 1.
- **A purchase during a free day.** Buying must clear the free-day marks on calendars so a later lapse keeps them, and must hide the free day button. Pinned in Tasks 2 and 5.
- **Stored calendar subscriptions from before this change.** Data saved without the new field must decode, unmarked. Pinned in Task 5.
- **The device clock moves backwards.** A free day whose start is in the future must not read as running for days; treat `start > now` as not running. Pinned in Task 1.

---

### Task 1: Free day rules

Pure date logic, compiled into the app, the widgets, the watch app and the watch widgets.

**Files:**
- Create: `Slackwater/FreeDay.swift`
- Modify: `Slackwater/AppGroup.swift` (keys), `project.yml` (add `Slackwater/FreeDay.swift` beside every `Slackwater/AppGroup.swift` and `Slackwater/PremiumStore.swift` entry)
- Test: `SlackwaterTests/FreeDayTests.swift`

**Interfaces:**
- Produces:
  - `struct FreeDay: Codable, Equatable { let start: Date; var end: Date { start + FreeDay.length } ; static var length: TimeInterval }`: 86,400 seconds. In DEBUG builds only, a `-freeDayLength <seconds>` launch argument overrides it, for the device check in Task 10.
  - `func freeDayAvailable(lastStart: Date?, now: Date, calendar: Calendar) -> Bool`
  - `func nextFreeDayDate(lastStart: Date, calendar: Calendar) -> Date` (start of the following month)
  - `func freeDayRunning(_ day: FreeDay?, at date: Date) -> Bool` (`start <= date < end`)
  - `func premiumActive(purchased: Bool, freeDay: FreeDay?, at date: Date) -> Bool`
  - `AppGroup.freeDayStartKey = "slackwater.freeDay.start"` (a `Date`, the App Group's copy for widgets)

- [ ] **Step 1: Write the failing tests**

```swift
final class FreeDayTests: XCTestCase {
    let seattle: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testAvailableWhenNeverUsed() { XCTAssertTrue(freeDayAvailable(lastStart: nil, now: date("2026-11-05T12:00:00Z"), calendar: seattle)) }
    func testUsedThisMonthIsUnavailable() {
        XCTAssertFalse(freeDayAvailable(lastStart: date("2026-11-02T18:00:00Z"), now: date("2026-11-20T18:00:00Z"), calendar: seattle))
    }
    func testLateLastMonthLocalIsAvailableOnTheFirst() {
        // Oct 31 23:00 Seattle is Nov 1 06:00 UTC; it still counts for October.
        XCTAssertTrue(freeDayAvailable(lastStart: date("2026-11-01T06:00:00Z"), now: date("2026-11-01T08:30:00Z"), calendar: seattle))
    }
    func testNextFreeDayIsStartOfNextLocalMonth() {
        XCTAssertEqual(nextFreeDayDate(lastStart: date("2026-11-02T18:00:00Z"), calendar: seattle), date("2026-12-01T08:00:00Z"))
    }
    func testRunningForTwentyFourHours() {
        let day = FreeDay(start: date("2026-11-05T22:00:00Z"))
        XCTAssertTrue(freeDayRunning(day, at: date("2026-11-06T21:59:59Z")))
        XCTAssertFalse(freeDayRunning(day, at: date("2026-11-06T22:00:00Z")))
    }
    func testFutureStartIsNotRunning() {
        XCTAssertFalse(freeDayRunning(FreeDay(start: date("2026-11-07T00:00:00Z")), at: date("2026-11-05T00:00:00Z")))
    }
    func testPremiumActive() {
        let day = FreeDay(start: date("2026-11-05T00:00:00Z"))
        XCTAssertTrue(premiumActive(purchased: true, freeDay: nil, at: .distantFuture))
        XCTAssertTrue(premiumActive(purchased: false, freeDay: day, at: date("2026-11-05T12:00:00Z")))
        XCTAssertFalse(premiumActive(purchased: false, freeDay: day, at: date("2026-11-06T00:00:00Z")))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodegen && SLACKWATER_ONLY=SlackwaterTests/FreeDayTests ./scripts/test.sh --unit`
Expected: build failure, `freeDayAvailable` not found.

- [ ] **Step 3: Implement the functions and keys listed under Interfaces**

`freeDayAvailable` compares `calendar.dateComponents([.year, .month], from:)` of `lastStart` and `now`; a `lastStart` after `now` (clock moved back) counts as used this month only if it falls in `now`'s month.

- [ ] **Step 4: Run to verify they pass**

Same command. Expected: PASS.

- [ ] **Step 5: Commit** — "Add the monthly free day's date rules"

---

### Task 2: Free day store and `PremiumStore.isPremium`

**Files:**
- Create: `Slackwater/FreeDayStore.swift` (app and watch app targets only)
- Modify: `Slackwater/PremiumStore.swift`, `Slackwater/TestSeeds.swift`, `project.yml`
- Test: `SlackwaterTests/PremiumTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `@MainActor final class FreeDayStore: ObservableObject { static let shared; @Published private(set) var lastStart: Date?; var current: FreeDay? ; func start(now: Date = appNow()) }` — `start` is a no-op unless `freeDayAvailable` and not purchased. It writes `lastStart` to `NSUbiquitousKeyValueStore` under `slackwater.freeDay.start` and to `AppGroup.defaults` under `AppGroup.freeDayStartKey`, and adopts a newer value arriving from iCloud (`didChangeExternallyNotification`, the way `FavoritesCloud.swift` does), copying it into the App Group.
  - `PremiumStore.hasPurchased: Bool` (published; what StoreKit says).
  - `PremiumStore.isPremium: Bool` stays published and becomes `premiumActive(purchased: hasPurchased, freeDay: FreeDayStore.shared.current, at: appNow())`. It re-evaluates when either input changes and at `current.end`, via a one-shot `Task.sleep` until the end, cancelled and replaced on change. Each change that flips it reloads widget timelines and calls `AlertScheduler.requestReschedule()` (iOS), as `refreshEntitlement` does now.
  - `AppGroup.premiumKey` caches `hasPurchased` only. Widgets combine it with `freeDayStartKey` themselves (Task 4).
  - `static func cache(_ purchased: Bool, into:)` is unchanged in signature.
  - Seeds: `-seedFreeDay` (a free day started now), `-seedFreeDayUsed` (one started earlier this month and ended).

- [ ] **Step 1: Write the failing tests**

Add to `PremiumTests`: `testFreeDayStartIgnoredWhenPurchased` and `testFreeDayStartIgnoredWhenUsedThisMonth`. Each builds a `FreeDayStore(cloud:defaults:)` over a test `UserDefaults` suite and an in-memory cloud stand-in (a protocol `FreeDayCloud { func date(forKey:) -> Date?; func set(_:forKey:) }` that `NSUbiquitousKeyValueStore` conforms to), and asserts `lastStart` doesn't change. `testFreeDayStartWritesBothStores` asserts the cloud and the App Group suite both hold the start.

- [ ] **Step 2: Run to verify they fail**

Run: `SLACKWATER_ONLY=SlackwaterTests/PremiumTests ./scripts/test.sh --unit`
Expected: build failure, `FreeDayStore` not found.

- [ ] **Step 3: Implement `FreeDayStore`, `hasPurchased`, and the derived `isPremium`, and the two seeds**

`-seedPremium` keeps setting both `hasPurchased` and `isPremium` true.

- [ ] **Step 4: Run to verify they pass**, plus `SLACKWATER_ONLY=SlackwaterTests ./scripts/test.sh --unit` for regressions in existing Premium gates.

- [ ] **Step 5: Commit** — "Let anyone turn on a free day of Premium once a month"

---

### Task 3: Alerts and Live Activities stop at the free day's end

**Files:**
- Modify: `Slackwater/AlertPlan.swift` (`deliveryPlan`), `Slackwater/AlertScheduler.swift:139` (the call)
- Test: `SlackwaterTests/DeliveryPlanTests.swift`

**Interfaces:**
- Consumes: `PremiumStore.hasPurchased`, `FreeDayStore.shared.current` (Task 2).
- Produces: `deliveryPlan(rules:occurrences:calendarOccurrences:now:premium:premiumEnds: Date? = nil) -> DeliveryPlan`. `premiumEnds` is nil when purchased, and the free day's end during a free day.

- [ ] **Step 1: Write the failing tests**

```swift
func testFreeDayDropsNotificationsFiringAfterItsEnd() {
    // A rule with occurrences firing at now+1h and now+30h, premium: true, premiumEnds: now+24h
    // XCTAssertEqual(plan.notifications.map(\.fire), [now + 3_600])
}
func testFreeDayDropsLiveActivitiesWhoseEventIsAfterItsEnd() {
    // 15-minute-lead rule: fire at end-5min, event at end+10min → in neither notifications' live candidates
    // XCTAssertTrue(plan.liveActivities.isEmpty); it stays a notification since its fire is before the end
}
func testPurchasedPremiumIsUncapped() { /* premiumEnds: nil keeps the now+30h occurrence */ }
```

Build the fixtures with the helpers already in `DeliveryPlanTests`.

- [ ] **Step 2: Run to verify they fail**

Run: `SLACKWATER_ONLY=SlackwaterTests/DeliveryPlanTests ./scripts/test.sh --unit`
Expected: compile error on `premiumEnds`.

- [ ] **Step 3: Implement**: notifications keep `o.fire < premiumEnds`; live activity candidates also need `o.event < premiumEnds`. `runPass` passes `premium: PremiumStore.shared.isPremium, premiumEnds: PremiumStore.shared.hasPurchased ? nil : FreeDayStore.shared.current?.end`.

- [ ] **Step 4: Run to verify they pass.**

- [ ] **Step 5: Commit** — "Stop free day alerts at the end of the day"

---

### Task 4: Widgets and complications end on their own

**Files:**
- Modify: `SlackwaterWidgets/SlackwaterWidgetsBundle.swift` (`entryBuilder`, `placeholder`, `timeline`), `SlackwaterWatchWidgets/ComplicationProvider.swift` (same three), `Slackwater/FreeDay.swift`
- Test: `SlackwaterTests/FreeDayTests.swift`, `SlackwaterTests/AccessoryWidgetTests.swift`

**Interfaces:**
- Consumes: Task 1, `AppGroup.premiumKey` (purchase) and `AppGroup.freeDayStartKey`.
- Produces in `FreeDay.swift`:
  - `func storedFreeDay(_ defaults: UserDefaults) -> FreeDay?`
  - `func widgetEntryDates(now: Date, freeDayEnd: Date?) -> [Date]`: the existing 30-minute stride over 24 hours, plus `freeDayEnd` itself when it falls inside, sorted and deduplicated.

- [ ] **Step 1: Write the failing tests**

```swift
func testEntryDatesIncludeTheFreeDayEnd() {
    let now = date("2026-11-05T12:10:00Z"), end = date("2026-11-05T15:47:00Z")
    let dates = widgetEntryDates(now: now, freeDayEnd: end)
    XCTAssertTrue(dates.contains(end)); XCTAssertEqual(dates.first, now); XCTAssertEqual(dates, dates.sorted())
}
func testEntryDatesWithoutAFreeDayAreTheStride() {
    XCTAssertEqual(widgetEntryDates(now: date("2026-11-05T12:00:00Z"), freeDayEnd: nil).count, 48)
}
```

- [ ] **Step 2: Run to verify they fail.** `SLACKWATER_ONLY=SlackwaterTests/FreeDayTests ./scripts/test.sh --unit`

- [ ] **Step 3: Implement**: `entryBuilder` reads `purchased` and `storedFreeDay` once. It builds the record source when `purchased || freeDayRunning(day, at: now)`, and sets each entry's `premium` (and whether it gets a record) from `premiumActive(purchased:freeDay:at: date)`, so an entry after the end is the locked view. `timeline` uses `widgetEntryDates`. The watch provider does the same. Its "no record at all" rule now applies per entry.

- [ ] **Step 4: Run** `FreeDayTests`, `AccessoryWidgetTests`, `WidgetFamilyCoverageTests`, `WatchWidgetFamilyCoverageTests`. Expected: PASS.

- [ ] **Step 5: Commit** — "Return widgets and complications to free when a free day ends"

---

### Task 5: Calendars turned on during a free day stop at its end

**Files:**
- Modify: `Slackwater/AlertStationCalendar.swift` (`StationCalendar`, `StationCalendarStore.subscribe`), `Slackwater/AlertScheduler.swift` (which stations publish), `Slackwater/PremiumStore.swift` (clear marks on purchase)
- Test: `SlackwaterTests/StationCalendarTests.swift`

**Interfaces:**
- Consumes: Task 2.
- Produces:
  - `StationCalendar.freeDay: Bool`, decoded with `decodeIfPresent` and defaulting to `false`.
  - `StationCalendarStore.subscribe(_ stationID: String, notify: Bool = true, freeDay: Bool = false)`
  - `StationCalendarStore.clearFreeDayMarks()`, called when `hasPurchased` becomes true.
  - `func publishingStations(_ subs: [StationCalendar], premium: Bool) -> [String]`: every subscription when `premium`, otherwise only the unmarked ones.

- [ ] **Step 1: Write the failing tests**

```swift
func testOldSubscriptionsDecodeUnmarked() {
    let json = #"[{"stationID":"noaa/9444900","calendarID":"x"}]"#.data(using: .utf8)!
    XCTAssertEqual(try JSONDecoder().decode([StationCalendar].self, from: json).first?.freeDay, false)
}
func testFreeDayCalendarStopsWithoutPremium() {
    let subs = [StationCalendar(stationID: "a"), StationCalendar(stationID: "b", freeDay: true)]
    XCTAssertEqual(publishingStations(subs, premium: true), ["a", "b"])
    XCTAssertEqual(publishingStations(subs, premium: false), ["a"])
}
func testPurchaseClearsFreeDayMarks() { /* store over a test suite: subscribe(freeDay: true), clearFreeDayMarks(), subscriptions.first?.freeDay == false */ }
```

- [ ] **Step 2: Run to verify they fail.** `SLACKWATER_ONLY=SlackwaterTests/StationCalendarTests ./scripts/test.sh --unit`

- [ ] **Step 3: Implement**: the calendar toggle in `CalendarStationsView` subscribes with `freeDay: !PremiumStore.shared.hasPurchased`. `runPass` passes `publishingStations(..., premium: isPremium)` both to `resolveAlerts` and as `subscribed:` to `AlertCalendar.apply`. Check that `apply` removes the events of a station that is in the store but not in `subscribed`, and that the station's calendar comes back on the next run once it is listed again. If `apply` instead deletes the calendar and forgets its `calendarID`, make it remove only the events, so buying restores the same calendar.

- [ ] **Step 4: Run to verify they pass**, plus `CalendarInvalidationTests`.

- [ ] **Step 5: Commit** — "Stop free day calendars when the free day ends"

---

### Task 6: Premium features and their examples

**Files:**
- Create: `Slackwater/PremiumFeature.swift`
- Modify: `Slackwater/PremiumFeaturePreview.swift` (add `.watch`, `.sky`; key the enum to `PremiumFeature`)
- Test: `SlackwaterTests/PremiumTests.swift`

**Interfaces:**
- Produces:
  - `enum PremiumFeature: String, CaseIterable, Identifiable { case alerts, calendars, lockScreen, watch, sky }` with `title: LocalizedStringKey`, `detail: LocalizedStringKey`, `symbol: String`, `tableLabel: LocalizedStringKey`.
  - `static func carousel(for platform: SettingsPlatform) -> [PremiumFeature]`: `allCases` in declared order, without `.lockScreen` off `.mobile`.
  - `PremiumFeaturePreview(feature: PremiumFeature)`: `.watch` draws the watch's `ComplicationReading` views for the bundled station, and `.sky` draws the chart strip with and without the sun, moon and stars. Both use the same bundled station and `Example` caption as the existing three.

Copy (English, the translators' source):

| case | title | detail | tableLabel |
|---|---|---|---|
| alerts | Alerts | A reminder before the slack or tide you're waiting for, right on your lock screen. | Alerts |
| calendars | Calendars | Tides and slack windows in your calendar, next to your plans. | Calendars |
| lockScreen | Lock screen | The next tide without unlocking your phone. | Lock screen widgets |
| watch | Watch complications | The tide on your watch face. | Watch complications |
| sky | Sky controls | A quieter chart, without the sun, moon and stars. | Sky controls |

- [ ] **Step 1: Write the failing test**: `testCarouselOrder` asserts `[.alerts, .calendars, .lockScreen, .watch, .sky]` on `.mobile` and `[.alerts, .calendars, .watch, .sky]` on `.mac`.
- [ ] **Step 2: Run to verify it fails.** `SLACKWATER_ONLY=SlackwaterTests/PremiumTests ./scripts/test.sh --unit`
- [ ] **Step 3: Implement the enum and the two new previews.**
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — "Describe each Premium feature with a live example"

---

### Task 7: The new Premium sheet

**Files:**
- Modify: `Slackwater/PremiumView.swift` (rewrite), `Slackwater/PremiumPurchaseControls.swift` (becomes the plan picker and pinned button)
- Create: `Slackwater/PremiumComparison.swift` (table), `Slackwater/FreeDayButton.swift`
- Test: `SlackwaterUITests/PremiumSheetTests.swift` (new shard; add it to the test plan and CI shard list beside the others)

**Interfaces:**
- Consumes: Tasks 2 and 6.
- Produces: `PremiumView(opening: PremiumFeature? = nil)`. Accessibility identifiers: `premium-card-<rawValue>`, `premium-table`, `premium-plan-yearly`, `premium-plan-lifetime`, `premium-buy`, `premium-free-day`, `premium-close`, `premium-purchases` (kept).

Layout, top to bottom, per the spec's "The sheet":
1. Carousel: a paged `TabView` over `PremiumFeature.carousel(for: .current)`, selection starting at `opening ?? first`. Each page is `PremiumFeaturePreview`, the title, and the detail. Page dots in `SN.leaf`.
2. Table: free rows first ("Every tide and current, every date, offline"; "Home screen widgets"; "The watch app"), then one row per carousel feature using `tableLabel`. Free and Premium check columns.
3. Plans: two selectable rows, yearly preselected. Yearly's subtitle is "Renews every year until you cancel." and lifetime's is "Pay once, never again."
4. Pinned at the bottom (`safeAreaInset(edge: .bottom)`): "Get Premium" with the selected plan's `displayPrice` beneath, and "per year" for yearly.
5. `FreeDayButton` under the plans, not pinned. "Try everything free today" when available. "Free day until <time>" while one is running, with `Text(end, style: .time)`. "Your next free day is <date>" once used. Hidden when `hasPurchased`.
6. Support note: "Slackwater is independent and open source. Premium is how it keeps going."
7. Restore purchase, Privacy Policy, Terms of Use, as now.

The title is "Slackwater Premium" with `sparkles`. A close button (`xmark`, `premium-close`) replaces Done. With `hasPurchased`, items 3–5 become "You have Premium — thank you." The unavailable and error states of `PremiumPurchaseControls` stay.

- [ ] **Step 1: Write the failing UI tests**: `testOpensOnFirstCardWithoutAFeature` (launch with `-seedPremiumSheet` → `premium-card-alerts` is hittable). `testYearlyIsPreselected` (`premium-plan-yearly` has the `.isSelected` trait). `testFreeDayTurnsOnPremium` (tap `premium-free-day`, close, then open Settings: the sky switch toggles without reopening the sheet). `testUsedFreeDayShowsNextDate` (launch `-seedFreeDayUsed`: `premium-free-day` label contains "next free day"). `testPurchasedHidesPlansAndFreeDay` (launch `-seedPremium`: `premium-plan-yearly` and `premium-free-day` don't exist).
- [ ] **Step 2: Run to verify they fail.** `SLACKWATER_ONLY=SlackwaterUITests/PremiumSheetTests ./scripts/test.sh`
- [ ] **Step 3: Implement the sheet**, plus a `-seedPremiumSheet [feature]` seed in `TestSeeds.swift` that presents it on launch.
- [ ] **Step 4: Run to verify they pass**, then `SLACKWATER_ONLY=SlackwaterUITests/SettingsLayoutTests ./scripts/test.sh` and `AccessibilityAuditTests`.
- [ ] **Step 5: Screenshot** the sheet on the phone simulator at each card, with Premium, during a free day, and with it used, and check them by eye in light and Dynamic Type XXL.
- [ ] **Step 6: Commit** — "Pitch every Premium feature on the Premium sheet"

---

### Task 8: Each entry point opens on its own feature

**Files:**
- Modify: `Slackwater/PremiumFeaturePreview.swift` (`PremiumRequirement(feature:)`), `Slackwater/SettingsView.swift` (sky → `.sky`, alerts section → `.alerts`, calendar section → `.calendars`, lock screen section → `.lockScreen`), `Slackwater/AlertsView.swift` (`.alerts`), `Slackwater/AlertSheet.swift` (`.alerts`), `Slackwater/CalendarStationsView.swift` (`.calendars`), `Slackwater/StationListView.swift` (the `premium` deep link from a locked accessory widget → `.lockScreen`; the list's Premium row → nil)
- Test: `SlackwaterUITests/PremiumSheetTests.swift`

**Interfaces:**
- Consumes: `PremiumView(opening:)` (Task 7).
- Produces: `PremiumRequirement(title:feature:)`. Each view's `showPremium: Bool` becomes `premiumFeature: PremiumFeature?` with `.sheet(item:)`, or keeps the Bool alongside a stored feature. The builder chooses.

- [ ] **Step 1: Write the failing UI tests**: `testSkySwitchOpensOnSkyCard` (Settings, tap the sky switch → `premium-card-sky` hittable). `testCalendarOpensOnCalendarsCard`. `testAlertRemindMeOpensOnAlertsCard`.
- [ ] **Step 2: Run to verify they fail.**
- [ ] **Step 3: Pass the feature from each entry point.**
- [ ] **Step 4: Run to verify they pass**, plus `DeepLinkUITests`, `CalendarSettingsTests` and `AlertLineUITests`.
- [ ] **Step 5: Commit** — "Open the Premium sheet on the feature that was tapped"

---

### Task 9: Translations and docs

**Files:**
- Modify: `Slackwater/Localizable.xcstrings`, `docs/premium.md`, `docs/alerts.md` (§5.1, §6), `CONTRIBUTING.md` (the "Support Slackwater sheet" mention in line 52), `Slackwater/DeepLink.swift` comment
- Test: `scripts/localization.py`

- [ ] **Step 1: Run** `python3 scripts/localization.py`. Expected: it lists every new key from Tasks 6–8 as missing in 15 locales.
- [ ] **Step 2: Add translator context and all 16 locales for each key**, by hand in Xcode's order. Remove the keys the old sheet used ("Support Slackwater's development.", "Support Slackwater", "Slackwater supporter" if no longer used, "Favourites calendars", "Chart controls", and others).
- [ ] **Step 3: Run** `python3 scripts/localization.py` and `git diff -- '*.xcstrings' | grep '^-'`. Expected: nothing missing; only the header and the removed keys' lines.
- [ ] **Step 4: Update the docs**: `premium.md` gets a "Free day" section (who, how often, how long, what it unlocks, that its end is a lapse except for calendars, iCloud). `alerts.md` §6 says the free day caps notifications and Live Activities at its end, and §5.1 says free-day calendars stop. Rename "Support Slackwater sheet" to "Premium sheet" wherever it appears. Current state only, no history.
- [ ] **Step 5: Build in a non-English locale** (`-AppleLanguages (de)`) and screenshot the sheet. Check that nothing truncates.
- [ ] **Step 6: Commit** — "Translate the Premium sheet and document the free day"

---

### Task 10: Device check

- [ ] **Step 1:** On a phone with a lock screen widget and a paired watch with a complication, turn on a free day with `-seedFreeDay` shortened to five minutes with `-freeDayLength 300` (Task 1). Add an alert 2 minutes out and one 10 minutes out. Turn on a station calendar. Quit the app.
- [ ] **Step 2:** Confirm the 2-minute alert fires and the 10-minute one doesn't. Confirm the lock screen widget goes back to locked at the end without opening the app, and the complication does once the watch app has run during the free day. Confirm the calendar's events disappear on the next app open.
- [ ] **Step 3:** Record the results in the PR's testing section.

---

### Task 11 (when #754 ships): Print and PDF card

- [ ] Add `case print` first in `PremiumFeature`: title "Print your week", detail "A week of tides and currents on paper or as a PDF, for the boat, the dock or the fridge.", tableLabel "Print and PDF". Its preview is a few rows of the week view's printable table for the bundled station. The week view's Premium gate opens `PremiumView(opening: .print)`. Update `testCarouselOrder`, translate, and add the free row to the table if the website's free print changes what's free in the app.
