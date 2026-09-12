# Alerts (calendar + notifications) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Alert rules set from a Calendar / Live row under every detail strip, resolved on the device into dated occurrences, and delivered as Slackwater calendar events (free; with alarms for Premium) and local notifications (Premium).

**Architecture:** Pure functions do the work and carry the tests: a rule becomes occurrences (`alertOccurrences`), occurrences become a `DeliveryPlan`, the plan becomes copy. A main-actor `AlertScheduler` runs them on launch and on every change, then hands the result to two thin writers, EventKit and UserNotifications. The alert row in the shared `ScrubDetailScaffold` offers a rule derived from what sits under the scrub centerline, and a tap only counts once the strip is at rest.

**Tech Stack:** Swift 5 language mode, SwiftUI, TideEngine (slackwater-engine), Almanac, EventKit, UserNotifications, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-12-notifications-design.md`

**Scope:** Everything in the spec except AlarmKit alarms and the Live Activity countdown (spec §5.3). Spike 1 (spec §11) decides how that rung works, so it gets its own plan once the spike has run on a device. `AlertLevel` has no `.alarm` case here; plan 2 adds it, and Live grows into it.

## Global Constraints

- iOS deployment target is `26.0` (`project.yml`). No `if #available` branches.
- No new entitlements or capabilities. Info.plist keys go in `project.yml` → `targets.Slackwater.info.properties`. This plan adds exactly one key: `NSCalendarsFullAccessUsageDescription`.
- No background execution: no `UIBackgroundModes`, no `BGTaskScheduler`.
- Calendar: full access (`requestFullAccessToEvents`). Write only to the calendar the app creates, titled `Slackwater`. Horizon 90 days. A free user's events carry no alarm; for a Premium user each event carries exactly one `EKAlarm` at `−lead`.
- Notifications: never provisional. Identifiers start with `alert.`. At most 64 pending; horizon 14 days. Interruption level stays the default (`.active`).
- Calendar events are free. Calendar alarms and notifications require `PremiumStore.shared.isPremium`.
- Titles lead with the place, then the event in as few words as possible, joined by ` - `: `Race Passage - Slack window`. Calendar events and notifications share the title, built from `alertEventName`.
- **The alert row:** a **Calendar** and a **Live** button in `ScrubDetailScaffold`, between the strip and the summary tiles. It is never hidden, faded or disabled while the strip moves; a tap counts only once the strip has rested for `Timeline.rest` (450 ms, the rule the strip's chrome already uses). Rules it creates start with a 30-minute lead. Calendar works for everyone; Live opens the tier sheet for a non-subscriber.
- Rules are device-local JSON in `AppGroup.defaults` under `slackwater.alertRules`. No iCloud sync.
- Heights are metres everywhere except display (`formatHeight`, `heightUnit`).
- Anything meaning a day goes through `Calendar`; everything else is absolute `Date`s.
- Notifications use `UNTimeIntervalNotificationTrigger(timeInterval:repeats: false)` on the absolute fire time, so they stay correct when the device changes time zone.
- Station ids are `StationItem` ids, the value `ScrubDetailScaffold.favoriteId` already carries. NOAA currents are `current:<id>`, e.g. `current:noaa/PUG1701`.
- Tap targets in the detail column use `.onTapGesture`, not `Button`: `Button` press tracking goes dead in the iPad split layout's detail column (`ReadoutTile`, `MultiDaySchedule`).
- New Swift files start with `// Slackwater — GPL v3. <one-line purpose>`. Mark deliberate shortcuts with a `ponytail:` comment naming the ceiling.
- The repo's CLAUDE.md applies: plans and specs are intent, not compiled source — if code here disagrees with the repo, trust the repo and say so in the task report.
- **Where to work:** a worktree off `origin/main`, never the shared checkout: `git -C ~/src/openwaters/slackwater-ios worktree add -b feat/alerts ../slackwater-ios-wt-alerts origin/main`. `slackwater-ios` is branch-and-PR; never push to `main`, never merge your own PR. Commit messages end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **The test machine is shared.** After adding files run `xcodegen generate`. The compile check is:
  ```sh
  xcodegen generate && lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
    -project Slackwater.xcodeproj -scheme Slackwater \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
  ```
  `lockf -t 0` fails immediately if another run holds the machine — wait, never force it. One test class runs with `SLACKWATER_ONLY=SlackwaterTests/<Class> ./scripts/test.sh` (do not add `--unit`). Under subagent-driven execution the implementer runs the compile check and the coordinator runs `scripts/test.sh` in the foreground; a backgrounded run dies with the subagent's turn.

---

## File map

| File | Responsibility | Task |
|---|---|---|
| `Slackwater/AlertRule.swift` | `AlertTrigger`, `AlertLevel`, `AlertRule`, `AlertRuleStore`, `alertEventName`, `alertRuleSummary` | 1 |
| `Slackwater/AlertOccurrences.swift` | `tideCrossings`, `daylightSpans`, `slackWindowOpenings` (Task 2); `AlertOccurrence`, `AlertPlace`, `alertOccurrences`, `WidgetRecord` helpers (Task 3) | 2, 3 |
| `Slackwater/AlertPlan.swift` | `AlertHorizon`, `DeliveryPlan`, `deliveryPlan`, `scheduledThrough`, `AlertCopy`, `alertCopy`, `alertLeads`, `alertLeadLabel`, `calendarEventKey` | 4 |
| `Slackwater/AlertScheduler.swift` | `AlertEntry`, `ResolvedAlerts`, `resolveAlerts`, `AlertStatusSnapshot`, `AlertScheduler` | 5, 6 |
| `Slackwater/AlertCalendar.swift` | EventKit writer | 5 |
| `Slackwater/AlertNotifications.swift` | UserNotifications writer, delegate, `AlertTap` | 6 |
| `Slackwater/AlertOffer.swift` | `tideAlertOffer`, `currentAlertOffer`, `derivedAlertOffer`, `isOnEclipseContact`, `AlertDelivery`, `AlertRuleChange`, `alertRowLead`, `alertRowToggle`, `alertRowState` | 7 |
| `Slackwater/AlertRow.swift` | The Calendar / Live row | 7 |
| `Slackwater/AlertSheet.swift` | The rule sheet (edit one rule) | 8 |
| `Slackwater/AlertsView.swift` | Alerts screen, `alertStatusText` | 8 |
| `Slackwater/AppGroup.swift` | `alertRulesKey`, `alertCalendarKey` | 1, 5 |
| `Slackwater/TimelineStrip.swift` | `Timeline.rest`, shared by the chrome and the row | 7 |
| `Slackwater/Theme.swift` (`ScrubDetailScaffold`), `TideDetailView.swift`, `CurrentDetailView.swift`, `DerivedGateDetailView.swift` | The row and each view's offer | 7 |
| `Slackwater/SlackwaterApp.swift`, `SettingsView.swift`, `PremiumStore.swift`, `StationListView.swift`, `project.yml` | Reschedule hooks, notification taps, Settings row, plist key | 5, 6, 8 |
| `SlackwaterTests/AlertRuleTests.swift`, `AlertPrimitivesTests.swift`, `AlertOccurrencesTests.swift`, `DeliveryPlanTests.swift`, `AlertCopyTests.swift`, `AlertResolveTests.swift`, `AlertOfferTests.swift`, `AlertStatusTests.swift` | Unit tests | 1–8 |
| `SlackwaterUITests/AlertRowTests.swift` | The row on tide and current details | 7 |

`OnlineGateDetailView` is deliberately untouched: it passes no offer, so the row is left out (spec §8).

---

### Task 1: Rules and their store

**Files:**
- Create: `Slackwater/AlertRule.swift`
- Modify: `Slackwater/AppGroup.swift` (after line 49, `slackWindowSpeedKey`)
- Test: `SlackwaterTests/AlertRuleTests.swift`

**Interfaces:**
- Consumes: `AppGroup.defaults`, `formatHeight(_:imperial:)`, `heightUnit(imperial:)` (`Units.swift`)
- Produces:
  - `enum AlertTrigger: Codable, Equatable { case slackWindowOpens, slack, currentPeak(flood: Bool), tideExtreme(high: Bool), tideCrossing(heightM: Double, rising: Bool), eclipse }`
  - `enum AlertLevel: String, Codable { case none, notification }`
  - `struct AlertRule: Codable, Identifiable, Equatable { var id: UUID; var stationID: String; var trigger: AlertTrigger; var lead: TimeInterval; var daylightOnly: Bool; var calendar: Bool; var alert: AlertLevel; var enabled: Bool }` — memberwise init `AlertRule(stationID:trigger:lead:daylightOnly:calendar:alert:enabled:)`, all but `stationID`/`trigger` defaulted
  - `@MainActor final class AlertRuleStore: ObservableObject { static let shared; init(defaults: UserDefaults); @Published private(set) var rules: [AlertRule]; var onChange: () -> Void; func upsert(_ rule: AlertRule); func remove(_ id: UUID) }`
  - `func alertEventName(_ trigger: AlertTrigger, noWindow: Bool = false, imperial: Bool) -> String`
  - `func alertRuleSummary(_ trigger: AlertTrigger, stationName: String, imperial: Bool) -> String`
  - `AppGroup.alertRulesKey = "slackwater.alertRules"`

- [ ] **Step 1: Write the failing test**

`SlackwaterTests/AlertRuleTests.swift`:

```swift
// Slackwater — GPL v3. Alert rules: coding, the store, and the place-first names.
import XCTest
@testable import Slackwater

@MainActor final class AlertRuleTests: XCTestCase {
    func testRulesRoundTripThroughTheStore() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        var changes = 0
        let store = AlertRuleStore(defaults: defaults)
        store.onChange = { changes += 1 }

        let rule = AlertRule(stationID: "current:noaa/PUG1701",
                             trigger: .tideCrossing(heightM: 1.4, rising: true),
                             lead: 1_800, daylightOnly: true)
        store.upsert(rule)
        var edited = rule
        edited.calendar = false
        store.upsert(edited)

        XCTAssertEqual(AlertRuleStore(defaults: defaults).rules, [edited])
        store.remove(rule.id)
        XCTAssertEqual(AlertRuleStore(defaults: defaults).rules, [])
        XCTAssertEqual(changes, 3)
    }

    func testEveryTriggerSurvivesCoding() throws {
        let triggers: [AlertTrigger] = [
            .slackWindowOpens, .slack, .currentPeak(flood: true), .tideExtreme(high: false),
            .tideCrossing(heightM: 0.25, rising: false), .eclipse,
        ]
        let decoded = try JSONDecoder().decode([AlertTrigger].self,
                                               from: JSONEncoder().encode(triggers))
        XCTAssertEqual(decoded, triggers)
    }

    func testDefaultsAreCalendarOnAndNotificationsOff() {
        let rule = AlertRule(stationID: "noaa/9449880", trigger: .tideExtreme(high: false))
        XCTAssertEqual(rule.lead, 0)
        XCTAssertFalse(rule.daylightOnly)
        XCTAssertTrue(rule.calendar)
        XCTAssertEqual(rule.alert, .none)
        XCTAssertTrue(rule.enabled)
    }

    func testSummaryPutsThePlaceFirst() {
        XCTAssertEqual(alertRuleSummary(.slackWindowOpens, stationName: "Race Passage", imperial: true),
                       "Race Passage - Slack window")
        XCTAssertEqual(alertRuleSummary(.slack, stationName: "Dodd Narrows", imperial: true),
                       "Dodd Narrows - Slack")
        XCTAssertEqual(alertRuleSummary(.currentPeak(flood: false), stationName: "Race Passage", imperial: true),
                       "Race Passage - Max ebb")
        XCTAssertEqual(alertRuleSummary(.tideExtreme(high: true), stationName: "Friday Harbor", imperial: true),
                       "Friday Harbor - High tide")
        XCTAssertEqual(alertRuleSummary(.tideCrossing(heightM: 1, rising: true), stationName: "Friday Harbor", imperial: false),
                       "Friday Harbor - Rising past 1.00 m")
        XCTAssertEqual(alertRuleSummary(.tideCrossing(heightM: 1, rising: false), stationName: "Friday Harbor", imperial: true),
                       "Friday Harbor - Falling past 3.3 ft")
        XCTAssertEqual(alertRuleSummary(.eclipse, stationName: "Friday Harbor", imperial: true),
                       "Friday Harbor - Lunar eclipse")
    }

    func testAHairlineSlackIsJustSlack() {
        XCTAssertEqual(alertEventName(.slackWindowOpens, noWindow: true, imperial: true), "Slack")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertRuleTests ./scripts/test.sh`
Expected: build failure, `cannot find 'AlertRuleStore' in scope`.

- [ ] **Step 3: Add the key**

In `Slackwater/AppGroup.swift`, directly after `static let slackWindowSpeedKey = "slackwater.slackWindowSpeedKn"`:

```swift
    /// Alert rules (notifications spec §3): JSON, device-local — two devices holding one
    /// rule would each deliver it.
    static let alertRulesKey = "slackwater.alertRules"
```

- [ ] **Step 4: Write the implementation**

`Slackwater/AlertRule.swift`:

```swift
// Slackwater — GPL v3. Alert rules — what the user asked to be told about — and the store that keeps them.
import Foundation

/// The water event a rule watches (notifications spec §3). Which stations each case
/// applies to is spec §8; a case that doesn't fit the station finds nothing.
enum AlertTrigger: Codable, Equatable {
    case slackWindowOpens
    /// A derived gate's slack: an instant, with no speed series to open a window from.
    case slack
    case currentPeak(flood: Bool)
    case tideExtreme(high: Bool)
    /// A height picked off the curve, in metres, in the direction the curve was moving.
    case tideCrossing(heightM: Double, rising: Bool)
    case eclipse
}

enum AlertLevel: String, Codable {
    case none, notification
}

struct AlertRule: Codable, Identifiable, Equatable {
    var id = UUID()
    /// A `StationItem` id — `current:`-prefixed for NOAA currents.
    var stationID: String
    var trigger: AlertTrigger
    /// Seconds before the event that a notification fires and a Premium calendar alarm rings.
    var lead: TimeInterval = 0
    var daylightOnly = false
    /// Free: write occurrences into the Slackwater calendar.
    var calendar = true
    /// Premium: interrupt.
    var alert: AlertLevel = .none
    var enabled = true
}

@MainActor final class AlertRuleStore: ObservableObject {
    static let shared = AlertRuleStore(defaults: AppGroup.defaults)

    @Published private(set) var rules: [AlertRule]
    /// Assigned once at launch (SlackwaterApp.init) to the scheduler. A no-op until then,
    /// so a store built in a test never reaches the system.
    var onChange: () -> Void = {}
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        rules = defaults.data(forKey: AppGroup.alertRulesKey)
            .flatMap { try? JSONDecoder().decode([AlertRule].self, from: $0) } ?? []
    }

    func upsert(_ rule: AlertRule) {
        if let i = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[i] = rule
        } else {
            rules.append(rule)
        }
        persist()
    }

    func remove(_ id: UUID) {
        rules.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(rules), forKey: AppGroup.alertRulesKey)
        onChange()
    }
}

/// The event in as few words as a title allows — "Slack window", "Low tide", "Rising past 3.3 ft".
/// The place goes in front of it (`alertRuleSummary`, `alertCopy`).
func alertEventName(_ trigger: AlertTrigger, noWindow: Bool = false, imperial: Bool) -> String {
    switch trigger {
    case .slackWindowOpens: noWindow ? "Slack" : "Slack window"
    case .slack: "Slack"
    case .currentPeak(let flood): flood ? "Max flood" : "Max ebb"
    case .tideExtreme(let high): high ? "High tide" : "Low tide"
    case .tideCrossing(let heightM, let rising):
        "\(rising ? "Rising" : "Falling") past \(formatHeight(heightM, imperial: imperial)) \(heightUnit(imperial: imperial))"
    case .eclipse: "Lunar eclipse"
    }
}

/// "Race Passage - Slack window": the place, then the event — the same shape calendar events
/// and notifications are titled with.
func alertRuleSummary(_ trigger: AlertTrigger, stationName: String, imperial: Bool) -> String {
    "\(stationName) - \(alertEventName(trigger, imperial: imperial))"
}
```

- [ ] **Step 5: Run the test and watch it pass**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertRuleTests ./scripts/test.sh`
Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/AlertRule.swift Slackwater/AppGroup.swift SlackwaterTests/AlertRuleTests.swift
git commit -m "feat(alerts): alert rules and their store

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Occurrence primitives — crossings, daylight, window openings

**Files:**
- Create: `Slackwater/AlertOccurrences.swift`
- Test: `SlackwaterTests/AlertPrimitivesTests.swift`

**Interfaces:**
- Consumes: `slackWindow(_:around:threshold:)`, `mergeWindows(_:)`, `WindowRun` (`SlackWindow.swift`); `CurrentPredicting` (`CurrentStation.swift:222`); Almanac `Observer`, `sunEvents(from:to:observer:)` (both throw)
- Produces:
  - `func tideCrossings(_ samples: [(time: Date, height: Double)], level: Double, rising: Bool) -> [Date]`
  - `func daylightSpans(from: Date, to: Date, lat: Double, lon: Double) -> [ClosedRange<Date>]`
  - `func slackWindowOpenings(_ station: any CurrentPredicting, from: Date, to: Date, threshold: Double) -> [(event: Date, end: Date?)]` — `end == nil` means a slack with no workable window

- [ ] **Step 1: Write the failing test**

`SlackwaterTests/AlertPrimitivesTests.swift`:

```swift
// Slackwater — GPL v3. The pure pieces alert occurrences are built from.
import XCTest
@testable import Slackwater
import TideEngine

final class AlertPrimitivesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    func testCrossingsInterpolateInTheRequestedDirection() {
        let samples: [(time: Date, height: Double)] = [(at(0), 0), (at(600), 2), (at(1200), 0)]
        let up = tideCrossings(samples, level: 1, rising: true)
        let down = tideCrossings(samples, level: 1, rising: false)
        XCTAssertEqual(up.count, 1)
        XCTAssertEqual(up[0].timeIntervalSince(t0), 300, accuracy: 1)
        XCTAssertEqual(down.count, 1)
        XCTAssertEqual(down[0].timeIntervalSince(t0), 900, accuracy: 1)
    }

    func testASampleExactlyOnTheLevelCountsOnce() {
        let samples: [(time: Date, height: Double)] = [(at(0), 0), (at(600), 1), (at(1200), 2)]
        XCTAssertEqual(tideCrossings(samples, level: 1, rising: true).map { $0.timeIntervalSince(t0) }, [600])
    }

    func testDaylightSpansFollowTheSunAcrossTheDSTChange() throws {
        // Friday Harbor. US clocks fall back at 02:00 local on 2026-11-01.
        let iso = ISO8601DateFormatter()
        let from = try XCTUnwrap(iso.date(from: "2026-11-01T08:00:00Z"))
        let spans = daylightSpans(from: from, to: from.addingTimeInterval(86_400), lat: 48.545, lon: -123.013)
        let noonPST = try XCTUnwrap(iso.date(from: "2026-11-01T20:00:00Z"))
        let predawnPST = try XCTUnwrap(iso.date(from: "2026-11-01T09:30:00Z"))
        XCTAssertTrue(spans.contains { $0.contains(noonPST) })
        XCTAssertFalse(spans.contains { $0.contains(predawnPST) })
        // A day of padding either side: Oct 31, Nov 1, Nov 2.
        XCTAssertEqual(spans.count, 3)
    }

    /// Two slacks whose windows touch, then a hairline slack no sample under the
    /// threshold brackets.
    private struct FakeCurrent: CurrentPredicting {
        let points: [CurrentPoint]
        let slacks: [Date]
        func speeds(from: Date, to: Date, step: TimeInterval) -> [CurrentPoint] { points }
        func events(from: Date, to: Date) -> [CurrentEvent] {
            slacks.map { CurrentEvent(time: $0, speed: 0, kind: .slack) }
        }
    }

    func testMergedWindowsOpenOnceAndAHairlineSlackStandsAlone() {
        let speeds: [Double] = [2, 1.5, 1, 0.6, 0.3, 0.1, 0,   // 0…3600: slack A at 3600
                                0.1, 0.3, 0,                   // 4200…5400: slack B at 5400
                                0.3, 0.6, 1, 1.5, 1.2, 1.1, 1, // 6000…9600
                                1, 0.8, -1, -1.5, -2]          // 10200…12600: hairline at 10800
        let points = speeds.enumerated().map { CurrentPoint(time: at(Double($0.offset) * 600), speed: $0.element) }
        let station = FakeCurrent(points: points, slacks: [at(3600), at(5400), at(10_800)])

        let openings = slackWindowOpenings(station, from: t0, to: at(12_600), threshold: 0.5)

        XCTAssertEqual(openings.count, 2)
        XCTAssertEqual(openings[0].event.timeIntervalSince(t0), 2000, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(openings[0].end).timeIntervalSince(t0), 6400, accuracy: 1)
        XCTAssertEqual(openings[1].event, at(10_800))
        XCTAssertNil(openings[1].end)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertPrimitivesTests ./scripts/test.sh`
Expected: build failure, `cannot find 'tideCrossings' in scope`.

- [ ] **Step 3: Write the implementation**

`Slackwater/AlertOccurrences.swift`:

```swift
// Slackwater — GPL v3. Alert rules → dated occurrences, read from the producers the strip already draws (notifications spec §4).
import Almanac
import Foundation
import TideEngine

/// Each time a sampled height series passes `level` in the given direction, linearly
/// interpolated between the two samples that bracket it. A sample exactly on the level
/// counts once, on the pair that arrives at it.
func tideCrossings(_ samples: [(time: Date, height: Double)], level: Double, rising: Bool) -> [Date] {
    guard samples.count > 1 else { return [] }
    var found: [Date] = []
    for i in 0..<(samples.count - 1) {
        let a = samples[i], b = samples[i + 1]
        let crosses = rising ? (a.height < level && b.height >= level)
                             : (a.height > level && b.height <= level)
        guard crosses else { continue }
        let f = (level - a.height) / (b.height - a.height)
        found.append(a.time.addingTimeInterval(b.time.timeIntervalSince(a.time) * f))
    }
    return found
}

/// Sunrise → sunset spans at a position, padded a day either side of the range so an
/// event near either end still finds its day. One Almanac search for the whole range.
/// ponytail: a polar day with no rise or set has no span, so it reads as night.
func daylightSpans(from: Date, to: Date, lat: Double, lon: Double) -> [ClosedRange<Date>] {
    guard let observer = try? Observer(latitudeDeg: lat, longitudeDeg: lon),
          let events = try? sunEvents(from: from.addingTimeInterval(-86_400),
                                      to: to.addingTimeInterval(86_400), observer: observer)
    else { return [] }
    var spans: [ClosedRange<Date>] = []
    var rise: Date?
    for event in events {
        switch event.kind {
        case .rise: rise = event.time
        case .set:
            if let r = rise { spans.append(r...event.time) }
            rise = nil
        default: break
        }
    }
    return spans
}

/// The opening of every merged slack run, with its close, plus the bare instant of any
/// slack no run covers (`end == nil`) — the moments `currentAxisMoments` prints. Series
/// and events are padded 6 h beyond the range so a window straddling either end is whole;
/// the caller clips to the range.
func slackWindowOpenings(_ station: any CurrentPredicting, from: Date, to: Date,
                         threshold: Double) -> [(event: Date, end: Date?)] {
    let start = from.addingTimeInterval(-21_600), stop = to.addingTimeInterval(21_600)
    let points = station.speeds(from: start, to: stop, step: 600)
    let slacks = station.events(from: start, to: stop).filter { $0.kind == .slack }.map(\.time)
    let runs = mergeWindows(slacks.compactMap { slackWindow(points, around: $0, threshold: threshold) })
    let opened: [(event: Date, end: Date?)] = runs.map { ($0.start, $0.end) }
    let hairline: [(event: Date, end: Date?)] = slacks
        .filter { t in !runs.contains { $0.contains(t) } }
        .map { ($0, nil) }
    return (opened + hairline).sorted { $0.event < $1.event }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertPrimitivesTests ./scripts/test.sh`
Expected: 4 tests pass. If `testDaylightSpansFollowTheSunAcrossTheDSTChange` reports a span count other than 3, print `spans` and check whether Almanac's window is half-open at the end before touching the assertion.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/AlertOccurrences.swift SlackwaterTests/AlertPrimitivesTests.swift
git commit -m "feat(alerts): tide crossings, daylight spans and slack window openings

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Occurrences per trigger, against real stations

**Files:**
- Modify: `Slackwater/AlertOccurrences.swift` (append)
- Test: `SlackwaterTests/AlertOccurrencesTests.swift`

**Interfaces:**
- Consumes: Task 1 `AlertRule`, `AlertTrigger`; Task 2 `tideCrossings`, `daylightSpans`, `slackWindowOpenings`; `WidgetStation`, `WidgetRecord`, `WidgetStationLoader.loadRecord(id:)`, `WidgetStationLoader.station(from:)`; `visibleEclipses(from:to:observer:)`, `WindowEclipse.start`; `PerfBudget.swift`'s `elapsed` and `perfScale`
- Produces:
  - `struct AlertOccurrence: Equatable, Sendable { let ruleID: UUID; let event: Date; let fire: Date; var end: Date? = nil; var noWindow = false; var heightM: Double? = nil; var key: String }`
  - `struct AlertPlace: Equatable, Sendable { let name: String; let tz: TimeZone }`
  - `extension WidgetRecord { var alertPosition: (lat: Double, lon: Double); var alertPlace: AlertPlace }`
  - `func alertOccurrences(_ rule: AlertRule, station: WidgetStation, position: (lat: Double, lon: Double), from: Date, to: Date, threshold: Double) -> [AlertOccurrence]`

- [ ] **Step 1: Write the failing test**

`SlackwaterTests/AlertOccurrencesTests.swift`:

```swift
// Slackwater — GPL v3. alertOccurrences against bundled stations: each trigger reads the producer the strip draws.
import XCTest
@testable import Slackwater
import Almanac
import TideEngine

@MainActor final class AlertOccurrencesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_755_800_000)   // 2025-08-21
    private var week: Date { now.addingTimeInterval(7 * 86_400) }
    private let deception = "current:noaa/PUG1701"

    private func load(_ id: String) throws -> (station: WidgetStation, position: (lat: Double, lon: Double)) {
        let record = try XCTUnwrap(WidgetStationLoader.loadRecord(id: id))
        return (WidgetStationLoader.station(from: record), record.alertPosition)
    }

    func testTideExtremesAreTheEngineLowsWithTheLeadApplied() throws {
        let (station, position) = try load(TideStationRecord.fridayHarborID)
        guard case .tide(let engine, _, _) = station else { return XCTFail("expected a tide station") }
        let rule = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .tideExtreme(high: false), lead: 1_800)

        let found = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5)

        let lows = engine.extremes(from: now, to: week).filter { $0.kind == .low && $0.time >= now && $0.time <= week }
        XCTAssertFalse(lows.isEmpty)
        XCTAssertEqual(found.map(\.event), lows.map(\.time))
        XCTAssertEqual(found.map(\.heightM), lows.map { Optional($0.height) })
        XCTAssertTrue(found.allSatisfy { $0.event.timeIntervalSince($0.fire) == 1_800 && $0.ruleID == rule.id })
    }

    func testRisingCrossingsSitBetweenALowBelowAndAHighAbove() throws {
        let (station, position) = try load(TideStationRecord.fridayHarborID)
        guard case .tide(let engine, _, _) = station else { return XCTFail("expected a tide station") }
        let extremes = engine.extremes(from: now.addingTimeInterval(-86_400), to: week.addingTimeInterval(86_400))
        let level = 1.0
        let rule = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .tideCrossing(heightM: level, rising: true))

        let found = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5)

        XCTAssertFalse(found.isEmpty)
        for o in found {
            guard let before = extremes.last(where: { $0.time <= o.event }),
                  let after = extremes.first(where: { $0.time > o.event }) else { continue }
            XCTAssertEqual(before.kind, .low)
            XCTAssertEqual(after.kind, .high)
            XCTAssertLessThan(before.height, level)
            XCTAssertGreaterThan(after.height, level)
        }
    }

    func testCurrentPeaksAreTheEngineMaxima() throws {
        let (station, position) = try load(deception)
        guard case .current(let engine, _, _) = station else { return XCTFail("expected a current station") }
        let rule = AlertRule(stationID: deception, trigger: .currentPeak(flood: true))

        let found = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5)

        let floods = engine.events(from: now, to: week).filter { $0.kind == .maxFlood && $0.time >= now && $0.time <= week }
        XCTAssertFalse(floods.isEmpty)
        XCTAssertEqual(found.map(\.event), floods.map(\.time))
    }

    func testTheFirstWindowOpeningAgreesWithTheSiriAnswer() throws {
        // A generous threshold so no slack in the week is a hairline and the Siri query
        // (which answers only a real window) has one to give.
        let saved = AppGroup.defaults.object(forKey: AppGroup.slackWindowSpeedKey)
        defer { AppGroup.defaults.set(saved, forKey: AppGroup.slackWindowSpeedKey) }
        AppGroup.defaults.set(2.0, forKey: AppGroup.slackWindowSpeedKey)
        let (station, position) = try load(deception)
        let rule = AlertRule(stationID: deception, trigger: .slackWindowOpens)

        let found = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 2.0)
        let siri = try XCTUnwrap(SlackWindowShortcutQuery.next(at: station, after: now))

        XCTAssertFalse(found.isEmpty)
        XCTAssertTrue(found.allSatisfy { $0.end != nil && !$0.noWindow })
        // The Siri query samples from its own slack − 6 h; ours from the range − 6 h. The two
        // 10-minute grids interpolate the same crossing a little differently.
        if siri.start >= now {
            XCTAssertEqual(try XCTUnwrap(found.first).event.timeIntervalSince1970,
                           siri.start.timeIntervalSince1970, accuracy: 120)
        }
    }

    func testAWiderThresholdOpensTheWindowEarlier() throws {
        // The threshold is the user's boat: moving it moves every window (spec §4, §6).
        let (station, position) = try load(deception)
        let rule = AlertRule(stationID: deception, trigger: .slackWindowOpens)
        let narrow = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 1.0)
        let wide = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 2.0)

        let first = try XCTUnwrap(narrow.first { !$0.noWindow })
        let same = try XCTUnwrap(wide.first { abs($0.event.timeIntervalSince(first.event)) < 3 * 3_600 })
        XCTAssertLessThan(same.event, first.event)
    }

    func testATriggerThatDoesNotFitTheStationFindsNothing() throws {
        let (station, position) = try load(TideStationRecord.fridayHarborID)
        let rule = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .slackWindowOpens)
        XCTAssertEqual(alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5), [])
    }

    func testDaylightOnlyKeepsTheLowsUnderTheSun() throws {
        let (station, position) = try load(TideStationRecord.fridayHarborID)
        var rule = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .tideExtreme(high: false))
        let all = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5)
        rule.daylightOnly = true
        let sunlit = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5)
        let spans = daylightSpans(from: now, to: week, lat: position.lat, lon: position.lon)

        XCTAssertLessThan(sunlit.count, all.count)
        XCTAssertFalse(sunlit.isEmpty)
        XCTAssertTrue(sunlit.allSatisfy { o in spans.contains { $0.contains(o.event) } })
        XCTAssertTrue(Set(sunlit.map(\.event)).isSubset(of: Set(all.map(\.event))))
    }

    func testEclipsesLandOnTheFirstBite() throws {
        // Aug 2025 → Apr 2026 holds the 2026-03-03 total eclipse, visible from the Salish Sea.
        let (station, position) = try load(TideStationRecord.fridayHarborID)
        let until = now.addingTimeInterval(240 * 86_400)
        let rule = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .eclipse)

        let found = alertOccurrences(rule, station: station, position: position, from: now, to: until, threshold: 0.5)

        let observer = try Observer(latitudeDeg: position.lat, longitudeDeg: position.lon)
        let expected = visibleEclipses(from: now, to: until, observer: observer).map(\.start).filter { $0 >= now && $0 <= until }
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(found.map(\.event), expected)
    }

    func testNinetyDaysOfWindowsStayInsideTheLaunchBudget() throws {
        let (station, position) = try load(deception)
        let rule = AlertRule(stationID: deception, trigger: .slackWindowOpens, daylightOnly: true)
        var found: [AlertOccurrence] = []
        let took = elapsed {
            found = alertOccurrences(rule, station: station, position: position,
                                     from: now, to: now.addingTimeInterval(90 * 86_400), threshold: 0.5)
        }
        print("90 days of daylight slack windows: \(took * 1000) ms, \(found.count) occurrences")
        XCTAssertGreaterThan(found.count, 100)
        // Spec §11 spike 3. If this fails, report the printed time; do not widen the budget.
        XCTAssertLessThan(took, 1.0 * perfScale)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertOccurrencesTests ./scripts/test.sh`
Expected: build failure, `cannot find 'alertOccurrences' in scope`.

- [ ] **Step 3: Write the implementation**

Append to `Slackwater/AlertOccurrences.swift`:

```swift
/// One dated event a rule found (notifications spec §4).
struct AlertOccurrence: Equatable, Sendable {
    let ruleID: UUID
    /// The water event itself.
    let event: Date
    /// When a notification fires: `event − lead`.
    let fire: Date
    /// A window's close.
    var end: Date? = nil
    /// A slack no run under the threshold covers.
    var noWindow = false
    /// Tide triggers: the height at the event, metres.
    var heightM: Double? = nil

    var key: String { "\(ruleID.uuidString).\(Int(event.timeIntervalSince1970))" }
}

/// What copy names: the station and the zone its times read in.
struct AlertPlace: Equatable, Sendable {
    let name: String
    let tz: TimeZone
}

extension WidgetRecord {
    /// Where the sky is read from. A derived gate uses its own position, not its reference port's.
    var alertPosition: (lat: Double, lon: Double) {
        switch self {
        case .tide(let r, _): (r.latitude, r.longitude)
        case .current(let r, _): (r.latitude, r.longitude)
        case .derived(let r): (r.gate.latitude, r.gate.longitude)
        }
    }

    var alertPlace: AlertPlace {
        switch self {
        case .tide(let r, _): AlertPlace(name: r.name, tz: r.tz)
        case .current(let r, _): AlertPlace(name: r.name, tz: r.tz)
        case .derived(let r): AlertPlace(name: r.gate.name, tz: r.gate.tz)
        }
    }
}

/// Every occurrence of `rule` at `station` with its event inside `[from, to]`. Pure: the
/// scheduler and the tests are its only callers.
func alertOccurrences(_ rule: AlertRule, station: WidgetStation, position: (lat: Double, lon: Double),
                      from: Date, to: Date, threshold: Double) -> [AlertOccurrence] {
    var found: [(event: Date, end: Date?, noWindow: Bool, heightM: Double?)]

    switch (rule.trigger, station) {
    case (.slackWindowOpens, .current(let s, _, _)):
        found = slackWindowOpenings(s, from: from, to: to, threshold: threshold)
            .map { (event: $0.event, end: $0.end, noWindow: $0.end == nil, heightM: nil) }
    case (.currentPeak(let flood), .current(let s, _, _)):
        found = s.events(from: from, to: to)
            .filter { $0.kind == (flood ? .maxFlood : .maxEbb) }
            .map { (event: $0.time, end: nil, noWindow: false, heightM: nil) }
    case (.slack, .derived(let g, _, _)):
        found = g.slacks(from: from, to: to)
            .map { (event: $0.time, end: nil, noWindow: false, heightM: nil) }
    case (.tideExtreme(let high), .tide(let s, _, _)):
        found = s.extremes(from: from, to: to)
            .filter { $0.kind == (high ? .high : .low) }
            .map { (event: $0.time, end: nil, noWindow: false, heightM: $0.height) }
    case (.tideCrossing(let level, let rising), .tide(let s, _, _)):
        let samples = s.heights(from: from, to: to, step: 600).map { (time: $0.time, height: $0.height) }
        found = tideCrossings(samples, level: level, rising: rising)
            .map { (event: $0, end: nil, noWindow: false, heightM: level) }
    case (.eclipse, _):
        guard let observer = try? Observer(latitudeDeg: position.lat, longitudeDeg: position.lon) else { return [] }
        found = visibleEclipses(from: from, to: to, observer: observer)
            .map { (event: $0.start, end: nil, noWindow: false, heightM: nil) }
    default:
        // The trigger doesn't apply to this kind of station (spec §8).
        return []
    }

    found = found.filter { $0.event >= from && $0.event <= to }
    if rule.daylightOnly {
        let spans = daylightSpans(from: from, to: to, lat: position.lat, lon: position.lon)
        found = found.filter { f in spans.contains { $0.contains(f.event) } }
    }
    return found.map {
        AlertOccurrence(ruleID: rule.id, event: $0.event, fire: $0.event.addingTimeInterval(-rule.lead),
                        end: $0.end, noWindow: $0.noWindow, heightM: $0.heightM)
    }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertOccurrencesTests ./scripts/test.sh`
Expected: 9 tests pass. The perf test prints its time; copy that line into the task report.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/AlertOccurrences.swift SlackwaterTests/AlertOccurrencesTests.swift
git commit -m "feat(alerts): occurrences for every trigger from the strip's producers

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: The delivery plan and its copy

**Files:**
- Create: `Slackwater/AlertPlan.swift`
- Test: `SlackwaterTests/DeliveryPlanTests.swift`, `SlackwaterTests/AlertCopyTests.swift`

**Interfaces:**
- Consumes: Task 1 `AlertRule`, `AlertLevel`, `alertEventName`; Task 3 `AlertOccurrence`, `AlertPlace`; `formatHeight`, `heightUnit`
- Produces:
  - `enum AlertHorizon { static let calendar: TimeInterval; static let notifications: TimeInterval; static let notificationLimit: Int }`
  - `struct DeliveryPlan: Equatable { var calendar: [AlertOccurrence]; var notifications: [AlertOccurrence] }`
  - `func deliveryPlan(rules: [AlertRule], occurrences: [AlertOccurrence], now: Date, premium: Bool) -> DeliveryPlan`
  - `func scheduledThrough(_ plan: DeliveryPlan) -> [UUID: Date]`
  - `struct AlertCopy: Equatable { let title: String; let body: String }`
  - `func alertCopy(_ rule: AlertRule, _ occurrence: AlertOccurrence, place: AlertPlace, imperial: Bool, threshold: Double, includeLead: Bool, locale: Locale = .autoupdatingCurrent) -> AlertCopy`
  - `let alertLeads: [TimeInterval]`
  - `func alertLeadLabel(_ lead: TimeInterval) -> String`
  - `func calendarEventKey(title: String, start: Date, end: Date, alarmOffset: TimeInterval?) -> String`

- [ ] **Step 1: Write the failing tests**

`SlackwaterTests/DeliveryPlanTests.swift`:

```swift
// Slackwater — GPL v3. deliveryPlan: horizons, the 64 ceiling, and the free/Premium line.
import XCTest
@testable import Slackwater

final class DeliveryPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func occurrence(_ rule: AlertRule, eventIn seconds: TimeInterval) -> AlertOccurrence {
        let event = now.addingTimeInterval(seconds)
        return AlertOccurrence(ruleID: rule.id, event: event, fire: event.addingTimeInterval(-rule.lead))
    }

    func testTheCalendarKeepsAnEventWhoseReminderHasPassed() {
        let rule = AlertRule(stationID: "a", trigger: .slack, lead: 3_600, alert: .notification)
        let o = occurrence(rule, eventIn: 1_800)   // fired 30 min ago, happens in 30 min

        let plan = deliveryPlan(rules: [rule], occurrences: [o], now: now, premium: true)

        XCTAssertEqual(plan.calendar, [o])
        XCTAssertEqual(plan.notifications, [])
    }

    func testNotificationsAreTheSoonestSixtyFourInsideFourteenDays() {
        let rule = AlertRule(stationID: "a", trigger: .slack, alert: .notification)
        let hourly = (1...(24 * 100)).map { occurrence(rule, eventIn: Double($0) * 3_600) }

        let plan = deliveryPlan(rules: [rule], occurrences: hourly.reversed(), now: now, premium: true)

        XCTAssertEqual(plan.notifications, Array(hourly.prefix(64)))
        XCTAssertEqual(plan.calendar.count, 24 * 90)
    }

    func testASparseRuleStopsAtFourteenDays() {
        let rule = AlertRule(stationID: "a", trigger: .slack, calendar: false, alert: .notification)
        let daily = (1...30).map { occurrence(rule, eventIn: Double($0) * 86_400) }

        let plan = deliveryPlan(rules: [rule], occurrences: daily, now: now, premium: true)

        XCTAssertEqual(plan.notifications, Array(daily.prefix(14)))
        XCTAssertEqual(plan.calendar, [])
    }

    func testWithoutPremiumOnlyTheCalendarIsPlanned() {
        let rule = AlertRule(stationID: "a", trigger: .slack, alert: .notification)
        let o = occurrence(rule, eventIn: 3_600)

        let plan = deliveryPlan(rules: [rule], occurrences: [o], now: now, premium: false)

        XCTAssertEqual(plan, DeliveryPlan(calendar: [o], notifications: []))
    }

    func testDisabledAndUnknownRulesPlanNothing() {
        var off = AlertRule(stationID: "a", trigger: .slack, alert: .notification)
        off.enabled = false
        let orphan = AlertRule(stationID: "b", trigger: .slack, alert: .notification)

        let plan = deliveryPlan(rules: [off],
                                occurrences: [occurrence(off, eventIn: 60), occurrence(orphan, eventIn: 60)],
                                now: now, premium: true)

        XCTAssertEqual(plan, DeliveryPlan())
    }

    func testScheduledThroughIsEachRulesLastDelivery() {
        let tide = AlertRule(stationID: "a", trigger: .tideExtreme(high: false), lead: 600, alert: .notification)
        let pass = AlertRule(stationID: "b", trigger: .slackWindowOpens, calendar: false, alert: .notification)
        let plan = DeliveryPlan(calendar: [occurrence(tide, eventIn: 86_400), occurrence(tide, eventIn: 40 * 86_400)],
                                notifications: [occurrence(tide, eventIn: 86_400), occurrence(pass, eventIn: 7_200)])

        let through = scheduledThrough(plan)

        XCTAssertEqual(through[tide.id], now.addingTimeInterval(40 * 86_400))
        XCTAssertEqual(through[pass.id], now.addingTimeInterval(7_200))
    }
}
```

`SlackwaterTests/AlertCopyTests.swift`:

```swift
// Slackwater — GPL v3. What an alert says: the place, then the event, then the time in the station's zone.
import XCTest
@testable import Slackwater

final class AlertCopyTests: XCTestCase {
    private let place = AlertPlace(name: "Race Passage", tz: TimeZone(identifier: "UTC")!)
    private let gb = Locale(identifier: "en_GB")
    private let event = Date(timeIntervalSince1970: 1_786_372_320)   // 2026-08-10 14:32 UTC

    private func copy(_ trigger: AlertTrigger, lead: TimeInterval = 0, end: Date? = nil, noWindow: Bool = false,
                      heightM: Double? = nil, imperial: Bool = true, includeLead: Bool = true) -> AlertCopy {
        let rule = AlertRule(stationID: "x", trigger: trigger, lead: lead)
        let o = AlertOccurrence(ruleID: rule.id, event: event, fire: event.addingTimeInterval(-lead),
                                end: end, noWindow: noWindow, heightM: heightM)
        return alertCopy(rule, o, place: place, imperial: imperial, threshold: 0.5,
                         includeLead: includeLead, locale: gb)
    }

    func testAWindowNamesItsSpanAndThreshold() {
        XCTAssertEqual(copy(.slackWindowOpens, lead: 1_800, end: event.addingTimeInterval(38 * 60)),
                       AlertCopy(title: "Race Passage - Slack window",
                                 body: "14:32–15:10, under 0.5 kn · in 30 min"))
    }

    func testAHairlineSlackSaysThereIsNoWindow() {
        XCTAssertEqual(copy(.slackWindowOpens, noWindow: true),
                       AlertCopy(title: "Race Passage - Slack", body: "14:32, no window under 0.5 kn"))
    }

    func testTheCalendarLeavesTheLeadOut() {
        XCTAssertEqual(copy(.currentPeak(flood: true), lead: 3_600, includeLead: false),
                       AlertCopy(title: "Race Passage - Max flood", body: "14:32"))
    }

    func testTideCopyCarriesTheHeightInTheUsersUnits() {
        XCTAssertEqual(copy(.tideExtreme(high: false), heightM: 0.4, imperial: false),
                       AlertCopy(title: "Race Passage - Low tide", body: "14:32 · 0.40 m"))
        XCTAssertEqual(copy(.tideCrossing(heightM: 1, rising: true), lead: 86_400, heightM: 1),
                       AlertCopy(title: "Race Passage - Rising past 3.3 ft", body: "14:32 · in 1 day"))
    }

    func testSlackAndEclipse() {
        XCTAssertEqual(copy(.slack), AlertCopy(title: "Race Passage - Slack", body: "14:32"))
        XCTAssertEqual(copy(.eclipse), AlertCopy(title: "Race Passage - Lunar eclipse", body: "14:32"))
    }

    func testLeadLabels() {
        XCTAssertEqual(alertLeads.map(alertLeadLabel),
                       ["At the time", "15 min before", "30 min before", "1 hr before", "3 hr before", "1 day before"])
    }

    func testCalendarIdentityChangesWhenAWindowMovesOrTheAlarmChanges() {
        let title = "Race Passage - Slack window"
        let end = event.addingTimeInterval(600)
        let plain = calendarEventKey(title: title, start: event, end: end, alarmOffset: nil)
        XCTAssertEqual(plain, "Race Passage - Slack window|1786372320|1786372920|none")
        XCTAssertEqual(calendarEventKey(title: title, start: event, end: end, alarmOffset: -1_800),
                       "Race Passage - Slack window|1786372320|1786372920|-1800")
        XCTAssertNotEqual(plain, calendarEventKey(title: title, start: event, end: event.addingTimeInterval(900), alarmOffset: nil))
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `SLACKWATER_ONLY=SlackwaterTests/DeliveryPlanTests,SlackwaterTests/AlertCopyTests ./scripts/test.sh`
Expected: build failure, `cannot find 'deliveryPlan' in scope`.

- [ ] **Step 3: Write the implementation**

`Slackwater/AlertPlan.swift`:

```swift
// Slackwater — GPL v3. Occurrences → what gets delivered where, and what it says (notifications spec §5–§6).
import Foundation

enum AlertHorizon {
    /// The calendar holds the long view; it survives the app never opening again.
    static let calendar: TimeInterval = 90 * 86_400
    /// Notifications hold until 14 days past the last launch.
    static let notifications: TimeInterval = 14 * 86_400
    /// iOS keeps only the soonest 64 pending requests an app holds.
    static let notificationLimit = 64
}

struct DeliveryPlan: Equatable {
    var calendar: [AlertOccurrence] = []
    var notifications: [AlertOccurrence] = []
}

/// Which occurrences go to the calendar (free) and which become notifications (Premium).
/// The calendar keeps an event until it happens; a notification is gone once its fire time passes.
/// Whether a calendar event carries an alarm is the writer's call, from the same `premium`.
func deliveryPlan(rules: [AlertRule], occurrences: [AlertOccurrence], now: Date, premium: Bool) -> DeliveryPlan {
    let live = Dictionary(uniqueKeysWithValues: rules.filter(\.enabled).map { ($0.id, $0) })
    let ordered = occurrences.sorted { $0.fire < $1.fire }

    let calendar = ordered.filter {
        live[$0.ruleID]?.calendar == true
            && $0.event > now && $0.event <= now.addingTimeInterval(AlertHorizon.calendar)
    }
    guard premium else { return DeliveryPlan(calendar: calendar) }
    let notifications = ordered.filter {
        live[$0.ruleID]?.alert == .notification
            && $0.fire > now && $0.fire <= now.addingTimeInterval(AlertHorizon.notifications)
    }
    return DeliveryPlan(calendar: calendar,
                        notifications: Array(notifications.prefix(AlertHorizon.notificationLimit)))
}

/// Each rule's last delivered moment — a calendar event's time or a notification's fire —
/// for the Alerts screen's "Scheduled through".
func scheduledThrough(_ plan: DeliveryPlan) -> [UUID: Date] {
    var through: [UUID: Date] = [:]
    for (id, moment) in plan.calendar.map({ ($0.ruleID, $0.event) }) + plan.notifications.map({ ($0.ruleID, $0.fire) }) {
        through[id] = max(through[id] ?? moment, moment)
    }
    return through
}

struct AlertCopy: Equatable {
    let title: String
    let body: String
}

let alertLeads: [TimeInterval] = [0, 900, 1_800, 3_600, 10_800, 86_400]

func alertLeadLabel(_ lead: TimeInterval) -> String {
    lead == 0 ? "At the time" : "\(leadAmount(lead)) before"
}

private func leadAmount(_ lead: TimeInterval) -> String {
    switch lead {
    case ..<3_600: "\(Int(lead / 60)) min"
    case ..<86_400: "\(Int(lead / 3_600)) hr"
    default: "\(Int(lead / 86_400)) day" + (lead >= 172_800 ? "s" : "")
    }
}

/// Title and body for one occurrence. The title is the place, then the event in as few words
/// as it takes; the body is the time in the station's zone, with the span, threshold or height
/// where they matter. The calendar passes `includeLead: false`: an event sits at its own time,
/// so "in 30 min" means nothing there.
func alertCopy(_ rule: AlertRule, _ o: AlertOccurrence, place: AlertPlace, imperial: Bool,
               threshold: Double, includeLead: Bool, locale: Locale = .autoupdatingCurrent) -> AlertCopy {
    let clock = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: place.tz).locale(locale)
    let time = o.event.formatted(clock)
    let limit = String(format: "%.1f kn", threshold)

    var body: String
    switch rule.trigger {
    case .slackWindowOpens where o.noWindow:
        body = "\(time), no window under \(limit)"
    case .slackWindowOpens:
        body = o.end.map { "\(time)–\($0.formatted(clock)), under \(limit)" } ?? time
    case .tideExtreme:
        body = o.heightM.map { "\(time) · \(formatHeight($0, imperial: imperial)) \(heightUnit(imperial: imperial))" } ?? time
    case .slack, .currentPeak, .tideCrossing, .eclipse:
        body = time
    }
    if includeLead, rule.lead > 0 { body += " · in \(leadAmount(rule.lead))" }

    let event = alertEventName(rule.trigger, noWindow: o.noWindow, imperial: imperial)
    return AlertCopy(title: "\(place.name) - \(event)", body: body)
}

/// A calendar event's identity is its content, alarm included. A moved window, or an event
/// that gains or loses its Premium alarm, is a different event: the old one is removed and
/// the new one added.
func calendarEventKey(title: String, start: Date, end: Date, alarmOffset: TimeInterval?) -> String {
    let alarm = alarmOffset.map { String(Int($0)) } ?? "none"
    return "\(title)|\(Int(start.timeIntervalSince1970))|\(Int(end.timeIntervalSince1970))|\(alarm)"
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `SLACKWATER_ONLY=SlackwaterTests/DeliveryPlanTests,SlackwaterTests/AlertCopyTests ./scripts/test.sh`
Expected: 13 tests pass. If a copy test fails only on the dash or the clock format, print the actual string. The en_GB `.shortened` time is `14:32`; the window body uses an en dash `–`; the title joins with a plain ` - `.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/AlertPlan.swift SlackwaterTests/DeliveryPlanTests.swift SlackwaterTests/AlertCopyTests.swift
git commit -m "feat(alerts): delivery plan, horizons and place-first alert copy

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Scheduler, calendar writer, and the reschedule hooks

**Files:**
- Create: `Slackwater/AlertScheduler.swift`, `Slackwater/AlertCalendar.swift`
- Modify: `Slackwater/AppGroup.swift` (after `alertRulesKey`), `project.yml` (app `info.properties`, after `NSLocationWhenInUseUsageDescription`), `Slackwater/SlackwaterApp.swift:18` and `:57-59`, `Slackwater/SettingsView.swift:154-157`
- Test: `SlackwaterTests/AlertResolveTests.swift`

**Interfaces:**
- Consumes: Tasks 1–4; `WidgetStationLoader.loadRecord(id:)`, `.station(from:)`; `slackThresholdKn`; `PremiumStore.shared.isPremium`; `shareURL(forStationID:at:tz:)`, `deepLink(forStationID:)` (`DeepLink.swift`); `appNow()`; `unitsKey`
- Produces:
  - `struct AlertEntry { let occurrence: AlertOccurrence; let copy: AlertCopy; let url: URL?; let place: AlertPlace; var alarmOffset: TimeInterval? }`
  - `struct ResolvedAlerts: Sendable { var occurrences: [AlertOccurrence]; var places: [String: AlertPlace]; var unresolved: Set<UUID> }`
  - `func resolveAlerts(_ rules: [AlertRule], now: Date, threshold: Double) -> ResolvedAlerts`
  - `struct AlertStatusSnapshot: Equatable { var scheduledThrough: [UUID: Date]; var unresolved: Set<UUID>; var notificationsAuthorized: Bool; var calendarAuthorized: Bool }`
  - `@MainActor final class AlertScheduler: ObservableObject { static let shared; @Published private(set) var status: AlertStatusSnapshot; nonisolated static func requestReschedule(); func reschedule(now: Date) async }`
  - `@MainActor enum AlertCalendar { static var authorized: Bool; static func requestAccess() async -> Bool; static func apply(_ entries: [AlertEntry], now: Date) }`
  - `AppGroup.alertCalendarKey = "slackwater.alertCalendar"`

- [ ] **Step 1: Write the failing test**

`SlackwaterTests/AlertResolveTests.swift`:

```swift
// Slackwater — GPL v3. resolveAlerts: rules → occurrences and places, with unknown stations reported rather than dropped.
import XCTest
@testable import Slackwater

final class AlertResolveTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_755_800_000)

    func testResolveNamesPlacesAndReportsUnknownStations() {
        let good = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .tideExtreme(high: true))
        let unknown = AlertRule(stationID: "noaa/does-not-exist", trigger: .tideExtreme(high: true))
        var off = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .tideExtreme(high: false))
        off.enabled = false

        let resolved = resolveAlerts([good, unknown, off], now: now, threshold: 0.5)

        XCTAssertEqual(resolved.unresolved, [unknown.id])
        XCTAssertEqual(resolved.places[TideStationRecord.fridayHarborID]?.name, "Friday Harbor")
        XCTAssertFalse(resolved.occurrences.isEmpty)
        XCTAssertTrue(resolved.occurrences.allSatisfy { $0.ruleID == good.id })
        XCTAssertTrue(resolved.occurrences.allSatisfy { $0.event.timeIntervalSince(self.now) <= AlertHorizon.calendar })
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertResolveTests ./scripts/test.sh`
Expected: build failure, `cannot find 'resolveAlerts' in scope`.

- [ ] **Step 3: Add the calendar key and the usage string**

In `Slackwater/AppGroup.swift`, after `alertRulesKey`:

```swift
    /// The identifier of the "Slackwater" calendar the app created (notifications spec §5.1).
    static let alertCalendarKey = "slackwater.alertCalendar"
```

In `project.yml`, under `targets.Slackwater.info.properties`, directly after the `NSLocationWhenInUseUsageDescription` entry:

```yaml
        NSCalendarsFullAccessUsageDescription: >-
          Slackwater adds the tide and current events you ask for to its own
          Slackwater calendar, and updates or removes them when they change. It
          never reads or changes your other calendars.
```

- [ ] **Step 4: Write the scheduler**

`Slackwater/AlertScheduler.swift`:

```swift
// Slackwater — GPL v3. Runs the alert pipeline — rules → occurrences → plan → writers — on launch and on every change (notifications spec §6).
import Foundation

/// One planned delivery with everything a writer needs.
struct AlertEntry {
    let occurrence: AlertOccurrence
    let copy: AlertCopy
    let url: URL?
    let place: AlertPlace
    /// A calendar event's alarm, relative to its start. Nil for a free user, and for notifications.
    var alarmOffset: TimeInterval? = nil
}

struct ResolvedAlerts: Sendable {
    var occurrences: [AlertOccurrence] = []
    /// Keyed by `AlertRule.stationID`.
    var places: [String: AlertPlace] = [:]
    /// Enabled rules whose station can't be loaded yet — a CHS station not fitted on this
    /// device, or an id that left the catalog.
    var unresolved: Set<UUID> = []
}

/// Occurrences for every enabled rule from `now` to the calendar horizon. Off the main
/// actor: a season-scale scan per station is real work.
/// ponytail: two rules on one station load it twice; share the record if that ever measures.
func resolveAlerts(_ rules: [AlertRule], now: Date, threshold: Double) -> ResolvedAlerts {
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
    return resolved
}

struct AlertStatusSnapshot: Equatable {
    var scheduledThrough: [UUID: Date] = [:]
    var unresolved: Set<UUID> = []
    var notificationsAuthorized = false
    var calendarAuthorized = false
}

@MainActor final class AlertScheduler: ObservableObject {
    static let shared = AlertScheduler()

    @Published private(set) var status = AlertStatusSnapshot()
    private var running = false
    private var again = false

    /// Safe from anywhere. One run at a time; any number of requests during a run buy
    /// exactly one more.
    nonisolated static func requestReschedule() {
        Task { @MainActor in await shared.coalesced() }
    }

    private func coalesced() async {
        if running { again = true; return }
        running = true
        repeat {
            again = false
            await reschedule()
        } while again
        running = false
    }

    func reschedule(now: Date = appNow()) async {
        let rules = AlertRuleStore.shared.rules
        let threshold = slackThresholdKn
        let premium = PremiumStore.shared.isPremium
        let imperial = AppGroup.defaults.string(forKey: unitsKey) != "metric"

        let resolved = await Task.detached(priority: .utility) {
            resolveAlerts(rules, now: now, threshold: threshold)
        }.value
        let plan = deliveryPlan(rules: rules, occurrences: resolved.occurrences, now: now, premium: premium)
        let byID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })

        func entries(_ list: [AlertOccurrence], includeLead: Bool, alarm: Bool) -> [AlertEntry] {
            list.compactMap { o in
                guard let rule = byID[o.ruleID], let place = resolved.places[rule.stationID] else { return nil }
                return AlertEntry(
                    occurrence: o,
                    copy: alertCopy(rule, o, place: place, imperial: imperial,
                                    threshold: threshold, includeLead: includeLead),
                    url: shareURL(forStationID: rule.stationID, at: o.event, tz: place.tz)
                        ?? deepLink(forStationID: rule.stationID),
                    place: place,
                    alarmOffset: alarm ? -rule.lead : nil)
            }
        }

        // Premium puts an alarm on every calendar event (spec §5.1).
        AlertCalendar.apply(entries(plan.calendar, includeLead: false, alarm: premium), now: now)

        status = AlertStatusSnapshot(scheduledThrough: scheduledThrough(plan),
                                     unresolved: resolved.unresolved,
                                     notificationsAuthorized: false,
                                     calendarAuthorized: AlertCalendar.authorized)
    }
}
```

- [ ] **Step 5: Write the calendar writer**

`Slackwater/AlertCalendar.swift`:

```swift
// Slackwater — GPL v3. Writes alert occurrences into the app's own "Slackwater" calendar, and only that one (notifications spec §5.1).
import EventKit

