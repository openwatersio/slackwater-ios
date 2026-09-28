# Alerts: long press and station calendars — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set a notification by long-pressing the moment on a station's strip, and subscribe a station's own calendar from Settings — one free, as many as you like with Premium.

**Architecture:** Two pipelines over one occurrence engine. `AlertRule` is a notification and nothing else, created by the long-press popup, optionally bound to a single instant by `once`. A station calendar is a subscription keyed by station id: the scheduler builds throwaway rules from a per-station trigger list, resolves them through the same `alertOccurrences`, and writes each station's events into a calendar of its own. Nothing Slackwater writes to a calendar carries an alarm.

**Tech Stack:** Swift 6 / SwiftUI, XcodeGen, XCTest, EventKit, UserNotifications, StoreKit 2, `slackwater-engine` (TideEngine) and `Almanac` as SPM dependencies.

**Spec:** `docs/superpowers/specs/2026-09-12-notifications-design.md`

## Global Constraints

- **The four scrubber consumers move together.** `TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView` and `OnlineGateDetailView` all render through `ScrubDetailScaffold`. A change to the scaffold is a change to all four — check each one (repo `CLAUDE.md`).
- **Never use `Button` for a control inside the scrub card.** `Button` press tracking goes dead in the iPad split layout's detail column. Use `.contentShape(...)` + `.onTapGesture` + `.accessibilityAddTraits(.isButton)`, as `ReadoutTile`, `MultiDaySchedule` and `AlertRow` do.
- **Every `formatHeight(`, `formatSpeed(`, `formatNm(` or `cardTime(` call is checked** by `SlackwaterTests/TypeScaleTests.swift:testNumericFormattersAreMonospacedDigit`. Either `.monospacedDigit()` appears within ±4 lines of the call, or the owning symbol is registered in `knownIndirections` (rendered by a `Text` of ours elsewhere) or `knownNonVisual` (never rendered by a `Text` of ours). The scanner attributes a call to the nearest brace-opening `func`/`var` line **above it by text**, not by real nesting — `AlertPlan.swift`'s calls key on `leadAmount`, not `alertCopy`.
- **Horizons are fixed by the platform, not tuned:** calendar 90 days (`AlertHorizon.calendar`), notifications 14 days (`AlertHorizon.notifications`), 64 pending requests (`AlertHorizon.notificationLimit`) because iOS keeps only the soonest 64 per app.
- **Instants are floored to the minute** with `alertMinute(_:)`, and sample series start on the fixed 10-minute grid, so two reschedules name the same instant. Calendar events match within `calendarMatchTolerance` (90 s) on top of that.
- **Copy:** a notification's title is the place then the event — `"Race Passage - Slack window"`. A calendar event's title carries no place, because the calendar is named for it — `"High tide 3.1 m"`.
- **No alarm on any calendar event, for any tier.**
- **Tests run through `scripts/test.sh`**, which takes the shared machine's lock. `SLACKWATER_ONLY=<TestClass>` narrows a run. `lockf -t 0` failing means another run holds the machine — wait for it, never force it.
- **Branch and PR.** Work on `feat/alerts` in the worktree `~/src/openwaters/slackwater-ios-wt-alerts`. Never commit to `main`.

## Review Focus

1. **A tide station and a current station with the same name** (Friday Harbor has both) both subscribed: two calendars would carry one title and the adopt-by-title path would hand both stations the same calendar, so each run rewrites the other's events. Titles must disambiguate. — Task 3.
2. **A subscribed station that no longer resolves** (a CHS station not yet fitted on this device, or an id that left the catalog) plans no events; the writer must skip that calendar, not read "no planned events" as "delete everything in it". — Task 5.
3. **Premium lapsing with four station calendars on** must leave all four in place and only stop the notifications; the free cap applies when a subscription is written, never when one is planned. — Task 4.
4. **The user deleted the calendar in Calendar.app.** The stored identifier dangles; the app must adopt by title or create exactly one replacement, not a new calendar on every foreground. No unit test reaches this — `EKEventStore` is unusable in the suite — so it is a device check on the PR's before-merge list, and the logic it exercises is isolated in `AlertCalendar.calendarFor(stationID:title:create:)` where a reviewer can read it whole. — Task 5.
5. **Two `once` rules on the same instant and trigger** must collapse to one rule and one notification, including when the second tap lands while the first is still being written. — Task 6.

---

### Task 1: A rule is a notification

Strips the delivery fields off `AlertRule`, adds `once`, and updates every reader. The Calendar/Live row goes with them: the popup that replaces it arrives in Task 7, so this commit leaves the app with no way to create a rule. That is deliberate — the type change reaches every call site at once, and half-migrating it with shims costs more than the gap.

**Files:**
- Modify: `Slackwater/AlertRule.swift`
- Modify: `Slackwater/AlertOffer.swift` (drop `AlertDelivery`, `alertRowToggle`, `alertRowState`, `alertRowLead`)
- Modify: `Slackwater/AlertPlan.swift:21-36` (`deliveryPlan`)
- Modify: `Slackwater/AlertScheduler.swift:81,99-101`
- Modify: `Slackwater/AlertSheet.swift`
- Modify: `Slackwater/AlertsView.swift:5-16,44-47`
- Modify: `Slackwater/Theme.swift:759-760,921-925`
- Delete: `Slackwater/AlertRow.swift`, `SlackwaterUITests/AlertRowTests.swift`
- Test: `SlackwaterTests/AlertRuleTests.swift`, `SlackwaterTests/DeliveryPlanTests.swift`, `SlackwaterTests/AlertStatusTests.swift`, `SlackwaterTests/AlertOfferTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `AlertRule(id:stationID:trigger:once:lead:daylightOnly:enabled:)` with `once: Date?`; `deliveryPlan(rules:occurrences:calendarOccurrences:now:premium:) -> DeliveryPlan`; `alertStatusText(_:_:premium:tz:locale:) -> String`. `AlertLevel`, `AlertDelivery`, `alertRowToggle`, `alertRowState` and `alertRowLead` no longer exist.

- [ ] **Step 1: Write the failing tests**

In `SlackwaterTests/AlertRuleTests.swift`, `testRulesRoundTripThroughTheStore` edits its rule with `edited.calendar = false`, a field that is going away. Change that one line to edit a field that stays:

```swift
        edited.daylightOnly = false
