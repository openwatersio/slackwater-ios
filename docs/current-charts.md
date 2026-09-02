# Current charts — spec

How to draw a tidal current. Normative: this is the target, whatever any given
codebase currently does.

Covers the signed-velocity curve and its annotations, including derived and
online gates. §15 covers the low-resolution surfaces — the list card and the
home-screen widget — which draw the same curve at a size where most of the
marks below cannot fit. The map is out of scope as a surface, but §5 and §6
bind it wherever it shows current state.

---

## 1. A current chart is not a tide chart

A tide reader wants the extremes. High and low *are* the events; the curve
between them is interpolation. Peak height is the number you act on.

A current reader wants the **equilibrium**. Max flood at 6.1 kn is context — it
says what you are avoiding, not what you are doing. The number you act on is
*when the water is slow enough for this boat to get through this pass, and for
how long*. That is a **run of time**, and it sits at the zero crossing, not at
the peaks.

This inverts figure and ground. On a tide track the curve is the subject and the
axis is reference. On a current track **the band around zero is the subject** and
the curve is what intrudes into it.

Everything below follows. It is also the standing review question: **any rule
that arrived from the tide track is suspect until re-argued here.** The two
tracks can share geometry, a strip, a palette. They do not share a thesis.

The plainest test of whether a chart obeys this: the reader should be able to
answer *can I go, and when* without reading a single speed number.

---

## 2. Quantities and signs

**Signed velocity**, knots, along the station's flood axis. A scalar, not a
vector: the y-axis is the component along that axis, and cross-axis flow is not
drawn.

- `> 0` — **flood**, toward the station's flood bearing
- `< 0` — **ebb**, toward flood bearing + 180°
- `0` — the slack instant

Sign is phase, never magnitude. Magnitude is drift; the flood axis is set.

This model assumes a **rectilinear** station — a pass that reverses between two
roughly opposed bearings. It is a lie at a rotary station, where the set sweeps
through 360° and there is no axis to project onto. See §10.

Three things that must never be conflated, in prose, labels, or names:

| Term | Is | Duration |
|---|---|---|
| **slack** | the zero crossing | an instant |
| **slack window** | the run where `\|v\| ≤ threshold` **and the sign reverses inside it** | minutes to hours |
| **weak water** | `\|v\| ≤ threshold`, no reversal | any |

Weak water is not slack. A lull that dips under the threshold and builds back
the way it came is the flood pausing, not the pass opening. Marking it green
promises a transit that never happens.

**This distinction is a predicate, not a rendering choice.** See §6.1: it holds
identically on every surface.

---

## 3. The threshold

The threshold is the single number that says what this chart considers workable
water. **Three marks derive from it**: the position of the threshold lines, the
extent of the inked run, and the baseline the speed fill starts from. One
number, so they cannot drift apart.

It prints **once**, next to the window's duration — `for 41m @ 0.5 kn`. Not on
the strip. One statement of a constant is information; six a day is texture.

### 3.1 Global, plus a per-station delta

The threshold is not a property of the boat alone. What matters is not the speed
when you arrive but **how fast the water builds while you are in there**.

Sechelt Rapids goes from workable to unmanageable in minutes. A 0.5 kn threshold
there buys a window whose edges are cliffs: being ten minutes late is a
categorically different event than being ten minutes late at a lazy pass, where
the same threshold gives you a shoulder on both sides and lateness costs a
little adverse set rather than the transit.

So: **one global value for the boat, plus a saved per-station delta.** A
per-station override is effectively *a mode for that station* — a narrows you
will only run at true slack, versus an open reach you will push through at 2 kn.
The station remembers its delta.

**Every surface keys off the effective value** — chart, countdown, schedule, map
pin, notifications, share card. The effective threshold is one lookup, never a
global constant read directly at a call site.

Settable range 0.1–10 kn, default 0.5. Where a surface genuinely cannot ask (a
public page with no settings), it ships the same default the settable version
uses — a reader comparing two of our surfaces for the same station on the same
day must not see two different windows.

### 3.2 What the threshold is allowed to be uncertain about

