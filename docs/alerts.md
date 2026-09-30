# Alerts

*A calendar per station, subscribed in Settings, and notifications set by long-pressing the
moment you care about on the strip. The calendar is free; anything that interrupts is Premium.
Source comments cite this document by section number.*

## 1. Goal

Tell a boater when the water will do the thing they are planning around, without opening the
app. The headline is the **slack window at a current station or gate** — "tell me when I can
get through the pass" — because it is the answer Slackwater computes and tide apps do not:
`slackWindow()` over the user's own threshold speed. Tide highs and lows, a tide height picked
off the curve, and lunar eclipses ride the same rails.

Two ways in, each matched to how far ahead the question is:

- **A station's calendar** answers "what is this place doing for the next three months", laid over
  the rest of the user's life in an app they already read. Subscribed once, in Settings.
- **A notification** answers "tell me before this particular moment". Set by pressing that moment
  on the strip.

Everything is computed on the device from the predictions the strip already draws. No server,
no account, no background execution.

## 2. The line

**Reading is free. Being interrupted is Premium. One place is free; a cruising ground is Premium.**

- **Free:** a calendar for one station, its events syncing to every device the user's calendar
  account reaches.
- **Premium:** notifications, and a calendar for as many stations as the user wants — each its own
  calendar, so they turn them on and off per trip in whatever calendar app they already use.

Nothing Slackwater writes to a calendar ever carries an alarm, for anyone. A station calendar is a
reference layer holding around four events a day; alarms on all of them is the behaviour people
uninstall over, and iOS Default Alert Times already lets anyone add their own per calendar.

The long-press popup (§7.2) is widgets-premium §5 item 3 and the third and last upsell surface.
Settings → Calendar upsells only at the point a second station is turned on, so a free user who
wants one calendar never meets the tier sheet.

## 3. Notification alerts

```swift
struct AlertRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var stationID: String        // a concrete catalog id, never a location sentinel
    var trigger: AlertTrigger
    /// Set: only the occurrence at this instant, and the rule expires once it passes.
    var once: Date?
    /// Seconds before the event that the notification fires. Zero by default: the calendar's
    /// throwaway rules (§5.1) are rules with no lead, and the long-press popup passes its own
    /// half hour (§7.2).
    var lead: TimeInterval = 0
    var daylightOnly = false
    var enabled = true
}

enum AlertTrigger: Codable, Equatable {
    case slackWindowOpens                      // current stations and fitted current gates
    case slack                                 // derived gates: an instant, no speed series
    case currentPeak(flood: Bool)
    case tideExtreme(high: Bool)
    case tideCrossing(heightM: Double, rising: Bool)
    case eclipse
}
```

- A rule is a notification. There is no delivery field: the calendar is not driven by rules (§5.1).
- A rule names a place the user chose. Rules are created from a detail view, whose station id is
  always concrete, so a rule never follows Current Location.
- **`once` is the whole difference between the popup's two offers.** Set, the rule watches for the
  single occurrence at that instant and the reschedule drops it once the instant is past. Unset,
  the rule watches every occurrence of its trigger. Copy comes from `trigger` either way, so
  nothing stores a rendered string.
- `tideCrossing` stores metres, the engine's unit, and displays in the user's units. `rising` is
  the direction of the curve at the moment the user pressed.
- Lead defaults to 30 minutes. Lead, daylight-only and `once` are edited from the Alerts screen
  (§7.3).
- Rules are JSON in the App Group suite under `slackwater.alertRules`, device-local. They do not
  sync through iCloud the way favourites do: two devices holding one rule would buzz twice. A rule
  a build cannot decode is kept byte-for-byte and written back, so moving between builds never
  loses one.

## 4. Occurrences

One pure function turns a rule into dated events. It has no OS dependency and carries most of
the testing.