@MainActor enum AlertCalendar {
    private static let store = EKEventStore()

    /// Full access only. Write-only access can save new events but never read back or
    /// remove them, so a moved window would strand the old one in someone's calendar.
    static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// The Slackwater calendar, created on first use in the account new events already go to,
    /// so it syncs wherever the user's calendars do. Recreated if the user deleted it.
    private static func slackwaterCalendar(create: Bool) -> EKCalendar? {
        if let id = AppGroup.defaults.string(forKey: AppGroup.alertCalendarKey),
           let existing = store.calendar(withIdentifier: id) { return existing }
        guard create else { return nil }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Slackwater"
        guard let source = store.defaultCalendarForNewEvents?.source
                ?? store.sources.first(where: { $0.sourceType == .local }) else { return nil }
        calendar.source = source
        do { try store.saveCalendar(calendar, commit: true) } catch { return nil }
        AppGroup.defaults.set(calendar.calendarIdentifier, forKey: AppGroup.alertCalendarKey)
        return calendar
    }

    /// Makes the calendar's future match `entries`: removes events no longer planned and adds
    /// the missing ones. Past events are left alone.
    /// ponytail: an event the user edited by hand (moved, a second alarm) stops matching and is
    /// replaced. Runs on the main actor — a few hundred EventKit saves; move off it if it measures.
    static func apply(_ entries: [AlertEntry], now: Date) {
        guard authorized, let calendar = slackwaterCalendar(create: !entries.isEmpty) else { return }
        let predicate = store.predicateForEvents(withStart: now,
                                                 end: now.addingTimeInterval(AlertHorizon.calendar + 86_400),
                                                 calendars: [calendar])
        let existing = store.events(matching: predicate)
        let wanted = Dictionary(entries.map { entry -> (String, AlertEntry) in
            let end = entry.occurrence.end ?? entry.occurrence.event
            return (calendarEventKey(title: entry.copy.title, start: entry.occurrence.event, end: end,
                                     alarmOffset: entry.alarmOffset), entry)
        }, uniquingKeysWith: { first, _ in first })

        var have = Set<String>()
        for event in existing {
            let key = calendarEventKey(title: event.title ?? "", start: event.startDate, end: event.endDate,
                                       alarmOffset: event.alarms?.first?.relativeOffset)
            if wanted[key] == nil {
                try? store.remove(event, span: .thisEvent, commit: false)
            } else {
                have.insert(key)
            }
        }
        for (key, entry) in wanted where !have.contains(key) {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = entry.copy.title
            event.notes = entry.copy.body
            event.startDate = entry.occurrence.event
            event.endDate = entry.occurrence.end ?? entry.occurrence.event
            event.timeZone = entry.place.tz
            event.url = entry.url
            if let offset = entry.alarmOffset { event.addAlarm(EKAlarm(relativeOffset: offset)) }
            try? store.save(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }
}
```

- [ ] **Step 6: Wire the reschedule hooks**

In `Slackwater/SlackwaterApp.swift`, replace line 18:

```swift
        WidgetReload.trigger = { WidgetCenter.shared.reloadAllTimelines() }
```

with:

```swift
        // Every CHS model save funnels through this hook, and a newly fitted station can
        // make a waiting alert schedulable (notifications spec §6).
        WidgetReload.trigger = {
            WidgetCenter.shared.reloadAllTimelines()
            AlertScheduler.requestReschedule()
        }
        AlertRuleStore.shared.onChange = { AlertScheduler.requestReschedule() }
```

In `RootView` (same file), replace:

```swift
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { LocationService.shared.refreshIfAuthorized() }
        }
```

with:

```swift
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                LocationService.shared.refreshIfAuthorized()
                // Tops up the notification horizon and picks up permission changes made in Settings.
                AlertScheduler.requestReschedule()
            }
        }
        // `.onChange` is not guaranteed to see the launch transition into `.active`.
        .task { AlertScheduler.requestReschedule() }