The threshold and the ramp anchors are **visual encodings, not computed hazard
calls**. An anchor wrong by half a knot shifts a colour, not a decision. That is
why estimated values may ship flagged rather than blocking on a source. The
moment a number starts driving an alert or a go/no-go statement, it stops being
an encoding and this latitude ends.

---

## 4. Slack windows

The window is the subject. Every rule here exists to keep it from over-claiming.

1. **Endpoints are the interpolated ±threshold crossings**, never the nearest
   sample. At a fast gate a 10-minute sample lands a long way from the edge, and
   the error is always in the dangerous direction.
2. **A run counts only if the sign reverses inside it** (§2). Test this on the
   entry and exit steps too, not only steps wholly inside: at a violent gate the
   reversal and the band edge land in the same sample.
3. **Touching or overlapping windows are one run**, and carry one label.
4. **A window narrower than the sample step is not a window.** Draw the slack
   instant instead (§5.3).
5. **Show the time remaining, not the original length.** An already-open window
   must not claim its full run.
6. **Count down to the window opening, not to the slack instant.** The question
   is *when can I be there*. The window brackets the slack, so it is often
   already open — then the answer is `now`.
7. **Window entry and exit are scrub snap targets**, alongside the peaks and sun
   events. They are the moments a planner is actually aiming at.

### 4.1 An unbounded window is not a countdown

A window whose endpoint is the **series boundary** rather than a crossing has
not been measured — it has been clipped by the frame. Treat it as unbounded.

An unbounded window must never be rendered as a duration. `for 173h 27m` is a
sampling artifact reported as a fact. Say what is true instead: *under 0.5 kn
all day*, or *no closing edge in this window*.

Same family as: a slack outside the sampled series has no measurable window
(§8.7), and a window open at the frame edge is real water with no visible end
(draw it to the edge, never draw a closing edge the data does not support).

### 4.2 Do not merge windows; summarise runs of them

A curve wandering 0.4–1.1 kn will split one obviously-transitable night into two
windows over a 0.6 kn excursion.

**The definition does not absorb this.** The water genuinely exceeded the limit;
hiding that inside the predicate makes the chart lie in the other direction, and
lie *silently* — the reader loses the excursion instead of seeing it and judging
it. A merge tolerance would also be a second arbitrary constant, invisible to
the user, and **itself per-station**: a 0.6 kn blip at a lazy channel is
nothing, while at Sechelt it means the water is already accelerating and you
have minutes.

So the window function returns exactly what it measured, and **the readout
summarises the run** — reporting the transit *opportunity* rather than the next
fragment of it: `~5h, 1.1 kn blip midway`.

The interpretation happens in words, where a reader can disagree with it, rather
than inside a predicate where they cannot.

### 4.3 The reader must be able to overrule the chart

The general rule behind §4.2, and the sharpest test of any window mark.

A binary render of an arbitrary constant looks like a physical boundary. If the
chart says *no* and the water was 0.1 kn over, the reader needs to see **how far
over** — otherwise the only judgement they can make is to trust or ignore the
mark entirely.

This is the argument for threshold lines over a filled region (§7.2), and
against any mark that resolves the threshold to a yes/no without also showing
the margin.

### 4.4 Direction within the window

The window is not symmetric and must not be drawn as if it were.

A flood→ebb window and an ebb→flood window are different transits. You enter one
with the water still pushing you one way and leave it with the water pushing the
other. Which half you are in determines whether the set is carrying you into the
pass or out of it, and whether being late means fighting the water or being
flushed through. For a pass with a dogleg, or an exit into a different body of
water, this is often the whole decision.

The chart owes the reader the **set on each side of the reversal**, not just the
run's extent. Showing that a window exists and how long it lasts, and leaving
the reader to recover direction from the curve's slope, is doing three quarters
of the job.

State the bearing; do not mime it (§6.4).

---

## 5. Marks and hierarchy

### 5.1 The order of loudness

1. **The window** — the run, and the threshold lines that give it scale
2. **The peaks** — context: what you are avoiding
3. **Everything else**