```swift
struct AlertOccurrence: Equatable, Sendable {
    let ruleID: UUID
    let event: Date          // the water event
    let fire: Date           // event − lead
    let end: Date?           // a window's close
    let noWindow: Bool       // a slack no run under the threshold covers
    let heightM: Double?
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
| `.tideCrossing` | `TidePredicting.heights(step: 600)`, linearly interpolated at each crossing of `heightM` in the rule's direction |
| `.eclipse` | `visibleEclipses(from:to:observer:)`, at `WindowEclipse.start` |

Every instant is floored to its minute, so two runs that find an event a second apart name the
same occurrence and the same `key`.

`daylightOnly` keeps an occurrence when its `event` falls between an Almanac `sunEvents` rise and
the following set at the station's position.

`once` filters the result to the occurrence on that minute: at most one, and none at all if a later
engine version moves the event further than a minute, in which case the rule quietly finds nothing
until §6 removes it.

A window's opening depends on `slackThresholdKn`, which describes the user's boat, so changing the
threshold changes every `.slackWindowOpens` occurrence (§6).

## 5. Delivery

| Mechanism | What feeds it | Horizon | Tier |
|---|---|---|---|
| EventKit, one calendar per station | station subscriptions | 90 days | one station free, more Premium |
| One-shot local notification | rules | 14 days, soonest 64 | Premium |
| AlarmKit `Alarm.Schedule.fixed(fire)` | rules | plan 2 | Premium |
| The alarm's Live Activity countdown | rules | plan 2 | Premium |

Every delivered item opens the station at the event: `shareURL(forStationID:at:tz:)` with the
event instant, falling back to `deepLink(forStationID:)` for a station with no published slug.

### 5.1 Station calendars

A subscription, not a rule. Turning a station on in Settings (§7.4) publishes that station's
planning events for the next 90 days into a calendar of its own.

```swift
struct StationCalendar: Codable, Equatable {
    var stationID: String
    var calendarID: String       // EKCalendar.calendarIdentifier
}
```

Stored under `slackwater.stationCalendars` in the App Group suite.

**What lands in it**, resolved through the same `alertOccurrences` with a fixed trigger list per
station kind, `lead: 0` and no daylight filter:

| Station kind | Events |
|---|---|
| Tide | every high and every low, plus lunar eclipse first contact |
| Current, or a fitted current gate | each slack window, one event spanning open to close at the user's comfort speed, plus first contact |
| Derived gate | each slack, plus first contact |
| Online gate | not offered (§8) |

Around 350 events per station over 90 days either way. Eclipses come twice a year and earn their
row. Each slack no run covers is written as a zero-length "Slack" event, the same as a notification
would say: the gate is shut, and a gap in the calendar would read as no data.

**Titles carry no place**, because the calendar is named for the place: "High tide 3.1 m",
"Slack window", "Low tide", "Lunar eclipse". A notification's title still leads with the station
(§5.2). The notes carry the time in the station's zone plus the span, threshold or height where it
matters, and the event's URL opens the app at that moment.

**Access** is full access (`requestFullAccessToEvents`), requested the first time a station is
turned on. Write-only access is authorized only "to save new items" (`EKTypes.h`): it cannot read
back or remove what it wrote, so a comfort-speed change would strand the old windows in someone's
calendar.

**Finding the calendar.** By stored identifier first. Failing that, by exact title across the same
sources it would create in, because the calendar syncs: without the title match a second device
turning the same station on creates a duplicate calendar with the same name and the user sees every
event twice. The cost of the title match is that two devices subscribed to one current station and
set to *different* comfort speeds rewrite each other's slack windows on every foreground. That is
a setting describing one boat, and the events are otherwise identical on both devices.

**Creating it.** Google and Exchange accounts refuse new calendars, so the source falls back from
the default for new events to iCloud to the device. If all three refuse, the toggle reports it and
stays off rather than silently doing nothing.

**Keeping it.** An event is identified by its content: a stored event is a planned one when their
titles agree and their start and end are each within 90 seconds. A reschedule fetches the
calendar's events from now forward, removes those the plan no longer contains, and adds the
missing ones, so an event already under way is left alone and two triggers that produce the same
event produce one entry.

**Turning it off** deletes that station's calendar, and with it the events. A free user turning on
a second station is offered the swap. Both paths go through one confirmation naming the station and
the number of events that will disappear; nothing synced vanishes off the user's Mac without them
having read that sentence.

**A lapsed Premium keeps its calendars** — they stay subscribed and keep publishing — but free
holds one, so with more than one on, turning another station on opens the tier sheet and changes
nothing. The swap is offered at exactly one; otherwise dropping one of five and adding a sixth
would hold five for free.

### 5.2 Notifications

- Interruption level `.active`. `.timeSensitive` needs the time-sensitive entitlement, which
  means regenerating the Manual-signed Release profiles.
- An interval trigger on the occurrence's absolute fire time, so it stays right when the phone
  changes time zone.
- Request identifier `alert.<key>`. Reschedule removes pending `alert.*` requests and adds the
  soonest 64 across all rules. iOS holds only the soonest 64 pending requests per app, so 64 is
  the platform's ceiling, not a tuning value.
- Title "Race Passage - Slack window": the place, then the event in as few words as it takes.
  Body "14:32–15:10, under 0.5 kn · in 30 min", in the station's time zone. With `noWindow`:
  "Race Passage - Slack", "14:32, no window under 0.5 kn".
- Never provisional: provisional delivery does not reach the Lock Screen.
- One notification per thing the user perceives: two rules agreeing on station, trigger, moment
  and fire time deliver once — a `once` rule and its repeating twin are separate rules (§3) and
  the long-press popup offers both rows for the same moment (§7.2). The same moment at two
  different leads stays two reminders. The `once` rule keeps the delivery, since it has no other
  occurrence to show on the Alerts screen (§7.3).

### 5.3 Alarms and the countdown

Plan 2, after the on-device spike (§11).

- AlarmKit alerts break through Silent mode and Focus. That is right for a 05:40 transit and
  wrong for anything else, so an alarm is offered only on current and slack triggers and is never
  a default. It is also where App Review scrutiny lands; keeping alarms to "wake me for a
  transit" is the mitigation.
- `AlarmManager.schedule(id:configuration:)` with `.alarm(schedule: .fixed(fire), attributes:)`,
  soonest-first, stopping at `AlarmManager.AlarmError.maximumLimitReached`.
- `AlarmAttributes` conforms to `ActivityAttributes`; the widget extension supplies the Live
  Activity UI, counting down with `Text(timerInterval:)` to the event and across the window.

## 6. Scheduling

```swift
struct DeliveryPlan: Equatable {
    var calendar: [AlertOccurrence]        // from station subscriptions
    var notifications: [AlertOccurrence]   // from rules
}

