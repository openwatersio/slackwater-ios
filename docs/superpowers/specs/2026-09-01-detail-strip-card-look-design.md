# Detail strip takes the station-card look — design

Builds on PR #252 (`feat/station-card-graphs`), which gave every tide and
current card a small curve: past swing faded, extremes labelled on a band,
times on one bottom axis, slack windows as green runs on the line. This spec
brings that look to the detail scrubber so the page a card opens into reads as
the same drawing at larger scale.

Normative references: `docs/current-charts.md` (the current spec) and the
existing scrubber behaviour in `Slackwater/TimelineStrip.swift`. Where this
document and the current spec disagree, the current spec wins and the
disagreement is listed in §8.

## 1. What does not change

- The scrub model: the strip pans under a fixed centerline, native momentum,
  magnet snap to stops, the floating readout at the centerline, the riding
  dot, return-to-now, the schedule rows that scrub the strip. Window entry and
  exit stay snap targets (current spec §4.7).
- `Timeline.window(anchor:)`, `pph`, tiling, the 228-hour strip.
- The day chrome: night bands, day tint, "Today / Sep 1" labels, sunrise and
  sunset dots with their times, the moon. Unchanged, pixel for pixel.
- The y-axis tick column overlay on both tracks, including the ±threshold pair
  on the current track.
- The readouts above the strip, the Range summary, the tide-at-port link, the
  footer, the schedule table.
- Derived gates: schematic ±1 curve, neutral fill, hairlines at slack, no speed
  marks, no windows (current spec §9). They only pick up the line weight and
  the past fade from §3.
- `TimelineData.build` and every predicate it calls. This is a drawing change.

## 2. Geometry (`TimelineGeo`)

The three band rows above and below the track (`topTimeY`, `topValueY`,
`topGlyphY` and their mirrors) and the current-only `slackRangeY` and
`maxTimeY` rows are removed. `drawBand` is removed with them.

Remaining vertical layout, top to bottom, both tracks:

| Row | Purpose |
|---|---|
| `dayY`, `sunY` | day chrome, unchanged |
| `bodyTop … bodyBottom` | the plot box, one for whichever track fills it |
| `timeY` | the single bottom axis row |

The plot box grows into the space the bands used. The strip is shorter than
today. Exact point values are chosen during implementation; the constraints
are: the tallest value label plus pointer fits inside the box, the axis row
clears a trough by at least the halo gap, and `floatingReadoutY` still keeps
the readout inside the strip.

Every number stays a literal point (current spec §7.5: chart labels do not
scale with Dynamic Type).

## 3. The curve, both tracks

Taken from `StationCardGraph` verbatim, with the constants moved to one shared
home so the two surfaces cannot drift:

- Line width 2.5pt.
- Past and future split by clipping the same path at `now`: past at 0.35
  opacity, future at full strength. When `now` is not on the strip (an anchored
  month out) the whole line is future.
- The dashed blue now line is removed. In its place the card's white now dot
  rides the curve at `now`, with a punched halo, drawn only when the strip
  contains `now`.
- Dots punch a halo through everything drawn under them in the same canvas
  (`destinationOut`), as the card does. Behind the strip canvas is the page
  ground, so a halo over a night band shows the page ground, not the night
  tint. Accepted; it is a 2.5pt ring.

Shared constants (`Theme.swift`, one enum): line width, past line opacity,
past label fade, extreme dot radius, halo gap. `StationCardGraph` reads them
from there instead of its private statics.

## 4. Tide track

- **Fill**: the card's vertical gradient, line colour at 0.5 opacity at the top
  of the box easing to 0.05 at the bottom. Replaces the flat blue.
- **Datum**: unchanged rule (drawn when 0 is inside the plotted span), restyled
  to the card's dotted reference line.
- **Rate as line colour**: the `››››` chevrons are removed. The stroke colour
  follows the tide-rate ramp along the curve instead. Below the ramp floor
  (`tideMovementRampAnchorsMHr[0]`, 0.6 m/hr) the line is the base line colour.
  From the floor up, the stroke takes `SN.speedColour(Timeline.rampT(forTideRateMHr:))`
  at each sample, so a fast run climbs yellow to red toward its fastest point
  and back to yellow, then returns to the base colour before the turn. A lazy
  tide never leaves the base colour. Implemented as one gradient stroke with
  stops at the sample times (the current track already builds per-sample stops
  with `currentFillStops`). The past fade applies on top.
  `tideFlowArrows` stays: `TideDetailView` reads it for the rate warning text.