A mark that inverts this re-teaches the tide-chart reading the whole chart
exists to undo. Peaks earn their place because they say how bad the alternative
is; they must not out-shout the thing the reader came for.

### 5.2 The window gets two marks, because it makes two claims

- **The threshold lines** — the limit made visible everywhere at once, so the
  reader can check any moment against it. They claim nothing about time.
- **The inked run** — when it is actually happening: the curve itself,
  overdrawn in the go colour between the crossings.

Drawing the run **on** the water rather than behind it is what stops it
over-claiming. A peak rising past the threshold breaks the run, and two windows
become comparable by length alone — which a mark whose height followed the
curve's steepness was not. A mark drawn behind the curve will eventually
disagree with the curve; one drawn on it cannot.

### 5.3 The slack instant gets no dot

Slack is the zero crossing. It is a mathematical point, and a point is not
something you can transit *at*. If the window and its threshold are the true
value, marking the instant adds a competing focal point that carries no
decision — an "interesting moment," like a peak, but without the peak's
justification.

**Draw the instant only when there is no window to draw**, as a hairline:

- a pass so fast the window is shorter than the sample step (§8.3)
- a derived gate, which knows slack timing and nothing else (§9)

A zero-width window must never look like a window; a hairline is the honest
form. And where a run exists, the run is the mark — the crossing is already
inside it.

Slack times still belong in the **schedule table** (§13). A table is where
absolute times belong; the chart is not a table.

### 5.4 Peaks are not points of interest

**No dot.** A peak or trough is context — what the window is measured
against — and a dot would make it a point of interest, which is the
tide-chart reading this whole chart exists to undo. The speed and the
**true bearing arrow** for the set hang off the peak inside its lobe, styled
as context, not as the event.

The arrow states the set. An up/down arrow would only restate which side of zero
the peak already sits on, which is a channel spent on nothing (§6.4).

### 5.4.1 The window's edges are the points of interest

The **opening** of a slack window is the major point of interest: the moment
a planner is aiming at (§4 rule 7). It gets the dot, and its time on the
axis. The **closing** is the minor point — a lesser mark — until the reader
is inside the window, when it becomes the one that matters: the question has
changed from *when can I be there* to *how long do I have*. A surface that
can count (the widget, the readout) counts down to the closing while inside
the window.

### 5.5 Absolute time has exactly one home per surface

Pick one place per surface where exact clock times live, and put every one of
them there. A chart with times on the events, times in a gutter, and times in
the readout has three homes and they will drift.

Times that leave the chart do not leave the product — the schedule table keeps
its absolute column.

Where two labels would collide, **measure the rendered text; never estimate
widths** — a hardcoded estimate stops being true the moment the font changes.
When they would overlap, collapse to one merged range. At typical zoom, merged
is the *common* case, not a smell.

---

## 6. Colour

**Colour is state. Form is kind.** Never colour by station kind, unit, or data
provider.

### 6.1 Green is one predicate everywhere

The go colour means: **`|v| ≤ effective threshold`, and the sign reverses inside
this run.** That is the definition from §2, and it is the same on the chart, the
map pin, the card, the widget and the notification.

Instantaneous speed under the threshold is **not** the predicate. A pin that
goes green during weak water invites a transit through a pass that is not
opening — the exact failure §2 exists to prevent, arriving through a surface
that reimplemented the test. Any surface that shows the go colour computes it
from the shared window definition, never from a fresh comparison against the
threshold.

Green is the only reserved meaning on the whole chart. Not "good", not "tide
station", not "rising".

### 6.2 The speed ramp: shape auto-fits, colour is absolute

An auto-fitted plot does not merely fail to convey magnitude — **it removes
it.** A 16 kn gate and a 3 kn pass draw the identical picture, the printed
number becomes the only carrier, and the drawing beside it is actively
equalizing.

The resolution is a division of labour:

- **Shape auto-fits.** That is what keeps a quiet station legible.
- **Colour is absolute.** It carries the magnitude the geometry gave up.

