# Colouring the current track by speed

Issue: [#97](https://github.com/openwatersio/slackwater-ios/issues/97). Supersedes the
hazard-band halves of #95 and #96. Sibling: #57 (the same visual language on the map).

## The defect

`TimelineGeo.init` normalizes both tracks to their own extremes:

```swift
maxAbsCur = max(data.currentPoints.map { abs($0.speed) }.max() ?? 1, 0.01) * 1.05
```

Sechelt Rapids at 16 kn and a 3 kn pass therefore draw as the *same picture*. The
visualization does not merely fail to convey magnitude — it removes it. The printed
number is the only carrier, and the drawing beside it is actively equalizing.

Colour on the current track is meanwhile spent on something the geometry already says.
The flood and ebb fills are clipped to the zero line (`TimelineStrip.swift:832-841`), so
blue can only render above it and amber only below. Hue is strictly redundant with
y-position.

**So: hue comes off direction and goes onto magnitude, on an absolute scale.** The
curve's *shape* stays auto-fitted — that is what keeps a quiet station legible — while
colour carries the absolute number the geometry gave up. `TimelineGeo` does not change.

## Scope

`drawCurrent` only.

The tide track keeps `SN.rising`/`SN.falling` and stays magnitude-blind. The jargon
argument that justifies taking hue off flood/ebb (#59: "a novice reads the arrow +
cardinal; the flood/ebb word demotes to a dimmer label") does not transfer to
"rising"/"falling", which is plain English. Whether tides move to a rate-of-rise ramp is
#95's question and is decided there, not here.

Cards, glyphs, map pins and detail views are untouched. `CurrentDetailView.phaseColor`
still returns the diverging axis, so `testPhaseColoursUseTheDivergingAxis`,
`testSlackIsGreenWhereverItAppears` and `testDirectionIsASignedDivergingAxis` hold
unchanged.

Direction keeps two novice-legible carriers on this surface: the rotated set arrow at
each max event, and position about the zero line. Nothing here removes either.

## 1 · The ramp

Inferno-family, six stops:

| t | hex |
|---|---|
| 0.0 | `#0D2033` |
| 0.2 | `#3B2C63` |
| 0.4 | `#7B2E62` |
| 0.6 | `#B8434F` |
| 0.8 | `#E8763C` |
| 1.0 | `#F5C96B` |

Piecewise-linear RGB interpolation, `SN.speedColour(_ t:)`, sibling to the existing
`Color.hex(_:lightenedBy:)`.

Why not a Windy-style rainbow: `Theme.swift:37` calls the existing axis "colourblind-safe
amber/blue", a property bought deliberately. Under the Viénot–Brettel matrices a
rainbow's blue→green→yellow half collapses to one band for both deuteranopia and
protanopia, and its greyscale is **non-monotonic** — mid speeds read brighter than the
top, so the ramp misstates rank order. Inferno's luminance climbs monotonically end to
end, which is also what makes it survive Reduce Motion without a motion channel.

Why no green in the ramp: green means slack and only slack. A rainbow passes through its
own green at moderate speed, a few hundred points from the green column that means *go*.

The finish in `SN.amber`'s neighbourhood is a bonus rather than a compromise: at the top
of a speed scale, reading as alarming is correct.

### On the dark base

`#0D2033` is roughly 1.4:1 against `SN.page` — nearly invisible. This is deliberate and
self-resolving. `t ≈ 0` only occurs at |v| ≤ 0.5 kn, which *is* the slack window, where
the green column sits. A station whose whole range is quiet reads as "almost nothing is
happening", which is true.

No contrast floor is applied to the fill. WCAG 1.4.11 governs graphics *required to
understand the content*; the shape is carried by the foam curve stroke and the zero line,
and the magnitude is carried redundantly by the printed peak-speed numbers. The fill is
the enhancement, not the requirement.

## 2 · The absolute domain

```
speedRampAnchorsKn = [0.5, 3, 6, 16]   at t = 0, 1/3, 2/3, 1
```

Piecewise linear between anchors, clamped at both ends.

Anchored to **capability**, not to quantiles — the same move Beaufort makes, and the
reason Windy's ramp reads well:

| Anchor | Meaning |
|---|---|
| 0.5 kn | `Timeline.slackThresholdKn` — a small boat transits |
| ~3 kn | around where a paddled craft can no longer make way against the stream |
| ~6 kn | around where a small displacement craft can no longer stem it |
| 16 kn | Sechelt Rapids; the overfall regime — timed, not transited |

Across the 842 bundled NOAA current stations this puts the median at 23% of the ramp and
p90 at 56%. A linear 0→16 kn ramp would put them at 14% and 31%, compressing 90% of
stations into the bottom third — this issue's original defect, re-entering through the
transfer function. A ceiling of 6 or 8 kn makes Sechelt and Seymour Narrows identical
again, which is the failure PredictWind's 6-kt tidal layer ships today (#57).

**The middle two anchors are estimates and want a source** — Sailing Directions or
small-craft guidance. They ship flagged in the code rather than blocking the PR: the ramp
is a visual encoding, not a computed hazard call, so an anchor wrong by half a knot shifts
a colour rather than a decision.

**The ceiling is a hard-coded constant and is never derived from the stations on the
device.** Computing it at runtime would make the same colour mean different speeds on
different phones, which breaks the absolute-scale requirement outright. Values above the
ceiling clamp to the top colour; "beyond the top of the scale" is not a distinction worth
resolving.

This array is also where a future **per-vessel** limit lands — a powerboat's thresholds
sit higher than a paddled craft's, and eventually the preference set would key off the
boat's SignalK identity. Structuring the domain as one anchors array keeps that door open.
No settings plumbing is built now: a constant, not a setting, until someone asks.

## 3 · `drawCurrent`

Net a deletion.

| Today | After |
|---|---|
| Two `ctx.drawLayer` blocks, each clipping a half-box, filling `SN.flood@0.32` / `SN.ebb@0.32` | **One** `ctx.fill(area, with: .linearGradient(stops, startPoint: (0,0), endPoint: (totalWidth,0)))` — one stop per current point, colour `SN.speedColour(rampT(abs(v)))`, alpha 0.9 |
| Slack window column drawn *after* the fills | Drawn *before* them — the full-height ground tint the design calls for. Works because near slack the area has ~zero height, so the column reads on page ground above and below the curve |
| Slack dot + 18pt time label in `SN.go` | `SN.foam`. Green narrows from doing double duty (instant *and* column) to meaning the window alone — the thing you can actually plan around. A mathematical point is not something you transit *at* |
| Max-event dot and speed/arrow tint in `SN.floodLabel`/`SN.ebbLabel` | Dot in `SN.foam`; label ink chosen by fill luminance (below). The rotated set arrow is unchanged |

The gradient's `startPoint`/`endPoint` are in full-strip coordinates, which is correct
under the per-tile `translateBy(x: -x0)` — every tile draws the whole strip clipped to its
own span.

### Two legibility bugs the change introduces

Both are fixed in the same pass rather than left for the screenshot to find:

- **White-on-light.** `mark = inside ? .white : tint` assumes a 0.32 fill. At the top of
  the ramp the fill is `#F5C96B` (luma 204) and white text on it fails. `SN.speedInk(forT:)`
  returns `.white` below a luminance threshold and `SN.page` above. Note the auto-fit means
  "inside" happens at a quiet station too, where the fill is dark — so the choice has to be
  made from the ramp position, not from the y-offset.
- **Foam stroke at peak.** `#DFEEE0` on `#F5C96B` is about 1.3:1. Foam is kept anyway: the
  stroke's *outer* edge always sits against the dark page ground, so the boundary still
  reads. Verified on the screenshot rather than pre-empted with a halo.

### Derived gates keep the ramp off

Found by the suite, not by the design: `testM46MalibuDerivedGateSeededOffline` went red
at ink 0.046 against a 0.05 floor.

`build(gate:)` synthesises a **schematic ±1 shape** for a derived gate — it means "flood,
then ebb", and no speed was ever measured. Running that through an absolute scale renders
a one-knot gate, which is a number nobody has. It is the same fiction `slackWindows`
already refuses to make out of the same shape ("a 0.5 kn window measured off a shape
would be fiction").

So `TimelineData` gains `speedsAreSchematic`, set only on the gate path, and
`currentFillStops` fills `SN.steel` at 0.32 instead — already this app's word for a state
it does not know (`StationGlyph.colour(for: .unknown)`). That also restores the ink
fraction, but the ink was the symptom; the fabricated speed was the bug.

Worth recording for #95: the tide track, if it ever moves to a rate-of-rise ramp, has no
equivalent schematic case — but it does have the same question about what a derived value
is allowed to assert.

### Accepted regression

Night bands stop showing through inside the area fill (they show at 0.32 today). Night
still reads in the unfilled half of the box and across the chrome rows above it.

## 4 · Tests

Stop-building is a pure function so it is testable without a `Canvas`.

- `rampT` lands the four anchors at 0, ⅓, ⅔, 1, and clamps above 16 kn and below 0.5 kn.
- **The defect itself, proven red:** a 3 kn series and a 16 kn series produce different
  fill colours at their peaks. This is the assertion that fails if auto-fitting ever gets
  reintroduced into the colour. Per CLAUDE.md, it is proven red before the fix goes in.
- Ramp luminance increases monotonically across sampled t — the greyscale and Reduce
  Motion property.
- No ramp stop is green-dominant, guarding "green means slack" against a future stop edit.
- `testChartDoesNotHardcodeDirectionColour` is retargeted: the `l.fill(area,` trigger dies
  with the `drawLayer`s. It becomes a ban on `SN.flood`/`SN.ebb`/`SN.floodLabel`/
  `SN.ebbLabel` inside the `drawCurrent` body, scoped to that function because `drawTide`
  legitimately keeps them.

## 5 · Explicitly not doing

**Motion as a second channel** (#57's map half). The monotonic-luminance ramp is already
the greyscale-safe carrier, so motion would be a third redundant channel with a Reduce
Motion problem attached to it.

**Words at the extreme end.** #97 leaves this open: is the darkest colour enough for
someone whose first-ever gate is Sechelt? The answer here is that the peak-speed number is
the day-one carrier and it is already on the chart. An always-on encoding is never
self-explanatory, which is exactly why the numeric readouts stay — the encoding replaces
the warning *band*, not the numbers.