func deliveryPlan(rules: [AlertRule], subscriptions: [StationCalendar],
                  occurrences: [AlertOccurrence], now: Date, premium: Bool) -> DeliveryPlan

@MainActor final class AlertScheduler {
    nonisolated static func requestReschedule()
}
```

`deliveryPlan` is pure. A reschedule loads rules and subscriptions, resolves stations through
`WidgetStationLoader.loadRecord(id:)`, builds occurrences from now out to each horizon off the main
thread, plans, and hands the plan to thin writers.

**Plan rules**

- Calendar: every subscribed station's events still ahead and within 90 days, whatever the tier.
  A free user's list is capped at one subscription when it is written, not when it is planned.
- Notifications, when Premium: rules with `fire` ahead and within 14 days, soonest 64.
- Not Premium: no notifications, so the writer clears them. Rules and calendars stay; entitlement
  returning restores delivery on the next run.
- Rules whose `once` is in the past are removed.

**Runs on:** the scene becoming active; a rule added, edited, toggled or removed; a station
calendar turned on or off; the slack threshold changing; `PremiumStore.isPremium` changing; a CHS
model finishing its fit. One run at a time; a request during a run queues one follow-up.

**No background execution.** An app the user does not open is not launched for background
refresh either, so `BGAppRefreshTask` would miss exactly the user a top-up is for. The calendar
holds 90 days regardless. Notifications hold for 14 days past the last time the app was opened,
and the Alerts screen shows each rule's "Scheduled through" date, so the horizon is visible
rather than a silent stop.

**Rule states** (Alerts screen): Scheduled through *date* · Waiting for station data (a CHS
station not yet fitted) · Notifications off in Settings · Premium needed · Off.

## 7. Entry points

### 7.1 The long press

A `UILongPressGestureRecognizer` alongside the tap recognizer already on the scroll view, with
`tap.require(toFail: press)` so a press held and then lifted does not also scrub. There is no
`DragGesture` anywhere near the strip — the scrub is `UIScrollView`'s own pan, which never starts
from a stationary touch — so the press needs nothing taken away from it.

On recognition: stop the intro slide, cancel any fling or magnet ride, take a haptic, **park the
pressed moment on the centerline**, and say so. Parking it is what keeps the rest simple. The
centerline is where every detail view already reads its offer from, so the popup's subject is
computed by code that exists and nothing but "the strip was pressed" has to cross from UIKit into
SwiftUI — an `onLongPress()` closure alongside `openWeekPicker`, which exists because the strip is
three views deep in every detail and the layers between have nothing to say. The jump is
instant rather than the tap's animated magnet ride: a press names one moment, and a popup opening
over a sliding strip would have to wait for it to land before it could say what it was about.

What a press resolves to, from where it landed:

| Where | Resolves to |
|---|---|
| Within `Timeline.magnetPts` (46 pt) of a `snapTimes` stop | that event |
| Within ±1 s of a `WindowEclipse.contacts` moment | `.eclipse` |
| Anywhere else in the plot or time row | that instant, and what the curve reads there |
| The day row | nothing — that row belongs to the week picker's tap |

An arbitrary instant on a tide curve is a height, so it becomes `.tideCrossing` at the displayed
height with `rising` from the curve's direction — the same either/or `tideAlertOffer` and
`currentAlertOffer` already compute, now fed a press time instead of the centerline. Because a
press only lands on a strip that is already still, none of the row's rest-state gating survives:
`Timeline.rest` stays for the strip's own chrome and nothing else consults it.

### 7.2 The popup

A `.popover` with `.presentationCompactAdaptation(.popover)`, so it is an arrow-anchored card on
iPhone as well as iPad, attached to the strip at `.point(.center)` — the centerline the press just
parked its moment on. Dismissal, positioning and the arrow come with the popover, and the strip's
riding-dot overlay keeps `allowsHitTesting(false)` untouched.

- A header: the station, then the moment and what it is — "Sat 14:32 · Max ebb".
- **Alert me** — a rule with `once` set to that instant.
- **Every max ebb** — the same rule without `once`. Named for the resolved trigger, so it reads
  "Every low tide", "Every slack window", "Every time it falls past 3.3 ft".
- A row whose rule already exists reads as on; tapping it removes the rule.
- A 30-minute lead, and no lead picker: that is the rule sheet's job (§7.3).
- For a free user both rows open the tier sheet and no rule is created.

Notification permission is requested the first time a rule is created, never at launch.

### 7.3 Rule sheet

Opened from the Alerts screen to edit one rule:

- One line naming it ("Race Passage - Slack window"), and for a `once` rule the date it fires
- Lead: at the time, 15 min, 30 min, 1 h, 3 h, 1 day
- Daylight only
- Every time — off for a `once` rule; on clears `once` and the rule starts repeating
- On, and Delete

### 7.4 Settings → Calendar

A section directly after Alerts, `NavigationLink` to a list of the user's saved stations with a
toggle each — the same row idiom the Alerts and Offline downloads rows use. The section's own line
says what is on: "Friday Harbor", "3 stations", or a hint when none is.

- Online gates are listed but unavailable, with the reason (§8).
- A free user with one station on sees the others offer the swap (§5.1); the tier sheet is reachable
  from that confirmation for anyone who would rather keep both.
- Denied calendar access leaves the toggles off and says so, with a link to Settings.

### 7.5 Alerts screen

A Settings row, "Alerts", lists rules by station with their state (§6). Tap opens the rule sheet;
swipe deletes. A free user who has never subscribed has none to list; rules left by a lapsed
subscription stay, read "Premium needed", and deliver again the moment the entitlement returns.

## 8. Station coverage

| Station kind | `WidgetStationLoader` | Triggers | Calendar |
|---|---|---|---|
| NOAA or TICON tide, harmonic or subordinate | `.tide` | `.tideExtreme`, `.tideCrossing`, `.eclipse` | yes |
| CHS tide station | `.tide` once fitted | same; waiting until fitted | once fitted |
| NOAA current, harmonic or subordinate | `.current` | `.slackWindowOpens`, `.currentPeak`, `.eclipse` | yes |
| CHS current gate, fittable | `.current` once fitted | same | once fitted |
| CHS derived gate | `.derived` once its reference port is fitted | `.slack`, `.eclipse` | once fitted |
| CHS current gate, online | nil | none | no |

Online gates predict only from a network fetch ([chs-data-model](chs-data-model.md))
and the loader returns nil for them, so nothing could be scheduled offline. A long press there does
nothing and their Settings row is unavailable, rather than offering an alert that never fires.

## 9. Technical shape

**Files**

- `Slackwater/AlertRule.swift` — `AlertRule`, `AlertTrigger`, the store, event names
- `Slackwater/AlertStationCalendar.swift` — `StationCalendar`, its store, the per-kind trigger list
- `Slackwater/AlertOccurrences.swift` — `alertOccurrences`, the crossing search, the daylight filter
- `Slackwater/AlertPlan.swift` — `deliveryPlan`, copy, calendar event identity
- `Slackwater/AlertScheduler.swift`, `Slackwater/AlertCalendar.swift`, `Slackwater/AlertNotifications.swift` — the run and its writers
- `Slackwater/AlertOffer.swift` — what a press resolves to, and what each popup row does
- `Slackwater/AlertPopup.swift` — the popover card
- `Slackwater/AlertSheet.swift`, `Slackwater/AlertsView.swift`, `Slackwater/CalendarStationsView.swift` — editing
- `Slackwater/TimelineStrip.swift` — the press recognizer and the popover anchor
- `Slackwater/Theme.swift` (`ScrubDetailScaffold`) — the `onLongPress` closure
- `SlackwaterWidgets/AlertLiveActivity.swift` — plan 2

Occurrences run in the app, which already links Almanac; the widget extension gains Live Activity
UI in plan 2 and no dependency now.

**`project.yml`**, app target `info.properties`: `NSCalendarsFullAccessUsageDescription`, plus
`NSAlarmKitUsageDescription` and `NSSupportsLiveActivities` with the alarms. None is an
entitlement, so the Manual-signed Release provisioning profiles stay as they are.

No engine or Almanac version change.

## 10. Testing

**Unit** (`SlackwaterTests`, failing test first):

- Occurrences — one case per trigger on the fixtures `SlackWindowTests` and `TideShortcutTests`
  already use. Merged runs yield one occurrence; a hairline slack yields a `noWindow` occurrence;
  the first opening agrees with `SlackWindowShortcutQuery.next`; crossings interpolate and respect
  direction; daylight filtering holds across a DST transition day; an eclipse lands on
  `WindowEclipse.start`; a wider threshold opens a window earlier.
- `once` — one occurrence at that minute and no more; none once the instant is past; the reschedule
  drops the rule then; clearing `once` makes the same rule repeat.
- The plan — lead applied; passed events and fires dropped; the 90-day, 14-day and 64 limits; a
  free plan keeps every subscribed calendar and no notifications.
- Station calendars — the trigger list per station kind; a tide station's day holds its highs and
  lows and nothing else; the free cap of one subscription; the swap's event count.
- Copy — place-first notification titles against place-less calendar titles; bodies per trigger;
  lead only on notifications.
- Calendar identity — an event a second out still matches; a retitled one does not; an event under
  way is never removed.
- The popup — what each press resolves to per consumer, and what each row does to the rules.

**A drift test** reschedules from two different 10-minute windows and requires the same instants to
within a minute, for every trigger read off a sampled series — the ones whose results could move
with the run's start time. An eclipse is searched from an absolute window rather than the sample
grid, and a derived gate's slack is skipped on a machine whose reference port isn't fitted.

**UI:** a long press on a tide strip and on a current strip opens the popup with the right header;
a free user's Alert me opens the tier sheet; Settings → Calendar turns a station on.

**On device**, because none of it is trustworthy in the simulator: a notification fires with the
app killed; two stations' calendars land separately and open the app at the event; a comfort-speed
change rewrites the windows; turning a station off takes its events with it; losing Premium clears
pending notifications and leaves the calendars alone.

## 11. Spikes before the alarm plan

1. **AlarmKit, on device.** How many `.fixed` alarms schedule before `maximumLimitReached`.
   Whether `CountdownDuration.preAlert` shows a countdown ahead of a `.fixed` alarm or only for
   timers. Whether the presentation needs `NSSupportsLiveActivities`. If a countdown cannot
   precede a fixed alarm, the countdown is a scheduled ActivityKit Live Activity
   (`Activity.request(…start:)`, iOS 26) for the soonest alarm.
2. **Cost.** Ninety days of occurrences for every subscribed station plus every rule, measured on a
   phone. The bar: reschedule never delays the first frame.

## 12. Release scoping

**Plan 1:** rules, occurrences, the plan, station calendars, the notification writer, the long
press and its popup, the Alerts screen, Settings → Calendar.

**Plan 2, after spike 1:** AlarmKit alarms and the countdown on current and slack triggers.

**Next, same tier:**

- `.tidePercentile` — "lowest low of the season" — on `Ranking.swift` (slackwater-engine v0.8.0)
  and the station LAT/HAT bounds, once the #217 range UI brings both into the app. Suppressed
  where the constituent set has no Sa/Ssa amplitude.
- Eclipse stages: a week, a day and an hour before, and at the start.
- `.timeSensitive` notifications, with the entitlement and regenerated profiles.
- A station calendar's own comfort speed, so a calendar stops depending on a device-wide setting.

## 13. Launch blockers

Inherited from widgets-premium §8: the seller entity and revenue split, and the Premium SKUs not
yet on sale. The free single calendar depends on neither and can ship first.

## 14. Out of scope

Server push and webcal feeds — Canadian predictions stay on the device
([chs-data-model §3](chs-data-model.md)). `BGAppRefreshTask` (§6). Wind and weather
conditions. Apple Watch. Rule sync across devices. A widget showing the next alert.