```

Then add these three cases, following the file's own `UserDefaults(suiteName: #function)` + `defer` idiom:

```swift
    func testARuleWrittenByTheRowEraBuildStillDecodes() {
        // calendar/alert are gone from the type; a stored rule that still carries them
        // must read back as the notification rule it always was.
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let stored: [[String: Any]] = [[
            "id": UUID().uuidString, "stationID": TideStationRecord.fridayHarborID,
            "trigger": ["tideExtreme": ["high": false]],
            "lead": 1_800, "daylightOnly": false,
            "calendar": true, "alert": "notification", "enabled": true,
        ]]
        defaults.set(try! JSONSerialization.data(withJSONObject: stored), forKey: AppGroup.alertRulesKey)

        let store = AlertRuleStore(defaults: defaults)

        XCTAssertEqual(store.rules.count, 1, "an old rule must not land in `unreadable`")
        XCTAssertEqual(store.rules.first?.stationID, TideStationRecord.fridayHarborID)
        XCTAssertEqual(store.rules.first?.lead, 1_800)
        XCTAssertNil(store.rules.first?.once, "a rule from before `once` existed repeats")
    }

    func testOnceSurvivesARoundTrip() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let moment = Date(timeIntervalSince1970: 1_700_000_040)
        AlertRuleStore(defaults: defaults)
            .upsert(AlertRule(stationID: "a", trigger: .slack, once: moment))

        XCTAssertEqual(AlertRuleStore(defaults: defaults).rules.first?.once, moment)
    }

    func testARuleWithoutOnceEncodesWithoutTheKey() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        AlertRuleStore(defaults: defaults).upsert(AlertRule(stationID: "a", trigger: .slack))

        let raw = try! JSONSerialization.jsonObject(
            with: defaults.data(forKey: AppGroup.alertRulesKey)!) as! [[String: Any]]

        XCTAssertNil(raw.first?["once"])
    }
```

In `SlackwaterTests/DeliveryPlanTests.swift`, replace every case with these — the calendar no longer comes from rules:

```swift
final class DeliveryPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func occurrence(_ rule: AlertRule, eventIn seconds: TimeInterval) -> AlertOccurrence {
        let event = now.addingTimeInterval(seconds)
        return AlertOccurrence(ruleID: rule.id, event: event, fire: event.addingTimeInterval(-rule.lead))
    }

    func testNotificationsAreTheSoonestSixtyFourInsideFourteenDays() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let hourly = (1...(24 * 100)).map { occurrence(rule, eventIn: Double($0) * 3_600) }

        let plan = deliveryPlan(rules: [rule], occurrences: hourly.reversed(),
                               calendarOccurrences: [], now: now, premium: true)

        XCTAssertEqual(plan.notifications, Array(hourly.prefix(64)))
    }

    func testASparseRuleStopsAtFourteenDays() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let daily = (1...30).map { occurrence(rule, eventIn: Double($0) * 86_400) }

        let plan = deliveryPlan(rules: [rule], occurrences: daily,
                               calendarOccurrences: [], now: now, premium: true)

        XCTAssertEqual(plan.notifications, Array(daily.prefix(14)))
    }

    func testAFiredNotificationIsDroppedAndItsEventIsNot() {
        let rule = AlertRule(stationID: "a", trigger: .slack, lead: 3_600)
        let o = occurrence(rule, eventIn: 1_800)   // fired 30 min ago, happens in 30 min

        let plan = deliveryPlan(rules: [rule], occurrences: [o],
                               calendarOccurrences: [o], now: now, premium: true)

        XCTAssertEqual(plan.notifications, [])
        XCTAssertEqual(plan.calendar, [o])
    }

    func testWithoutPremiumTheCalendarIsPlannedAndNothingElseIs() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let o = occurrence(rule, eventIn: 3_600)

        let plan = deliveryPlan(rules: [rule], occurrences: [o],
                               calendarOccurrences: [o], now: now, premium: false)

        XCTAssertEqual(plan, DeliveryPlan(calendar: [o], notifications: []))
    }

    func testDisabledAndUnknownRulesPlanNothing() {
        var off = AlertRule(stationID: "a", trigger: .slack)
        off.enabled = false
        let orphan = AlertRule(stationID: "b", trigger: .slack)

        let plan = deliveryPlan(rules: [off],
                                occurrences: [occurrence(off, eventIn: 60), occurrence(orphan, eventIn: 60)],
                                calendarOccurrences: [], now: now, premium: true)

        XCTAssertEqual(plan, DeliveryPlan())
    }

    func testADuplicatedRuleIdPlansOnceAndDoesNotCrash() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let o = occurrence(rule, eventIn: 3_600)

        let plan = deliveryPlan(rules: [rule, rule], occurrences: [o],
                               calendarOccurrences: [], now: now, premium: true)

        XCTAssertEqual(plan, DeliveryPlan(calendar: [], notifications: [o]))
    }

    func testCalendarOccurrencesStopAtNinetyDaysAndSortByEvent() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let late = occurrence(rule, eventIn: 91 * 86_400)
        let soon = occurrence(rule, eventIn: 86_400)
        let sooner = occurrence(rule, eventIn: 3_600)

        let plan = deliveryPlan(rules: [], occurrences: [],
                               calendarOccurrences: [late, soon, sooner], now: now, premium: false)

        XCTAssertEqual(plan.calendar, [sooner, soon])
    }

    func testScheduledThroughIsEachRulesLastNotification() {
        let tide = AlertRule(stationID: "a", trigger: .tideExtreme(high: false), lead: 600)
        let pass = AlertRule(stationID: "b", trigger: .slackWindowOpens)
        let plan = DeliveryPlan(calendar: [],
                                notifications: [occurrence(tide, eventIn: 40 * 86_400),
                                                occurrence(tide, eventIn: 86_400),
                                                occurrence(pass, eventIn: 7_200)])

        let through = scheduledThrough(plan)

        XCTAssertEqual(through[tide.id], now.addingTimeInterval(40 * 86_400 - 600))
        XCTAssertEqual(through[pass.id], now.addingTimeInterval(7_200))
    }
}
```

In `SlackwaterTests/AlertStatusTests.swift`, replace the cases that mention the calendar with:

```swift
    func testAPremiumlessRuleSaysSo() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        XCTAssertEqual(alertStatusText(rule, AlertStatusSnapshot(), premium: false),
                       "Notifications are Premium")
    }

    func testAPremiumRuleWithNotificationsOffSaysSo() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let status = AlertStatusSnapshot(notificationsAuthorized: false)
        XCTAssertEqual(alertStatusText(rule, status, premium: true),
                       "Notifications are off in Settings")
    }
```

Delete `SlackwaterUITests/AlertRowTests.swift` and, in `SlackwaterTests/AlertOfferTests.swift`, delete every case that calls `alertRowToggle` or `alertRowState`, keeping the `tideAlertOffer` / `currentAlertOffer` / `derivedAlertOffer` / `displayedHeightM` / `isOnEclipseContact` cases untouched.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `SLACKWATER_ONLY=AlertRuleTests scripts/test.sh`
Expected: FAIL — `AlertRule` has no `once`, and `deliveryPlan` has no `calendarOccurrences:`.

- [ ] **Step 3: Change the model**

In `Slackwater/AlertRule.swift`, delete the `AlertLevel` enum and replace the `AlertRule` struct:

```swift
struct AlertRule: Codable, Identifiable, Equatable {
    var id = UUID()
    /// A `StationItem` id — `current:`-prefixed for NOAA currents.
    var stationID: String
    var trigger: AlertTrigger
    /// Set: the single occurrence on this minute, and the rule expires once it is past
    /// (spec §3). Unset: every occurrence of the trigger.
    var once: Date?
    /// Seconds before the event that the notification fires.
    var lead: TimeInterval = 0
    var daylightOnly = false
    var enabled = true
}
```

`once` is Optional, so the synthesized decoder reads an absent key as nil and a rule written before it existed repeats — which is what it always did. The synthesized encoder omits a nil, so nothing stored grows a null.

- [ ] **Step 4: Update `deliveryPlan`**

In `Slackwater/AlertPlan.swift`, replace `deliveryPlan` (the `DeliveryPlan` struct above it is unchanged):

```swift
/// Which occurrences the calendar publishes and which become notifications. The two have
/// separate sources: `calendarOccurrences` come from a station's subscription (spec §5.1) and
/// are free at any tier; `occurrences` come from rules, and rules are Premium. The calendar
/// keeps an event until it happens; a notification is gone once its fire time passes.
func deliveryPlan(rules: [AlertRule], occurrences: [AlertOccurrence],
                  calendarOccurrences: [AlertOccurrence],
                  now: Date, premium: Bool) -> DeliveryPlan {
    let calendar = calendarOccurrences
        .filter { $0.event > now && $0.event <= now.addingTimeInterval(AlertHorizon.calendar) }
        .sorted { $0.event < $1.event }
    guard premium else { return DeliveryPlan(calendar: calendar) }
    // A duplicated rule id would trap uniqueKeysWithValues; keep the first.
    let live = Dictionary(rules.filter(\.enabled).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let notifications = occurrences
        .sorted { $0.fire < $1.fire }
        .filter {
            live[$0.ruleID] != nil
                && $0.fire > now && $0.fire <= now.addingTimeInterval(AlertHorizon.notifications)
        }
    return DeliveryPlan(calendar: calendar,
                        notifications: Array(notifications.prefix(AlertHorizon.notificationLimit)))
}
```

And in the same file, `scheduledThrough` now reads a notification's fire time only:

```swift
/// Each rule's last scheduled notification, for the Alerts screen's "Scheduled through".
func scheduledThrough(_ plan: DeliveryPlan) -> [UUID: Date] {
    var through: [UUID: Date] = [:]
    for o in plan.notifications {
        through[o.ruleID] = max(through[o.ruleID] ?? o.fire, o.fire)
    }
    return through
}
```

- [ ] **Step 5: Update the offer file and delete the row**

In `Slackwater/AlertOffer.swift`, delete `AlertDelivery`, `alertRowLead`, `alertRowToggle` and `alertRowState`. Keep `displayedHeightM`, the three `*AlertOffer` functions, `isOnEclipseContact` and `AlertRuleChange`, and change the file's header comment to:

```swift
// Slackwater — GPL v3. What the strip offers for the moment on the centerline (notifications spec §7.1).
```

Then:

```bash
git rm Slackwater/AlertRow.swift SlackwaterUITests/AlertRowTests.swift
```

In `Slackwater/Theme.swift`, delete the `alertOffer` block from `scrubCard` (lines 921-925), leaving:

```swift
    private func scrubCard(_ tl: TimelineData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Full bleed, no chrome: the curve is the hero and the page is its
            // frame. No "‹ swipe to scrub ›" label here, and none is coming
            // back (#58): "scrubber" is audio-editing jargon, and testers who
            // read the label still didn't find the horizontal scroll. The
            // strip's own opening slide-into-place is the affordance now —
            // `TimelineScrubber.centerIfNeeded`.
            card(tl)

            links(tl, jump)
                .padding(.top, 12)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }
```

Leave the scaffold's `alertOffer` property at `Theme.swift:759` in place — Task 7 reads it — and update its doc comment to:

```swift
    /// What a long press on the strip offers to alert on (spec §7.1). Nil — the online
    /// gate — means a press does nothing.
    var alertOffer: AlertTrigger? = nil
```

- [ ] **Step 6: Update the scheduler and the two screens**

In `Slackwater/AlertScheduler.swift`, change the `deliveryPlan` call and drop the alarm:

```swift
        let plan = deliveryPlan(rules: rules, occurrences: resolved.occurrences,
                                calendarOccurrences: [], now: now, premium: premium)
```

and, in the `entries` helper, delete the `alarm` parameter and the `alarmOffset:` argument, then:

```swift
        AlertCalendar.apply(entries(plan.calendar, includeLead: false), now: now)
        await AlertNotifications.apply(entries(plan.notifications, includeLead: true))
```

Delete `AlertEntry.alarmOffset` in the same file, and in `Slackwater/AlertCalendar.swift:73` delete the line that adds the alarm and the `alarmOffset:` argument at `:57`, passing `alarmOffset: nil` nowhere — `CalendarEventShape`'s field stays, always nil, so `calendarChanges` keeps matching on it for a calendar that still holds alarmed events from an older build.

In `Slackwater/AlertsView.swift`, replace `alertStatusText` and the empty-state line:

```swift
func alertStatusText(_ rule: AlertRule, _ status: AlertStatusSnapshot, premium: Bool,
                     tz: TimeZone = .current, locale: Locale = .autoupdatingCurrent) -> String {
    if !rule.enabled { return "Off" }
    if status.unresolved.contains(rule.id) { return "Waiting for station data" }
    if !premium { return "Notifications are Premium" }
    if !status.notificationsAuthorized { return "Notifications are off in Settings" }
    guard let date = status.scheduledThrough[rule.id] else { return "Nothing coming up" }
    return "Scheduled through \(date.formatted(Date.FormatStyle(timeZone: tz).day().month(.abbreviated).locale(locale)))"
}
```

```swift
                Text("No alerts yet. Press and hold any station's timeline to set one.")
```

In `Slackwater/AlertSheet.swift`, delete the delivery `Section` (lines 28-40), delete the `notify` binding, change the Save button's `disabled` to `saving`, and reduce `save()` to:

```swift
    /// A denial still saves the rule; the Alerts screen says why it is quiet.
    private func save() async {
        saving = true
        _ = await AlertNotifications.requestAccess()
        store.upsert(rule)
        dismiss()
    }
```

- [ ] **Step 7: Run the whole suite**

Run: `scripts/test.sh`
Expected: PASS, on both simulators.

- [ ] **Step 8: Commit**

```bash
git add -A Slackwater SlackwaterTests SlackwaterUITests
git commit -m "feat(alerts): a rule is a notification, and can name one moment

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `once` finds one occurrence, then expires

**Files:**
- Modify: `Slackwater/AlertOccurrences.swift:152-157`
- Modify: `Slackwater/AlertScheduler.swift` (`reschedule`)
- Test: `SlackwaterTests/AlertOccurrencesTests.swift`

**Interfaces:**
- Consumes: `AlertRule.once` (Task 1).
- Produces: `expiredRules(_ rules: [AlertRule], now: Date) -> [UUID]`.

- [ ] **Step 1: Write the failing tests**

Append to `SlackwaterTests/AlertOccurrencesTests.swift`, inside the existing class. It is `@MainActor`, and its fixtures are the `load(_:)` helper, `now`, `week` and `TideStationRecord.fridayHarborID` — use those, as the neighbouring cases do:

```swift
    func testAOnceRuleFindsOnlyItsOwnMoment() throws {
        let id = TideStationRecord.fridayHarborID
        let (station, position) = try load(id)
        let every = AlertRule(stationID: id, trigger: .tideExtreme(high: false))
        let all = alertOccurrences(every, station: station, position: position,
                                   from: now, to: week, threshold: 0.5)
        XCTAssertGreaterThan(all.count, 2, "the fixture needs several lows to pick one out of")
        let chosen = all[1].event

        var only = every
        only.once = chosen
        let found = alertOccurrences(only, station: station, position: position,
                                     from: now, to: week, threshold: 0.5)

        XCTAssertEqual(found.map(\.event), [chosen])
    }

    func testAOnceRuleGivenAnUnflooredInstantStillMatches() throws {
        let id = TideStationRecord.fridayHarborID
        let (station, position) = try load(id)
        let every = AlertRule(stationID: id, trigger: .tideExtreme(high: false))
        let chosen = alertOccurrences(every, station: station, position: position,
                                      from: now, to: week, threshold: 0.5)[1].event

        var only = every
        only.once = chosen.addingTimeInterval(47)   // a caller's un-floored Date

        XCTAssertEqual(alertOccurrences(only, station: station, position: position,
                                        from: now, to: week, threshold: 0.5).map(\.event),
                       [chosen])
    }

    func testAOnceRuleWhoseMomentIsNotAnEventFindsNothing() throws {
        let id = TideStationRecord.fridayHarborID
        let (station, position) = try load(id)
        var only = AlertRule(stationID: id, trigger: .tideExtreme(high: false))
        // 37 minutes past a 10-minute grid instant: no extreme lands on this minute.
        only.once = now.addingTimeInterval(37 * 60)

        XCTAssertEqual(alertOccurrences(only, station: station, position: position,
                                        from: now, to: week, threshold: 0.5), [])
    }

    func testExpiryTakesOnlyOnceRulesWhoseMomentHasPassed() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let repeating = AlertRule(stationID: "a", trigger: .slack)
        let past = AlertRule(stationID: "a", trigger: .slack, once: now.addingTimeInterval(-60))
        let coming = AlertRule(stationID: "a", trigger: .slack, once: now.addingTimeInterval(60))

        XCTAssertEqual(expiredRules([repeating, past, coming], now: now), [past.id])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `SLACKWATER_ONLY=AlertOccurrencesTests scripts/test.sh`
Expected: FAIL — `expiredRules` is not defined, and a `once` rule still returns every occurrence.

- [ ] **Step 3: Filter and expire**

In `Slackwater/AlertOccurrences.swift`, insert the `once` filter immediately after the range filter at line 153:

```swift
    found = found.filter { $0.event >= from && $0.event <= to }
    if let once = rule.once {
        // The stored instant is compared floored, so a caller that kept the popup's raw
        // Date matches the same event the reschedule found.
        let minute = alertMinute(once)
        found = found.filter { $0.event == minute }
    }
```

At the end of the same file:

```swift
/// `once` rules whose moment has passed. Their notification, if it had one, fired at
/// `event − lead` and is long gone; the rule is what is left to clear (spec §6).
func expiredRules(_ rules: [AlertRule], now: Date) -> [UUID] {
    rules.filter { ($0.once ?? .distantFuture) < now }.map(\.id)
}
```

- [ ] **Step 4: Clear them on every run**

In `Slackwater/AlertScheduler.swift`, at the top of `reschedule(now:)`:

```swift
    func reschedule(now: Date = appNow()) async {
        for id in expiredRules(AlertRuleStore.shared.rules, now: now) {
            AlertRuleStore.shared.remove(id)
        }
        let rules = AlertRuleStore.shared.rules
```

`remove` calls `persist`, whose `onChange` asks for another reschedule; the scheduler coalesces that into the single follow-up run it already allows, and the second run finds nothing to expire.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `SLACKWATER_ONLY=AlertOccurrencesTests scripts/test.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/AlertOccurrences.swift Slackwater/AlertScheduler.swift SlackwaterTests/AlertOccurrencesTests.swift
git commit -m "feat(alerts): a once rule fires for its own moment and then clears

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Station calendar subscriptions

Pure model and store. Nothing consumes it until Task 4.

**Files:**
- Create: `Slackwater/AlertStationCalendar.swift`
- Modify: `Slackwater/AppGroup.swift` (add `stationCalendarsKey`)
- Modify: `project.yml` is **not** touched — the app target globs `Slackwater/**`
- Test: `SlackwaterTests/StationCalendarTests.swift`

**Interfaces:**
- Consumes: `AlertTrigger` (Task 1), `WidgetRecord`.
- Produces: `StationCalendar(stationID:calendarID:)`; `StationCalendarStore.shared` with `subscriptions`, `calendarID(for:)`, `setCalendarID(_:for:)`, `subscribe(_:)`, `unsubscribe(_:)`; `StationCalendarKind` and `WidgetRecord.calendarKind`; `calendarTriggers(for: StationCalendarKind) -> [AlertTrigger]`; `stationCalendarTitle(name:kind:) -> String`; `CalendarSubscriptionChange` and `calendarSubscriptionChange(_:stationID:premium:)`.

- [ ] **Step 1: Write the failing tests**

Create `SlackwaterTests/StationCalendarTests.swift`:

```swift
// Slackwater — GPL v3. Station calendar subscriptions: what each kind publishes, what it's
// called, and the free tier's one-at-a-time rule.
import XCTest
@testable import Slackwater

final class StationCalendarTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "station-calendar-\(UUID().uuidString)")!
        d.removePersistentDomain(forName: d.dictionaryRepresentation().description)
        return d
    }

    // MARK: what a kind publishes

    func testATideStationPublishesBothExtremesAndEclipses() {
        XCTAssertEqual(calendarTriggers(for: .tide), [.tideExtreme(high: true),
                                                      .tideExtreme(high: false), .eclipse])
    }

    func testACurrentStationPublishesSlackWindowsAndEclipses() {
        XCTAssertEqual(calendarTriggers(for: .current), [.slackWindowOpens, .eclipse])
    }

    func testADerivedGatePublishesItsSlacksAndEclipses() {
        XCTAssertEqual(calendarTriggers(for: .derived), [.slack, .eclipse])
    }

    func testMaxFloodAndEbbAreNotPublished() {
        // ~8 events a day would make the calendar unreadable (spec §5.1).
        XCTAssertFalse(calendarTriggers(for: .current).contains(.currentPeak(flood: true)))
        XCTAssertFalse(calendarTriggers(for: .current).contains(.currentPeak(flood: false)))
    }

    // MARK: titles

    func testATideAndACurrentStationSharingANameGetDifferentTitles() {
        // Friday Harbor is both a tide station and a current station. One title between them
        // would have each run adopt the other's calendar and rewrite its events.
        XCTAssertNotEqual(stationCalendarTitle(name: "Friday Harbor", kind: .tide),
                          stationCalendarTitle(name: "Friday Harbor", kind: .current))
    }

    func testATitleNamesTheStationAndItsSeries() {
        XCTAssertEqual(stationCalendarTitle(name: "Friday Harbor", kind: .tide), "Friday Harbor Tides")
        XCTAssertEqual(stationCalendarTitle(name: "Race Passage", kind: .current), "Race Passage Currents")
        XCTAssertEqual(stationCalendarTitle(name: "Dodd Narrows", kind: .derived), "Dodd Narrows Currents")
    }

    // MARK: the free tier's one calendar

    func testAFreeUsersFirstStationJustGoesOn() {
        XCTAssertEqual(calendarSubscriptionChange([], stationID: "a", premium: false), .add)
    }

    func testAFreeUsersSecondStationReplacesTheFirst() {
        let on = [StationCalendar(stationID: "a", calendarID: "cal-a")]
        XCTAssertEqual(calendarSubscriptionChange(on, stationID: "b", premium: false),
                       .replace(stationID: "a"))
    }

    func testPremiumAddsAlongsideWhatIsAlreadyOn() {
        let on = [StationCalendar(stationID: "a", calendarID: "cal-a")]
        XCTAssertEqual(calendarSubscriptionChange(on, stationID: "b", premium: true), .add)
    }

    func testTurningOffTheStationThatIsOnRemovesIt() {
        let on = [StationCalendar(stationID: "a", calendarID: "cal-a")]
        XCTAssertEqual(calendarSubscriptionChange(on, stationID: "a", premium: false), .remove)
        XCTAssertEqual(calendarSubscriptionChange(on, stationID: "a", premium: true), .remove)
    }

    // MARK: the store

    @MainActor func testSubscriptionsSurviveARoundTrip() {
        let d = defaults()
        let store = StationCalendarStore(defaults: d)
        store.subscribe("a")
        store.setCalendarID("cal-a", for: "a")

        let reloaded = StationCalendarStore(defaults: d)

        XCTAssertEqual(reloaded.subscriptions, [StationCalendar(stationID: "a", calendarID: "cal-a")])
        XCTAssertEqual(reloaded.calendarID(for: "a"), "cal-a")
    }

    @MainActor func testSubscribingTwiceKeepsOneSubscriptionAndItsCalendar() {
        let store = StationCalendarStore(defaults: defaults())
        store.subscribe("a")
        store.setCalendarID("cal-a", for: "a")
        store.subscribe("a")

        XCTAssertEqual(store.subscriptions.count, 1)
        XCTAssertEqual(store.calendarID(for: "a"), "cal-a")
    }

    @MainActor func testUnsubscribingForgetsTheCalendar() {
        let store = StationCalendarStore(defaults: defaults())
        store.subscribe("a")
        store.setCalendarID("cal-a", for: "a")
        store.unsubscribe("a")

        XCTAssertEqual(store.subscriptions, [])
        XCTAssertNil(store.calendarID(for: "a"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `SLACKWATER_ONLY=StationCalendarTests scripts/test.sh`
Expected: FAIL — none of these symbols exist.

- [ ] **Step 3: Add the key**

In `Slackwater/AppGroup.swift`, beside `alertCalendarKey`:

```swift
    /// Which stations publish a calendar, and the identifier of each one (spec §5.1).
    static let stationCalendarsKey = "slackwater.stationCalendars"
```

There is no single app-wide calendar or key: each subscribed station gets its own calendar,
stored under its own entry in `stationCalendarsKey`. A station without a stored identifier yet
adopts a same-titled calendar only when Task 5's ownership check finds one of its own future
events naming that station — proof this app wrote it for that station, not a same-named one or a
calendar a person made by hand.

- [ ] **Step 4: Write the model**

Create `Slackwater/AlertStationCalendar.swift`:

```swift
// Slackwater — GPL v3. Which stations publish a calendar of their own, and what goes in one (notifications spec §5.1).
import Foundation

/// One station's calendar. `calendarID` is empty until EventKit has made or adopted it.
struct StationCalendar: Codable, Equatable, Identifiable {
    var stationID: String
    var calendarID: String = ""
    var id: String { stationID }
}

/// Which series a station reads in — the half of its calendar's title that keeps a tide
/// station and a current station of the same name apart.
enum StationCalendarKind {
    case tide, current, derived
}

extension WidgetRecord {
    var calendarKind: StationCalendarKind {
        switch self {
        case .tide: .tide
        case .current: .current
        case .derived: .derived
        }
    }
}

/// What a station's calendar publishes (spec §5.1): the planning events, not everything the
/// station knows. A current station's maxima and bare slacks would put ~8 events a day in
/// someone's calendar and make it unreadable. Eclipses come twice a year and ride along
/// everywhere.
func calendarTriggers(for kind: StationCalendarKind) -> [AlertTrigger] {
    switch kind {
    case .tide: [.tideExtreme(high: true), .tideExtreme(high: false), .eclipse]
    case .current: [.slackWindowOpens, .eclipse]
    case .derived: [.slack, .eclipse]
    }
}

/// The calendar's name, as it reads in someone's calendar list. The series is part of it
/// because a place can have both: Friday Harbor is a tide station AND a current station, and
/// one title between the two would have each reschedule adopt the other's calendar and
/// rewrite its events.
func stationCalendarTitle(name: String, kind: StationCalendarKind) -> String {
    switch kind {
    case .tide: "\(name) Tides"
    case .current, .derived: "\(name) Currents"
    }
}

/// What turning a station's toggle does, given what is already on.
enum CalendarSubscriptionChange: Equatable {
    case add
    /// Free holds one calendar: this station goes on and the named one comes off, once the
    /// user has read what that removes (spec §5.1).
    case replace(stationID: String)
    case remove
}

func calendarSubscriptionChange(_ subscriptions: [StationCalendar], stationID: String,
                                premium: Bool) -> CalendarSubscriptionChange {
    if subscriptions.contains(where: { $0.stationID == stationID }) { return .remove }
    if !premium, let only = subscriptions.first { return .replace(stationID: only.stationID) }
    return .add
}

@MainActor final class StationCalendarStore: ObservableObject {
    static let shared = StationCalendarStore(defaults: AppGroup.defaults)

    @Published private(set) var subscriptions: [StationCalendar]
    /// Assigned once at launch (SlackwaterApp.init) to the scheduler, like AlertRuleStore's.
    var onChange: () -> Void = {}
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        subscriptions = defaults.data(forKey: AppGroup.stationCalendarsKey)
            .flatMap { try? JSONDecoder().decode([StationCalendar].self, from: $0) } ?? []
    }

    func calendarID(for stationID: String) -> String? {
        subscriptions.first { $0.stationID == stationID }
            .map(\.calendarID).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Idempotent: subscribing to a station already on keeps the calendar it already has.
    func subscribe(_ stationID: String) {
        guard !subscriptions.contains(where: { $0.stationID == stationID }) else { return }
        subscriptions.append(StationCalendar(stationID: stationID))
        persist()
    }

    func unsubscribe(_ stationID: String) {
        subscriptions.removeAll { $0.stationID == stationID }
        persist()
    }

    func setCalendarID(_ id: String, for stationID: String) {
        guard let i = subscriptions.firstIndex(where: { $0.stationID == stationID }) else { return }
        subscriptions[i].calendarID = id
        persist()
    }

    private func persist() {
        defer { onChange() }
        // An encoding failure keeps what's stored rather than overwriting it with nothing.
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        defaults.set(data, forKey: AppGroup.stationCalendarsKey)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `SLACKWATER_ONLY=StationCalendarTests scripts/test.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/AlertStationCalendar.swift Slackwater/AppGroup.swift SlackwaterTests/StationCalendarTests.swift
git commit -m "feat(alerts): a station can publish a calendar of its own

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Subscriptions become occurrences and copy

**Files:**
- Modify: `Slackwater/AlertScheduler.swift` (`ResolvedAlerts`, `resolveAlerts`, `reschedule`)
- Modify: `Slackwater/AlertPlan.swift` (`alertCopy`)
- Test: `SlackwaterTests/AlertResolveTests.swift`, `SlackwaterTests/AlertCopyTests.swift`

**Interfaces:**
- Consumes: `calendarTriggers(for:)`, `StationCalendar` (Task 3); `deliveryPlan(rules:occurrences:calendarOccurrences:now:premium:)` (Task 1).
- Produces: `resolveAlerts(_ rules: [AlertRule], subscriptions: [String], now: Date, threshold: Double) -> ResolvedAlerts` with `calendarOccurrences: [AlertOccurrence]`, `calendarRules: [UUID: AlertRule]`, `calendarStations: [UUID: String]`; `alertCopy(_:_:place:imperial:threshold:includeLead:includePlace:locale:)`.

- [ ] **Step 1: Write the failing tests**

In `SlackwaterTests/AlertCopyTests.swift`, give the file's existing `copy(...)` helper the new argument (add the parameter and pass it through):

```swift
    private func copy(_ trigger: AlertTrigger, lead: TimeInterval = 0, end: Date? = nil, noWindow: Bool = false,
                      heightM: Double? = nil, imperial: Bool = true, includeLead: Bool = true,
                      includePlace: Bool = true) -> AlertCopy {
        let rule = AlertRule(stationID: "x", trigger: trigger, lead: lead)
        let o = AlertOccurrence(ruleID: rule.id, event: event, fire: event.addingTimeInterval(-lead),
                                end: end, noWindow: noWindow, heightM: heightM)
        return alertCopy(rule, o, place: place, imperial: imperial, threshold: 0.5,
                         includeLead: includeLead, includePlace: includePlace, locale: gb)
    }
```

then append these cases:

```swift
    func testACalendarTitleLeavesThePlaceToTheCalendarsName() {
        XCTAssertEqual(copy(.slackWindowOpens, end: event.addingTimeInterval(38 * 60),
                            includeLead: false, includePlace: false).title,
                       "Slack window")
    }

    func testANotificationTitleStillLeadsWithThePlace() {
        XCTAssertEqual(copy(.slackWindowOpens).title, "Race Passage - Slack window")
    }

    func testACalendarTideTitleCarriesItsHeight() {
        XCTAssertEqual(copy(.tideExtreme(high: true), heightM: 1.0, imperial: false,
                            includeLead: false, includePlace: false).title,
                       "High tide 1.00 m")
    }

    func testACalendarSlackWithNoWindowStillGetsAnEvent() {
        // A gap in the calendar would read as missing data rather than a shut gate.
        let c = copy(.slackWindowOpens, noWindow: true, includeLead: false, includePlace: false)

        XCTAssertEqual(c.title, "Slack")
        XCTAssertTrue(c.body.contains("no window under 0.5 kn"))
    }
```

Append to `SlackwaterTests/AlertResolveTests.swift`, which already has a `now` and reaches Friday Harbor through `TideStationRecord.fridayHarborID`:

```swift
    func testASubscribedStationResolvesItsOwnTriggersAndNoRules() {
        let resolved = resolveAlerts([], subscriptions: [TideStationRecord.fridayHarborID],
                                     now: now, threshold: 0.5)

        XCTAssertTrue(resolved.occurrences.isEmpty, "no rules, so no notifications")
        XCTAssertFalse(resolved.calendarOccurrences.isEmpty)
        let triggers = Set(resolved.calendarOccurrences.compactMap {
            resolved.calendarRules[$0.ruleID]?.trigger
        })
        XCTAssertTrue(triggers.contains(.tideExtreme(high: true)))
        XCTAssertTrue(triggers.contains(.tideExtreme(high: false)))
        XCTAssertFalse(triggers.contains(.currentPeak(flood: true)),
                       "a tide station publishes its extremes and nothing else")
    }

    func testEveryCalendarOccurrenceKnowsItsStation() {
        let resolved = resolveAlerts([], subscriptions: [TideStationRecord.fridayHarborID],
                                     now: now, threshold: 0.5)

        XCTAssertFalse(resolved.calendarOccurrences.isEmpty)
        for o in resolved.calendarOccurrences {
            XCTAssertEqual(resolved.calendarStations[o.ruleID], TideStationRecord.fridayHarborID)
        }
    }

    func testASubscriptionWhoseStationCannotLoadResolvesNothingAndIsNamed() {
        let resolved = resolveAlerts([], subscriptions: ["noaa/does-not-exist"],
                                     now: now, threshold: 0.5)

        XCTAssertEqual(resolved.calendarOccurrences, [])
        XCTAssertEqual(resolved.unresolvedStations, ["noaa/does-not-exist"])
    }

    func testCalendarOccurrencesCarryNoLead() {
        let resolved = resolveAlerts([], subscriptions: [TideStationRecord.fridayHarborID],
                                     now: now, threshold: 0.5)

        for o in resolved.calendarOccurrences {
            XCTAssertEqual(o.fire, o.event, "a calendar event sits at its own time")
        }
    }

    func testLosingPremiumKeepsEveryCalendarAndStopsTheNotifications() {
        // Review Focus 3: the free cap applies when a subscription is written, never when one
        // is planned — a lapsed subscriber keeps the four calendars they set up.
        let stations = [TideStationRecord.fridayHarborID]
        let rule = AlertRule(stationID: TideStationRecord.fridayHarborID,
                             trigger: .tideExtreme(high: false), lead: 1_800)
        let resolved = resolveAlerts([rule], subscriptions: stations, now: now, threshold: 0.5)

        let free = deliveryPlan(rules: [rule], occurrences: resolved.occurrences,
                                calendarOccurrences: resolved.calendarOccurrences,
                                now: now, premium: false)

        XCTAssertFalse(free.calendar.isEmpty)
        XCTAssertEqual(free.notifications, [])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `SLACKWATER_ONLY=AlertResolveTests scripts/test.sh`
Expected: FAIL — `resolveAlerts` takes no `subscriptions:`.

- [ ] **Step 3: Give copy a place switch**

In `Slackwater/AlertPlan.swift`, change `alertCopy`'s signature and its last three lines:

```swift
/// Title and body for one occurrence. A notification's title is the place, then the event in
/// as few words as it takes; a calendar event's carries no place, because its calendar is named
/// for one (spec §5.1) — and a tide's height rides in the title there, where the body is a note
/// nobody opens. The calendar passes `includeLead: false`: an event sits at its own time, so
/// "in 30 min" means nothing there.
func alertCopy(_ rule: AlertRule, _ o: AlertOccurrence, place: AlertPlace, imperial: Bool,
               threshold: Double, includeLead: Bool, includePlace: Bool = true,
               locale: Locale = .autoupdatingCurrent) -> AlertCopy {
```

and, replacing the final two lines of the function body:

```swift
    let event = alertEventName(rule.trigger, noWindow: o.noWindow, imperial: imperial)
    if includePlace { return AlertCopy(title: "\(place.name) - \(event)", body: body) }
    guard case .tideExtreme = rule.trigger, let h = o.heightM else {
        return AlertCopy(title: event, body: body)
    }
    return AlertCopy(title: "\(event) \(formatHeight(h, imperial: imperial)) \(heightUnit(imperial: imperial))",
                     body: body)
```

That `formatHeight` call lands inside `alertCopy`, whose two-line signature makes the type-scale scanner attribute it to `leadAmount` just above — already registered in `knownNonVisual`. Nothing to add.

- [ ] **Step 4: Resolve subscriptions**

In `Slackwater/AlertScheduler.swift`, replace `ResolvedAlerts` and `resolveAlerts`:

```swift
struct ResolvedAlerts: Sendable {
    /// From rules: what becomes a notification.
    var occurrences: [AlertOccurrence] = []
    /// From station subscriptions: what the calendar publishes.
    var calendarOccurrences: [AlertOccurrence] = []
    /// The throwaway rules behind `calendarOccurrences`, so copy has a trigger to read.
    var calendarRules: [UUID: AlertRule] = [:]
    /// Which station each of those belongs to, so the writer knows the calendar.
    var calendarStations: [UUID: String] = [:]
    /// Keyed by station id.
    var places: [String: AlertPlace] = [:]
    /// Enabled rules whose station can't be loaded yet — a CHS station not fitted on this
    /// device, or an id that left the catalog.
    var unresolved: Set<UUID> = []
    /// Subscribed stations that can't be loaded. Their calendars are left exactly as they
    /// are: an empty plan is "nothing known yet", not "delete the next 90 days".
    var unresolvedStations: Set<String> = []
}

/// Occurrences for every enabled rule and every subscribed station, from `now` to the calendar
/// horizon. Off the main actor: a season-scale scan per station is real work.
/// ponytail: two rules on one station load it twice; share the record if that ever measures.
func resolveAlerts(_ rules: [AlertRule], subscriptions: [String],
                   now: Date, threshold: Double) -> ResolvedAlerts {
    var resolved = ResolvedAlerts()
    let until = now.addingTimeInterval(AlertHorizon.calendar)

    for rule in rules where rule.enabled {
        guard let record = WidgetStationLoader.loadRecord(id: rule.stationID) else {
            resolved.unresolved.insert(rule.id)
            continue
        }
        resolved.places[rule.stationID] = record.alertPlace
        resolved.occurrences += alertOccurrences(rule, station: WidgetStationLoader.station(from: record),
                                                 position: record.alertPosition,
                                                 from: now, to: until, threshold: threshold)
    }

    for stationID in subscriptions {
        guard let record = WidgetStationLoader.loadRecord(id: stationID) else {
            resolved.unresolvedStations.insert(stationID)
            continue
        }
        resolved.places[stationID] = record.alertPlace
        let station = WidgetStationLoader.station(from: record)
        for trigger in calendarTriggers(for: record.calendarKind) {
            // A throwaway rule per trigger. Its id only has to be unique within this run:
            // a calendar event is matched by its content, never by an occurrence key.
            let rule = AlertRule(stationID: stationID, trigger: trigger)
            resolved.calendarRules[rule.id] = rule
            resolved.calendarStations[rule.id] = stationID
            resolved.calendarOccurrences += alertOccurrences(rule, station: station,
                                                             position: record.alertPosition,
                                                             from: now, to: until, threshold: threshold)
        }
    }
    return resolved
}
```

- [ ] **Step 5: Plan and write both halves**

In `reschedule(now:)`, replace everything from the `resolved` assignment to the `AlertNotifications.apply` line:

```swift
        let subscriptions = StationCalendarStore.shared.subscriptions.map(\.stationID)

        let resolved = await Task.detached(priority: .utility) {
            resolveAlerts(rules, subscriptions: subscriptions, now: now, threshold: threshold)
        }.value
        let plan = deliveryPlan(rules: rules, occurrences: resolved.occurrences,
                                calendarOccurrences: resolved.calendarOccurrences,
                                now: now, premium: premium)
        // A duplicated rule id would trap uniqueKeysWithValues; keep the first, as deliveryPlan does.
        let byID = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .merging(resolved.calendarRules) { mine, _ in mine }

        func entries(_ list: [AlertOccurrence], includeLead: Bool, includePlace: Bool) -> [AlertEntry] {
            list.compactMap { o in
                guard let rule = byID[o.ruleID], let place = resolved.places[rule.stationID] else { return nil }
                return AlertEntry(
                    stationID: rule.stationID,
                    occurrence: o,
                    copy: alertCopy(rule, o, place: place, imperial: imperial,
                                    threshold: threshold, includeLead: includeLead,
                                    includePlace: includePlace),
                    url: shareURL(forStationID: rule.stationID, at: o.event, tz: place.tz)
                        ?? deepLink(forStationID: rule.stationID),
                    place: place)
            }
        }

        AlertCalendar.apply(entries(plan.calendar, includeLead: false, includePlace: false),
                            skipping: resolved.unresolvedStations, now: now)
        await AlertNotifications.apply(entries(plan.notifications, includeLead: true, includePlace: true))
```

Add `stationID` to `AlertEntry` as its first field:

```swift
/// One planned delivery with everything a writer needs.
struct AlertEntry {
    /// Which station's calendar this belongs in.
    let stationID: String
    let occurrence: AlertOccurrence
    let copy: AlertCopy
    let url: URL?
    let place: AlertPlace
}
```

`AlertCalendar.apply(_:skipping:now:)` does not exist yet — Task 5 writes it. For this commit, change the existing signature in `Slackwater/AlertCalendar.swift:45` to accept and ignore the new argument so the tree builds:

```swift
    static func apply(_ entries: [AlertEntry], skipping: Set<String> = [], now: Date) {
```

- [ ] **Step 6: Cover the last trigger a station calendar publishes**

`testOccurrencesDoNotDriftBetweenRuns` in `SlackwaterTests/AlertOccurrencesTests.swift` already pins `.tideExtreme` both ways, `.slackWindowOpens`, `.tideCrossing` and `.currentPeak`. A derived gate's `.slack` is the one a station calendar publishes that it does not. Add it to the `cases` list:

```swift
            ("chs-malibu-rapids", .slack),           // a derived gate, when its reference is fitted
```

and make the loop tolerate a gate this machine hasn't fitted, replacing the `let (station, position) = try load(id)` line inside the `for`:

```swift
            // A CHS derived gate predicts only once its reference port is fitted, which not
            // every machine has done. Skipping is right; asserting would fail by geography.
            guard let record = WidgetStationLoader.loadRecord(id: id) else { continue }
            let (station, position) = (WidgetStationLoader.station(from: record), record.alertPosition)
```

`.eclipse` needs nothing here: `visibleEclipses` searches from an absolute window rather than the 10-minute sample grid, so its instants do not move with the run's start time the way a sampled series can.

- [ ] **Step 7: Run the suite**

Run: `scripts/test.sh`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Slackwater/AlertScheduler.swift Slackwater/AlertPlan.swift Slackwater/AlertCalendar.swift SlackwaterTests/AlertResolveTests.swift SlackwaterTests/AlertCopyTests.swift SlackwaterTests/AlertOccurrencesTests.swift
git commit -m "feat(alerts): a subscription resolves a station's own events

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: One calendar per station

**Files:**
- Modify: `Slackwater/AlertCalendar.swift`
- Test: `SlackwaterTests/StationCalendarTests.swift` (the grouping and skip logic, which is pure)

**Interfaces:**
- Consumes: `AlertEntry.stationID` (Task 4), `StationCalendarStore` and `stationCalendarTitle(name:kind:)` (Task 3).
- Produces: `AlertCalendar.apply(_ entries: [AlertEntry], skipping: Set<String>, now: Date)`, `AlertCalendar.calendarFor(stationID:title:create:) -> EKCalendar?`, `AlertCalendar.removeCalendar(for stationID: String)`, `AlertCalendar.futureEventCount(for stationID: String, now: Date) -> Int`; `calendarWriteGroups(_ entries: [AlertEntry], subscribed: [String], skipping: Set<String>) -> [String: [AlertEntry]]`.

- [ ] **Step 1: Write the failing tests**

Append to `SlackwaterTests/StationCalendarTests.swift` — EventKit can't be exercised in the suite, so the decision about *which* calendars get rewritten is pulled out where it can be:

```swift
    // MARK: which calendars a run rewrites

    private func entry(_ stationID: String) -> AlertEntry {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        return AlertEntry(stationID: stationID,
                          occurrence: AlertOccurrence(ruleID: UUID(), event: t, fire: t),
                          copy: AlertCopy(title: "Slack window", body: "14:32"),
                          url: nil,
                          place: AlertPlace(name: "Race Passage", tz: .gmt))
    }

    func testASubscribedStationWithNoEventsIsStillEmptied() {
        // It resolved and genuinely has nothing in the next 90 days — an empty plan is the
        // truth, and a calendar holding last month's events must be cleared.
        let groups = calendarWriteGroups([], subscribed: ["a"], skipping: [])

        XCTAssertEqual(groups, ["a": []])
    }

    func testAStationThatCouldNotLoadIsLeftAlone() {
        // "Nothing known yet" is not "delete the next 90 days" — a CHS station waiting on its
        // fit must not have its calendar wiped on every foreground.
        let groups = calendarWriteGroups([], subscribed: ["a", "b"], skipping: ["b"])

        XCTAssertEqual(Set(groups.keys), ["a"])
    }

    func testEntriesGoToTheirOwnStationsCalendar() {
        let groups = calendarWriteGroups([entry("a"), entry("b"), entry("a")],
                                         subscribed: ["a", "b"], skipping: [])

        XCTAssertEqual(groups["a"]?.count, 2)
        XCTAssertEqual(groups["b"]?.count, 1)
    }

    func testAnUnsubscribedStationsEntriesAreDropped() {
        // Belt and braces: a stale entry can't resurrect a calendar the user turned off.
        let groups = calendarWriteGroups([entry("gone")], subscribed: ["a"], skipping: [])

        XCTAssertEqual(groups, ["a": []])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `SLACKWATER_ONLY=StationCalendarTests scripts/test.sh`
Expected: FAIL — `calendarWriteGroups` is not defined.

- [ ] **Step 3: Rewrite the writer**

Replace the whole of `Slackwater/AlertCalendar.swift`:

```swift
// Slackwater — GPL v3. One calendar per subscribed station, and only the calendars this app made (notifications spec §5.1).
import EventKit

/// Which calendars this run rewrites, and with what. A subscribed station that resolved gets
/// its plan even when that plan is empty — it genuinely has nothing coming, and last month's
/// events have to go. A station that could NOT be loaded is absent instead: an empty plan from
/// a CHS station still waiting on its fit would read as "delete the next 90 days".
func calendarWriteGroups(_ entries: [AlertEntry], subscribed: [String],
                         skipping: Set<String>) -> [String: [AlertEntry]] {
    var groups: [String: [AlertEntry]] = [:]
    for stationID in subscribed where !skipping.contains(stationID) { groups[stationID] = [] }
    for entry in entries where groups[entry.stationID] != nil {
        groups[entry.stationID]?.append(entry)
    }
    return groups
}

@MainActor enum AlertCalendar {
    private static let store = EKEventStore()

    /// Full access only. Write-only access can save new events but never read back or
    /// remove them, so a comfort-speed change would strand the old windows in someone's calendar.
    static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Where a new calendar can go. Google and Exchange accounts refuse new calendars, so the
    /// default for new events falls back to iCloud and then to the device.
    private static var sources: [EKSource] {
        [store.defaultCalendarForNewEvents?.source].compactMap { $0 }
            + store.sources.filter { $0.sourceType == .calDAV && $0.title == "iCloud" }
            + store.sources.filter { $0.sourceType == .local }
    }

    /// This station's calendar: the stored identifier, else one already carrying the title,
    /// else a new one.
    ///
    /// The title match is what keeps a second device from making a duplicate. These calendars
    /// sync, so device B turning the same station on sees device A's calendar already there —
    /// without adopting it, the user ends up with two calendars of one name and every event
    /// twice. Adopting is safe here because a station calendar's contents are a function of the
    /// station, not of anything device-local: both devices plan the same events. The exception
    /// is a current station under two different comfort speeds, which rewrite each other's
    /// windows; that setting describes one boat (spec §5.1).
    static func calendarFor(stationID: String, title: String, create: Bool) -> EKCalendar? {
        if let id = StationCalendarStore.shared.calendarID(for: stationID),
           let existing = store.calendar(withIdentifier: id) { return existing }
        let allowed = Set(sources.map(\.sourceIdentifier))
        if let adopted = store.calendars(for: .event).first(where: {
            $0.title == title && allowed.contains($0.source.sourceIdentifier)
        }) {
            StationCalendarStore.shared.setCalendarID(adopted.calendarIdentifier, for: stationID)
            return adopted
        }
        guard create else { return nil }
        for source in sources {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = title
            calendar.source = source
            guard (try? store.saveCalendar(calendar, commit: true)) != nil else { continue }
            StationCalendarStore.shared.setCalendarID(calendar.calendarIdentifier, for: stationID)
            return calendar
        }
        return nil
    }

    /// Turning a station off takes its events with it — that is what the confirmation the user
    /// read said would happen.
    static func removeCalendar(for stationID: String) {
        guard authorized, let id = StationCalendarStore.shared.calendarID(for: stationID),
              let calendar = store.calendar(withIdentifier: id) else { return }
        try? store.removeCalendar(calendar, commit: true)
    }

    /// How many of this station's events are still to come — the number the swap and the
    /// turn-off confirmations name.
    static func futureEventCount(for stationID: String, now: Date) -> Int {
        guard authorized, let id = StationCalendarStore.shared.calendarID(for: stationID),
              let calendar = store.calendar(withIdentifier: id) else { return 0 }
        return store.events(matching: store.predicateForEvents(
            withStart: now, end: now.addingTimeInterval(AlertHorizon.calendar + 86_400),
            calendars: [calendar])).count
    }

    /// Makes each subscribed station's calendar match its plan: removes events that haven't
    /// started and are no longer planned, and adds the missing ones. An event already under way
    /// is left alone. It matches within a tolerance rather than by exact content, since the
    /// engine's event search can land an instant a second apart from one reschedule to the next.
    /// ponytail: an event the user edited by hand (moved, retitled) stops matching and is
    /// replaced. Runs on the main actor — a few hundred EventKit saves; move off it if it measures.
    static func apply(_ entries: [AlertEntry], skipping: Set<String> = [], now: Date) {
        guard authorized else { return }
        let subscribed = StationCalendarStore.shared.subscriptions.map(\.stationID)
        for (stationID, planned) in calendarWriteGroups(entries, subscribed: subscribed, skipping: skipping) {
            guard let record = WidgetStationLoader.loadRecord(id: stationID) else { continue }
            let title = stationCalendarTitle(name: record.alertPlace.name, kind: record.calendarKind)
            // Nothing planned and no calendar yet: don't make an empty one.
            guard let calendar = calendarFor(stationID: stationID, title: title,
                                             create: !planned.isEmpty) else { continue }
            sync(calendar, to: planned, now: now)
        }
    }

    private static func sync(_ calendar: EKCalendar, to entries: [AlertEntry], now: Date) {
        let predicate = store.predicateForEvents(withStart: now,
                                                 end: now.addingTimeInterval(AlertHorizon.calendar + 86_400),
                                                 calendars: [calendar])
        let existing = store.events(matching: predicate)
        let stored = existing.map { event in
            CalendarEventShape(title: event.title ?? "", start: event.startDate, end: event.endDate,
                               alarmOffset: event.alarms?.first?.relativeOffset)
        }
        let planned = entries.map { entry in
            CalendarEventShape(title: entry.copy.title, start: entry.occurrence.event,
                               end: entry.occurrence.end ?? entry.occurrence.event, alarmOffset: nil)
        }
        let changes = calendarChanges(existing: stored, wanted: planned, now: now)
        for i in changes.remove {
            try? store.remove(existing[i], span: .thisEvent, commit: false)
        }
        for i in changes.add {
            let entry = entries[i]
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = entry.copy.title
            event.notes = entry.copy.body
            event.startDate = entry.occurrence.event
            event.endDate = entry.occurrence.end ?? entry.occurrence.event
            event.timeZone = entry.place.tz
            event.url = entry.url
            try? store.save(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }
}
```

An event carrying an alarm from an older build no longer matches anything planned (`alarmOffset: nil` on every planned shape), so the first run after this ships replaces it with an alarm-free one. That is the intent: no Slackwater calendar event carries an alarm.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `SLACKWATER_ONLY=StationCalendarTests scripts/test.sh`
Expected: PASS.

- [ ] **Step 5: Run the suite**

Run: `scripts/test.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/AlertCalendar.swift SlackwaterTests/StationCalendarTests.swift
git commit -m "feat(alerts): write each station's events to its own calendar

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: What the popup offers

Pure logic, no view. Task 7 renders it.

**Files:**
- Modify: `Slackwater/AlertOffer.swift`
- Modify: `SlackwaterTests/TypeScaleTests.swift:88-136` (register the new formatter caller)
- Test: `SlackwaterTests/AlertOfferTests.swift`

**Interfaces:**
- Consumes: `AlertRule.once`, `AlertRuleChange`, `alertMinute(_:)`, `alertEventName(_:noWindow:imperial:)`.
- Produces: `alertPopupLead: TimeInterval`; `AlertPopupRow`; `alertPopupState(_:stationID:offer:at:premium:) -> (once: Bool, every: Bool)`; `alertPopupToggle(_:stationID:offer:at:row:) -> AlertRuleChange`; `alertEveryLabel(_:imperial:) -> String`.

- [ ] **Step 1: Write the failing tests**

Append to `SlackwaterTests/AlertOfferTests.swift`:

```swift
    // MARK: the popup's two rows

    private let moment = Date(timeIntervalSince1970: 1_700_000_040)

    func testTheFirstTapMakesARuleForThatMomentAlone() {
        let change = alertPopupToggle([], stationID: "a", offer: .slack, at: moment, row: .once)

        guard case .upsert(let rule) = change else { return XCTFail("expected a new rule") }
        XCTAssertEqual(rule.once, moment)
        XCTAssertEqual(rule.lead, alertPopupLead)
        XCTAssertEqual(rule.trigger, .slack)
        XCTAssertTrue(rule.enabled)
    }

    func testTheEveryRowMakesARuleWithNoMoment() {
        let change = alertPopupToggle([], stationID: "a", offer: .slack, at: moment, row: .every)

        guard case .upsert(let rule) = change else { return XCTFail("expected a new rule") }
        XCTAssertNil(rule.once)
    }

    func testTappingARowThatIsOnRemovesItsRule() {
        let rule = AlertRule(stationID: "a", trigger: .slack, once: moment)

        XCTAssertEqual(alertPopupToggle([rule], stationID: "a", offer: .slack, at: moment, row: .once),
                       .remove(rule.id))
    }

    func testTheTwoRowsAreIndependent() {
        let once = AlertRule(stationID: "a", trigger: .slack, once: moment)

        // The every row doesn't see the once rule as its own.
        guard case .upsert(let made) = alertPopupToggle([once], stationID: "a", offer: .slack,
                                                        at: moment, row: .every)
        else { return XCTFail("expected a new rule") }
        XCTAssertNil(made.once)
        XCTAssertNotEqual(made.id, once.id)
    }

    func testASecondTapOnTheSameMomentDoesNotMakeASecondRule() {
        // Review Focus 5: a double tap, or a tap landing while the first write is in flight.
        let first = alertPopupToggle([], stationID: "a", offer: .slack, at: moment, row: .once)
        guard case .upsert(let rule) = first else { return XCTFail("expected a new rule") }

        XCTAssertEqual(alertPopupToggle([rule], stationID: "a", offer: .slack, at: moment, row: .once),
                       .remove(rule.id))
    }

    func testAnUnflooredMomentFindsTheRuleMadeFromItsMinute() {
        let rule = AlertRule(stationID: "a", trigger: .slack, once: alertMinute(moment))

        XCTAssertEqual(alertPopupToggle([rule], stationID: "a", offer: .slack,
                                        at: moment.addingTimeInterval(31), row: .once),
                       .remove(rule.id))
    }

    func testASwitchedOffRuleWakesInsteadOfASecondBeingMade() {
        var off = AlertRule(stationID: "a", trigger: .slack)
        off.enabled = false

        guard case .upsert(let woken) = alertPopupToggle([off], stationID: "a", offer: .slack,
                                                         at: moment, row: .every)
        else { return XCTFail("expected the rule back") }
        XCTAssertEqual(woken.id, off.id)
        XCTAssertTrue(woken.enabled)
    }

    func testARuleOnAnotherStationOrTriggerIsNotThisRow() {
        let elsewhere = AlertRule(stationID: "b", trigger: .slack, once: moment)
        let other = AlertRule(stationID: "a", trigger: .tideExtreme(high: true), once: moment)

        guard case .upsert = alertPopupToggle([elsewhere, other], stationID: "a", offer: .slack,
                                              at: moment, row: .once)
        else { return XCTFail("expected a new rule") }
    }

    // MARK: which rows read on

    func testARowReadsOnOnlyForItsOwnRule() {
        let rules = [AlertRule(stationID: "a", trigger: .slack, once: moment)]

        let state = alertPopupState(rules, stationID: "a", offer: .slack, at: moment, premium: true)

        XCTAssertTrue(state.once)
        XCTAssertFalse(state.every)
    }

    func testNothingReadsOnWithoutPremium() {
        // However the stored rule reads, notifications never fire without it.
        let rules = [AlertRule(stationID: "a", trigger: .slack, once: moment)]

        XCTAssertEqual(alertPopupState(rules, stationID: "a", offer: .slack, at: moment,
                                       premium: false).once, false)
    }

    func testASwitchedOffRuleReadsOff() {
        var off = AlertRule(stationID: "a", trigger: .slack, once: moment)
        off.enabled = false

        XCTAssertEqual(alertPopupState([off], stationID: "a", offer: .slack, at: moment,
                                       premium: true).once, false)
    }

    // MARK: the repeating row's words

    func testTheEveryLabelReadsAsASentence() {
        XCTAssertEqual(alertEveryLabel(.slackWindowOpens, imperial: true), "Every slack window")
        XCTAssertEqual(alertEveryLabel(.tideExtreme(high: false), imperial: true), "Every low tide")
        XCTAssertEqual(alertEveryLabel(.currentPeak(flood: true), imperial: true), "Every max flood")
        XCTAssertEqual(alertEveryLabel(.eclipse, imperial: true), "Every lunar eclipse")
    }

    func testACrossingsEveryLabelIsAClause() {
        // "Every rising past 3.3 ft" is not English.
        XCTAssertEqual(alertEveryLabel(.tideCrossing(heightM: 1.0, rising: false), imperial: false),
                       "Every time it falls past 1.00 m")
        XCTAssertEqual(alertEveryLabel(.tideCrossing(heightM: 1.0, rising: true), imperial: false),
                       "Every time it rises past 1.00 m")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `SLACKWATER_ONLY=AlertOfferTests scripts/test.sh`
Expected: FAIL — none of `alertPopupToggle`, `alertPopupState`, `alertEveryLabel`, `alertPopupLead` exist.

- [ ] **Step 3: Write the logic**

Append to `Slackwater/AlertOffer.swift`:

```swift
/// The popup's two rows (spec §7.2): this moment, or every one like it.
enum AlertPopupRow: Equatable {
    case once, every
}

/// A rule made from the popup reminds half an hour ahead; the Alerts screen changes it.
let alertPopupLead: TimeInterval = 1_800

/// The rule a row would own: same station, same trigger, and either bound to this minute or
/// not bound at all.
private func popupRule(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                       at moment: Date, row: AlertPopupRow, enabled: Bool) -> AlertRule? {
    let want: Date? = row == .once ? alertMinute(moment) : nil
    return rules.first {
        $0.stationID == stationID && $0.trigger == offer && $0.once == want && $0.enabled == enabled
    }
}

/// Which rows read on. Neither does without Premium: notifications never fire without it,
/// however the stored rule reads.
func alertPopupState(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                     at moment: Date, premium: Bool) -> (once: Bool, every: Bool) {
    guard premium else { return (false, false) }
    return (popupRule(rules, stationID: stationID, offer: offer, at: moment,
                      row: .once, enabled: true) != nil,
            popupRule(rules, stationID: stationID, offer: offer, at: moment,
                      row: .every, enabled: true) != nil)
}

/// One tap on a row: remove the rule it owns, wake the switched-off one, or make it. The
/// moment is floored, so a second tap finds the first tap's rule however the caller rounded.
func alertPopupToggle(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                      at moment: Date, row: AlertPopupRow) -> AlertRuleChange {
    if let on = popupRule(rules, stationID: stationID, offer: offer, at: moment,
                          row: row, enabled: true) {
        return .remove(on.id)
    }
    if var off = popupRule(rules, stationID: stationID, offer: offer, at: moment,
                           row: row, enabled: false) {
        off.enabled = true
        return .upsert(off)
    }
    return .upsert(AlertRule(stationID: stationID, trigger: offer,
                             once: row == .once ? alertMinute(moment) : nil,
                             lead: alertPopupLead))
}

/// The repeating row's words. A crossing needs a clause — "Every rising past 3.3 ft" is not
/// English — and everything else is its event name with a small letter.
func alertEveryLabel(_ trigger: AlertTrigger, imperial: Bool) -> String {
    switch trigger {
    case .tideCrossing(let heightM, let rising):
        "Every time it \(rising ? "rises" : "falls") past "
            + "\(formatHeight(heightM, imperial: imperial)) \(heightUnit(imperial: imperial))"
    default:
        {
            let name = alertEventName(trigger, imperial: imperial)
            return "Every \(name.prefix(1).lowercased())\(name.dropFirst())"
        }()
    }
}
```

- [ ] **Step 4: Register the new formatter caller**

In `SlackwaterTests/TypeScaleTests.swift`, add to `knownIndirections` after the `AlertRule.swift:alertEventName` entry:

```swift
            // The popup's repeating row: built here, rendered by AlertPopup's one Text, which
            // carries the mono trait (AlertPopup.swift).
            "AlertOffer.swift:alertEveryLabel",
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `SLACKWATER_ONLY=AlertOfferTests scripts/test.sh` then `SLACKWATER_ONLY=TypeScaleTests scripts/test.sh`
Expected: PASS for both.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/AlertOffer.swift SlackwaterTests/AlertOfferTests.swift SlackwaterTests/TypeScaleTests.swift
git commit -m "feat(alerts): the popup's two rows, and what each tap means

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Press and hold the strip

**Files:**
- Create: `Slackwater/AlertPopup.swift`
- Modify: `Slackwater/TimelineStrip.swift:1150-1172` (`makeUIView`), `:1490` (the coordinator), `:1592-1636` (`TimelineScrubStrip`)
- Modify: `Slackwater/Theme.swift:911-932` (`scrubCard`), `:1000-1013` (the environment keys)
- Test: `SlackwaterUITests/AlertPopupTests.swift`

**Interfaces:**
- Consumes: `alertPopupState`, `alertPopupToggle`, `alertEveryLabel`, `alertPopupLead` (Task 6); `ScrubDetailScaffold.alertOffer` (Task 1).
- Produces: `EnvironmentValues.openAlertPopup: () -> Void`; `TimelineScrubber.onLongPress: () -> Void`; `AlertPopup(stationID:offer:moment:place:)`.

- [ ] **Step 1: Write the failing UI test**

Create `SlackwaterUITests/AlertPopupTests.swift`:

```swift
// Slackwater — GPL v3. A long press on the strip offers an alert for the moment under it (notifications spec §7.1–§7.2).
import XCTest

final class AlertPopupTests: ScreenshotTestCase {
    /// Press and hold the middle of the strip, where the plot is.
    private func pressStrip(_ app: XCUIApplication) {
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 5))
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            .press(forDuration: 1.0)
    }

    func testALongPressOnATideStripOffersAnAlert() {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        pressStrip(app)

        XCTAssert(app.buttons["alert-popup-once"].appears(within: 5))
        XCTAssert(app.buttons["alert-popup-every"].exists)
    }

    func testALongPressOnACurrentStripOffersTheSlackWindow() {
        let app = launch("-seedGate")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        pressStrip(app)

        XCTAssert(app.buttons["alert-popup-every"].appears(within: 5))
        XCTAssertTrue(app.buttons["alert-popup-every"].label.contains("slack window"))
    }

    func testAFreeUsersTapOpensTheTierSheet() {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        pressStrip(app)
        XCTAssert(app.buttons["alert-popup-once"].appears(within: 5))
        app.buttons["alert-popup-once"].tap()

        XCTAssert(app.navigationBars["Slackwater Premium"].appears(within: 5))
    }

    func testTheStripIsStillScrubbableAfterThePopupCloses() {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        pressStrip(app)
        XCTAssert(app.buttons["alert-popup-once"].appears(within: 5))
        // Dismiss by tapping outside the popover.
        app.tap()

        let reading = app.descendants(matching: .any)["detail-reading"].firstMatch
        let before = reading.label
        app.otherElements["timeline-strip"].firstMatch.swipeLeft()

        XCTAssertNotEqual(reading.label, before)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `SLACKWATER_ONLY=AlertPopupTests scripts/test.sh`
Expected: FAIL — no `alert-popup-once` element.

- [ ] **Step 3: Recognize the press**

In `Slackwater/TimelineStrip.swift`, add the callback to `TimelineScrubber` beside `onPickDate` (search for `var onPickDate` and put it after):

```swift
    /// The strip was pressed and held; its moment is already on the centerline.
    var onLongPress: () -> Void = {}
```

Replace the recognizer registration in `makeUIView` (lines 1165-1166):

```swift
        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handlePress(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        // A press held and then lifted must not also scrub. The press fails the instant the
        // finger leaves before its half second, so an ordinary tap is not delayed.
        tap.require(toFail: press)
        sv.addGestureRecognizer(press)
        sv.addGestureRecognizer(tap)
```

In the `Coordinator`, after `handleTap`:

```swift
        /// A press and hold: park its moment on the centerline and let the scaffold open the
        /// popup there. Instant, not the tap's animated magnet ride — a press names one moment,
        /// and a popup opening over a sliding strip could not say what it was about until the
        /// slide landed. The day row belongs to the picker's tap and answers a press with
        /// nothing.
        @objc func handlePress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let sv = g.view as? UIScrollView, sv.bounds.width > 0 else { return }
            let p = g.location(in: sv)
            guard p.y <= (parent.geo.timeY + parent.geo.dayY) / 2 else { return }
            stopIntro()
            sv.setContentOffset(sv.contentOffset, animated: false)
            cancelMagnet()
            // The same magnet the strip settles into: a press near a turn means that turn.
            let target: Date
            if let stop = nearest(parent.data.snapTimes, toX: p.x), stop.dx < Timeline.magnetPts {
                target = stop.time
            } else {
                target = parent.data.time(atX: p.x)
            }
            let maxOffset = max(parent.data.totalWidth - sv.bounds.width, 0)
            let desired = min(max(parent.data.x(target) - sv.bounds.width / 2, 0), maxOffset)
            sv.contentOffset = CGPoint(x: desired, y: 0)
            parent.scrubTime = parent.data.time(atX: desired + sv.bounds.width / 2)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress()
        }
```

In `TimelineScrubStrip`, read the new environment closure beside `openWeekPicker` (line 1612) and pass it down (line 1621):

```swift
    @Environment(\.openWeekPicker) private var openWeekPicker
    @Environment(\.openAlertPopup) private var openAlertPopup
```

```swift
                         onPickDate: openWeekPicker,
                         onLongPress: openAlertPopup)
```

- [ ] **Step 4: Add the environment key and the popover**

In `Slackwater/Theme.swift`, beside `OpenWeekPickerKey`:

```swift
/// How the strip tells the scaffold it was pressed and held. Same reasoning as
/// `openWeekPicker`: the strip is three views deep in every detail, and the layers between
/// have nothing to say about alerts.
private struct OpenAlertPopupKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openAlertPopup: () -> Void {
        get { self[OpenAlertPopupKey.self] }
        set { self[OpenAlertPopupKey.self] = newValue }
    }
}
```

In `ScrubDetailScaffold`, beside `showPicker` (line 62):

```swift
    @State private var showAlertPopup = false
```

Inject it beside `openWeekPicker` (line 839):

```swift
            .environment(\.openAlertPopup, { if alertOffer != nil { showAlertPopup = true } })
```

And attach the popover to the card in `scrubCard`:

```swift
            card(tl)
                // `.point(.center)` is the centerline, which is where the press just parked
                // its moment. `.presentationCompactAdaptation(.popover)` keeps it an
                // arrow-anchored card on iPhone instead of adapting to a sheet.
                .popover(isPresented: $showAlertPopup, attachmentAnchor: .point(.center),
                         arrowEdge: .top) {
                    if let alertOffer {
                        AlertPopup(stationID: favoriteId, offer: alertOffer,
                                   moment: scrubTime, tz: tz, stationName: name)
                            .presentationCompactAdaptation(.popover)
                    }
                }
```

- [ ] **Step 5: Write the popup**

Create `Slackwater/AlertPopup.swift`:

```swift
// Slackwater — GPL v3. Press and hold a moment on the strip: alert me then, or every time (notifications spec §7.2).
import SwiftUI

/// Two rows and a header naming what the press landed on. No lead picker: half an hour, and
/// the Alerts screen changes it. Without Premium both rows lead to the tier sheet and no rule
/// is made — this is the third and last upsell surface (widgets-premium §5).
struct AlertPopup: View {
    let stationID: String
    let offer: AlertTrigger
    let moment: Date
    let tz: TimeZone
    let stationName: String

    @ObservedObject private var store = AlertRuleStore.shared
    @ObservedObject private var premium = PremiumStore.shared
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @Environment(\.dismiss) private var dismiss
    @State private var showPremium = false
    /// True while a tap's permission prompt and store write are in flight: a second tap in
    /// that gap must be ignored, not read the rules as they stood before the first landed.
    @State private var applying = false

    private var imperial: Bool { units == "imperial" }

    var body: some View {
        let state = alertPopupState(store.rules, stationID: stationID, offer: offer,
                                    at: moment, premium: premium.isPremium)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stationName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SN.foam.opacity(0.62))
                Text("\(moment.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: tz))) · \(alertEventName(offer, imperial: imperial))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider().overlay(Color.white.opacity(0.08))
            row("Alert me", on: state.once, id: "alert-popup-once") { tap(.once) }
            Divider().overlay(Color.white.opacity(0.08))
            row(alertEveryLabel(offer, imperial: imperial), on: state.every,
                id: "alert-popup-every") { tap(.every) }
        }
        .frame(width: 280)
        .background(SN.cardFill)
        .sheet(isPresented: $showPremium) { PremiumView() }
    }

    private func row(_ title: String, on: Bool, id: String,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: on ? "bell.fill" : "bell")
                .font(.footnote)
                .foregroundStyle(on ? SN.leaf : SN.foam.opacity(0.62))
            Text(title)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(on ? SN.leaf : .white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        // A tap gesture, not a Button: Button press tracking goes dead in the iPad split
        // layout's detail column (ReadoutTile, MultiDaySchedule).
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }

    private func tap(_ row: AlertPopupRow) {
        guard !applying else { return }
        guard premium.isPremium else {
            showPremium = true
            return
        }
        applying = true
        Task {
            defer { applying = false }
            // Notification permission is asked the first time a rule is made, never at launch.
            if case .upsert = alertPopupToggle(store.rules, stationID: stationID, offer: offer,
                                               at: moment, row: row) {
                _ = await AlertNotifications.requestAccess()
            }
            // Decide against the rules as they stand after the prompt, so nothing that changed
            // while it was up can turn this tap into a duplicate.
            switch alertPopupToggle(store.rules, stationID: stationID, offer: offer,
                                    at: moment, row: row) {
            case .upsert(let rule): store.upsert(rule)
            case .remove(let id): store.remove(id)
            }
            dismiss()
        }
    }
}
```

- [ ] **Step 6: Run the UI test to verify it passes**

Run: `SLACKWATER_ONLY=AlertPopupTests scripts/test.sh`
Expected: PASS.

- [ ] **Step 7: Run the suite**

Run: `scripts/test.sh`
Expected: PASS on both simulators.

- [ ] **Step 8: Commit**

```bash
git add Slackwater/AlertPopup.swift Slackwater/TimelineStrip.swift Slackwater/Theme.swift SlackwaterUITests/AlertPopupTests.swift
git commit -m "feat(alerts): press and hold the strip to set an alert

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Settings → Calendar

**Files:**
- Create: `Slackwater/CalendarStationsView.swift`
- Modify: `Slackwater/SettingsView.swift:15,58-75`
- Modify: `Slackwater/SlackwaterApp.swift` (wire `StationCalendarStore.shared.onChange`)
- Test: `SlackwaterUITests/CalendarSettingsTests.swift`

**Interfaces:**
- Consumes: `StationCalendarStore`, `calendarSubscriptionChange`, `stationCalendarTitle(name:kind:)` (Task 3); `AlertCalendar.removeCalendar(for:)`, `.futureEventCount(for:now:)`, `.requestAccess()` (Task 5).
- Produces: `CalendarStationsView`.

- [ ] **Step 1: Write the failing UI test**

Create `SlackwaterUITests/CalendarSettingsTests.swift`:

```swift
// Slackwater — GPL v3. Settings → Calendar: subscribe a station, one at a time without Premium (notifications spec §7.4).
import XCTest

final class CalendarSettingsTests: ScreenshotTestCase {
    private func openCalendarSettings(_ app: XCUIApplication) {
        app.buttons["Settings"].tap()
        let row = app.buttons["settings-calendar-row"].firstMatch
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssert(app.navigationBars["Calendar"].appears(within: 5))
    }

    /// One tide station and one current station: the two calendar kinds, both in the bundle.
    private let tide = "noaa/9444900"
    private let current = "current:noaa/PUG1701"

    func testTheCalendarSectionListsSavedStations() {
        let app = launch("-seedGate", "-seedFavorites", "\(tide),\(current)")
        openCalendarSettings(app)

        XCTAssert(app.switches["calendar-station-\(tide)"].appears(within: 5))
        XCTAssert(app.switches["calendar-station-\(current)"].exists)
    }

    func testAStationWithNoSavedStationsExplainsItself() {
        let app = launch("-seedGate", "-resetFavorites")
        openCalendarSettings(app)

        XCTAssert(app.staticTexts["calendar-empty"].appears(within: 5))
    }

    func testAFreeUserTurningOneOnLeavesTheOtherOff() {
        let app = launch("-seedGate", "-seedFavorites", "\(tide),\(current)")
        openCalendarSettings(app)
        app.switches["calendar-station-\(tide)"].tap()
        allowCalendarIfAsked(app)

        XCTAssertEqual(app.switches["calendar-station-\(current)"].value as? String, "0")
    }

    /// The calendar prompt is a system alert and only appears on the first run of a fresh sim.
    private func allowCalendarIfAsked(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        guard springboard.alerts.firstMatch.appears(within: 6) else { return }
        for label in ["Allow Full Access", "Allow", "OK", "Continue"] {
            let button = springboard.alerts.buttons[label].firstMatch
            if button.exists { button.tap(); return }
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `SLACKWATER_ONLY=CalendarSettingsTests scripts/test.sh`
Expected: FAIL — no `settings-calendar-row`.

- [ ] **Step 3: Write the screen**

Create `Slackwater/CalendarStationsView.swift`:

```swift
// Slackwater — GPL v3. Which stations publish a calendar: one for free, as many as you like with Premium (notifications spec §7.4).
import SwiftUI

struct CalendarStationsView: View {
    @ObservedObject private var calendars = StationCalendarStore.shared
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var premium = PremiumStore.shared
    @State private var showPremium = false
    @State private var pending: PendingSwap?
    @State private var denied = false

    /// A swap a free user has to read before it happens: turning `on` on takes `off`'s
    /// calendar, and its events, away.
    private struct PendingSwap: Identifiable {
        let on: String
        let off: String
        let offName: String
        let events: Int
        var id: String { on }
    }

    private func name(_ stationID: String) -> String { StationItem.byId[stationID]?.name ?? stationID }

    /// A station can publish only what this device can predict offline. An online-only CHS
    /// gate has no loader record, so it has nothing to write (spec §8).
    private func canPublish(_ stationID: String) -> Bool {
        WidgetStationLoader.loadRecord(id: stationID) != nil
    }

    var body: some View {
        List {
            if favorites.ids.isEmpty {
                Text("Save a station and it can publish its tides or slack windows to your calendar.")
                    .foregroundStyle(SN.foam.opacity(0.62))
                    .accessibilityIdentifier("calendar-empty")
            }
            ForEach(favorites.ids, id: \.self) { stationID in
                row(stationID)
            }
            if !premium.isPremium, !favorites.ids.isEmpty {
                Section {
                    Text("One station's calendar is free. Slackwater Premium publishes as many as you like, each its own calendar you can switch on and off.")
                        .font(.caption)
                        .foregroundStyle(SN.foam.opacity(0.62))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CanvasBackground())
        .sheet(isPresented: $showPremium) { PremiumView() }
        .alert("Calendar access is off", isPresented: $denied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Slackwater needs calendar access to publish a station's events. Turn it on in Settings → Slackwater.")
        }
        .confirmationDialog("Replace \(pending?.offName ?? "")?", isPresented: swapPrompt,
                            presenting: pending) { swap in
            Button("Replace", role: .destructive) { Task { await apply(swap) } }
            Button("Get Premium") { showPremium = true }
            Button("Cancel", role: .cancel) {}
        } message: { swap in
            Text("\(swap.offName)'s calendar and its \(swap.events) upcoming events will be removed. One station's calendar is free.")
        }
    }

    private var swapPrompt: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private func row(_ stationID: String) -> some View {
        let on = calendars.subscriptions.contains { $0.stationID == stationID }
        let publishable = canPublish(stationID)
        return Toggle(isOn: Binding(get: { on }, set: { _ in Task { await toggle(stationID) } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name(stationID)).foregroundStyle(.white)
                Text(publishable
                     ? (on ? stationCalendarTitle(name: name(stationID),
                                                  kind: WidgetStationLoader.loadRecord(id: stationID)!.calendarKind)
                           : "Publish this station's events")
                     : "Needs a download before it can publish")
                    .font(.caption)
                    .foregroundStyle(SN.foam.opacity(0.62))
            }
        }
        .disabled(!publishable)
        .accessibilityIdentifier("calendar-station-\(stationID)")
    }

    private func toggle(_ stationID: String) async {
        switch calendarSubscriptionChange(calendars.subscriptions, stationID: stationID,
                                          premium: premium.isPremium) {
        case .remove:
            AlertCalendar.removeCalendar(for: stationID)
            calendars.unsubscribe(stationID)
        case .add:
            guard await grantedAccess() else { return }
            calendars.subscribe(stationID)
        case .replace(let off):
            guard await grantedAccess() else { return }
            pending = PendingSwap(on: stationID, off: off, offName: name(off),
                                  events: AlertCalendar.futureEventCount(for: off, now: appNow()))
        }
    }

    private func apply(_ swap: PendingSwap) async {
        AlertCalendar.removeCalendar(for: swap.off)
        calendars.unsubscribe(swap.off)
        calendars.subscribe(swap.on)
        pending = nil
    }

    private func grantedAccess() async -> Bool {
        if AlertCalendar.authorized { return true }
        guard await AlertCalendar.requestAccess() else {
            denied = true
            return false
        }
        return true
    }
}
```

- [ ] **Step 4: Add the section and wire the store**

In `Slackwater/SettingsView.swift`, beside the `alerts` observed object (line 15):

```swift
    @ObservedObject private var calendars = StationCalendarStore.shared
```

and, between the Alerts section (ending line 75) and Offline downloads (line 79):

```swift
                    section("Calendar") {
                        NavigationLink {
                            CalendarStationsView()
                                .navigationTitle("Calendar")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(SN.canvas, for: .navigationBar)
                        } label: {
                            HStack {
                                Text(calendarSummary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(SN.leaf)
                        }
                        .accessibilityIdentifier("settings-calendar-row")
                    }
```

and, beside `version`:

```swift
    /// What the Calendar row says it is doing, from what is actually subscribed.
    private var calendarSummary: String {
        let on = calendars.subscriptions.map(\.stationID)
        switch on.count {
        case 0: "Publish a station's tides or slack windows to your calendar"
        case 1: StationItem.byId[on[0]]?.name ?? "1 station"
        default: "\(on.count) stations"
        }
    }
```

In `Slackwater/SlackwaterApp.swift`, beside the line that sets `AlertRuleStore.shared.onChange`:

```swift
        StationCalendarStore.shared.onChange = { AlertScheduler.requestReschedule() }
```

- [ ] **Step 5: Run the UI test to verify it passes**

Run: `SLACKWATER_ONLY=CalendarSettingsTests scripts/test.sh`
Expected: PASS.

- [ ] **Step 6: Run the suite**

Run: `scripts/test.sh`
Expected: PASS on both simulators.

- [ ] **Step 7: Commit**

```bash
git add Slackwater/CalendarStationsView.swift Slackwater/SettingsView.swift Slackwater/SlackwaterApp.swift SlackwaterUITests/CalendarSettingsTests.swift
git commit -m "feat(alerts): subscribe a station's calendar from Settings

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: The rule sheet learns about `once`

**Files:**
- Modify: `Slackwater/AlertSheet.swift`
- Modify: `Slackwater/AlertsView.swift`
- Test: `SlackwaterTests/AlertStatusTests.swift`

**Interfaces:**
- Consumes: `AlertRule.once` (Task 1), `alertRuleSummary`.
- Produces: `alertRuleWhen(_ rule: AlertRule, tz:locale:) -> String?`.

- [ ] **Step 1: Write the failing test**

Append to `SlackwaterTests/AlertStatusTests.swift`:

```swift
    func testAOnceRuleNamesItsDayAndARepeatingOneDoesNot() {
        let moment = Date(timeIntervalSince1970: 1_700_000_040)
        let once = AlertRule(stationID: "a", trigger: .slack, once: moment)

        XCTAssertNotNil(alertRuleWhen(once, tz: .gmt))
        XCTAssertNil(alertRuleWhen(AlertRule(stationID: "a", trigger: .slack), tz: .gmt))
    }

    func testAOnceRuleReadsInTheStationsZone() {
        let moment = Date(timeIntervalSince1970: 1_700_000_040)   // 2023-11-14 22:13 UTC

        let utc = alertRuleWhen(AlertRule(stationID: "a", trigger: .slack, once: moment), tz: .gmt)
        let pacific = alertRuleWhen(AlertRule(stationID: "a", trigger: .slack, once: moment),
                                    tz: TimeZone(identifier: "America/Los_Angeles")!)

        XCTAssertNotEqual(utc, pacific)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `SLACKWATER_ONLY=AlertStatusTests scripts/test.sh`
Expected: FAIL — `alertRuleWhen` is not defined.

- [ ] **Step 3: Name the moment**

Append to `Slackwater/AlertsView.swift`:

```swift
/// When a `once` rule fires, for the Alerts list and the rule sheet. Nil for a repeating rule:
/// it has no one moment to name.
func alertRuleWhen(_ rule: AlertRule, tz: TimeZone,
                   locale: Locale = .autoupdatingCurrent) -> String? {
    rule.once.map {
        $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: tz)
            .locale(locale))
    }
}
```

In the same file's list row, under the summary `Text`:

```swift
                                if let when = alertRuleWhen(rule, tz: .current) {
                                    Text(when)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(SN.foam.opacity(0.62))
                                }
```

- [ ] **Step 4: Let the sheet clear `once`**

In `Slackwater/AlertSheet.swift`, inside the "When" section after the daylight toggle:

```swift
                    if let when = alertRuleWhen(rule, tz: .current) {
                        LabeledContent("This one", value: when)
                            .monospacedDigit()
                    }
                    Toggle("Every time", isOn: Binding(get: { rule.once == nil },
                                                       set: { rule.once = $0 ? nil : rule.once }))
                        .disabled(rule.once == nil)
```

The toggle is on and disabled for a rule that already repeats: there is no moment to go back to, and offering to bind one here would need a date picker the popup already is.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `SLACKWATER_ONLY=AlertStatusTests scripts/test.sh`
Expected: PASS.

- [ ] **Step 6: Run the full suite on both simulators**

Run: `scripts/test.sh`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Slackwater/AlertsView.swift Slackwater/AlertSheet.swift SlackwaterTests/AlertStatusTests.swift
git commit -m "feat(alerts): the Alerts screen names a one-off's moment

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
