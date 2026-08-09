# The scrubber gutter: exact times below the strip, slack as a band

2026-08-08. Approved in brainstorm. Refines the strip anatomy settled by the
split-scrubbers spec (2026-08-07) — that spec kept extreme time labels *on*
the event ("the absolute time lives on the event itself"); this one moves them
to a gutter under the track and reverses that particular call.

## Decision (settled, do not relitigate)

Three changes, one theme — **absolute time has exactly one home per surface**:

1. **Exact event times leave the track.** They move to a label gutter below the
   curve, reached by a dotted dropline from the event's own dot. Sun times are
   the sole exception; they stay in the day header at the top.
2. **The readouts go fully relative.** With every exact time in the gutter (and
   the scrubbed instant in `ScrubWhen`), the readout above the strip carries
   countdowns and durations only.
3. **Readout above the strip, everywhere.** Tide already does this. Current and
   derived gate move to match.

And one addition: a **slack band** — the sub-0.5 kn window drawn as a filled
green column from the zero line down to the gutter, where its opening and
closing times are labelled.

## §1 Geometry — one gutter, one rule

> Superseded by Amendment A (two-row gutter staggering; heights are 274
> tide-only / 368 current-only, not the 262/356 below) — see
> `docs/superpowers/plans/2026-08-08-scrubber-gutter-and-slack-bands.md`.

`TimelineGeo` grows a label gutter below the track:

```swift
var gutterY: CGFloat { bodyBottom + 24 }   // label baseline
// height = gutterY + 12
```

| case | `bodyBottom` | `gutterY` | `height` (was) |
|------|-----|-----|-----|
| tide-only | 226 | 250 | **262** (258) |
| current-only | 320 | 344 | **356** (340) |

The 24pt clearance is set by the max-ebb speed label, not by the gutter text:
that label draws at `curY(e.speed) + 14` and `curY` clamps to `zeroY + curHalf`
= 317, so it reaches ~331. The gutter has to clear it.

Value labels (`10.2 ft`, `0.6 kn`) do not move. They stay on their dots. Only
*times* move.

`TimelineTests.swift:69,80` pin 258 and 340 — update the numbers and the
comments, do not delete the assertions. Add `gutterY < height` for both cases.

The fixed-point-geometry rule from the `TimelineGeo` doc comment still holds:
gutter labels are `.system(size: 10)`, not Dynamic Type. Do not "finish the
job" here either.

## §2 Droplines and gutter times

> Superseded by Amendment B: max flood/max ebb were dropped from the gutter
> entirely — the gutter now carries slack windows only, and peaks keep their
> speed label on the dot plus their exact time in the schedule table. See
> `docs/superpowers/plans/2026-08-08-scrubber-gutter-and-slack-bands.md`.

One helper on `TimelineCanvas`, called from both `drawTide` and `drawCurrent`:

```swift
private func drawDrop(_ ctx: GraphicsContext, x: CGFloat, from y: CGFloat, time: Date)
```

- Dashed line from the event dot at `y` down to `gutterY - 8`: white at 0.35,
  `StrokeStyle(lineWidth: 1, dash: [2, 3])` — the now-line's dash, in white
  rather than `SN.leaf`, so it reads as the same family without competing with
  the one mark that means *now*.
- `cardTime(time, tz)` with spaces stripped (`8:15PM`), `.system(size: 10)`
  monospaced, white at 0.65, drawn at `(x, gutterY)`, anchor `.center`. That is
  the exact style the inline time labels use today — the type is unchanged, only
  its position.

Applies to: tide highs and lows, max flood, max ebb, and any slack that has no
window (§3). Slacks that do have a window are drawn by the band instead — the
band already reaches the gutter, so a dropline would double the line.

**Deletes** `TimelineStrip.swift:399–402`, the `y ± 26` inline extreme time.
The `y ± 11` height label above it stays.

## §3 Slack bands

`slackWindow()` stops being a per-view call and becomes build-time data on
`TimelineData`:

```swift
let slackWindows: [(slack: Date, start: Date, end: Date)]
```

Computed in `TimelineData.build` inside the `if let current` branch only — one
call to the existing `slackWindow(_:around:threshold:)` per slack event, over
the same `currentPoints` the strip draws. The derived-gate builder leaves it
empty: `build(gate:)` synthesises a schematic ±1 curve, and a sub-0.5 kn window
computed off a shape would be fiction. A gate's slacks fall to §2's dropline.

Each band draws as a rect from `x(start)` to `x(end)`, `zeroY` down to
`gutterY - 8`, filled `SN.go.opacity(0.12)` — the app's go colour, the same one
the `slack` word and the SLACK pill already carry.

**Draw order: last**, after the curve stroke. The band overlaps the `SN.ebb`
fill below the zero line, so at 0.12 it reads as a highlight column tinting
what is under it rather than as an opaque patch fighting it. The 2pt near-white
curve still reads through. The opacity is the one number here likely to want a
tuning pass against a real screenshot.