```

In `Slackwater/SettingsView.swift`, replace `slackWindowSpeedBinding` (lines 154-157):

```swift
    private var slackWindowSpeedBinding: Binding<Double> {
        Binding(get: { normalizedSlackThresholdKn(slackWindowSpeed) },
                set: { slackWindowSpeed = normalizedSlackThresholdKn($0) })
    }
```

with:

```swift
    private var slackWindowSpeedBinding: Binding<Double> {
        Binding(get: { normalizedSlackThresholdKn(slackWindowSpeed) },
                set: {
                    slackWindowSpeed = normalizedSlackThresholdKn($0)
                    // Every scheduled slack window was computed at the old threshold.
                    AlertScheduler.requestReschedule()
                })
    }
```

- [ ] **Step 7: Run the test and watch it pass, then compile everything**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertResolveTests ./scripts/test.sh`
Expected: 1 test passes.

Run the compile check from Global Constraints. Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Slackwater/AlertScheduler.swift Slackwater/AlertCalendar.swift Slackwater/AppGroup.swift \
        Slackwater/SlackwaterApp.swift Slackwater/SettingsView.swift project.yml SlackwaterTests/AlertResolveTests.swift
git commit -m "feat(alerts): scheduler and the Slackwater calendar writer

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Notification writer, taps, and the Premium hook

