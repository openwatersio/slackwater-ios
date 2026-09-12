# Alerts — design

*2026-09-12. Alert rules set from the detail strip and delivered through the calendar, local
notifications and AlarmKit. Refines the free/paid line in
[widgets-premium §2 and §5](2026-08-21-widgets-premium-design.md).*

## 1. Goal

Tell a boater when the water will do the thing they are planning around, without opening the
app. The headline is the **slack window at a current station or gate** — "tell me when I can
get through the pass" — because it is the answer Slackwater computes and tide apps do not:
`slackWindow()` over the user's own threshold speed. Tide highs and lows, a tide height picked
off the curve, and lunar eclipses ride the same rails.

Everything is computed on the device from the predictions the strip already draws. No server,
no account, no background execution.

## 2. The line

**The calendar is free. Anything that interrupts you is Premium.**

- **Free:** any alert rule can write its occurrences into a Slackwater calendar. Those events
  carry no alarms.
- **Premium:** the same rules as local notifications, as AlarmKit alarms, and the alarm's Live
  Activity countdown.

This is the widgets-premium sentence applied to alerts: seeing future slack windows in your own
calendar is "what is the water doing"; "tell me without opening the app from my pocket" is
Premium. It ships in the existing tier with no new SKU.

The 🔔 is widgets-premium §5 item 3 and stays the third and last upsell surface. It lives in the
detail header beside Share and Favorite (§7.1). For a non-subscriber it opens the rule sheet,
where the calendar works, and the interrupting options open the tier sheet.

## 3. Rules

```swift
struct AlertRule: Codable, Identifiable, Equatable {
    let id: UUID
    var stationID: String        // a concrete catalog id, never a location sentinel
    var trigger: AlertTrigger
    var lead: TimeInterval       // fire = event − lead
    var daylightOnly: Bool
    var calendar: Bool           // free
    var alert: AlertLevel        // Premium
    var enabled: Bool
}

enum AlertTrigger: Codable, Equatable {
    case slackWindowOpens                      // current stations and fitted current gates
    case slack                                 // derived gates: an instant, no speed series
    case currentPeak(flood: Bool)
    case tideExtreme(high: Bool)
    case tideCrossing(heightM: Double, rising: Bool)
    case eclipse
}

enum AlertLevel: String, Codable { case none, notification, alarm }
```

- A rule names a place the user chose. `WidgetStationLoader.resolvedStationID` runs when the rule
  is created, so a rule never follows Current Location.
- `tideCrossing` stores metres, the engine's unit, and displays in the user's units. `rising` is
  the direction of the curve at the moment the user picked.
- `.alarm` is offered only for `.slackWindowOpens`, `.slack` and `.currentPeak` (§5.3).
- Rules are JSON in the App Group suite under `slackwater.alertRules`, device-local. They do not
  sync through iCloud the way favourites do: two devices holding one rule would ring the same
  alarm twice.

## 4. Occurrences

One pure function turns a rule into dated events. It has no OS dependency and carries most of
the testing.

```swift
struct AlertOccurrence: Equatable {
    let ruleID: UUID
    let event: Date          // the water event
    let fire: Date           // event − lead
    let end: Date?           // a window's close
    let noWindow: Bool       // a slack no run under the threshold covers
    var key: String { "\(ruleID.uuidString).\(Int(event.timeIntervalSince1970))" }
}

func alertOccurrences(_ rule: AlertRule, station: WidgetStation,
                      position: (lat: Double, lon: Double),
                      from: Date, to: Date, threshold: Double) -> [AlertOccurrence]
```

Every trigger reads a producer that exists today:

| Trigger | Source |
|---|---|
| `.slackWindowOpens` | `CurrentPredicting.events()` slacks → `speeds(step: 600)` over the span ±6 h → `slackWindow()` → `mergeWindows()`. One occurrence per run, at its opening — the moment `currentAxisMoments()` prints as "the time a planner is aiming at". A slack no run covers is an occurrence at the slack with `noWindow`. |
| `.slack` | `DerivedSlackStation.slacks(from:to:)` |
| `.currentPeak` | `events()` filtered to `.maxFlood` or `.maxEbb` |
| `.tideExtreme` | `TidePredicting.extremes()` filtered by kind |
| `.tideCrossing` | New: `TidePredicting.heights(step: 600)`, linearly interpolated at each crossing of `heightM` in the rule's direction |
| `.eclipse` | `visibleEclipses(from:to:observer:)`, at `WindowEclipse.start` |