**A gradient keyed to plot position is the original defect returning through the
transfer function.** If the day's peak always renders as the reddest thing on
screen, the ramp has become another auto-fit and the chart is equalizing again.

### 6.3 The ramp's constraints

1. **Absolute, capability-anchored, hard-coded.** Anchors say what you can still
   do about the water, not what percentile the station is in — the move Beaufort
   makes. Deriving a ceiling from whatever stations are on the device makes the
   same colour mean different speeds on different devices, which is the absolute
   scale gone. Values above the ceiling clamp; *beyond the top of the scale* is
   not a distinction worth resolving.
2. **Quantile and linear-to-max domains are both wrong.** A linear 0→max
   compresses most stations into the bottom third. A ceiling set at a moderate
   speed makes every fierce pass identical to every other.
3. **No green, at any stop.** A ramp that passes through green puts a second,
   opposite meaning a few hundred points from the mark that means *go*. This is
   the specific reason it is not a rainbow.
4. **Starts at the threshold, never at zero.** Only the excess above the limit is
   inked. Water you can work in is not drawn hot at all, and warm colour never
   appears inside the band, which would contradict §6.1.
5. **Luminance should climb monotonically** across the ramp — that is what makes
   it survive greyscale and Reduce Motion, and what preserves rank order. A ramp
   that descends in luminance across part of its range makes mid speeds *harder*
   to rank than the extremes; if the full span is wanted, run light → saturated
   → dark rather than doubling back.
6. **Watch the green-beside-yellow adjacency.** Green survives partly by sitting
   against a dark ground at maximum separation. Putting the go colour next to a
   yellow ramp floor spends that margin, and green/yellow is the deuteranopia
   trap. Mitigate with hard edges on the go marks, or by warming the ramp's
   floor away from yellow.
7. **The anchors array is where a per-vessel limit eventually lands.** Structure
   the domain as one array so that door stays open.

### 6.4 Channel economy

**Do not spend a channel on a fact another channel already carries.**

Hue came off direction because hue was strictly redundant with y-position: the
fills were clipped to the zero line, so one hue could only ever render above it
and the other below. Direction was being said twice while magnitude had no
channel at all.

The same test kills tiled arrows sweeping along the curve: on a speed-versus-time
chart a diagonal reads as **rate of change**, not as NE. An arrow that follows
the curve's slope encodes nothing. If direction needs to be legible from the
fill area rather than only from a dot, **state the cardinal** — a large, dim
`NE ↗` inside each flood lobe and `SW ↙` inside each ebb lobe, under the curve
stroke, skipped when the lobe is too narrow to hold it.

**Motion is not a channel.** A monotonic-luminance ramp is already the
greyscale-safe carrier, so motion would be a third redundant encoding with a
Reduce Motion problem attached.

### 6.5 An always-on encoding is never self-explanatory

The ramp replaces the warning *band*. It does not replace the numbers. The
printed peak speed is the day-one carrier for a reader who has never seen this
chart before, and it stays.

### 6.6 Contrast

Ink drawn **on** the fill picks its colour from the ramp position, not from its
offset off the zero line — the auto-fit means a quiet station puts a label deep
inside a dark fill just as a violent one puts one inside a bright fill.

**No contrast floor is applied to the fill itself.** WCAG 1.4.11 governs
graphics *required* to understand the content: the shape is carried by the curve
stroke and the zero line, and the magnitude redundantly by the printed numbers.
The fill is the enhancement, not the requirement — a near-invisible low end
correctly reads as "almost nothing is happening."

---

## 7. Geometry

### 7.1 The fit

Symmetric about zero; the zero line is the vertical centre of the plot. Symmetry
is not cosmetic — an asymmetric fit makes flood and ebb look like different sizes
when they are not.

The axis stays signed, so the zero line reads as the slack boundary and the
`+`/`−` are load-bearing. Ticks are symmetric and speak the reader's selected
unit while the curve keeps its physics in knots. The ±threshold value is
labelled as its own pair, and excluded from the round ticks so it never prints
twice.

### 7.2 Lines, not a filled region