**Files:**
- Create: `Slackwater/AlertNotifications.swift`
- Modify: `Slackwater/AlertScheduler.swift` (`reschedule`), `Slackwater/SlackwaterApp.swift` (`init`), `Slackwater/PremiumStore.swift:86-88`, `Slackwater/StationListView.swift:171`

**Interfaces:**
- Consumes: Task 5 `AlertEntry`, `AlertScheduler`; `StationListView.handleDeepLink(_:)` (private, same file)
- Produces:
  - `@MainActor enum AlertNotifications { static let prefix: String; static func authorized() async -> Bool; static func requestAccess() async -> Bool; static func apply(_ entries: [AlertEntry]) async }`
  - `final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate { static let shared }`
  - `@MainActor final class AlertTap: ObservableObject { static let shared; nonisolated static let urlKey: String; @Published var url: URL? }`

This task's behaviour is system delivery, which a unit test can't observe. It is verified in the simulator in Task 9. Its deliverable here is a clean compile plus a green unit suite.

- [ ] **Step 1: Write the notification writer**

`Slackwater/AlertNotifications.swift`:

```swift
// Slackwater — GPL v3. Schedules Premium alert notifications and routes a tap to the station at the event (notifications spec §5.2).
import UserNotifications

@MainActor enum AlertNotifications {
    /// Every request this writer owns. Nothing else in the app schedules notifications, but
    /// the prefix keeps a replace from ever touching one that isn't ours.
    static let prefix = "alert."

    static func authorized() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    /// Never provisional: provisional delivery never reaches the Lock Screen.
    static func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces every pending alert request with `entries`.
    static func apply(_ entries: [AlertEntry]) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard await authorized() else { return }
        for entry in entries {
            // An interval, not calendar components: the occurrence is an absolute instant,
            // and this stays right when the phone changes time zone.
            let wait = entry.occurrence.fire.timeIntervalSinceNow
            guard wait > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = entry.copy.title
            content.body = entry.copy.body
            content.sound = .default
            if let url = entry.url { content.userInfo = [AlertTap.urlKey: url.absoluteString] }
            let request = UNNotificationRequest(
                identifier: prefix + entry.occurrence.key, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false))
            try? await center.add(request)
        }
    }
}

/// Where a tapped alert's link waits for the station list to open it. Published, so a list
/// that appears after a cold launch from the notification still receives it.
@MainActor final class AlertTap: ObservableObject {
    static let shared = AlertTap()
    nonisolated static let urlKey = "url"
    @Published var url: URL?
}

final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo[AlertTap.urlKey] as? String,
              let url = URL(string: text) else { return }
        await MainActor.run { AlertTap.shared.url = url }
    }
}
```

