# Alerts

*A calendar per station, subscribed in Settings, and notifications set from the line under the
strip: press the moment you care about, or say what you want in a sentence. Both are Premium:
reading the app is free, being told is not. Source comments cite this document by section number.*

## 1. Goal

Tell a boater when the water will do the thing they are planning around, without opening the
app. The headline is the **slack window at a current station or gate** — "tell me when I can
get through the pass" — because it is the answer Slackwater computes and tide apps do not:
`slackWindow()` over the user's own threshold speed. Tide highs and lows, a tide height picked
off the curve, and lunar eclipses ride the same rails.

Two ways in, each matched to how far ahead the question is:

- **A station's calendar** answers "what is this place doing for the next three months", laid over
  the rest of the user's life in an app they already read. Subscribed once, in Settings.
- **A notification** answers "tell me before this particular moment". Set from the alert line
  under the strip (§7.1): press the moment, or type or dictate the question — "next lower low in
  daylight" — and the app turns it into a rule (§7.3).

Everything is computed on the device from the predictions the strip already draws. No server,
no account, no background execution.

## 2. The line

**Reading is free. Being told is Premium.**

- **Free:** every prediction the app shows, as it always has been.
- **Premium:** notifications, and a calendar for as many stations as the user wants — each its own
  calendar syncing to every device the user's calendar account reaches, so they turn them on and
  off per trip in whatever calendar app they already use.

Nothing Slackwater writes to a calendar ever carries an alarm, for anyone. A station calendar is a
reference layer holding around four events a day; alarms on all of them is the behaviour people
uninstall over, and iOS Default Alert Times already lets anyone add their own per calendar.

The alert sheet's Save (§7.2), premium requirement buttons, and Settings support button open the dedicated Support Slackwater sheet.
Reading an answer in the sheet is free; a free user can ask "when is the next lower low" and see
it, and is upsold only on saving the alert.
Settings → Calendar upsells at the point a station is turned on; the list itself, and turning a
station off, never open the Premium purchase controls.

## 3. Notification alerts