The threshold mark is **two lines**, not a filled band.

A filled region's height is `plot half-height × threshold ÷ peak`, so it swings
by an order of magnitude with the station's own peak: at a station whose day
never exceeds the threshold it is 95% of the chart, and at a 16 kn gate it is a
few points tall and invisible. **It fails at both ends of the exact distribution
the chart has to cover.** Lines are legible at every point of that range.

The general rule: **the mark must be proportional to the fact it reports.** A
mark that degrades at the extremes of its own domain is the wrong mark, however
well it reads in the middle.

### 7.3 Where the lines land is itself the reading

A free property, and half the value of §7.2. Because the curve auto-fits, the
lines' position encodes the day's magnitude in geometry:

- lines near the plot edges — the whole day is inside the limit
- lines pinched toward the centre — the window is a knife edge

This recovers in position what the auto-fit gave up, in a channel that costs
nothing and works in greyscale.

### 7.4 Drop the zero stroke when the threshold lines are drawn

At a violent station the threshold lines land within a few points of zero. Three
near-coincident strokes are a smear, and the pair's centre *is* zero. Draw the
zero line only when no threshold lines are present.

### 7.5 Labels and edges

- **Drop events near the frame edge; do not clip them.** The fill fades over the
  outer few percent, so a label landing there annotates a curve the reader can
  barely see and looks broken. The frame edge is arbitrary; the label is not
  worth defending.
- **Fade the fill at the frame edges.** A hard vertical cut reads as a rendering
  fault.
- **Chart labels do not scale with Dynamic Type** while the geometry around them
  is fixed points. Text scaled inside fixed-point geometry degrades by
  *overprinting the chart*, not by wrapping. Making labels scale means making the
  geometry scale — a chart-layout change, not a font swap. Do not do half of it.
- **A calendar day is not 86,400 seconds.** Anything meaning *a day* goes through
  a calendar with its timezone set; a window spanning a DST transition is 23 or
  25 hours.

---

## 8. Edge cases

Each of these is a real reading.

**8.1 The whole day inside the limit.** No excursion anywhere. The tide-chart
instinct handles this worst, because there is no "event" — and it is arguably
the most useful thing a current chart can say. The lines pin near the plot edges
and say it geometrically (§7.3); the readout says it in words (§4.1). Watch for
threshold-derived marks escaping the plot: a threshold above the fitted maximum
can pin to the plot edge, reading as a boundary that is not one, or render
off-canvas and make dependent geometry — clip regions, gradient endpoints —
degenerate or inverted.

**8.2 Threshold just above the fitted peak.** Same root cause, less extreme.
Handled by 8.1, not separately.

**8.3 A window shorter than the sample step.** A violent gate stepped over by
the sampling interval. Hairline, not a run (§5.3). The *events* still resolve,
because crossings are interpolated rather than looked up among the samples —
this is why §4.1's interpolation rule is not an optimisation.

**8.4 A shallow excursion mid-window.** Two windows, one run, one summary
(§4.2). Do not merge in the predicate.

**8.5 A local max that never crosses zero.** An extremes finder will hand you a
local maximum in the middle of an ebb. That is the ebb weakening, not a turn,
and labelling it a max misdescribes the day. A flood max must be positive, an
ebb max negative — filter on sign, not on the extremum.

**8.6 Exact-zero samples.** Official series contain them. A zero preceded by a
nonzero sample *is* the crossing; a run of consecutive zeros is one crossing,
not several. Exclude exact zeros when picking a run's peak.

**8.7 Events scanned wider than the series drawn.** Events are typically scanned
with a pad beyond the visible window while the drawn points are clipped to it. A
padded crossing can then walk the series' trailing sub-threshold run and return
a window lying entirely before itself. A crossing outside the sampled series has
no measurable window; return nothing.

**8.8 A prediction API that snaps to a grid.** A point-query API may snap to a
coarse grid, so sampling it in a loop returns a staircase — and scanning a
staircase for turning points invents an extreme at every plateau edge. Use the
predictor's own timeline API.