- **Extremes**: a dot on the curve, teal for a high and amber for a low, halo
  punched. The value with unit on a band at the vertical middle of the plot
  box. The pointer is the to-bar arrow (`⤒` / `⤓`) on the dot's side of the
  value: above for a high, below for a low. Past extremes fade to 0.45.
- **Axis**: each high and low prints its time on the bottom row under its dot.
  Edge rule as today (0.3h in from the strip ends).

## 5. Current track

Reading order from the current spec §5.1: the window first, the peaks as
context, everything else after.

- **Excess fill**: unchanged. The area between the ±threshold line and the
  curve keeps the absolute speed ramp (`currentExcessSegments`). This is what
  the §14 different-peaks-different-colours invariant tests.
- **Threshold lines**: kept, as two 1pt hairlines in the go colour at 0.35
  opacity (down from 0.85). No zero line while they are drawn (§7.4).
- **The window, two marks**: the threshold lines above, and the run on the
  line. The line itself is stroked in the go colour between each window's
  interpolated start and end, over a wider round-capped eraser, exactly as the
  card draws it. The green sine-envelope area fill and the dashed start/end
  rails are removed.
- **The window start dot**: a dot in the go colour at each window's start, on
  the curve, halo punched, same radius as an extreme dot. It is the only dot on
  the current track. Its axis time sits directly under it.
- **Slack instant**: no dot (§5.3). The hairline stays only when a slack has no
  window: a gate the sampling steps over, and every derived gate.
- **Peaks**: no dot. The speed with unit on the band at the zero line, the
  compass set arrow (`CompassArrow` rotated to the station's flood or ebb
  bearing) on the dot's side: above for flood, below for ebb. On a derived
  gate there is no set arrow and no speed, as today. Past peaks fade to 0.45.
- **Axis**: one time per window, at the window's start. Max flood and ebb
  times leave the strip; the schedule table keeps them. A slack with no window
  prints the slack instant under its hairline. Touching windows are already one
  run from `TimelineData`, so one label per run falls out.

## 6. The card

`StationCardGraph` gains the window start dot from §5 and its axis time moves
from the zero crossing to the window start. Both surfaces then name the same
moment for the same window, from the same `slackWindow` predicate (§6.1).

The crossing scan inside the card canvas is replaced by a pure function that
returns the axis moments for a current curve: each window's start, or the
slack instant where a slack has no window. The strip calls the same function.

## 7. Tests

- One unit test for the axis-moments function: a window yields its start, a
  windowless slack yields the instant, a merged run yields one moment.
- `suppressesSlackLabel` and its tests are removed; the merged run makes it
  redundant.
- `ColourAndFormTests` source tripwires target `drawCurrent`'s body by name.
  They are retargeted, not deleted, and re-read to check each still guards what
  it says it guards.
- The `PhaseGlossTests` and `TypeScaleTests` chart guards are re-run; any that
  assert on the removed chevrons or band rows are updated to the new marks.
- Tide-rate ramp tests (August 19 design) keep passing: the ramp function is
  untouched, only its consumer changed from glyph tint to stroke colour.
- The UI screenshot tests (`m2-current-scrubbed`, `m4-gate-detail`,
  `m46-derived-gate-seeded`, `online-gate-*`) are re-run and the images opened.
  The check is visual: the readout pill over a band value, a trough against
  the axis row, the halo over a night band.

## 8. Deviations from the current spec

- §5.4 says a peak gets a dot. This design draws none on the current track,
  by product decision: the value and set arrow say what is happening, and a
  dot invites the tide-chart reading the spec exists to undo.
- §3 says the threshold prints once, not on the strip; §7.1 says the ±threshold
  pair is labelled on the axis. The spec disagrees with itself. The axis column
  is kept as is, so today's behaviour continues.

## 9. Out of scope

- VoiceOver for the strip (the card's own open item in PR #252).
- Label collision measurement (§5.5): the strip's 18pt per hour keeps the
  tightest real pair apart, as the `pph` comment argues. Revisit if it fails
  in the screenshots.
- Any change to `TimelineData`, the window predicate, or the ramp anchors.
