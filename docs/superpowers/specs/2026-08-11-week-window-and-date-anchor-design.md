# The week window, and the date it hangs from

*Design spec, 2026-08-11. Changes `TimelineStrip.swift`, `ChsCurrentGate.swift`,
`ChsFitService.swift`, and the schedule/return-to-now paths in `TideDetailView`,
`CurrentDetailView`, `DerivedGateDetailView` and `OnlineGateDetailView`.*

## Why

The schedule list shows today, tomorrow, and six hours of the day after. Not
because of paging, lazy loading, or a data limit — because of one constant:

```swift
static let scheduleHours = 54.0       // tableEl TOP: list runs today 00:00 → +54h
```

`Timeline.scheduleHours` (`TimelineStrip.swift:26`) is a hard filter at
`today + 54h`, inherited verbatim from the HTML prototype's `tableEl` TOP. Its
two siblings — `backHours = 48`, `forwardHours = 132` — are the prototype's TMIN
and TMAX. Nothing about them was ever a decision about how far ahead a sailor
plans.

Two things follow. The list is bounded at 2.25 days when planning a passage
means looking at a week. And the strip already carries 5.5 days, more than
double the list, so the two surfaces on the same screen disagree about how much
future exists.

The horizon is not a data problem. Bundled NOAA stations and CHS-fitted stations
are harmonic constituents: a week in March 2027 costs the same as today and
needs no network. The one exception is the seven fit-reject **online gates**
(`2026-08-08-online-gates-design.md`), which render fetched 15-min samples whose
window is defined as −48h…+132h and enforced by `ChsOnlineWindow.coversStrip`.
They are the only real ceiling, and they are also exactly the stations — Seymour
Narrows among them — someone plans a passage around a month out.

This spec widens the window to a week and makes the date it hangs from a
parameter, so that a calendar picker becomes a UI addition rather than a
re-plumb of every detail view.

## Decisions

1. **The window is a week**, and the list and the strip agree on it.
2. **`TimelineData.build` takes an `anchor`** — the local midnight the window is
   built around — instead of computing `today` internally.
3. **The 48h look-back exists only on the current week.** It answers a question
   about *now*; it is noise on a Tuesday in September.
4. **The window has one definition**, `Timeline.window(anchor:today:)`, and the
   four sites that currently re-derive it call it.
5. **Online gates fetch 30 days**, merge rather than replace on save, and page
   with honest failure rather than a range-limited picker.
6. **The picker is date-granular, not week-granular.** Tap Sept 14, get
   Sept 14–21.

## 1. Two dates where there was one

`anchor` and `today` are both local midnights and conflating them is the defect
this section exists to prevent.

| | source | drives |
|---|---|---|
| **`anchor`** | `@State` on the detail view, initially today | geometry: `start`, `end`, `days`, the schedule filter |
| **`today`** | `appNow()` | language and liveness: `Today`/`Tomorrow`/`Yesterday`, the now-marker, return-to-now |

`TimelineData.build` gains an `anchor:` parameter on all three overloads;
`dayChrome` derives the window from it. Detail views hold
`@State private var anchor = todayLocal(tz)`.

**`TimelineDay.offset` becomes anchor-relative.** It is currently days-from-today
and does double duty: label input for `relativeDayLabel`, and lookup key in
`MultiDaySchedule:1186` (`days.first(where: { $0.offset == group.offset })`).
Once the anchor moves, those want different numbers. `offset` keeps the key job;
`relativeDayLabel` takes a `today:` argument and computes the relative word
itself. `MultiDaySchedule` already receives `today:` separately, so both are in
hand at the call site.

Three behaviors follow, each a decision rather than plumbing:

- **The back-pad is conditional.** `Timeline.window` yields `backHours` only when
  `anchor == today`. The current week behaves exactly as it does now; a future
  week starts clean at its own 00:00.
- **The now-marker draws only when `now` is inside the window.** It is
  unconditional today (`TimelineCanvas.draw:552`); on a September strip that
  dashed line would be pinned somewhere meaningless off the left edge.
- **Return-to-now resets the anchor.** `returnToNow()` in all four views becomes
  `anchor = todayLocal(tz); live = appNow(); scrubTime = live`. `ScrubWhen`'s
  visibility already keys on `scrubbedAway(scrubTime, from: live)`, which is true
  for any non-today anchor by construction — the affordance is already correct,
  it simply has more to undo.

## 2. The constants

```swift
enum Timeline {
    static let backHours = 48.0       // current week only; 0 for any other anchor
    static let scheduleDays = 7.0
    static let scheduleHours = scheduleDays * 24          // 168
    static let forwardHours = scheduleHours + centerPad   // 180
    /// Half a viewport, so the LAST listed event can still sit under the
    /// centerline instead of jamming against the scroll view's clamp.
    static let centerPad = 12.0
}
```

**The strip must stay wider than the list, and the pad is why.** Tapping a
schedule row scrubs the strip (`MultiDaySchedule.onTap` → `scrubTime`), and
`updateUIView` centers by setting `contentOffset = x(scrubTime) − width/2`, which
UIScrollView clamps. An event exactly at the strip's edge would land the
centerline short of it, so the readout would disagree with the row just tapped.
Today's 132-vs-54 mismatch hides this by accident; an explicit 12h pad — 216pt at
`pph = 18`, comfortably over half a phone's width — keeps the property on purpose.

Mechanical widenings, all in `TimelineStrip.swift`:

| Site | now | becomes | why |
|---|---|---|---|
| `dayChrome` `days` range | `(-2...6)` | `(-2...8)` | window ends at anchor+7.5d; the last night's moon reads day+1's sunrise (`drawDayChrome:628`) |
| `drawDayChrome` `visible` filter | `offset <= 5` | `offset <= 7` | |
| `sunTimes` filters | `offset <= 5` | `offset <= 7` | both `build:298` and `build:358` |