**8.9 Two charts on one page.** Shared element ids across two instances (a phone
layout and a desktop one, one hidden) make the second reference the first's
definitions, which sit in a hidden subtree and paint nothing. **The stroke
survives and the fill silently vanishes**, which is why this is found late. Ids
are per-instance.

**8.10 Luminance masks.** An SVG mask reveals with white and hides with black.
Black stops in a fade mask erase the curve.

---

## 9. When magnitude is unknown

**Never invent a number.**

A derived gate knows slack **times** — a reference port's high or low water plus
a lag, often from cruising consensus rather than a published current prediction
— and knows a flood/ebb **phase**. It does not know speed.

On a derived gate:

- The curve is **schematic**: a ±1 shape meaning "flood, then ebb", drawn in a
  **neutral** colour with the ramp **off**. Running a ±1 shape through a speed
  scale renders a one-knot gate — a number nobody measured. Colour is state, and
  the state of this curve's magnitude is *unknown*; the neutral fill is the
  honest encoding.
- **No speed labels, no threshold lines, no window.** A window is defined in
  knots; without knots there is no window, and drawing one would invent the
  number by implication.
- **Slack instants draw as hairlines** — the one case where the instant is the
  mark, because it is all that is known (§5.3).
- **No set arrow.** The gate knows timing and nothing about set; inventing a
  bearing is the schematic-curve mistake in glyph form. Fall back to a mark that
  claims only phase.
- The readout says **slack timing**, not a speed.
- A gate whose accuracy fails validation is **absent, not broken-looking**.
  Shipping a bad prediction with a caveat is worse than shipping nothing.

**Online gates** — real official predictions fetched on demand — are a third
case. Events come from scanning the fetched series rather than a harmonic model.
Everything in §3–§8 applies unchanged; only provenance differs.

---

## 10. Rotary stations

At an open-water station the set sweeps through 360° over a cycle rather than
reversing between two bearings. **A signed scalar along a flood axis is not a
simplification there, it is false** — there is no axis, and "negative" names
nothing.

A rotary station must not be rendered with the rectilinear chart. The candidate
form is a hodograph or an hourly-arrow ring, where the shape of the sweep is the
reading.

*Open: which form, and how the threshold and window concepts translate — "under
0.5 kn" still means something at a rotary station, but "the sign reverses inside
it" does not.* Until this is answered, a rotary station is better shown as a
table than as a chart that implies an axis it does not have.

---

## 11. Confidence

Prediction quality is not uniform: bundled harmonic models, on-demand official
fetches, and offset-derived timings are three different levels of certainty, and
certainty also degrades the further out in time the reader scrubs.

**This must not become a badge.** A badge is a label the reader learns to
ignore, and it makes confidence a property of the station rather than of the
moment being read — which is wrong, because the same station is more certain
tomorrow than in six weeks.

The intent is that **the chart itself gets harder to see** as confidence drops:
fog, desaturation, a softening curve, a widening band. Recorded here explicitly
so that it does not get flattened back into a badge by default.

*Open: which cue reads as "less certain" without reading as "broken."*

---

## 12. Tide pairing

The model is **current-led, tide-paired**. Current is the hero; a paired tide
track is reference.

- The paired tide must come from a **reference station that is honestly nearby
  and relevant**, carried as a data-layer field, and **named as a different
  place**. Never synthesise a co-located tide curve from the current model. A
  faked co-located curve is convincing precisely because it comes from one model
  — and that is the problem.
- **Fallback: current-only.** Where no honest association exists, drop the tide
  track rather than inventing one, and link out to nearby tide information
  instead.
- A scrubber scrubs **one track**. Sharing a time axis is the point of pairing;
  sharing a scrubber is what made both tracks crowded.

---

## 13. The table, and accessibility

**Every chart has a table behind it.** The events table is the trust anchor and
the primary accessibility path: plain rows of slack, max flood and max ebb with
times and speeds. It is where absolute clock times belong (§5.5), and it is what
a reader falls back to when they do not trust the drawing.