`daylightOnly` keeps an occurrence when its `event` falls between an Almanac `sunEvents` rise and
the following set at the station's position, in the station's time zone. Days go through
`Calendar`, never 86,400 seconds.

A window's opening depends on `slackThresholdKn`, which describes the user's boat, so changing the
threshold changes every `.slackWindowOpens` occurrence (§6).

## 5. Delivery

Four mechanisms, each holding the horizon it can hold without the app running.

| Rung | Mechanism | Horizon | Tier |
|---|---|---|---|
| Plan | EventKit, a "Slackwater" calendar | 90 days | Free |
| Heads-up | one-shot `UNCalendarNotificationTrigger` | 14 days, soonest 64 | Premium |
| Must not miss | AlarmKit `Alarm.Schedule.fixed(fire)` | 14 days, until `maximumLimitReached` | Premium |
| Countdown | the alarm's Live Activity presentation | the alarm | Premium |

Every delivered item opens the station at the event: `shareURL(forStationID:at:tz:)` with the
event instant, falling back to `deepLink(forStationID:)` for a station with no published slug.

### 5.1 Calendar

- **Full access** (`requestFullAccessToEvents`). Write-only access is authorized only "to save
  new items" (`EKTypes.h`): it cannot read back or remove what it wrote, so a threshold change or
  a deleted rule would strand stale windows in someone's calendar.
- The app creates one calendar titled "Slackwater" and never reads or writes any other.
- An event is identified by its content: URL plus title. Reschedule fetches the Slackwater
  calendar's events from now forward, removes those the plan no longer contains, and adds the
  missing ones. Two rules that produce the same event produce one calendar entry.