- [ ] **Step 2: Deliver notifications from the scheduler**

In `Slackwater/AlertScheduler.swift`, inside `reschedule`, replace:

```swift
        // Premium puts an alarm on every calendar event (spec §5.1).
        AlertCalendar.apply(entries(plan.calendar, includeLead: false, alarm: premium), now: now)

        status = AlertStatusSnapshot(scheduledThrough: scheduledThrough(plan),
                                     unresolved: resolved.unresolved,
                                     notificationsAuthorized: false,
                                     calendarAuthorized: AlertCalendar.authorized)
```

with:

```swift
        // Premium puts an alarm on every calendar event (spec §5.1).
        AlertCalendar.apply(entries(plan.calendar, includeLead: false, alarm: premium), now: now)
        await AlertNotifications.apply(entries(plan.notifications, includeLead: true, alarm: false))

        status = AlertStatusSnapshot(scheduledThrough: scheduledThrough(plan),
                                     unresolved: resolved.unresolved,
                                     notificationsAuthorized: await AlertNotifications.authorized(),
                                     calendarAuthorized: AlertCalendar.authorized)
```

- [ ] **Step 3: Install the delegate at launch**

In `Slackwater/SlackwaterApp.swift`, add `import UserNotifications` below `import WidgetKit`. Then add these lines to `init()` directly after `AlertRuleStore.shared.onChange = { AlertScheduler.requestReschedule() }`:

