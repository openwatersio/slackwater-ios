# DRAFT — Slack as a pair of lines, not a column

**Status: DRAFT. Not approved, not planned, nothing implemented.** Captured from a
brainstorm on 2026-08-22 so it survives the transcript. Three questions in §7 are
open and at least the first must be answered before this becomes a plan.

Supersedes, if approved, the slack-band half of
`2026-08-08-scrubber-gutter-and-slack-bands-design.md` §3. Sibling to
`2026-08-15-current-speed-ramp-design.md` (#97), whose ramp §5 reopens.
Touches the same `slackWindow` that `feat/green-pins` hoists into
`Slackwater/SlackWindow.swift`.

## The defect

The slack window renders as a full-track-height green column across its time span
(`TimelineStrip.swift:933-938`, `SN.go` @0.12). The column is a **binary render of an
arbitrary constant**. `Timeline.slackThresholdKn = 0.5` is one hard-coded number, and
painting it as filled/not-filled makes it look like a physical boundary. Three observed
failures, in increasing severity:

1. **False fragmentation.** At a weak station whose curve wanders between 0.4 and 1.1 kn,
   one obviously-transitable night splits into two columns with a "no" between them — over
   a 0.6 kn excursion. The skipper cannot see from the render how *far* outside it went,
   which is the only thing that would let them overrule it.
2. **The number lies with it.** `slackWindow()` crosses at |v| = 0.5, so the readout
   reports 47m where the honest answer is about five hours with a 0.6 kn blip in it.
   Repainting the chart alone leaves the countdown wrong.
3. **Degenerate at a quiet station.** San Francisco southern traffic lane never exceeds
   0.5 kn, so every pixel qualifies: the chart is 100% green and the mark carries zero
   information. The readout reads `NEXT SLACK — now, for 173h 27m @ 0.5 kn` — the window
   runs to the end of the sampled series and reports a week as a countdown. Meanwhile the
   speed fill under the curve is inferno's `#0D2033`, deliberately ~1.4:1 against the page.
   So the only thing painted is the thing with no content and the curve reads as a ghost.

## §1 Two horizontal lines

Two 1pt strokes at `geo.curY(±Timeline.slackThresholdKn)`, full chart width, in `SN.go`
at full-ish strength. Nothing between them.

**Not a filled band.** The band's height is `curHalf · 0.5 / (peak · 1.05)` and `curHalf`
is 97pt, so it swings an order of magnitude with the station's own peak — the same
auto-fit `TimelineGeo` applies to the curve:

| station | peak | line offset from zero |
|---|---|---|
| SF southern traffic lane | 0.5 kn | ±92pt of 97 — hugging the edges |
| median bundled station | ~2.2 kn | ±21pt |
| image-4 station | 3.7 kn | ±12pt |
| Hole in the Wall | 7.8 kn | ±6pt |
| Sechelt / Seymour | 16 kn | ±3pt — effectively one line |

A tint between the lines fails at both ends: at SF it is 95% of the chart (the
green-everything problem, unchanged), and at Sechelt it is 6pt tall and invisible. Lines
work at every row of that table, and are the smaller diff. That the *fill* fails at both
ends while the *lines* survive is the whole argument for this design.

The median figure is derived, not measured: the #97 ramp spec puts the median of 842
bundled stations at 23% of the ramp, which inverts through `speedRampAnchorsKn` to
~2.2 kn. Worth re-measuring with `tools/ramp-domain.mjs` before this ships.

**Free property, worth stating because it is half the value:** since the curve auto-fits,
**where the lines land is the absolute-scale readout**. Lines near the edges means the
whole day is inside; lines pinched to the centre means the window is a knife edge. The
chart gains an absolute cue in the one channel (`TimelineGeo`) that #97 explicitly gave
up on and could not recover through colour alone.

**Zero line.** At a violent station the existing zero stroke (white @0.4,
`TimelineStrip.swift:957-960`) lands within ~3pt of both threshold lines. Drop the zero
stroke whenever the threshold lines are drawn — the pair's centre *is* zero. Do not ship
a 6pt smear of three near-coincident lines.

## §2 The curve says when you are inside

Delete the column. Do not replace it with a rectangle. Instead **split the foam curve
stroke at the |v| = 0.5 crossings and draw the interior segments in `SN.go`**, 3pt against
the foam's 2pt if the weight reads thin.

- SF: the entire curve is green — "transitable all week", in one glance, no text.
- Sechelt: two short green runs a day, exactly as long as the window.
- The image-4 station: two green runs with a foam blip between them, and the lines let the
  eye measure that the blip is 0.1 kn over the boundary.

This degrades gracefully at every station because the mark is proportional to the fact it
reports, which the rectangle never was. The gutter's window times (§4 of the 08-08 spec)
hang off the green run's endpoints instead of the column's edges — a change of anchor, not
of layout.

No green enters the speed ramp; #97's invariant that green means slack and only slack is
preserved, and `feat/green-pins` extends the same word to the map.

## §3 The SLACK WINDOW label goes

Green already means transitable on the chart, in the schedule pill, and (on
`feat/green-pins`) on the map pins. A legend for a word the app says everywhere is
redundant, and the mockup that carried it put it inside a band that is 6pt tall at the
gates this app is named for.

## §4 Direction in the fill: a cardinal, not arrows

The brainstorm started from tiled arrows sweeping along the curve inside the fill. Those
are rejected, on #97's own logic: hue came off direction because hue was strictly
redundant with y-position, and tiled arrows re-spend a channel on that same fact. Worse,
arrows that follow the curve's slope encode nothing — on a speed-vs-time chart a diagonal
reads as rate of change, not as NE.

The real requirement underneath is sound: **direction should be legible from the fill
area, not only from the max-event dot.** Answer it with the cardinal itself — a large dim
`NE ↗` watermark inside each flood lobe, `SW ↙` inside each ebb lobe, one per lobe, drawn
under the curve stroke. A flood lobe is ~112pt wide at `pph = 18`, so it fits; skip below
a minimum lobe width.

It states the bearing rather than miming it, adds no motion, and does not carpet the
gradient that now carries speed. The rotated set arrow at the max event
(`TimelineStrip.swift:998-1041`) stays as the precise version of the same fact.

**No animation.** Motion has been ruled out twice already — #97 §5 ("motion as a second
channel… explicitly not doing") and the fill graduation ("streaks stay spiked. No streak
code ships"). Pulsing arrows in the chart would reverse both.

## §5 Readout inside the plot box

Proposed, less settled than §1–§4.

Today the scrubbed instant lives below the strip (`ScrubWhen`, `Theme.swift:327-377`) and
speed + phase + `CompassArrow` live above it (`CurrentDetailView.readout:135-205`).
Consolidate both into one floating capsule at the top of the plot box: time, speed,
`CompassArrow` + 16-point cardinal.

The geometry is free. `TimelineScrubber` is pan-under-a-fixed-centerline
(`TimelineStrip.swift:1064-1208`), not a draggable playhead, so the Neaps behaviour of
"stays roughly in the middle" is what the existing scrubber already does — no follow,
no clamp. Pin the capsule to a lane at `y ≈ curTop`: it never collides with the curve and
never sits under the thumb.

**Cost:** §5 of the 08-08 spec converged tide, current and derived gate on "readout above
the strip, everywhere". Either all three move or that convergence breaks. Decide
deliberately; do not move current alone.

What fills the freed rows is not decided and is out of scope here.

## §6 The ramp — reopening #97's colour, not its domain

The complaint is that the purple/navy end is hard to read. It is a fair one:
`#7B2E62` at t=0.4 is muddy against the page and `#0D2033` at t=0 is ~1.4:1 by design.

Three costs to know before changing it:

1. **The ramp is shared with the tide track** since `aca15ba` (#95, rate of rise).
   Changing it repaints tides too, or forks one ramp into two.
2. **A yellow→red ramp runs luminance backwards and short.** Inferno climbs
   navy (≈30) → gold (≈204) monotonically, a property bought for greyscale and Reduce
   Motion. Yellow (204) → red (100) is monotonic but descending across a third of the
   range, so mid speeds get *harder* to rank. If the range is wanted back, run
   yellow → red → near-black maroon: still monotonic, full span, darkest = worst.
3. **Green beside yellow is the deuteranopia trap.** Today green sits against near-black,
   maximum separation. Under §1 the lines are green and the ramp's low end would be
   yellow. Mitigate with the lines' hard 1pt edges, or start the ramp at warm cream.

**Whatever is chosen must stay absolute.** On the current anchors 7.1 kn is 70% of the
ramp, not 100%. A ramp where every station's own peak renders as the reddest thing on
screen is #97's original defect returning through the palette.

**Cheapest version that answers the complaint:** keep inferno's top, replace the bottom
two stops with brighter, warmer ones. Two hex values in `Theme.swift:83-86`, tide track
unaffected, every #97 test still green.

## §7 Open questions — answer before planning

1. **Does the window definition change, or only its paint?** §1 and §2 make the chart
   honest but leave `slackWindow()` alone, so `for 47m` and `for 173h 27m` both survive.
   Putting a merge rule (a short, shallow excursion does not split a window) and a
   whole-span suppression into `slackWindow()` fixes chart, countdown and map pin at once
   — at the price of a second arbitrary rule, and it changes what green means on
   `feat/green-pins`, which reads instantaneous speed against the threshold rather than
   window membership. The alternative is that the definition stays strictly `|v| < 0.5`
   and the lines do all the arguing. **This one blocks planning.**
2. **§6:** raise inferno's floor, or fork a new ramp and decide what tides do?
3. **§5:** move all three readouts or none, and what fills the freed rows?

## Not in scope

- The slack-threshold editor from the mockup. The lines are what would make an adjustable
  threshold legible later — that is an argument for the lines, not for building the editor.
- Any change to the schedule table, sun/moon chrome, or the map.
- Dynamic Type for chart labels (still governed by the `TimelineGeo` doc comment).