Nothing else in the rendering path changes. The 8192px texture cap that forced
`TimelineCanvas.tileWidth` is already handled: 228h × 18pt/hr is 4104pt, five
tiles instead of four, each independently under the cap. `tidePoints` goes
1080 → 1368 samples at the 10-min step.

**`pph` is not touched.** A 7-day strip at 18pt/hr is a long scroll — roughly 20
swipes end to end. That is the picker's job to solve, not a reason to compress
the chart and re-open the label-collision fight settled in the NEAPS pass
(`TimelineStrip.swift:17-22`).

## 3. One window definition

Four sites currently re-derive `today ± hours` independently: `dayChrome`,
`ChsOnlineWindow.coversStrip`, `seedOnlineWindow` (`SlackwaterApp.swift:64`), and
`ChsFitService.fetchOnlineWindow`. With a conditional back-pad they will drift,
and the failure mode is a coverage check passing on a window with a hole in it —
a strip with a dead zone, which is the exact defect the online-gates spec already
had to defend against once with its sample-clamping.

```swift
extension Timeline {
    static func window(anchor: Date, today: Date) -> (start: Date, end: Date)
}
```

All four call it. `coversStrip(now:)` becomes `covers(anchor:today:)` and is a
one-liner over it.

## 4. Online gates

**The fetch goes to 30 days.** `fetchOnlineWindow(for:from:)` takes a start
anchor and fetches `anchor − backHours … anchor + 30d`. `chunkPlan` already lands
on an absolute 7-day epoch grid, so blocks are cache-identity-stable and
overlapping refetches cost nothing new.

**Stored windows merge, they do not replace.** `ChsModelStore.saveOnline` unions
incoming samples into the stored `times`/`speeds` by timestamp and widens
`start`/`end`. Without this, prefetching the next block discards the current one
and paging back refetches what you just had. Samples before `today − 48h` are
pruned on merge: past current has no value once it is past, and pruning is what
keeps the file from growing in the direction nobody looks.

```swift
// ponytail: no forward cap. A 30-day block is ~2880 samples (~90KB JSON); someone
// who pages a year out accumulates ~1MB on a gate they evidently care about, and
// -chsResetModels already clears it. Add a cap when a real file gets big.
```

**The prefetch rides an existing seam.** Opening the picker on an online gate,
with `net.online`, fires `fetchOnlineWindow(for: gate, from: stored.end)`
detached — on the assumption the user is heading forward. It merges, saves, and
bumps `ChsFitService.onlineFetchStamp`, which `OnlineGateDetailView` and
`OnlineGateCard` already observe (`SlackwaterApp.swift:1520`). No new UI plumbing:
the prefetch lands and the view updates itself. If the user instead lands on a
week the merged window does not cover, the path that already exists at
`OnlineGateDetailView.swift:103` — refetch when online, amber honesty card on
throw — moves from `.onAppear` to also fire on `.onChange(of: anchor)`.

**No range-limiting.** Online gates get the same unbounded picker as every other
station. A greyed-out calendar would make two classes of station visibly disagree
about how far the future goes and leave the user to work out why; an honest
failure at the moment of asking says it in words.

## 5. The picker

A native `DatePicker(selection:displayedComponents: .date)` in `.graphical` style,
presented in a sheet. Native buys Dynamic Type, VoiceOver, and localization for
nothing, and adds no dependency.

Date-granular: tapping Sept 14 sets `anchor = Sept 14` and yields Sept 14–21.
Not week-granular — calendar weeks would mean picking a Saturday shows a two-day
stub, which serves planning worst at the moment it matters most. Unbounded in
both directions: last Saturday's tide is as free as next month's.

**Placement is deliberately not decided here.** Toolbar, the `when` row, or
tapping the day label are all plausible, and it is a layout question better
answered against mockups than a paragraph. It belongs to the second
implementation plan.

## Implementation order

Two plans against this spec:

- **Plan A** — the anchor model, the window constants, `Timeline.window`, and
  the 30-day online fetch, shipping with `anchor = today` and no picker UI. The
  visible win (a week in the list) with no new surface.
- **Plan B** — the picker, its placement, and the prefetch trigger, on top of an
  anchor that is already a parameter.

## Verification

`scripts/test.sh`, with these added to `TimelineTests` / `ChsCurrentGateTests`:

1. `Timeline.window` — back-pad present iff `anchor == today`, absent otherwise;
   end is `anchor + 180h` in both cases.
2. A future anchor's schedule yields exactly 7 day-groups, the first starting at
   `anchor` 00:00.
3. `TimelineDay.offset` is anchor-relative, and `relativeDayLabel` says "Today"
   only when the day is today — asserted on both a today-anchor and a
   future-anchor strip.
4. The now-marker is suppressed when `now` falls outside the window.
5. `covers(anchor:today:)` on a stored 30-day window — true for every anchor up
   to 22 days out (30d fetched less the 7.5d each anchor needs), false past that
   edge.
6. Merge-on-save — an overlapping fetch produces no duplicate timestamps, and
   the prune drops everything before `today − 48h`.
7. Existing assertions at `TimelineTests:56`, `TimelineTests:399-400` and
   `ChsCurrentGateTests:154-155` follow the new constants.

## Not in scope

- **`pph` and the strip's scroll length.** See §2.
- **Picker placement.** See §5.
- **Alerts on a paged date.** Tapping a row to set a threshold notification
  (`2026-07-12-tide-app-design.md` §5a) is orthogonal and unbuilt on iOS.
- **slackwater-web.** It has its own ‹ Today › day-pager (`EventList.tsx:130`)
  and its own anchor model. Bringing the two in line is worth doing and is not
  this.
