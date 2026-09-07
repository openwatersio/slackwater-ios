# A lunar eclipse the app can show, list, scrub to, and explain

Design for [#222](https://github.com/openwatersio/slackwater-ios/issues/222). Written 2026-09-07 against `d851548`.

## What this builds

Four surfaces, one fact:

1. The sky dome's moon takes an umbral shadow while the scrub time is inside the eclipse.
2. The schedule list carries a row for the eclipse's start.
3. Every contact instant (P1, U1, greatest, U4, P4) is a scrubber snap target, so the magnet steps through the event.
4. The Moon tile opens a detail sheet — phase, rise/set, distance, and both the last and next eclipse, each of which the sheet can jump to.

## What is already solved

`openwatersio/almanac` ships the astronomy and the app already links it (`import Almanac` in `Theme.swift`, since #284):

- `nextLunarEclipse(after:) throws -> LunarEclipse` — `kind` (penumbral/partial/total), `peak`, `magUmbral`, `magPenumbral`, and the contacts `p1`, `u1?`, `u2?`, `u3?`, `u4?`, `p4`. Validated against the full 1950–2100 Espenak catalog (344/344 within 60 s).
- `lunarEclipseVisibility(_:observer:) throws -> LunarEclipseVisibility` — `visibleAtPeak`, `moonGeometricAltAtPeakDeg`, and a per-contact `contactsVisible` whose optionals mirror the eclipse's.

The 2026-08-28 partial (umbral magnitude 0.93), including Victoria visibility at peak, is one of Almanac's pinned regression cases.

Nothing is ported into the app. #228 closed on 2026-09-06, so `SunMoon.swift` is gone and there is no dead call site to add to.

## What Almanac does not have

There is no `previousLunarEclipse` and no range search. The sheet's "last eclipse" line is therefore iteration over the existing API in the app:

```swift
lunarEclipses(from: now.addingTimeInterval(-400 * 86_400), to: now).last
```

400 days covers the catalog's longest gap between consecutive lunar eclipses (under a year). This is iteration, not astronomy — no Meeus lands in this repo. An `openwatersio/almanac` issue tracks whether the package should own a backward or range search with its TypeScript twin and parity corpus; if it does, this helper collapses into a one-line call and the change is confined to `Eclipse.swift`.

## Where the data lives

New `Slackwater/Eclipse.swift`:

```swift
struct WindowEclipse {
    let eclipse: LunarEclipse
    let visibility: LunarEclipseVisibility

    /// The instant the shadow first bites — U1, or P1 when there is no umbral
    /// phase at all. What the list row and the strip mark point at.
    var start: Date { eclipse.u1 ?? eclipse.p1 }
    /// P1, U1, peak, U4, P4 — the snap targets, in order, nils dropped.
    var contacts: [Date]
    /// Any contact with the moon above this observer's horizon.
    var anyContactVisible: Bool
    /// Fraction of the moon's diameter inside the umbra at `t`, 0 outside the
    /// event. Drives the glyph's shadow.
    func shadow(at t: Date) -> Double
}

func lunarEclipses(from: Date, to: Date, observer: Observer) -> [WindowEclipse]
```

`lunarEclipses` walks `nextLunarEclipse(after:)` forward from `from`, stopping once a peak passes `to`, attaching visibility to each, and keeping only those with `anyContactVisible`. Almanac throws outside 1950–2101; the function swallows that and returns what it has, the same way `SummaryTiles` drops its tile rather than the row.

`TimelineData` gains `let eclipses: [WindowEclipse]` (defaulted empty), filled in `TimelineData.build(tide:current:...)` and the online-gate builder — the two places that already hold the station's lat/lon and the window. Each eclipse's `contacts` join `snapTimes` under the existing `filter { $0 >= start && $0 <= end }`.

**Cost.** The search is per timeline *build* — a rebuild or an anchor move — never per scrub frame. `SkyState.init` runs on every frame and must not learn about eclipses; it is handed the answer. Before the search runs at all, a gate: if `searchMoonPhases(from:to:)` puts no full moon inside the window, there can be no eclipse and the builder skips it, which is most weeks. The plan measures the un-gated and gated build cost and records both; if a gated build costs more than ~10 ms the search moves to a `Task` that merges its result in.

### Visibility

An eclipse earns a row and a mark when *any* contact has the moon above the horizon here — which keeps the moonrise-mid-eclipse case, the most striking one to watch. A fully-below-horizon eclipse gets no row, no strip mark, and no snap target; the sky dome already handles itself, since it draws the moon only while `moon.altDeg >= 0`. The Moon sheet still names such an eclipse and says it is not visible from here.

## The three in-window surfaces

### Schedule row

`SchedulePill` gains `.eclipse`. `ScheduleEntry` needs no new fields: `time` is the start contact, `value` is the peak time.

The rows are merged **in `ScrubDetailScaffold`**, not in the four detail views: the scaffold already receives `entries: (TimelineData) -> [ScheduleEntry]` and the timeline, so it appends the eclipse rows for eclipses inside `scheduleRange` and re-sorts by time. `TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView`, and `OnlineGateDetailView` are unchanged here — CLAUDE.md's four-consumer rule satisfied by construction rather than by four edits.

The pill reads `PENUMBRAL` / `PARTIAL` / `TOTAL ECLIPSE` in a copper capsule. `MultiDaySchedule` caps the pill column at 100 pt for `WSW FLOOD`; the widest of these must fit or the cap moves.

### Strip mark

`TimelineCanvas` draws sun rise/set dots at `geo.sunY` with `↑5:24AM` labels at `geo.dayY`. The eclipse gets the same treatment at its `start`: a copper dot and a `🌘10:11pm` label, one mark per eclipse. Every contact stays magnetic regardless, so scrubbing steps P1 → U1 → greatest → U4 → P4 while only one label sits on the axis.

### Sky moon and the glyph

`SkyState` gains `eclipse: WindowEclipse?` — the eclipse containing its `time`, chosen by the caller from `timeline.eclipses`. That is the one edit in each of the four detail views.

`MoonGlyph` gains `umbra: Double = 0`. The disc is already a lit circle plus an offset dark limb (`moonLimbShift`); the shadow is a **third** element — a copper-tinted dark disc entering from the limb-opposite side, clipped to the moon — so it never competes with the phase reading. At `umbra == 0` the glyph is byte-for-byte what it draws today. The dome's radial glow warms and dims in proportion to the same number.

`shadow(at:)` interpolates linearly between contacts: 0 at P1/P4, `magPenumbral` shading through the penumbral legs, `magUmbral` at greatest, with U1/U4 as the umbral endpoints. Almanac reports contact instants and peak magnitudes, not a coverage curve; the curve between them is presentation. Marked with a `ponytail:` comment naming the approximation, and the tested claims are only the endpoints and the peak.

### Moon tile text

While the scrub time is between P1 and P4, the Moon tile's value line reads `Partial Eclipse` (the kind, title-cased) in place of `Full Moon`. The `N% lit` caption is unchanged — an eclipsed moon is still a full moon, and the number is still true.

## The tile sheet

`ReadoutTile` gains `var detail: (() -> AnyView)? = nil`. When it is non-nil the tile gets a chevron affordance and a tap gesture — a gesture, not a `Button`, because `Button` press tracking goes dead in the iPad split layout's detail column, the same reason `MultiDaySchedule`'s rows use one — and presents the sheet. Only the Moon tile passes a detail for now; `Range` and `Next max` stay inert until they have something to say.

`MoonDetailSheet(at:observer:tz:onJump:)`:

- Glyph (eclipsed if the scrub time is inside one), phase name, `N% lit`.
- Moonrise and moonset for the scrub day, from `moonEvents(from:to:observer:)`.
- Next full moon and next new moon, from `searchMoonPhases(from:to:)`.
- Distance in km from `moonPosition(_:).distanceKm`, with the month's closest and farthest approach found by sampling distance at 6-hour steps across ±15 days. Almanac has no apogee/perigee search; sampling is ~120 cheap calls and it happens once, off the scrub path.
- **Last eclipse** and **Next eclipse**: kind, date, and whether it is visible from here. Each row jumps.

Everything above is computed in a `.task`, not in `body`.

### Jumping

`ScrubDetailScaffold` already owns this logic, in the `onChange` that applies a shared link's `linkedInstant` (#187): set `scrubTime`, and when the instant falls outside `Timeline.window(anchor:)`, move the anchor to its local day and fire `onPicked`. That block becomes a `jump(to:)` method, called by both the link path and the sheet.

The scaffold hands `jump(to:)` to `links(tl)` as an explicit closure parameter. **Not an Environment value**: sheet content sits in its own host and does not inherit the presenter's environment, which is why `openChsRoute` is re-forwarded onto every `.sheet` in this app. A closure captured at construction has no such problem.

The sheet dismisses on jump. An online gate with nothing downloaded for the target week lands on the usual honesty card, exactly as the week picker does.

## Tests

Unit (`SlackwaterTests/EclipseTests.swift`):

- The 2026-08-28 partial at Victoria — `lunarEclipses` over a window containing it returns exactly one; `start` equals `u1`; `contacts` is the five instants in chronological order.
- `shadow(at:)` is 0 before P1 and after P4, and equals `magUmbral` at the peak.
- A full moon that is not an eclipse yields nothing.
- An eclipse entirely below the horizon for the observer is filtered out; the same eclipse with a contact above the horizon is kept.
- `TimelineData.build` puts every contact of a windowed eclipse into `snapTimes`, and puts nothing there for a window with no full moon.

Schedule: the merged eclipse row lands in the correct day group and in time order among the tide rows.

Render: a probe of `MoonGlyph` at `umbra: 0` (unchanged from today) and at peak coverage, in the style of `SkyBackdropTests`/`RenderedStripTests`.

UI: one test — tap the Moon tile, the sheet appears, tapping the next-eclipse row moves the scrub time and dismisses.

## Out of scope

Unchanged from the issue: solar eclipses, notifications, animation, and per-contact P1/U2/U3 detail beyond the snap targets. Also out: sheets for the `Range` and `Next max` tiles, and any Almanac API change — the `previousLunarEclipse` question is filed there, not answered here.