```swift
        // Before launch finishes, so a tap that cold-launches the app is delivered.
        UNUserNotificationCenter.current().delegate = AlertNotificationDelegate.shared
```

- [ ] **Step 4: Reschedule when Premium changes**

In `Slackwater/PremiumStore.swift`, `refreshEntitlement()`, replace:

```swift
        isPremium = premium
        Self.cache(premium, into: AppGroup.defaults)
        WidgetCenter.shared.reloadAllTimelines()
```

with:

```swift
        isPremium = premium
        Self.cache(premium, into: AppGroup.defaults)
        WidgetCenter.shared.reloadAllTimelines()
        // Gaining Premium schedules notifications and calendar alarms; losing it clears them
        // (notifications spec §6).
        AlertScheduler.requestReschedule()
```

- [ ] **Step 5: Open a tapped alert**

In `Slackwater/StationListView.swift`, replace line 171:

```swift
        .onOpenURL(perform: handleDeepLink)
```

with:

```swift
        .onOpenURL(perform: handleDeepLink)
        // A tapped alert carries the same station link a share does.
        .onReceive(AlertTap.shared.$url) { url in
            guard let url else { return }
            AlertTap.shared.url = nil
            handleDeepLink(url)
        }
```

- [ ] **Step 6: Compile, then run the unit suite**

Run the compile check from Global Constraints. Expected: `** TEST BUILD SUCCEEDED **`.
Run: `./scripts/test.sh --unit`
Expected: every unit test passes, including the Alert* classes from Tasks 1–5.

- [ ] **Step 7: Commit**

```bash
git add Slackwater/AlertNotifications.swift Slackwater/AlertScheduler.swift Slackwater/SlackwaterApp.swift \
        Slackwater/PremiumStore.swift Slackwater/StationListView.swift
git commit -m "feat(alerts): Premium notifications and tap-to-station

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: The Calendar / Live row

**Files:**
- Create: `Slackwater/AlertOffer.swift`, `Slackwater/AlertRow.swift`
- Modify: `Slackwater/TimelineStrip.swift:45` (add `Timeline.rest`) and `:1663` (use it), `Slackwater/Theme.swift:756` and `:916-918` (`ScrubDetailScaffold`), `Slackwater/TideDetailView.swift:96`, `Slackwater/CurrentDetailView.swift:91`, `Slackwater/DerivedGateDetailView.swift:51`
- Test: `SlackwaterTests/AlertOfferTests.swift`, `SlackwaterUITests/AlertRowTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 5, 6 (`AlertRule`, `AlertRuleStore`, `AlertCalendar.authorized`/`requestAccess`, `AlertNotifications.requestAccess`); `PremiumStore`, `PremiumView`; `WindowEclipse.contacts`; `scrubbedAway(_:from:)`; `SN`
- Produces:
  - `func tideAlertOffer(scrubbedAway: Bool, turnIsHigh: Bool?, onEclipseContact: Bool, heightM: Double, rising: Bool) -> AlertTrigger`
  - `func currentAlertOffer(maxIsFlood: Bool?, onEclipseContact: Bool) -> AlertTrigger`
  - `func derivedAlertOffer(onEclipseContact: Bool) -> AlertTrigger`
  - `func isOnEclipseContact(_ time: Date, _ eclipses: [WindowEclipse]) -> Bool`
  - `enum AlertDelivery { case calendar, live }`
  - `enum AlertRuleChange: Equatable { case upsert(AlertRule), remove(UUID) }`
  - `let alertRowLead: TimeInterval` (1 800)
  - `func alertRowToggle(_ rules: [AlertRule], stationID: String, offer: AlertTrigger, delivery: AlertDelivery) -> AlertRuleChange`
  - `func alertRowState(_ rules: [AlertRule], stationID: String, offer: AlertTrigger) -> (calendar: Bool, live: Bool)`
  - `struct AlertRow: View { init(stationID: String, offer: AlertTrigger, scrubTime: Date) }`
  - `Timeline.rest: Duration`
  - `ScrubDetailScaffold.alertOffer: AlertTrigger?` (default nil)

- [ ] **Step 1: Write the failing unit test**

`SlackwaterTests/AlertOfferTests.swift`:

```swift
// Slackwater — GPL v3. The alert row: what it offers for the moment under the centerline, and what a tap does (notifications spec §7.1).
import XCTest
@testable import Slackwater
import Almanac

final class AlertOfferTests: XCTestCase {
    func testTideOfferReadsTheCenterline() {
        XCTAssertEqual(tideAlertOffer(scrubbedAway: true, turnIsHigh: true, onEclipseContact: false, heightM: 2.1, rising: false),
                       .tideExtreme(high: true))
        XCTAssertEqual(tideAlertOffer(scrubbedAway: true, turnIsHigh: nil, onEclipseContact: true, heightM: 1.4, rising: true),
                       .eclipse)
        XCTAssertEqual(tideAlertOffer(scrubbedAway: true, turnIsHigh: nil, onEclipseContact: false, heightM: 1.4, rising: true),
                       .tideCrossing(heightM: 1.4, rising: true))
        XCTAssertEqual(tideAlertOffer(scrubbedAway: false, turnIsHigh: nil, onEclipseContact: false, heightM: 1.4, rising: true),
                       .tideExtreme(high: false))
    }

    func testCurrentAndDerivedOffers() {
        XCTAssertEqual(currentAlertOffer(maxIsFlood: false, onEclipseContact: false), .currentPeak(flood: false))
        XCTAssertEqual(currentAlertOffer(maxIsFlood: nil, onEclipseContact: true), .eclipse)
        XCTAssertEqual(currentAlertOffer(maxIsFlood: nil, onEclipseContact: false), .slackWindowOpens)
        XCTAssertEqual(derivedAlertOffer(onEclipseContact: false), .slack)
        XCTAssertEqual(derivedAlertOffer(onEclipseContact: true), .eclipse)
    }

    func testAnEclipseContactMatchesWithinASecond() throws {
        let iso = ISO8601DateFormatter()
        let observer = try Observer(latitudeDeg: 48.545, longitudeDeg: -123.013)
        let eclipses = visibleEclipses(from: try XCTUnwrap(iso.date(from: "2026-03-01T00:00:00Z")),
                                       to: try XCTUnwrap(iso.date(from: "2026-03-05T00:00:00Z")),
                                       observer: observer)
        let contact = try XCTUnwrap(eclipses.first?.contacts.first)
        XCTAssertTrue(isOnEclipseContact(contact.addingTimeInterval(0.5), eclipses))
        XCTAssertFalse(isOnEclipseContact(contact.addingTimeInterval(5), eclipses))
        XCTAssertFalse(isOnEclipseContact(contact, []))
    }

    func testCalendarCreatesARuleWithAThirtyMinuteLead() {
        let change = alertRowToggle([], stationID: "noaa/9449880", offer: .tideExtreme(high: false), delivery: .calendar)
        guard case .upsert(let rule) = change else { return XCTFail("expected a new rule") }
        XCTAssertEqual(rule.stationID, "noaa/9449880")
        XCTAssertEqual(rule.trigger, .tideExtreme(high: false))
        XCTAssertEqual(rule.lead, 1_800)
        XCTAssertTrue(rule.calendar)
        XCTAssertEqual(rule.alert, .none)
    }

    func testLiveJoinsTheSameRuleAndARuleWithNothingLeftIsRemoved() {
        let calendarOnly = AlertRule(stationID: "s", trigger: .slackWindowOpens, lead: 1_800)

        guard case .upsert(let both) = alertRowToggle([calendarOnly], stationID: "s", offer: .slackWindowOpens, delivery: .live)
        else { return XCTFail("expected an update") }
        XCTAssertEqual(both.id, calendarOnly.id)
        XCTAssertTrue(both.calendar)
        XCTAssertEqual(both.alert, .notification)

        guard case .upsert(let liveOnly) = alertRowToggle([both], stationID: "s", offer: .slackWindowOpens, delivery: .calendar)
        else { return XCTFail("expected an update") }
        XCTAssertFalse(liveOnly.calendar)
        XCTAssertEqual(liveOnly.alert, .notification)

        XCTAssertEqual(alertRowToggle([liveOnly], stationID: "s", offer: .slackWindowOpens, delivery: .live),
                       .remove(calendarOnly.id))
    }

    func testADifferentOfferIsADifferentRule() {
        let existing = AlertRule(stationID: "s", trigger: .tideCrossing(heightM: 1.4, rising: true))
        let change = alertRowToggle([existing], stationID: "s", offer: .tideCrossing(heightM: 1.2, rising: true), delivery: .calendar)
        guard case .upsert(let rule) = change else { return XCTFail("expected a new rule") }
        XCTAssertNotEqual(rule.id, existing.id)
    }

    func testTheRowReadsEnabledDeliveriesAndATapWakesAnOffRule() {
        var rule = AlertRule(stationID: "s", trigger: .slack, alert: .notification)
        XCTAssertTrue(alertRowState([rule], stationID: "s", offer: .slack).calendar)
        XCTAssertTrue(alertRowState([rule], stationID: "s", offer: .slack).live)
        XCTAssertFalse(alertRowState([rule], stationID: "s", offer: .eclipse).calendar)

        rule.enabled = false
        let off = alertRowState([rule], stationID: "s", offer: .slack)
        XCTAssertFalse(off.calendar)
        XCTAssertFalse(off.live)

        guard case .upsert(let woken) = alertRowToggle([rule], stationID: "s", offer: .slack, delivery: .calendar)
        else { return XCTFail("expected an update") }
        XCTAssertTrue(woken.enabled)
        XCTAssertTrue(woken.calendar)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertOfferTests ./scripts/test.sh`