```swift
struct AlertRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var stationID: String        // a concrete catalog id, never a location sentinel
    var trigger: AlertTrigger
    /// Set: only the occurrence at this instant, and the rule expires once it passes.
    var once: Date?
    /// Seconds before the event that the notification fires. Zero by default: the calendar's
    /// throwaway rules (§5.1) are rules with no lead, and the alert sheet starts a new rule at
    /// its own half hour (§7.2).
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
- **`once` is the whole difference between the sheet's repeat choices (§7.2).** Set, the rule
  watches for the single occurrence nearest that instant — within six hours, under the gap
  between two of any trigger — because the pressed minute is not always the event's own: a press
  on a current strip parks on the slack instant while the occurrence is the window's opening, and
  a press on the curve names a minute the rounded height crosses a little before or after. The
  reschedule drops the rule once the instant is past. Unset, the rule watches every occurrence of
  its trigger. Copy comes from `trigger` either way, so nothing stores a rendered string.
- A sentence makes the same two kinds of rule. "The next low tide" is a `once` rule on the first
  occurrence the sentence describes; "every low tide" is the rule without `once`. The sentence is
  never stored: once it has become a rule, the rule is the whole record (§7.3).
- `tideCrossing` stores metres, the engine's unit, and displays in the user's units. `rising` is
  the direction of the curve at the moment the user pressed.
- Lead defaults to 30 minutes. Lead, daylight-only and `once` are edited in the alert sheet,
  from the line that made the rule or from the Alerts screen (§7.2).
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
| EventKit, one calendar per station | station subscriptions | 90 days | Premium |
| One-shot local notification | rules | 14 days, soonest 64 | Premium |
| Scheduled Live Activity, its start alert replacing the notification | rules | soonest few, plan 2 | Premium |

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
event twice. The comfort speed syncs through iCloud with the units, so devices on one account
write the same slack windows. Two devices that do not share it, and are set to *different* comfort
speeds, rewrite each other's slack windows on every foreground. That is a setting describing one
boat, and the events are otherwise identical on both devices.

**Creating it.** Google and Exchange accounts refuse new calendars, so the source falls back from
the default for new events to iCloud to the device. If all three refuse, the toggle reports it and
stays off rather than silently doing nothing.

**Keeping it.** An event is identified by its content: a stored event is a planned one when their
titles agree and their start and end are each within 90 seconds. A reschedule fetches the
calendar's events from now forward, removes those the plan no longer contains, and adds the
missing ones, so an event already under way is left alone and two triggers that produce the same
event produce one entry.

**Turning it off** deletes that station's calendar, and with it the events, through one
confirmation naming the station and the number of events that will disappear; nothing synced
vanishes off the user's Mac without them having read that sentence.

**A lapsed Premium keeps its calendars** — they stay subscribed, keep publishing, and can still be turned off — but turning a station on opens the dedicated Support Slackwater sheet and changes nothing. Without Premium the toggles read off and do the same.

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
  nothing stops a user holding both for the same moment. The same moment at two different leads
  stays two reminders. The `once` rule keeps the delivery, since it has no other occurrence to
  show on the Alerts screen (§7.5).

### 5.3 Live Activities

Plan 2, after the on-device spike (§11). The last half hour before an occurrence, and a slack
window while it is open, live in the Dynamic Island and on the Lock Screen so the boater is not
reopening the app at the dock.

**One scheduled thing, not two.** iOS 26's
`Activity.request(attributes:content:pushType:style:alertConfiguration:start:)` schedules a Live
Activity for a date and the system starts it then, app in the background. A scheduled start
must carry an `alertConfiguration`, and that alert is the notification: it fires at `fire` with
the §5.2 title and body. The occurrence that gets an activity is dropped from the notification
writer, so nothing buzzes twice. Not an alarm: AlarmKit's countdown is templated, breaks through
Silent and Focus, and is where App Review looks, so it stays the opt-in transit alarm under
Next (§12).

**Budget.** Scheduled activities count toward the system's handful of simultaneous Live
Activities, shared with every other app. The plan takes the soonest N of its notification
occurrences, in the writer's order, where N is whatever the system accepts: the writer requests
in order and stops at the first `ActivityAuthorizationError`, and every occurrence it could not
place stays an ordinary notification. N is never hard-coded. A `once` rule, a repeating rule,
any trigger: whichever is soonest. No new UI decides this.

**Static content, system timers.** The app has no background execution (§6), so the content
state is fixed when the activity is scheduled and nothing updates it. Everything that moves is a
timer the system draws: `Text(timerInterval:)` down to `event`, then across `event…end`.
`ActivityContent.staleDate` is `event`; the widget reads `context.isStale` to turn one scheduled
start into two faces:

| | Counting down | Stale, after `event` |
|---|---|---|
| Island compact | tide or current glyph · `14:32` · timer to the event | glyph · timer to `end` ("open 38m"), or the height for a tide |
| Island expanded, Lock Screen | "Race Passage · Slack window" · timer · "14:32–15:10, under 0.5 kn" | "Open" · timer to close · the same line |
| Minimal | glyph | glyph |

A tide extreme, a peak and a derived slack have no `end`: the stale face names the moment and
the height, and the activity is ended on the next run. `noWindow` never shows "Open". The tap
opens the station at the event through the same URL every delivery carries.

The attributes are the occurrence's facts, nothing rendered: station name, trigger, `event`,
`end`, `noWindow`, `heightM`, the threshold, the units, the URL.

**Ending.** Nothing ends an activity on time while the app is closed. Past its window it sits on
the Lock Screen with a stopped timer until the user swipes it, the app next foregrounds and the
run ends it, or iOS ends it at eight hours. For a window under two hours that is acceptable and
documented here rather than worked around. A run ends every activity of ours that is
scheduled but not started, or whose window has closed, before requesting the plan's; a rule
removed takes its activity with it.

The watch Smart Stack would come with `.supplementalActivityFamilies([.small])` and is not in
plan 2.

## 6. Scheduling

```swift
struct DeliveryPlan: Equatable {
    var calendar: [AlertOccurrence]        // from station subscriptions
    var notifications: [AlertOccurrence]   // from rules
    var liveActivities: [AlertOccurrence]  // plan 2: the soonest of `notifications`, moved here (§5.3)
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
  The tier gates turning a station on (§7.4), not what an existing subscription publishes.
- Notifications, when Premium: rules with `fire` ahead and within 14 days, soonest 64.
- Live Activities, plan 2: the soonest of those, as many as the system takes (§5.3). The two
  lists never share an occurrence; one the activity writer cannot place goes back to the
  notification writer in the same run.
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

Every rule is made in one place: the alert sheet (§7.2), opened from the alert line under the
strip (§7.1) or from the Alerts screen (§7.5). The line is what makes alerts findable — it is on
screen on every detail, on the first visit — and the sheet is where every way of describing an
alert ends up: a pressed moment, the centerline's own offer, or a sentence (§7.3).

### 7.1 The alert line

One line of caption text, centred, directly under the strip and above the summary tiles: drawn
by the scaffold between the strip card and its `links` slot, where `ChsDownloadNotice` leads on a
CHS station while its download runs. On a CHS tide station `alertOffer` is nil exactly while it
is still a preview (§8), so the notice has the space while there is nothing to alert on and the
line takes it the moment the station can alert. A CHS current gate on a provisional model can
alert (§8), so there the notice and the line both show. An online gate has neither.

The line lives in `ScrubDetailScaffold`, not in the detail views, so the four phone details draw
it from one place.

| State | Reads | Tap |
|---|---|---|
| Rest | "Set an alert" — `bell`, `SN.foam` at 62 % | Opens the sheet on the centerline's offer, bound to its next occurrence, with the sentence field focused |
| Pressed | "Set alert for low tide · Sat 14:32" — the resolved trigger's `alertEventName` and the parked moment in the station's zone | Opens the sheet on that moment |
| Set | "Alert set · low tide · Sat 14:32" — `bell.fill` in `SN.leaf` | Opens the sheet on the existing rule, whose Delete removes it |

Pressed is the strip's own state: a long press parks a moment and the line names it until the
strip moves off that moment, by scrub, fling, return-to-now or a shared link, when it drops back to
rest. While it holds, the strip's reading line runs on down through the time and day rows and
into the line itself, so the parked moment and its name read as one thing. Set wins over the
other two whenever a rule already exists for the centerline's offer: a `once` rule on that
minute, then at rest the soonest `once` rule still ahead (a Rest tap binds to the offer's next
occurrence, not the centerline's minute), then a repeating rule for its trigger —
`alertLineRule`, in that order — so a rule can be found again from the place that made it. Without Premium the line reads the same and the sheet's Save
does the upselling (§7.2); a rule left by a lapsed subscription still reads
Set.

A quiet line, not a button: no fill, no stroke, caption weight, a 44 pt tap target. It is the only
chrome under the strip that invites an action, and it is there to be found on the second visit
rather than seen on the first.

#### The long press

A `UILongPressGestureRecognizer` alongside the tap recognizer already on the scroll view, with
`tap.require(toFail: press)` so a press held and then lifted does not also scrub. There is no
`DragGesture` anywhere near the strip — the scrub is `UIScrollView`'s own pan, which never starts
from a stationary touch — so the press needs nothing taken away from it.

On recognition: stop the intro slide, cancel any fling or magnet ride, take a haptic, **park the
pressed moment on the centerline**, and say so. Parking it is what keeps the rest simple. The
centerline is where every detail view already reads its offer from, so the line's subject is
computed by code that exists and nothing but "the strip was pressed" has to cross from UIKit into
SwiftUI — an `onLongPress()` closure alongside `openWeekPicker`, which exists because the strip is
three views deep in every detail and the layers between have nothing to say. The jump is
instant rather than the tap's animated magnet ride: a press names one moment, and a line changing
under a sliding strip would have to wait for it to land before it could say what it was about.

A press opens nothing. It turns the line to Pressed, and the line's tap opens the sheet. A press
landed by accident costs a glance, not a dismissal.

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

### 7.2 The alert sheet

One `AlertSheet` makes and edits rules. It is a `.sheet` at the medium detent, which lands on
iPhone and in the iPad split layout alike. It holds a draft `AlertRule`, and every control edits
that draft:

- **The sentence field**, at the top, when the parser is available (§7.3). Placeholder "Tell me
  when…", with the keyboard's own dictation button for voice. Focused when the sheet opens from
  the line's Rest state; present but empty when it opens on a pressed moment or an existing rule,
  because the draft already says what the alert is. A sentence that parses replaces the draft
  below it, and the field keeps the words until the sheet closes so the user can see what the
  app made of them.
- **The summary**, `alertRuleSummary`: "Hope Bay - Low tide". No date: the moment a `once` rule
  watches is the line's to name (§7.1) and the Alerts screen's (§7.5), and the bound minute is
  not always the event's own (§3). For a sentence the parser could not fit, the summary line
  carries its reply instead — "Slackwater can't alert on wind yet" — and Save is disabled.
- **Repeat**, written the way a calendar event writes it: a menu reading "Does not repeat" or the
  trigger's `alertEveryLabel` — "Every low tide", "Every slack window", "Every time it falls past
  3.3 ft". Choosing the latter clears `once`; choosing "Does not repeat" binds the rule to the
  moment the sheet opened on, or for a sentence to the first occurrence it described. A rule
  opened from the Alerts screen that already repeats offers only "Every …": there is no moment
  left to bind back to, and the Alerts screen has no strip to pick one from.
- **Remind me**: at the time, 15 min, 30 min, 1 h, 3 h, 1 day. A new rule starts at 30 min.
- **Daylight only.**
- **On**, and **Delete**, for an existing rule.
- **Save.** Without Premium it opens the dedicated Support Slackwater sheet and nothing is written.
  Notification permission is requested on the first save, never at launch; a denial still saves
  the rule, and the Alerts screen says why it is quiet.

Reading is free here. A free user types "next lower low in daylight", sees "Hope Bay - Low tide"
with "Does not repeat", and is asked to support the app only when they ask to be told.

**A moment already past cannot be saved.** The strip shows 48 hours back and a press can land
there; a `once` rule bound there would be dropped by the reschedule its save triggers (§6). The
sheet says "This moment has passed" under When and disables Save. The Rest tap never meets this:
it binds to the offer's next occurrence after now, or opens a repeating draft when the
notification horizon holds none.

### 7.3 The sentence

The field is parsed on the device by the Foundation Models framework. The model is a parser, not
a predictor: it turns words into the same `AlertRule` a press makes, and the engine finds the
occurrence. It never does arithmetic, never sees a date, and never answers a question itself.

```swift
@Generable struct AlertDraft {
    var trigger: Trigger              // the station kind's own cases only, see below
    var repeats: Bool                 // "every" / "whenever" against "the next" / "tomorrow's"
    var daylightOnly: Bool
    var leadMinutes: Int?             // "an hour before"; nil keeps the sheet's 30
    var day: RelativeDay?             // .today, .tomorrow, .daysAhead(Int); nil means the first
    var unsupported: String?          // set, and nothing else trusted, when the ask does not fit
}
```

- **One `Trigger` enum per station kind**, so the model cannot propose what the station cannot
  do. A tide station's cases are low tide, high tide, rises past a height, falls past a height,
  and lunar eclipse; a current station's are slack window, max flood, max ebb and eclipse; a
  derived gate's are slack and eclipse. A height is a number in the user's units; Swift converts
  it with `displayedHeightM`, the same rounding a press gets.
- **`RelativeDay`, never a `Date`.** The model is weak at dates and knows nothing of the
  station's zone. Swift resolves the day through `Calendar` with the station's `timeZone`,
  then searches `alertOccurrences` from that day's start across the notification horizon (§6)
  for the first occurrence, and that minute becomes `once`. A sentence with nothing in the
  horizon reads "Nothing in the next 14 days" and Save is disabled.
- **Instructions are a fixed paragraph per station kind**: what the place is, what each trigger
  means in a boater's words, the user's units, and that unsupported asks go in `unsupported`.
  One `LanguageModelSession` per parse, no transcript carried between parses, so the on-device
  4K-token budget is never a concern.
- **Availability.** `SystemLanguageModel.default.availability` is checked when the sheet opens.
  Anything but `.available` — a phone without Apple Intelligence, a device language it does not
  support, the model still downloading — hides the field, and the sheet works as it does for a
  press: the Rest tap opens it on the centerline's offer, which on an unscrubbed tide strip is the
  next low. The line's copy never mentions the field. The App Store cannot require Apple
  Intelligence, so this is the shipped experience for every phone before the iPhone 15 Pro, not a
  degraded one.
- **Nothing leaves the phone, and nothing is kept.** The words are discarded with the sheet. There
  is no log of what people asked (§14); learning what the triggers lack is a Next item (§12).
- **Every parse is shown before it is saved.** The draft is the summary, the repeat menu and the
  toggles, and the user reads it the way they would read a rule they pressed for. A model that
  misreads "slack before the flood" as "slack window" is corrected by the user in the same sheet,
  not trusted.

Two deliberate omissions. The `Speech` framework is not used: the keyboard's dictation key is
voice input with no microphone or speech-recognition usage string and no privacy review. And the
station is never parsed from the sentence: the sheet belongs to a detail view, so the place is the
one on screen. "At Race Passage" from Hope Bay's sheet lands in `unsupported`.

### 7.4 Settings → Calendar

A section directly after Alerts, `NavigationLink` to a list of the user's saved stations with a
toggle each — the same row idiom the Alerts row uses. The section's own line
says what is on: "Friday Harbor", "3 stations", or a hint when none is.

- Online gates are listed but unavailable, with the reason (§8).
- Without Premium, turning a station on opens the dedicated Support Slackwater sheet and nothing changes; turning one off works at any tier (§5.1).
- Denied calendar access leaves the toggles off and says so, with a link to Settings.

### 7.5 Alerts screen

A Settings row, "Alerts", lists rules by station with their state (§6). Tap opens the alert
sheet (§7.2) on that rule; swipe deletes. A free user who has never subscribed has none to list; rules left by a lapsed
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
nothing, the alert line is absent, and their Settings row is unavailable, rather than offering an
alert that never fires.

## 9. Technical shape

**Files**

- `Slackwater/AlertRule.swift` — `AlertRule`, `AlertTrigger`, the store, event names
- `Slackwater/AlertStationCalendar.swift` — `StationCalendar`, its store, the per-kind trigger list
- `Slackwater/AlertOccurrences.swift` — `alertOccurrences`, the crossing search, the daylight filter
- `Slackwater/AlertPlan.swift` — `deliveryPlan`, copy, calendar event identity
- `Slackwater/AlertScheduler.swift`, `Slackwater/AlertCalendar.swift`, `Slackwater/AlertNotifications.swift` — the run and its writers
- `Slackwater/AlertLiveActivities.swift` — plan 2, the activity writer
- `Slackwater/AlertOffer.swift` — what a press resolves to, and the draft a new rule starts from
- `Slackwater/AlertLine.swift` — the line under the strip, which rule it reads, its three states,
  and the next occurrence a Rest tap binds to
- `Slackwater/AlertSheet.swift` — the one sheet that makes and edits a rule
- `Slackwater/AlertSentence.swift` — `AlertDraft`, the per-kind instructions, the session, and the
  pure mapping from a draft to a rule
- `Slackwater/AlertsView.swift`, `Slackwater/CalendarStationsView.swift` — the lists
- `Slackwater/TimelineStrip.swift` — the press recognizer
- `Slackwater/Theme.swift` (`ScrubDetailScaffold`) — the `onLongPress` closure, the line's place
  between the strip card and `links`, and the sheet's presentation
- `SlackwaterWidgets/AlertLiveActivity.swift` — plan 2, the attributes and the three presentations;
  the attributes are shared with the app through the `PortableSources` template

Occurrences run in the app, which already links Almanac; the widget extension gains Live Activity
UI in plan 2 and no dependency now.

**`project.yml`**, app target `info.properties`: `NSCalendarsFullAccessUsageDescription`, plus
`NSSupportsLiveActivities` in plan 2. Neither is an entitlement, so the Manual-signed Release
provisioning profiles stay as they are.

`FoundationModels` is imported by the app target only. The deployment target already carries it,
so there is no `#available` gate, no new entitlement, no usage string and no new package;
availability is a runtime question (§7.3), not a build one.

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
  free plan keeps every subscribed calendar and no notifications. Plan 2: the activity list is
  the soonest of the notification list and the two never overlap; an occurrence the writer
  cannot place returns to the notifications; a removed rule's activity goes; `staleDate` is the
  event; copy per trigger for each face.
- Station calendars — the trigger list per station kind; a tide station's day holds its highs and
  lows and nothing else; the tier gate on turning a station on; the turn-off's event count.
- Copy — place-first notification titles against place-less calendar titles; bodies per trigger;
  lead only on notifications.
- Calendar identity — an event a second out still matches; a retitled one does not; an event under
  way is never removed.
- The line — what each press resolves to per consumer; Rest, Pressed and Set against a rule set
  that holds a `once` rule, a repeating rule, both, or neither; Set surviving a lapsed Premium.
- The sentence — the mapping from `AlertDraft` to `AlertRule` is pure and tested without a model:
  each trigger case per station kind, a height in feet landing as the displayed metres, `repeats`
  deciding `once`, a `RelativeDay` resolved across a DST transition in the station's zone, the
  first occurrence found and bound, an empty horizon reported, `unsupported` disabling Save. The
  model itself is not under test here.

**Phrasings, on a device** with Apple Intelligence, because the model runs nowhere in CI: a list
of twenty sentences per station kind in `SlackwaterTests/Fixtures/alert-phrasings.md` with the
rule each should make, walked by hand before a release that touches the instructions. The bar is
every sentence landing on the right trigger and repeat choice; lead and daylight may need a tap.

**A drift test** reschedules from two different 10-minute windows and requires the same instants to
within a minute, for every trigger read off a sampled series — the ones whose results could move
with the run's start time. An eclipse is searched from an absolute window rather than the sample
grid, and a derived gate's slack is skipped on a machine whose reference port isn't fitted.

Alerts and Calendar identify their Premium requirement at the top. For free users, this message opens the Support Slackwater sheet; supporters see their active tier. Saved alerts with “Notifications are Premium” provide the same link separately from the edit button. Benefits follow each list, while the empty state explains how to add an alert or calendar.

**UI:** the line reads "Set an alert" on a tide detail and a current detail and is absent on an online gate; a long press turns it to "Set alert for …" with the right event, and its tap opens the sheet on that moment; the Rest tap opens the sheet on the next low; saving turns the line to Set; a free user's Save and calendar toggle each open the dedicated Support Slackwater sheet; with Premium, Settings → Calendar turns a station on and asks before turning it off. The sentence field is not driven in UI tests: GitHub-hosted runners have no Apple Intelligence, and the field hides itself there.

**On device**, because none of it is trustworthy in the simulator: a notification fires with the
app killed; two stations' calendars land separately and open the app at the event; a comfort-speed
change rewrites the windows; turning a station off takes its events with it; losing Premium clears
pending notifications and leaves the calendars alone. Plan 2: an activity scheduled, the app
force-quit, starts at `fire` with its alert and no second notification; each face renders in the
Island and on the Lock Screen; the window face flips at the event.

## 11. Spikes before the Live Activity plan

1. **Scheduled start, on device.** Whether a Live Activity scheduled with `start:` starts after
   the app is force-quit, not merely backgrounded; Apple documents only the background case.
   How many scheduled requests succeed before `ActivityAuthorizationError`, with another app's
   activity running. Whether `isStale` flips the face at `staleDate` with the app closed.
2. **Cost.** Ninety days of occurrences for every subscribed station plus every rule, measured on a
   phone. The bar: reschedule never delays the first frame.

## 12. Release scoping

**Plan 1:** rules, occurrences, the plan, station calendars, the notification writer, the long
press, the Alerts screen, Settings → Calendar.

**Plan 2, after spike 1:** scheduled Live Activities for the soonest occurrences (§5.3).

**Plan 3:** the alert line, the one sheet, and the sentence (§7). Lands in two steps: first the
line and the sheet with the field hidden, which retires the popover and gives every phone the
findable entry; then the sentence, which is a field and a parser on top of a sheet that already
works.

**Next, same tier:**

- An AlarmKit alarm, opt-in per rule, on current and slack triggers only: it breaks through
  Silent and Focus, which is right for a 05:40 transit and wrong for anything else, and is where
  App Review looks. `AlarmManager.schedule(id:configuration:)` with
  `.alarm(schedule: .fixed(fire), attributes:)`, stopping at `maximumLimitReached`; needs
  `NSAlarmKitUsageDescription`.
- `.tideExtreme(high:, rank:)` — the lower of a day's two lows, the higher of its highs — so
  "the next lower low in daylight" is a trigger and not a near miss. The first ask the sentence
  cannot express; ranked within the station-local calendar day the extreme falls in.
- A way to learn what people ask for that the triggers cannot express. The app has no server
  (§14), so this is an opt-in share from the sheet's "can't alert on …" line into the feedback
  channel, never a log.
- `.tidePercentile` — "lowest low of the season" — on `Ranking.swift` (slackwater-engine v0.8.0)
  and the station LAT/HAT bounds, once the #217 range UI brings both into the app. Suppressed
  where the constituent set has no Sa/Ssa amplitude.
- "Hey Siri, tell Slackwater to …": an App Intent with a free-text parameter that runs the same
  parser against the nearest station, beside `NextLowTideIntent` in `TideShortcuts.swift`.
- Eclipse stages: a week, a day and an hour before, and at the start.
- `.timeSensitive` notifications, with the entitlement and regenerated profiles.
- A station calendar's own comfort speed, so a calendar stops depending on a device-wide setting.

## 13. Launch blockers

Inherited from widgets-premium §8: the seller entity and revenue split, and the Premium SKUs not
yet on sale. Every delivery in this document is Premium, so none of it ships before the SKUs do.

## 14. Out of scope

Server push and webcal feeds — Canadian predictions stay on the device
([chs-data-model §3](chs-data-model.md)). `BGAppRefreshTask` (§6). Wind and weather
conditions. Apple Watch. Rule sync across devices. A widget showing the next alert. A cloud model
behind the sentence for phones without Apple Intelligence: iOS 27's language-model protocol makes
it a small change, but it is a server and a key, and §1 promises neither. Logging what people
type. Parsing a station name out of a sentence.