- Every chart carries a spoken description: the station, what the next event is,
  and its **dated** time. A bare `hh:mm` leaves a reader unable to tell which
  day.
- The description must be true on **every rendering path**. "Computed from
  harmonic constituents" is true everywhere; "computed on this device" is false
  the moment the same markup is prerendered.
- **A prerendered chart must not make claims about the present.** A countdown
  against a build-time clock is a reading that is days old and drifting, in the
  one place a reader without scripting sees it. Relative time requires a live
  clock; without one, state the absolute time.
- Times and speeds use tabular figures, so a scanned column does not jitter.
- The shareable unit is **the window**, not "the tide" — a transit opportunity is
  the thing a crew puts in a calendar.

---

## 14. Executable invariants

The rules above that can be tested should be, because most of them have already
regressed once. Minimum set:

- Two series with different peak speeds produce **different fill colours at their
  peaks**. This is the assertion that fails if auto-fitting is ever reintroduced
  into colour (§6.2).
- **No ramp stop is green-dominant** (§6.3).
- **Ramp luminance is monotonic** across sampled positions (§6.3).
- Label ink on the fill clears its contrast floor **at the ramp's worst point**,
  not at a convenient one (§6.6).
- The go colour resolves from the **shared window predicate** on every surface
  that shows it (§6.1).
- A schematic series yields **no windows and no speed marks** (§9).
- **Source-text tripwires** for retired colour literals and for direction colours
  inside the current-drawing path. These catch the actual failure mode — a
  literal creeping back in — which a rendered-colour test does not.

---

## 15. Low-resolution surfaces: the list card and the widget

A card in the list and a medium widget are the same drawing at about a
sixth of the detail's width, with no scrubber and no axis. They keep the
thesis of §1 — *can I go, and when* without reading a speed — and drop
every mark that only earns its place at scale. The card and the widget are
**identical**: the widget is the card, rendered on the home screen.

### 15.1 What the curve shows

- **One swing back, three ahead.** Half the M2 period per swing (≈6.2 h);
  the past faded, the forecast at full strength, a white dot at now.
- **The window is the only window mark.** The run is drawn on the line in
  the go colour (§5.2), from the SHARED window predicate (§6.1). The
  threshold lines are dropped: their job — letting the reader see the margin
  and overrule the chart (§4.3) — belongs to the detail, one tap away.
- **The window's edges get the dots** (§5.4.1): the opening at full
  strength while it is ahead, the closing at half; inside the window they
  swap. Nothing else on a current curve gets a dot.
- **Peaks are context** (§5.4): the speed, no unit, and the set arrow hang
  off the peak inside its lobe. Values near the curve never carry a unit —
  the reading in the top-right corner states the unit once.
- **Absolute times have one home** (§5.5): a single row under the curve,
  one time per run at its opening. Peak times are not shown; they are in
  the schedule behind the detail.
- **Colour is state** (§6): the go colour for the run and its dots, the
  speed ramp for the fill above the threshold where the fill is drawn, and
  nothing coloured by direction.

### 15.2 The reading

The top-right reading is the surface's readout: the speed with its unit,
and under it the set — the phase word, the cardinal and the bearing arrow
by the sign of the velocity. Inside a window the word is *Slack* in the go
colour and the set still shows; under 0.05 kn the set gives way to a
neutral mark of the same footprint so the header never changes size. No
pill: a pill states a phase without a speed or a set, which is two of the
three things the reader came for.

### 15.3 Counting down

A surface that is refreshed on a clock — the widget — counts. Inside a
window the reading's first line becomes a timer to the window's closing,
minutes and seconds, or *> 2 hrs* beyond two hours, because inside the
window the question has changed to *how long do I have* (§5.4.1). The list
card, which the reader is looking at rather than glancing at, keeps the
speed; the countdown is one tap away in the detail readout.

### 15.4 Tides on the same surface

A tide card draws its turns with a dot, the height (no unit) and a to-bar
arrow hanging off the turn toward the plot middle, and every turn's time on
the bottom row. It follows the geometry of §15.1, not its thesis: on a tide
the turns *are* the events (§1).