Expected: build failure, `cannot find 'tideAlertOffer' in scope`.

- [ ] **Step 3: Write the offer and toggle logic**

`Slackwater/AlertOffer.swift`:

```swift
// Slackwater — GPL v3. What the alert row offers for the moment under the centerline, and what a tap on it does (notifications spec §7.1).
import Foundation

/// A tide detail: the extreme the strip parked on; an eclipse contact; otherwise, once scrubbed
/// away from now, the height under the line in the direction the curve moves. Tapping the
/// timeline lands on an arbitrary instant, and on a tide curve that instant is a height.
/// Unscrubbed, the everyday ask: the next low.
func tideAlertOffer(scrubbedAway: Bool, turnIsHigh: Bool?, onEclipseContact: Bool,
                    heightM: Double, rising: Bool) -> AlertTrigger {
    if let high = turnIsHigh { return .tideExtreme(high: high) }
    if onEclipseContact { return .eclipse }
    return scrubbedAway ? .tideCrossing(heightM: heightM, rising: rising) : .tideExtreme(high: false)
}

/// A current detail: the max the strip parked on, an eclipse contact, or else the slack window.
func currentAlertOffer(maxIsFlood: Bool?, onEclipseContact: Bool) -> AlertTrigger {
    if let flood = maxIsFlood { return .currentPeak(flood: flood) }
    return onEclipseContact ? .eclipse : .slackWindowOpens
}

/// A derived gate knows only its slacks.
func derivedAlertOffer(onEclipseContact: Bool) -> AlertTrigger {
    onEclipseContact ? .eclipse : .slack
}

/// The magnet parks `scrubTime` on a snap target's own second; ±1 s is `atTurn`'s tolerance too.
func isOnEclipseContact(_ time: Date, _ eclipses: [WindowEclipse]) -> Bool {
    eclipses.contains { $0.contacts.contains { abs($0.timeIntervalSince(time)) < 1 } }
}

enum AlertDelivery {
    case calendar, live
}

enum AlertRuleChange: Equatable {
    case upsert(AlertRule)
    case remove(UUID)
}

/// A rule made from the row reminds half an hour ahead; the Alerts screen changes it.
let alertRowLead: TimeInterval = 1_800

/// One tap on Calendar or Live for this station and offer: turn that delivery on or off on the
/// matching rule, create the rule with it on, or remove a rule left with nothing. Turning a
/// delivery on also turns a rule that was switched off back on.
func alertRowToggle(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                    delivery: AlertDelivery) -> AlertRuleChange {
    guard var rule = rules.first(where: { $0.stationID == stationID && $0.trigger == offer }) else {
        return .upsert(AlertRule(stationID: stationID, trigger: offer, lead: alertRowLead,
                                 calendar: delivery == .calendar,
                                 alert: delivery == .live ? .notification : .none))
    }
    let wasOn = rule.enabled && (delivery == .calendar ? rule.calendar : rule.alert == .notification)
    switch delivery {
    case .calendar: rule.calendar = !wasOn
    case .live: rule.alert = wasOn ? .none : .notification
    }
    if !wasOn { rule.enabled = true }
    return (!rule.calendar && rule.alert == .none) ? .remove(rule.id) : .upsert(rule)
}

/// Which of the row's two buttons read on for this station and offer.
func alertRowState(_ rules: [AlertRule], stationID: String, offer: AlertTrigger) -> (calendar: Bool, live: Bool) {
    guard let rule = rules.first(where: { $0.stationID == stationID && $0.trigger == offer && $0.enabled })
    else { return (false, false) }
    return (rule.calendar, rule.alert == .notification)
}
```

- [ ] **Step 4: Run the unit test and watch it pass**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertOfferTests ./scripts/test.sh`
Expected: 7 tests pass.

- [ ] **Step 5: Share the strip's rest rule**

In `Slackwater/TimelineStrip.swift`, directly after `static let magnetPts: CGFloat = 46    // snap radius around the centerline` (line 45), add:

```swift
    /// No scrub change for this long is a strip at rest: the chrome comes back and the alert
    /// row's taps start counting.
    static let rest: Duration = .milliseconds(450)
```

In the same file, in `chromeRow`'s `.task(id: scrubTime)`, replace:

```swift
            guard (try? await Task.sleep(for: .milliseconds(450))) != nil else { return }
```

with:

```swift
            guard (try? await Task.sleep(for: Timeline.rest)) != nil else { return }
```

- [ ] **Step 6: Write the row**

`Slackwater/AlertRow.swift`:

```swift
// Slackwater — GPL v3. Calendar and Live under the strip: set an alert for the moment on screen (notifications spec §7.1).
import SwiftUI

/// Always on screen and never disabled, so it never flickers while someone scrubs. A tap only
/// counts once the strip has rested (`Timeline.rest`), because until then the centerline isn't
/// a moment anyone chose. The buttons show the resting moment's rule, not every frame's.
struct AlertRow: View {
    let stationID: String
    let offer: AlertTrigger
    let scrubTime: Date

    @ObservedObject private var store = AlertRuleStore.shared
    @ObservedObject private var premium = PremiumStore.shared
    /// True once the strip has rested on the current `scrubTime`.
    @State private var settled = false
    /// The offer at the last rest — what the buttons show, so they don't change every frame.
    @State private var shown: AlertTrigger?
    @State private var showPremium = false

    var body: some View {
        let state = alertRowState(store.rules, stationID: stationID, offer: shown ?? offer)
        HStack(spacing: 10) {
            button("Calendar", image: state.calendar ? "calendar.badge.checkmark" : "calendar.badge.plus",
                   on: state.calendar, id: "alert-calendar-button") { tap(.calendar) }
            button("Live", image: state.live ? "bell.fill" : "bell",
                   on: state.live, id: "alert-live-button") { tap(.live) }
        }
        .task(id: scrubTime) {
            // A cancelled sleep is a scrub still in motion, not a rest.
            settled = false
            guard (try? await Task.sleep(for: Timeline.rest)) != nil else { return }
            shown = offer
            settled = true
        }
        // The third upsell surface (widgets-premium §5): only Live leads here.
        .sheet(isPresented: $showPremium) { PremiumView() }
    }

    private func tap(_ delivery: AlertDelivery) {
        guard settled, let offer = shown else { return }
        if delivery == .live && !premium.isPremium {
            showPremium = true
            return
        }
        let change = alertRowToggle(store.rules, stationID: stationID, offer: offer, delivery: delivery)
        Task {
            // Each permission is asked the first time its mechanism is turned on, never at launch.
            if case .upsert(let rule) = change {
                if delivery == .calendar, rule.calendar, !AlertCalendar.authorized {
                    _ = await AlertCalendar.requestAccess()
                }
                if delivery == .live, rule.alert == .notification {
                    _ = await AlertNotifications.requestAccess()
                }
            }
            switch change {
            case .upsert(let rule): store.upsert(rule)
            case .remove(let id): store.remove(id)
            }
        }
    }

    private func button(_ title: String, image: String, on: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        Label(title, systemImage: image)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(on ? SN.leaf : .white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(SN.cardFill, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? SN.leaf.opacity(0.6) : SN.cardStroke, lineWidth: on ? 1 : 0.5))
            .contentShape(Capsule())
            // A tap gesture, not a Button: Button press tracking goes dead in the iPad split
            // layout's detail column (ReadoutTile, MultiDaySchedule).
            .onTapGesture(perform: action)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier(id)
    }
}
```

- [ ] **Step 7: Put the row between the strip and the tiles**

In `Slackwater/Theme.swift`, directly after `var topBackdrop: AnyView? = nil` (line 756), add:

```swift
    /// The rule the alert row offers for the moment on screen (notifications spec §7.1). Nil —
    /// the online gate — leaves the row out.
    var alertOffer: AlertTrigger? = nil
```

In `scrubCard(_:)`, replace:

```swift
            card(tl)

            links(tl, jump)
                .padding(.top, 12)
                .padding(.horizontal, 16)
```

with:

```swift
            card(tl)

            if let alertOffer {
                AlertRow(stationID: favoriteId, offer: alertOffer, scrubTime: scrubTime)
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
            }

            links(tl, jump)
                .padding(.top, 12)
                .padding(.horizontal, 16)
```

- [ ] **Step 8: Each consumer supplies its offer**

In `Slackwater/TideDetailView.swift`, directly after `topBackdrop: AnyView(SkyBackdrop(sky: sky)),` (line 96):

```swift
                            alertOffer: tideAlertOffer(
                                scrubbedAway: scrubbedAway(scrubTime, from: live),
                                turnIsHigh: atTurn.map { $0.kind == .high },
                                onEclipseContact: isOnEclipseContact(scrubTime, timeline?.eclipses ?? []),
                                heightM: scrubHeight, rising: rising),
```

In `Slackwater/CurrentDetailView.swift`, directly after `topBackdrop: AnyView(SkyBackdrop(sky: sky)),` (line 91):

```swift
                            alertOffer: currentAlertOffer(
                                // CurrentLead's `atMax`, read here because the lead keeps it private.
                                maxIsFlood: timeline?.currentEvents.first {
                                    $0.kind != .slack && abs($0.time.timeIntervalSince(scrubTime)) < 1
                                }.map { $0.kind == .maxFlood },
                                onEclipseContact: isOnEclipseContact(scrubTime, timeline?.eclipses ?? [])),
```

In `Slackwater/DerivedGateDetailView.swift`, directly after `topBackdrop: AnyView(SkyBackdrop(sky: sky)),` (line 51):

```swift
                            alertOffer: derivedAlertOffer(
                                onEclipseContact: isOnEclipseContact(scrubTime, timeline?.eclipses ?? [])),
```

`OnlineGateDetailView.swift` stays unchanged, and has no row (spec §8).

- [ ] **Step 9: Write the UI test**

`SlackwaterUITests/AlertRowTests.swift`:

```swift
// Slackwater — GPL v3. The Calendar / Live row sits under tide and current strips, and Live offers Premium to a free user.
import XCTest

final class AlertRowTests: ScreenshotTestCase {
    func testTheRowSitsUnderATideStrip() {
        let app = launch("-seedGate")
        openFridayHarbor(app)

        XCTAssert(app.buttons["alert-calendar-button"].firstMatch.appears(within: 5), "no Calendar button on a tide detail")
        XCTAssert(app.buttons["alert-live-button"].firstMatch.exists, "no Live button on a tide detail")
        save(app, "alert-row-tide.png")
    }

    func testTheRowSitsUnderACurrentStrip() {
        let app = launch("-seedGate")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))

        XCTAssert(app.buttons["alert-calendar-button"].firstMatch.appears(within: 5), "no Calendar button on a current detail")
        XCTAssert(app.buttons["alert-live-button"].firstMatch.exists, "no Live button on a current detail")
    }

    func testLiveOffersPremiumToAFreeUserOnceTheStripRests() {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        let live = app.buttons["alert-live-button"].firstMatch
        XCTAssert(live.appears(within: 5))

        // The strip opens with a slide into place; a tap only counts once it has come to rest.
        sleep(2)
        live.tap()

        XCTAssert(app.navigationBars["Slackwater Premium"].appears(within: 5), "Live did not open the tier sheet")
    }
}
```

- [ ] **Step 10: Run the UI test and look at the screenshot**

Run: `SLACKWATER_ONLY=SlackwaterUITests/AlertRowTests ./scripts/test.sh`
Expected: 3 tests pass. Open `/tmp/slackwater-shots/alert-row-tide.png`. The Calendar and Live capsules should sit between the strip and the Range / Moon tiles, full width, on the dark canvas.

- [ ] **Step 11: Commit**