- Title names the event and station ("Slack window · Race Passage", "Low 0.4 m · Friday
  Harbor"). A window spans its start and end; an instant is zero-length. Time zone is the
  station's. No `EKAlarm`.
- A slack-window rule at a busy pass writes roughly 350 events over 90 days. The calendar toggle
  is per rule, off switches are one tap, and `daylightOnly` applies to the calendar path too.

### 5.2 Notifications

- Interruption level `.active`. `.timeSensitive` needs the time-sensitive entitlement, which
  means regenerating the Manual-signed Release profiles.
- Request identifier `alert.<key>`. Reschedule removes pending `alert.*` requests and adds the
  soonest 64 across all rules. iOS holds only the soonest 64 pending requests per app, so 64 is
  the platform's ceiling, not a tuning value.
- Title "Slack window opens at Race Passage"; body "14:32–15:10 under 0.5 kn · in 30 min", in the
  station's time zone. With `noWindow`: "Slack at 14:32 — no window under 0.5 kn".
- Never provisional: provisional delivery does not reach the Lock Screen.

### 5.3 Alarms and the countdown

- AlarmKit alerts break through Silent mode and Focus. That is right for a 05:40 transit and
  wrong for anything else, so `.alarm` is offered only on current and slack triggers and is never
  a default. It is also where App Review scrutiny lands; keeping alarms to "wake me for a
  transit" is the mitigation.
- `AlarmManager.schedule(id:configuration:)` with `.alarm(schedule: .fixed(fire), attributes:)`.
  Reschedule cancels the app's alarms and schedules the plan soonest-first, stopping at
  `AlarmManager.AlarmError.maximumLimitReached`.
- `AlarmAttributes` conforms to `ActivityAttributes`. The widget extension supplies its Live
  Activity UI, which counts down with `Text(timerInterval:)` to the event and then across the
  window. That is the Live Activity for this release.
- Buttons: Stop, and an Open intent that lands on the station at the event.

## 6. Scheduling

```swift
struct DeliveryPlan: Equatable {
    var calendar: [AlertOccurrence]
    var notifications: [AlertOccurrence]
    var alarms: [AlertOccurrence]
}

func deliveryPlan(_ occurrences: [AlertOccurrence], rules: [AlertRule],
                  now: Date, premium: Bool) -> DeliveryPlan

@MainActor enum AlertScheduler {
    static func reschedule() async
}
```

`deliveryPlan` is pure. `reschedule` loads rules, resolves stations through
`WidgetStationLoader.load(id:)`, builds occurrences from now to 90 days out off the main thread,
plans, and hands the plan to three thin writers.

**Plan rules**

- An occurrence whose `fire` has passed is dropped.
- Calendar: calendar-enabled rules, events within 90 days.
- Notifications, when Premium: `.notification` rules, `fire` within 14 days, soonest 64.
- Alarms, when Premium: `.alarm` rules, `fire` within 14 days, soonest first.
- Not Premium: no notifications or alarms, so the writers clear them. Rules and the calendar
  stay; entitlement returning restores delivery on the next run.

**Runs on:** the scene becoming active; a rule added, edited, toggled or removed; the slack
threshold changing; `PremiumStore.isPremium` changing; a CHS model finishing its fit. One run at
a time; a request during a run queues one follow-up.

**No background execution.** An app the user does not open is not launched for background
refresh either, so `BGAppRefreshTask` would miss exactly the user a top-up is for. The calendar
holds 90 days regardless. Notifications and alarms hold for 14 days past the last time the app
was opened, and the Alerts screen shows each rule's "Scheduled through" date, so the horizon is
visible rather than a silent stop.

**Rule states** (Alerts screen): Scheduled through *date* · Waiting for station data (a CHS
station not yet fitted) · Calendar, Notifications or Alarms off in Settings · Calendar only
(an interrupting level without Premium).

## 7. Entry point

### 7.1 The bell

A 44 pt glass circle between Share and Favorite in `DetailHeader`, a `Button` like its
neighbours (the tap-gesture rule for iPad split applies to schedule rows, not header chrome).
`accessibilityIdentifier("detail-alert")`. `DetailHeader` takes `alertOffer: AlertTrigger?`;
nil hides the bell. The header is shared, so the bell reaches all four scrubber consumers, and
each consumer computes its own offer.

The offer comes from what sits under the centerline:

| Consumer | Under the centerline | Offer |
|---|---|---|
| `TideDetailView` | an extreme (`atTurn`) | `.tideExtreme` of that kind |
| | an eclipse contact | `.eclipse` |
| | any other moment, scrubbed away | `.tideCrossing` at the height there, `rising` from the eyebrow |
| | now | `.tideExtreme(high: false)` |
| `CurrentDetailView` | a max (`atMax`) | `.currentPeak` of that kind |
| | an eclipse contact | `.eclipse` |
| | anything else | `.slackWindowOpens` |
| `DerivedGateDetailView` | an eclipse contact | `.eclipse` |
| | anything else | `.slack` |
| `OnlineGateDetailView` | — | nil (§8) |

Tapping the timeline lands on a snap target within 46 pt and on an arbitrary instant otherwise.
On a tide curve an arbitrary instant is a height, so the tapped spot becomes a crossing rule
without a mode of its own. An eclipse contact is `WindowEclipse.contacts` within ±1 s of
`scrubTime`, the same tolerance `atTurn` uses; the magnet parks `scrubTime` on the target's own
second.

### 7.2 Rule sheet

Prefilled from the offer:

- One line naming the rule ("Slack window opens · Race Passage")
- Lead: at the time, 15 min, 30 min, 1 h, 3 h, 1 day
- Daylight only
- Add to calendar (on)
- Alert: None · Notification · Alarm — Alarm on current and slack triggers only

For a non-subscriber the Alert row opens the tier sheet and Add to calendar works. Each
permission is requested the first time its mechanism is chosen, never at launch.

### 7.3 Alerts screen

A Settings row, "Alerts", lists rules by station with their delivery and state (§6). Tap edits in
the rule sheet; swipe deletes.

## 8. Station coverage

| Station kind | `WidgetStationLoader` | Triggers |
|---|---|---|
| NOAA or TICON tide, harmonic or subordinate | `.tide` | `.tideExtreme`, `.tideCrossing`, `.eclipse` |
| CHS tide station | `.tide` once fitted | same; waiting until fitted |
| NOAA current, harmonic or subordinate | `.current` | `.slackWindowOpens`, `.currentPeak`, `.eclipse` |
| CHS current gate, fittable | `.current` once fitted | same |
| CHS derived gate | `.derived` once its reference port is fitted | `.slack`, `.eclipse` |
| CHS current gate, online | nil | none |

Online gates predict only from a network fetch ([online-gates §1](2026-08-08-online-gates-design.md))
and the loader returns nil for them, so nothing could be scheduled offline. The bell is hidden
there rather than offering a rule that never fires.

## 9. Technical shape

**Files**

- `Slackwater/AlertRule.swift` — `AlertRule`, `AlertTrigger`, `AlertLevel`, the store
- `Slackwater/AlertOccurrences.swift` — `alertOccurrences`, the crossing search, the daylight filter
- `Slackwater/AlertScheduler.swift` — `deliveryPlan`, `reschedule`, the three writers
- `Slackwater/AlertSheet.swift`, `Slackwater/AlertsView.swift`
- `SlackwaterWidgets/AlertLiveActivity.swift` — `ActivityConfiguration(for: AlarmAttributes<AlertAlarmMetadata>.self)`
- `Slackwater/DetailHeader.swift` and the four detail views — the bell and each offer

Occurrences run in the app, which already links Almanac; the widget extension gains Live Activity
UI and no dependency.

**`project.yml`**, app target `info.properties`: `NSAlarmKitUsageDescription`,
`NSCalendarsFullAccessUsageDescription`, `NSSupportsLiveActivities`. None is an entitlement, so
the Manual-signed Release provisioning profiles stay as they are.

No engine or Almanac version change.

## 10. Testing

**Unit** (`SlackwaterTests`, failing test first):

- `AlertOccurrencesTests` — one case per trigger on the fixtures `SlackWindowTests` and
  `TideShortcutTests` already use. Merged runs yield one occurrence; a hairline slack yields a
  `noWindow` occurrence; for an unmerged window the opening equals `SlackWindowShortcutQuery.next`'s
  start; crossings interpolate and respect direction; daylight filtering holds across a DST
  transition day; an eclipse lands on `WindowEclipse.start`.
- `DeliveryPlanTests` — lead applied; passed fires dropped; the 90-day, 14-day and 64 limits; a
  non-Premium plan keeps the calendar and nothing else; alarms only on current and slack
  triggers; a threshold change moves window occurrences.
- `AlertRuleTests` — Codable round-trip; a location sentinel resolves at creation.
- Offer selection per consumer, as pure functions of `scrubTime`, now and the loaded events.

**UI:** the bell is present with the right label on tide, current and derived details, and absent
on an online gate.

**On device**, because none of it is trustworthy in the simulator: a notification fires with the
app killed; an alarm rings through a Focus; calendar events land only in the Slackwater calendar
and open the app at the event; a threshold change rewrites them; losing Premium under the StoreKit
test configuration clears pending notifications and alarms.

## 11. Spikes before the plan

1. **AlarmKit, on device.** How many `.fixed` alarms schedule before `maximumLimitReached`.
   Whether `CountdownDuration.preAlert` shows a countdown ahead of a `.fixed` alarm or only for
   timers. Whether the presentation needs `NSSupportsLiveActivities`. If a countdown cannot
   precede a fixed alarm, the countdown rung is a scheduled ActivityKit Live Activity
   (`Activity.request(…start:)`, iOS 26) for the soonest alarm.
2. **EventKit.** Full access creates the Slackwater calendar and removes its events; write-only
   does neither.
3. **Cost.** Occurrences for every rule across 90 days, measured on a phone. The bar: reschedule
   never delays the first frame.

## 12. Release scoping

**This release:** §3–§9.

**Next, same tier:**

- `.tidePercentile` — "lowest low of the season" — on `Ranking.swift` (slackwater-engine v0.8.0)
  and the station LAT/HAT bounds, once the #217 range UI brings both into the app. Suppressed
  where the constituent set has no Sa/Ssa amplitude.
- Eclipse stages: a week, a day and an hour before, and at the start.
- A scheduled ActivityKit Live Activity for notification-level rules.
- `.timeSensitive` notifications, with the entitlement and regenerated profiles.

## 13. Launch blockers

Inherited from widgets-premium §8: the seller entity and revenue split, and the Premium SKUs not
yet on sale. The free calendar path depends on neither and can ship first.

## 14. Out of scope

Server push and webcal feeds — Canadian predictions stay on the device
([chs-data-model §3](../../chs-data-model.md)). `BGAppRefreshTask` (§6). Wind and weather
conditions. Apple Watch. Rule sync across devices. A widget showing the next alert.