`CurrentDetailView.slackWin` becomes a lookup into this array rather than a
recompute. That is the point of moving it: the band on the strip and the
duration in the readout are now the same numbers by construction, not by two
call sites agreeing.

## §4 Window edge labels

Two labels in the gutter, one per crossing, growing **inward** from the band's
edges — start anchored `.leading` at `x(start)`, end anchored `.trailing` at
`x(end)`. When they would overlap, they collapse to a single merged
`12:30PM–10:43AM` centred on the band.

Widths come from `ctx.resolve(text).measure(in:)`, not a hardcoded point
estimate, so the rule survives a font change.

The decision extracts as a pure function, testable without a `Canvas`:

```swift
enum GutterLabels { case pair, merged }

func gutterLabels(bandWidth: CGFloat, startWidth: CGFloat, endWidth: CGFloat) -> GutterLabels
```

`pair` when `startWidth + endWidth < bandWidth`, `merged` otherwise (equality
merges — touching labels are unreadable).

Expect `merged` to be the common render: at 12pt/hour a typical 1–3h window is
12–36pt wide and a `12:30PM` label is ~46pt. `pair` is the wide-window case
(the weak stations, where the window runs many hours). That distribution is
expected, not a smell.

## §5 Readouts — relative only, above the strip

All three details converge on tide's order: readout `HStack`, strip,
`‹ swipe to scrub ›`, `ScrubWhen`. `CurrentDetailView.scrubCard` and
`DerivedGateDetailView.scrubCard` move their readout block above
`TimelineScrubStrip` and drop the `.padding(.top, 8)` that separated it below.

### Current

```
NEXT SLACK
in 3h 1m
for 4h 13m @ 0.5 kn
```

- **Line 1 counts to the window OPENING, not to the slack instant.** This
  question is about planning an arrival — when can I be there — and the window
  is when the pass is transitable. When the window is already open (common:
  the window brackets the slack, so it opens before the slack arrives), line 1
  reads `now`.
- **Line 2 is the time remaining**, `countdown(from: max(scrubTime, win.start),
  to: win.end)` — so an already-open window reports what is left of it, not its
  original length. Paired with `now` on line 1 it answers "go, and you have
  this long".
- `@ 0.5 kn` is `Timeline.slackThresholdKn` through `formatSpeed`, never a
  literal.
- Drops `· 9:51 PM` from line 1 and `· 12:30 PM–10:43 AM` from line 2. Those
  times now live in the gutter under the band.
- Drops the `then max flood 0.3 kn` line entirely, and the `following` computed
  property behind it.
- When `slackWin` is nil, line 1 falls back to counting to the slack instant
  and line 2 is omitted.
- `slack-window` keeps its accessibility identifier — `ScreenshotTests.swift:369`
  asserts on it and the element still exists, just above the strip now.
- The provisional `~` prefix and the amber colouring apply to these lines
  exactly as they do today. Nothing in the fast-answer treatment changes.

### Derived gate

Loses `· 9:51 PM` from its `in \(countdown(…))` line the same way. Keeps
`at high water` / `at low water` — that is a derivation fact, not a time. No
band, per §3.

### Tide

Already relative-only and already above the strip. Geometry change only.

## §6 What this unifies

Worth stating, because it is half the reason to do this:

- One time-label implementation serves both tracks (§2) instead of tide having
  inline times and current having none.
- One slack-window computation (§3) instead of a free function called from a
  view's computed property.
- One readout order across three details (§5).
- Four things deleted: the inline extreme time, `CurrentDetailView.following`,
  the `then max …` line, the per-view `slackWindow` call.

No new files. Net deletion in the views.

## §7 Tests

Unit (`SlackwaterTests/TimelineTests.swift`):

- Updated `height` assertions: 262 tide-only, 356 current-only, with the
  comments pointing at §1.
- `gutterY < height` and `gutterY > bodyBottom` for both cases.
- `TimelineData.build(gate:)` yields `slackWindows == []`; a current build over
  a station with a real slack yields a window bracketing that slack.
- `gutterLabels(bandWidth:startWidth:endWidth:)`: `pair` when the band is
  wider than both labels, `merged` when narrower, `merged` at exact equality.

The existing `slackWindow` tests (`:107–130`) stand unchanged — the function
keeps its shape, only its caller moves.

UI (`SlackwaterUITests/ScreenshotTests.swift`): no new assertions. Canvas
content is not queryable; the existing `timeline-strip` and `slack-window`
checks continue to cover that the strip renders and the window line exists.

## Not in scope

- Dynamic Type for gutter labels (see §1).
- Any change to the schedule table below the strip — it keeps its absolute
  `HH:MM` column. It is a table; that is where a table's times belong.
- Any change to sun/moon chrome.
- Tuning `SN.go.opacity(0.12)` beyond a first look at a real screenshot.