```bash
git add Slackwater/AlertOffer.swift Slackwater/AlertRow.swift Slackwater/TimelineStrip.swift Slackwater/Theme.swift \
        Slackwater/TideDetailView.swift Slackwater/CurrentDetailView.swift Slackwater/DerivedGateDetailView.swift \
        SlackwaterTests/AlertOfferTests.swift SlackwaterUITests/AlertRowTests.swift
git commit -m "feat(alerts): Calendar / Live row under the detail strip

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: The Alerts screen and the rule sheet

**Files:**
- Create: `Slackwater/AlertSheet.swift`, `Slackwater/AlertsView.swift`
- Modify: `Slackwater/SettingsView.swift` (properties at :7-14; a new section after the "Slack window" section)
- Test: `SlackwaterTests/AlertStatusTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 4, 5, 6 (`AlertRuleStore`, `alertRuleSummary`, `alertLeads`, `alertLeadLabel`, `AlertScheduler.shared.status`, `AlertStatusSnapshot`, `AlertCalendar`, `AlertNotifications`); `PremiumStore`, `PremiumView`; `StationItem.byId`; `SN`, `CanvasBackground`
- Produces: `func alertStatusText(_ rule: AlertRule, _ status: AlertStatusSnapshot, premium: Bool, tz: TimeZone = .current, locale: Locale = .autoupdatingCurrent) -> String`; `struct AlertSheet: View { init(rule: AlertRule, stationName: String) }`; `struct AlertsView: View`

- [ ] **Step 1: Write the failing test**

`SlackwaterTests/AlertStatusTests.swift`:

```swift
// Slackwater — GPL v3. The Alerts screen says why a rule is quiet, never just that it is.
import XCTest
@testable import Slackwater

final class AlertStatusTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let gb = Locale(identifier: "en_GB")
    private let through = Date(timeIntervalSince1970: 1_787_529_600)   // 2026-08-24 00:00 UTC

    private func text(_ rule: AlertRule, _ status: AlertStatusSnapshot, premium: Bool = true) -> String {
        alertStatusText(rule, status, premium: premium, tz: utc, locale: gb)
    }

    func testStatusSaysWhyARuleIsQuiet() {
        let rule = AlertRule(stationID: "x", trigger: .slack, alert: .notification)
        var status = AlertStatusSnapshot(scheduledThrough: [rule.id: through], unresolved: [],
                                         notificationsAuthorized: true, calendarAuthorized: true)

        XCTAssertEqual(text(rule, status), "Scheduled through 24 Aug")
        XCTAssertEqual(text(rule, status, premium: false), "Calendar only — notifications are Premium")

        status.notificationsAuthorized = false
        XCTAssertEqual(text(rule, status), "Notifications are off in Settings")

        status.unresolved = [rule.id]
        XCTAssertEqual(text(rule, status), "Waiting for station data")

        var off = rule
        off.enabled = false
        XCTAssertEqual(text(off, status), "Off")
    }

    func testCalendarOnlyRules() {
        let rule = AlertRule(stationID: "x", trigger: .eclipse)
        var status = AlertStatusSnapshot(calendarAuthorized: false)
        XCTAssertEqual(text(rule, status), "Calendar access is off in Settings")

        status.calendarAuthorized = true
        XCTAssertEqual(text(rule, status), "Nothing coming up")

        let notifyOnly = AlertRule(stationID: "x", trigger: .slack, calendar: false, alert: .notification)
        XCTAssertEqual(text(notifyOnly, status, premium: false), "Notifications are Premium")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertStatusTests ./scripts/test.sh`
Expected: build failure, `cannot find 'alertStatusText' in scope`.

- [ ] **Step 3: Write the rule sheet**

`Slackwater/AlertSheet.swift`:

```swift
// Slackwater — GPL v3. Edit one alert rule — lead, daylight, deliveries — from the Alerts screen (notifications spec §7.2).
import SwiftUI

struct AlertSheet: View {
    @State var rule: AlertRule
    let stationName: String
    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var store = AlertRuleStore.shared
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @Environment(\.dismiss) private var dismiss
    @State private var showPremium = false
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(alertRuleSummary(rule.trigger, stationName: stationName, imperial: units == "imperial"))
                        .accessibilityIdentifier("alert-summary")
                }
                Section("When") {
                    Picker("Remind me", selection: $rule.lead) {
                        ForEach(alertLeads, id: \.self) { Text(alertLeadLabel($0)).tag($0) }
                    }
                    Toggle("Daylight only", isOn: $rule.daylightOnly)
                }
                Section {
                    Toggle("Add to Calendar", isOn: $rule.calendar)
                    Toggle(isOn: notify) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notify me")
                            if !premium.isPremium {
                                Text("Slackwater Premium").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("With Slackwater Premium, calendar events carry an alarm and alerts arrive as notifications.")
                }
                Section {
                    Toggle("On", isOn: $rule.enabled)
                    Button("Delete Alert", role: .destructive) {
                        store.remove(rule.id)
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CanvasBackground())
            .navigationTitle("Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || (!rule.calendar && rule.alert == .none))
                }
            }
            .sheet(isPresented: $showPremium) { PremiumView() }
        }
        .preferredColorScheme(.dark)
    }

    private var notify: Binding<Bool> {
        Binding(get: { rule.alert == .notification },
                set: { on in
                    if on && !premium.isPremium {
                        showPremium = true
                        return
                    }
                    rule.alert = on ? .notification : .none
                })
    }

    /// A denial still saves the rule; the Alerts screen says why it is quiet.
    private func save() async {
        saving = true
        if rule.calendar && !AlertCalendar.authorized { _ = await AlertCalendar.requestAccess() }
        if rule.alert == .notification { _ = await AlertNotifications.requestAccess() }
        store.upsert(rule)
        dismiss()
    }
}
```

- [ ] **Step 4: Write the screen**

`Slackwater/AlertsView.swift`:

```swift
// Slackwater — GPL v3. Every alert rule, grouped by station, with why each one is or isn't delivering (notifications spec §7.3).
import SwiftUI

/// The first thing that explains a quiet rule, or when its deliveries run out.
func alertStatusText(_ rule: AlertRule, _ status: AlertStatusSnapshot, premium: Bool,
                     tz: TimeZone = .current, locale: Locale = .autoupdatingCurrent) -> String {
    if !rule.enabled { return "Off" }
    if status.unresolved.contains(rule.id) { return "Waiting for station data" }
    if rule.alert == .notification && !premium {
        return rule.calendar ? "Calendar only — notifications are Premium" : "Notifications are Premium"
    }
    if rule.alert == .notification && !status.notificationsAuthorized { return "Notifications are off in Settings" }
    if rule.calendar && !status.calendarAuthorized { return "Calendar access is off in Settings" }
    guard let date = status.scheduledThrough[rule.id] else { return "Nothing coming up" }
    return "Scheduled through \(date.formatted(Date.FormatStyle(timeZone: tz).day().month(.abbreviated).locale(locale)))"
}

struct AlertsView: View {
    @ObservedObject private var store = AlertRuleStore.shared
    @ObservedObject private var scheduler = AlertScheduler.shared
    @ObservedObject private var premium = PremiumStore.shared
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @State private var editing: AlertRule?

    private struct StationRules: Identifiable {
        let name: String
        let rules: [AlertRule]
        var id: String { name }
    }

    private func name(_ stationID: String) -> String { StationItem.byId[stationID]?.name ?? stationID }

    private var groups: [StationRules] {
        Dictionary(grouping: store.rules) { name($0.stationID) }
            .map { StationRules(name: $0.key, rules: $0.value) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            if store.rules.isEmpty {
                Text("No alerts yet. Tap Calendar or Live under any station's timeline to set one.")
                    .foregroundStyle(SN.foam.opacity(0.62))
            }
            ForEach(groups) { group in
                Section(group.name) {
                    ForEach(group.rules) { rule in
                        Button { editing = rule } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alertRuleSummary(rule.trigger, stationName: group.name,
                                                      imperial: units == "imperial"))
                                    .foregroundStyle(.white)
                                Text(alertStatusText(rule, scheduler.status, premium: premium.isPremium))
                                    .font(.caption)
                                    .foregroundStyle(SN.foam.opacity(0.62))
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { group.rules[$0].id }.forEach { store.remove($0) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CanvasBackground())
        .sheet(item: $editing) { rule in AlertSheet(rule: rule, stationName: name(rule.stationID)) }
    }
}
```

- [ ] **Step 5: Add the Settings row**

In `Slackwater/SettingsView.swift`, after `@State private var showWidgets = false` (line 14), add:

```swift
    @ObservedObject private var alerts = AlertRuleStore.shared
```

Directly after the closing brace of `section("Slack window") { … }`, which ends with the `Text("0.1–10 kn. …")` line, add:

```swift
                    section("Alerts") {
                        NavigationLink {
                            AlertsView()
                                .navigationTitle("Alerts")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(SN.canvas, for: .navigationBar)
                        } label: {
                            HStack {
                                Text(alerts.rules.isEmpty
                                     ? "Set alerts from Calendar or Live under any station's timeline"
                                     : "\(alerts.rules.count) alert\(alerts.rules.count == 1 ? "" : "s")")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(SN.leaf)
                        }
                    }
```

- [ ] **Step 6: Run the test and watch it pass, then compile**

Run: `SLACKWATER_ONLY=SlackwaterTests/AlertStatusTests ./scripts/test.sh`
Expected: 2 tests pass.
Run the compile check from Global Constraints. Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Slackwater/AlertSheet.swift Slackwater/AlertsView.swift Slackwater/SettingsView.swift SlackwaterTests/AlertStatusTests.swift
git commit -m "feat(alerts): Alerts screen and rule sheet

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Verify the whole arc, then the PR

**Files:** none created. This task is verification plus the PR.

- [ ] **Step 1: Full offline suite**

Run: `./scripts/test.sh --full`
Expected: green on both simulators. Read the result bundle (`build/results-*.xcresult`) as well as the exit code. A "Test crashed with signal kill" with zero assertion failures is machine contention, not a failure: rerun.

- [ ] **Step 2: Simulator walkthrough — the row and the calendar (spec §11 spike 2)**

Boot one simulator (`xcrun simctl boot "iPhone 17"`), install the Debug build, and launch it without launch arguments (the walkthrough needs the real clock). Then:

1. Open Friday Harbor. Flick the strip and, while it is still gliding, tap **Calendar**: nothing happens and no permission prompt appears.
2. Let the strip stop, then tap **Calendar**. Grant full calendar access. The button reads on.
3. Open the Calendar app. A calendar named **Slackwater** exists and holds `Friday Harbor - Low tide` events for the next 90 days. Each event has its URL set and **no** alert.
4. Back in Slackwater, open Settings → Alerts. The rule reads `Scheduled through <a date about 90 days out>`.
5. Tap **Calendar** again under the strip at the same resting moment. The rule is removed, and within a second its future events are gone from the Slackwater calendar, which is still there.

Record what you observed in the task report, including any step that behaved differently.

- [ ] **Step 3: Simulator walkthrough — Premium, alarms and notifications**

1. On Friday Harbor at rest, tap **Live**. The Slackwater Premium sheet opens. Close it.
2. In Xcode's StoreKit transaction manager, buy `org.openwaters.slackwater.premium.lifetime`.
3. Tap **Calendar** once more. In the Calendar app, the new events now carry an alert 30 minutes before.
4. Scrub the strip to a moment about 33 minutes ahead and let it rest. Tap **Live** and grant notifications. The rule's lead is 30 minutes, so its notification fires in about 3 minutes.
5. Background the app. A banner titled `Friday Harbor - Rising past …` or `Friday Harbor - Falling past …` arrives.
6. Tap the banner. Slackwater opens Friday Harbor scrubbed to the crossing.
7. Refund the purchase in the transaction manager and foreground the app. The Live rule reads "Notifications are Premium" or "Calendar only — notifications are Premium", and the calendar events lose their alert.

- [ ] **Step 4: Shut down every simulator you booted**

Run: `xcrun simctl shutdown <udid>` for each one. Never `shutdown all`.

- [ ] **Step 5: Device checklist for Bryan**

Copy this block into the PR description:

```markdown
### On a device before merge
- [ ] A notification fires with Slackwater force-quit
- [ ] Calendar events appear on a Mac signed into the same iCloud account, with their alarm for a Premium account
- [ ] Tapping a calendar event's URL opens Slackwater at the event
- [ ] Changing Settings → Slack window → Comfort current rewrites future slack-window events
- [ ] A rule on a CHS station that isn't downloaded reads "Waiting for station data" and schedules once it is
- [ ] On iPad in split view, Calendar and Live respond in the detail column
```

- [ ] **Step 6: Open the PR**

Check the branch holds only this work: `git log --oneline origin/main..HEAD` should list just the Task 1–8 commits. Then `rtk gh auth status` in its own call, `git push -u origin feat/alerts`, and draft the PR body with the `pr-writing` skill. `slackwater-ios` is public, so show Bryan the drafted title and body and open the PR only on his go. Never merge it yourself.
