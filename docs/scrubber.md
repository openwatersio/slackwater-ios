# Slackwater scrubber — living product specification

Status: normative, living document

This document defines the Slackwater detail scrubber as a product and interaction
contract. It is the source of truth for reimplementing the scrubber on iOS,
Android, and the web. Platform code may use different scrolling, drawing, and
animation APIs, but a person should perceive the same control and get the same
answer from it.

The current iOS implementation is the reference implementation. Exact iOS values
are recorded here as reference tokens so another implementation can reproduce the
same rhythm. Requirements use **must**, recommendations use **should**, and iOS
implementation details are labelled as such.

`docs/current-charts.md` remains the deeper domain specification for the meaning
of a tidal-current chart. This document wins for the scrubber's composition,
motion, and visible marks if an older design note disagrees with it.

## 1. Scope

The scrubber is the complete, time-linked composition containing:

1. the lead reading above the graph;
2. the commentary pill and conditional Now pill;
3. the fixed reading line and riding dot;
4. one horizontally moving tide or current graph;
5. graph-owned event times, day labels, dates, sunrise and sunset marks, and
   eclipse mark; and
6. the sky backdrop behind the lead and graph.

The following are deliberately outside this specification because they are
separate surfaces or are under active development:

- the multi-day event list or schedule;
- day disclosure and list-row highlighting;
- the week-range bar and date picker;
- range, next-maximum, and Moon summary tiles;
- station header, favourite control, navigation, provenance, and related-station
  links; and
- loading, download, and error cards shown instead of the scrubber.

Those surfaces may set the selected time, but they do not define how the scrubber
works. A later spec may define their relationship without changing this control.

## 2. Product idea

The scrubber is a continuous timeline moving beneath a stationary reader.

The vertical reading line is fixed at the exact horizontal centre of the
viewport. The graph, event annotations, clock times, and day chrome move together
under it. The instant beneath that line is the selected time. The lead reading,
sky, riding dot, and direct controls all describe that same instant.

This is intentionally the reverse of a conventional slider:

- there is no thumb travelling across a fixed track;
- the selected time never moves away from the visual centre;
- dragging the content left advances time;
- dragging the content right moves into history; and
- momentum belongs to the timeline, not to a detached handle.

The model gives one invariant that every implementation must preserve:

> The graph point beneath the centreline, the lead reading, the displayed clock,
> the sky, and the exposed accessibility value always represent one selected
> instant.

The control shows exactly one water track. A tide detail scrubs tide. A measured
or online-current detail scrubs current. A derived gate scrubs a schematic current
phase. Tide and current must never share one scrubber.

## 3. Conceptual anatomy

The fixed and moving layers are distinct:

```text
FIXED TO VIEWPORT

                 state + direction
                   large reading
                    local time

 [Now when needed]  [commentary]  [Now when needed]
                         │
                         │ fixed reading line
                         ● riding dot

MOVES HORIZONTALLY AS ONE CONTINUOUS STRIP

  event labels ─────── curve ─────── event labels
  absolute event times
  sunrise / day + date / sunset
```

Only one Now pill is ever present. It occupies the side toward which “now” lies;
the two positions above illustrate the alternatives.

The layers, back to front, are:

1. the time-dependent sky;
2. opaque water ground under the curve;
3. tide/current fill and daylight/night shading;
4. reference line, curve, event runs, labels, and the absolute-now dot;
5. day and celestial chrome;
6. the fixed reading line and riding dot;
7. lead reading; and
8. glass pills.

The sky, graph, and overlay form one visual scene even when a platform renders
them with separate views.

## 4. Time model

### 4.1 Three different times

An implementation must keep these concepts separate:

| Name | Meaning | What it drives |
|---|---|---|
| `anchor` | Station-local midnight around which the loaded window is built | Window geometry and day metadata |
| `now` | The live reference instant captured for this scrubber session | Opening destination, past/future treatment, absolute-now dot, and Now pill |
| `selectedTime` | The instant under the fixed centreline | Lead, sky, riding dot, commentary, and accessible value |

The reference implementation samples `now` when the detail opens and again when
the person activates Now. It does not need to move the reference beneath a person
who is actively planning. A platform may refresh it while idle, but it must never
allow that refresh to move `selectedTime` or the strip unexpectedly.

All visible civil-time language uses the station's time zone, never the device's
time zone. Horizontal geometry uses elapsed time. A daylight-saving transition
therefore produces a 23- or 25-hour civil day while the curve remains continuous.

Anything meaning “calendar day,” “midnight,” or “noon” must use a calendar in the
station's time zone. It must not be implemented as a multiple of 86,400 seconds.

### 4.2 Loaded window

The reference window is a fixed 228 elapsed hours:

```text
windowStart = anchor - 48 hours
windowEnd   = anchor + 180 hours
duration    = 228 hours
```

The extra time at each side lets useful instants sit beneath the centreline
without exposing blank space. A host that replaces this window must retain the
same centreability property: every advertised target needs at least half a
viewport of valid content on both sides, or explicit equivalent insets.

The scrubber must not render a partially covered data window as if it were
complete. Missing coverage is a loading or honesty-state concern outside this
component.

### 4.3 Horizontal mapping

Use a constant horizontal scale across the entire strip:

```text
pointsPerHour = 18 logical units
x(time)       = elapsedHours(windowStart, time) * pointsPerHour
time(x)       = windowStart + (x / pointsPerHour) hours
selectedTime  = time(scrollOffset + viewportWidth / 2)
```

One logical unit means one iOS point, one Android density-independent pixel, or
one CSS pixel before device-pixel scaling. The 18-unit reference makes a 390-unit
phone show about 21.7 hours at once and produces a 4,104-unit strip.

The mapping and its inverse must round-trip. Rendering may quantize an offset to
a device pixel, but the displayed reading must be derived from the resulting
centre position rather than from the requested offset.

## 5. Reference geometry and type

These are the current iOS logical-unit values. Preserve them on phone-sized
surfaces. A wider surface may reveal more time; it must not stretch the time
scale or move the selected time away from centre.

| Token | Value | Purpose |
|---|---:|---|
| `pointsPerHour` | 18 | Horizontal time scale |
| `topPad` | 160 | Clear scene for lead and pills |
| `pillTop` | 124 | Top of the pill row (`topPad - 36`) |
| `plotTop` | 170 | Top of tide/current plot |
| `plotBottom` | 320 | Bottom of tide/current plot |
| `eventTimeY` | 338 | Absolute event-time row |
| `dayY` | 364 | Day names and sunrise/sunset times |
| `dateY` | 381 | Calendar date under the day name |
| `sunDotY` | 378 | Sunrise/sunset dots and eclipse glyph |
| `stripHeight` | 396 | Bottom of graph-owned chrome plus margin |

The fixed reading line begins at `topPad` and ends at `plotBottom`. The lead is
centred on the viewport centreline and overlaid in the top pad; it does not
consume horizontal strip width.

Reference typography:

| Content | iOS reference |
|---|---|
| Lead value | 44, medium, rounded, tabular digits |
| Lead unit | title level 2, light |
| Lead state | footnote, semibold |
| Lead time | caption, tabular digits |
| Pill text | caption, semibold, tabular digits |
| Turn/peak value | 18, semibold, tabular digits |
| Event time | 12, medium, tabular digits |
| Day name | 13, semibold |
| Date | 10, medium, monospaced |
| Sunrise/sunset time | 11, medium, monospaced |
| Eclipse glyph | 6.5 |

Graph labels stay fixed to graph geometry rather than scaling independently.
The lead and interactive controls must participate in the platform's accessible
text sizing; see §18 for the current iOS gaps.

## 6. State and motion

### 6.1 States

The scrubber has six observable motion states:

| State | Selected-time source | Pills | Snap allowed |
|---|---|---|---|
| Initial positioning | Initial input | Hidden | No |
| Opening motion | Animation frame | Hidden | No |
| Direct drag | Finger/pointer offset | Hidden or inert | No |
| Momentum | Native scroll physics | Hidden or inert | At final rest |
| Programmatic settle | Animated target offset | Hidden or inert | Target already chosen |
| Resting | Final centre offset | Visible after settle rule | No further automatic movement |

The state names are conceptual. A platform does not need an enum if its native
scroll APIs already expose the same transitions.

### 6.2 Opening

On an ordinary opening at now:

1. Position the centreline at `now - 2 hours`.
2. Move linearly through time to `now` over 650 ms.
3. Recompute the selected time, lead, riding dot, and sky on every display frame.
4. Finish exactly on `now`, not merely near it.

The motion is an affordance: it teaches that the graph moves beneath a fixed
reader without adding instructional copy.

The opening is one-shot. If the initial selection is an explicit historical or
future instant, centre that instant directly and do not replay the opening. If a
person touches the scrubber during the opening, cancel it immediately and leave
the graph exactly where they grabbed it.

With Reduce Motion enabled, skip the opening motion and land directly on now.

### 6.3 Direct manipulation and momentum

The graph must track a horizontal drag one-to-one:

- content moving left selects a later time;
- content moving right selects an earlier time;
- `selectedTime` updates during the drag, not only when it ends;
- the lead, sky, and riding dot update in the same rendered frame; and
- releasing with velocity continues with the platform's native-feeling
  horizontal momentum.

The full strip height is the direct-manipulation surface. There is no separate
grab handle and no visible native scrollbar. A tap on otherwise empty graph
space does not jump the selected time. Pinch zoom and variable time scale are
not part of this control; horizontal scale remains 18 logical units/hour.

The scrubber commonly sits inside a vertically scrolling page. Use native gesture
arbitration or directional locking so a clearly vertical gesture scrolls the page
and a clearly horizontal gesture scrubs time. Do not add a full-screen drag
recognizer that steals vertical navigation or an edge-back gesture.

There is no haptic tick for ordinary samples or magnetic targets in the reference
behavior.

### 6.4 Rest and pill visibility

A rest begins after `selectedTime` has not changed for 450 ms. In the reference
appearance, the pills and the conditional reading line then fade in over 200 ms.
Any new selected-time change hides them and disables their hit testing
immediately.

The riding dot and lead never disappear during movement. Those are the feedback
that makes direct manipulation legible.

When Reduce Motion is enabled, do not animate pill opacity. Controls should remain
visible where space permits; if an implementation suppresses them during active
movement, restore them immediately at rest.

## 7. Magnetic settling

The magnet runs only after a person-driven scroll comes fully to rest:

- immediately after a drag that has no momentum; or
- after momentum finishes.

It does not pull during a drag, and it does not repeatedly quantize free
scrubbing.

Find the snap target whose x-coordinate is closest to the viewport centre. Snap
when its distance is strictly less than 46 logical units and greater than 0.5
logical units. At 18 units/hour, the capture radius is about 2 h 33 m. A target
already within half a logical unit is treated as already parked. If two targets
are exactly equidistant, choose the earlier one for deterministic behavior.

The reference target set is the sorted, de-duplicated union of all applicable
in-window moments:

- tide high and low extrema;
- the fastest-rate instant of each tide run that reaches the rate-warning scale;
- current maxima and slack instants;
- measured slack-window openings and closings;
- sunrise and sunset;
- every contact of a visible lunar eclipse; and
- derived-gate slack instants.

Animate a magnetic settle with the platform's standard short scroll animation,
then assign `selectedTime` to the exact target when the animation completes. This
final assignment prevents interpolation or pixel rounding from leaving an event
readout a few seconds off its own time.

## 8. Programmatic movement and interruption

The direct scrubber controls may request an exact target. A direct-control target
is not subject to the 46-unit capture radius.

An animated request must:

1. cancel the opening motion;
2. stop any active momentum without first accepting another momentum frame;
3. cancel an in-progress magnetic animation and forget its old destination;
4. animate the requested target beneath the centreline; and
5. park `selectedTime` on the exact requested instant at completion.

A finger that is still down retains control. Do not fight an active drag with an
external state update.

Reduce Motion, a target less than 0.5 logical units away, or a non-visual restore
must land directly without animation.

When the viewport width changes—rotation, split screen, browser resize, or a
foldable posture change—recompute the offset so the existing `selectedTime`
remains under the new centreline. Cancel momentum or a magnetic settle if needed.
The resize must not change `selectedTime`, replay the opening, or briefly publish
the wrong centre value.

## 9. Fixed lead reading

The lead is the primary textual answer for the selected instant. It stays centred
above the graph and updates continuously while scrubbing.

Its anatomy is:

1. state word followed by a state/direction glyph;
2. one large value and a lighter unit, when magnitude is known; and
3. station-local selected clock time.

The state and value form one accessible reading. Visual time uses a twelve-hour
clock with no leading zero, lowercase `am`/`pm`, no space, and no periods—for
example `4:22pm`, `12:05pm`, and `12:36am`. Spoken time should follow platform
locale while retaining the station time zone and full date context.

### 9.1 Tide lead

The tide value is the engine-exact height at `selectedTime`, not the graph's
ten-minute interpolation. Format feet to one decimal or metres to two decimals;
strip negative zero.

Within one second of an extreme, the state is `High` or `Low` and uses the
corresponding to-bar glyph. Otherwise the state is `Rising` or `Falling`, inferred
from the next extreme, with a diagonal arrow.

State colour:

- high/rising uses the high teal for the glyph;
- low/falling uses the low amber for the glyph; and
- a fast-rate warning overrides the glyph with the magnitude-ramp colour.

### 9.2 Measured-current lead

The value is the absolute speed at `selectedTime`; the phase carries its sign.
Harmonic stations use an engine-exact value. Online sampled currents use linear
interpolation through the displayed series. Format all supported speed units to
one decimal and strip negative zero.

The state is:

- `Slack` while `selectedTime` lies in a measured slack window, including its
  opening but excluding its closing;
- `Slack` for an instantaneous magnitude below 0.15 kn when no measured window
  supplies the state;
- `Max flood` or `Max ebb` within one second of that maximum; or
- `Flooding` / `Ebbing` otherwise.

Outside slack, show a true-bearing arrow and one of 16 compass points for the set.
Positive velocity selects the station's flood bearing; negative velocity selects
its ebb bearing. In slack, use the opposed-arrows slack glyph instead of claiming
a set.

A provisional model prefixes numeric values and commentary events with `~` and
uses the attention colour for the value. Provenance is outside this spec.

### 9.3 Derived-gate lead

A derived gate knows phase and slack times but no speed or set bearing. Its lead
contains the state (`Flooding`, `Ebbing`, or `Slack`), a simple forward/back/slack
glyph, and selected time. It must not display a numeric value, unit, compass point,
or true-bearing arrow.

## 10. Commentary and Now pills

Both controls use compact, capsule-shaped translucent material with semibold,
tabular text. “Glass” describes the visual role—legible interactive chrome
floating above a changing sky—not a requirement to use an Apple-only material.

### 10.1 Commentary

The commentary pill is centred on the reading line. It names what is important
next and is also a command to move there.

Countdowns floor to whole minutes and never go below zero:

```text
under 60 minutes: 28m
60 minutes or more: 3h 28m
```

When the selected time is within one horizontal logical unit of now—200 seconds
at the reference scale—the phrase is reader-relative:

```text
High in 28m
Slack in 1h 12m
```

When farther away, it is selected-time-relative:

```text
High 3h 28m later
Max ebb 42m later
```

The commentary is absent when there is no applicable later target in the loaded
window.

#### Tide commentary

Ordinarily name the next extreme: `High …` or `Low …`.

When the absolute tide rate reaches 0.6 m/hour, commentary instead explains the
warm-coloured curve at the selected instant:

```text
Rising 0.60 m/hr
Falling 5.2 ft/hr
```

Tint this text with a lightened form of the rate-ramp colour. Activating it moves
to the closest fastest-rate point in the same rising/falling run, unless already
within one second of that point; from there it advances to the next extreme.

#### Current commentary

Walk strictly forward—more than one second after `selectedTime`—through these
significant stops:

1. a measured slack window opening, named `Slack`;
2. its closing, named `Flood` or `Ebb` from the velocity immediately after it;
3. `Max flood` and `Max ebb`; and
4. a bare slack instant when no measured window exists.

A window ending at the sampled series boundary has no measured closing and must
not invent one. Activating the pill moves to the stop it names. Once parked on a
stop, the pill names the following stop rather than pointing to itself.

A derived gate only walks to its next slack instant.

### 10.2 Now

Show Now only when:

```text
abs(selectedTime - now) > 1 / pointsPerHour hours
```

At the reference scale this is 200 seconds. The threshold is one visible unit:
smaller round-trip error means the centreline has not visibly moved.

The pill sits at the outer edge on the side where now lies:

- selected in the future: `← Now` on the left;
- selected in the past: `Now →` on the right.

The arrow is both instruction and spatial truth. Activating Now refreshes the
reference `now`, ensures its data window is active, and moves that instant beneath
the centreline. After landing, the pill disappears.

The Now request must win over momentum or a magnetic animation. A fling must
never swallow the tap.

## 11. Fixed centre overlay

The overlay is not part of the horizontally moving content.

The riding dot is always visible and always sits at:

```text
x = viewportWidth / 2
y = graphY(valueAt(selectedTime))
```

Use a white 13-unit dot with a four-unit glow for tide, and a white 10-unit dot
with a three-unit glow for current and derived current. The larger tide dot keeps
its presence against the more varied datum fill.

At rest, a one-unit white line at 18% opacity connects the pill row to the plot
floor. Show it only when commentary exists; the riding dot alone carries the
selection when there is no commentary. The line must not intercept input.

Do not confuse the riding dot with the graph's absolute-now dot:

- the riding dot is fixed to the viewport and marks `selectedTime`;
- the absolute-now dot is drawn into the moving graph and marks `now`; and
- the two coincide when the scrubber is home.

## 12. Shared graph rules

### 12.1 Samples and interpolation

The reference harmonic series is sampled every ten minutes. Official online
series may arrive every fifteen minutes. Draw a continuous polyline through the
samples and linearly interpolate the riding-dot position between them.

Prediction generation, event finding, slack-window calculation, sun/moon event
searches, and eclipse searches happen when the timeline is built—not on each
scrub frame. A scrub frame may interpolate values and calculate the current sky,
but must not rebuild the week.

### 12.2 Past and future

Split every curve stroke and overlaid run at the absolute-now x-coordinate:

- past stroke opacity: 35%;
- future stroke opacity: 100%; and
- past event-label opacity: 45%.

“Event label” here means a water turn/peak value or its axis time. Day names,
dates, sunrise/sunset chrome, and eclipse context do not fade merely because
their instant is in the past.

If now is before the window, all content is future. If now is after it, all
content is past.

Draw a seven-unit white absolute-now dot on the curve only when now lies inside
the loaded window. Punch a 2.5-unit clear halo beyond its edge so it remains
legible over fills and day/night shading.

### 12.3 Reference marks and labels

The base curve is 2.5 units wide with round caps and joins. Dashed reference lines
are one unit wide at 35% foam opacity with a `[1, 3]` dash pattern.

Turn and peak values hang 23 units toward the plot's vertical middle. The glyph
sits nearest the curve and the value beyond it. The reference gaps are eight
units for the glyph and seven for the value.

Absolute event times have one home: the event-time row beneath the plot. Sort
candidate times first. If the next label would be within 64 horizontal units of
the last retained label, keep the earlier label and omit the later one. The event
still exists and remains magnetic.

Do not draw turn or peak labels within 0.3 hours (18 minutes) of either strip
edge. Edge clipping makes a valid event look broken.

### 12.4 Colour tokens

These sRGB values are the portable reference palette:

| Role | Hex | Meaning |
|---|---|---|
| Deep ink | `#00183C` | Text over a light sky |
| Canvas | `#05122A` | Water/page ground |
| Foam | `#E4F0E4` | Primary light ink |
| Graph line | `#38BDF8` | Base water curve |
| High | `#2DD4BF` | Tide high |
| Low | `#FBBF24` | Tide low |
| Go | `#88B868` | A measured slack-window run, or a known bare slack instant when no duration can be measured |
| Neutral unknown | `#5888A8` | Schematic magnitude |
| Sun | `#F0C860` | Sunrise/sunset dot |
| Sunrise label | `#F0D890` | Sunrise time |
| Sunset label | `#C8A86A` | Sunset time |
| Night | `#00101F` | Night shading |
| Attention | `#EF6F4A` | Provisional or exceptional state, not alarm |
| Eclipse umbra | `#6B2A18` | Eclipse-only copper |

Green is reserved for slack evidence: a measured, sign-reversing slack window
and its direct state, or a known slack instant when no duration can honestly be
measured. It must not identify a station type, rising tide, weak water without a
reversal, or generic success.

The magnitude ramp contains no green:

| Normalized position | Hex | Physical anchor |
|---:|---|---:|
| 0 | `#F5C96B` | 0.5 kn current / 0.6 m/hr tide rate |
| 1/3 | `#F5C96B` | 3 kn / 1.0 m/hr |
| 2/3 | `#E8763C` | 8 kn / 1.5 m/hr |
| 1 | `#C93A32` | 12 kn / 1.8 m/hr |

Interpolate piecewise in sRGB and clamp beyond the ends. Geometry auto-fits per
station; magnitude colour remains absolute so equal speeds mean equal colours.

## 13. Track variants

### 13.1 Tide

Fit the full loaded tide series vertically around its midpoint. Use half the
series range multiplied by 1.06 as the padded half-span, with a nonzero floor to
avoid degenerate geometry.

Draw in this order:

1. opaque canvas colour from the curve to the plot floor;
2. a datum-anchored fill clipped to the plot;
3. daylight/night shading clipped beneath the curve;
4. a dashed chart-datum line when zero lies inside the fitted span;
5. the rate-coloured curve;
6. high/low marks and hanging readings;
7. absolute event times; and
8. the absolute-now dot.

The datum fill is graph blue at 50% at the top, fading to clear at chart datum.
Below datum, low amber fades from clear at datum to 50% at the bottom. If the
week never reaches datum, finish the blue fade at the lowest visible trough and
do not invent an amber region.

The tide curve is base graph blue while `abs(rate) < 0.6 m/hr`. At and above
that floor it follows the absolute rate ramp in §12.4. The past/future opacity
split applies on top of the gradient.

Each high or low gets:

- a five-unit diameter dot with a 2.5-unit clear outer halo;
- high teal or low amber;
- its height without a unit, since the lead owns the unit;
- a to-bar glyph—`⤒` for high, `⤓` for low—nearest the dot; and
- its local time in the event-time row.

The arrow-to-bar means “arrives and stops.” A plain up arrow must not label a
high, because rising is precisely what has ended.

### 13.2 Measured current

Fit symmetrically around zero using the largest absolute speed in the loaded
series multiplied by 1.05. The zero line stays at the vertical middle so equal
flood and ebb magnitudes occupy equal heights.

Draw in this order:

1. opaque canvas colour from the curve to the plot floor;
2. a zero-anchored blue fill;
3. daylight/night shading beneath the curve;
4. the dashed zero reference line;
5. the base curve and its magnitude thread;
6. measured slack runs;
7. bare-slack hairlines and peak readings;
8. run-opening/bare-slack times; and
9. the absolute-now dot.

The current fill is clear at zero and reaches 50% graph blue toward both vertical
extremes. It does not encode flood versus ebb; y-position and bearing labels do.

Draw the curve in graph blue at 2.5 units. Down its middle, draw a two-unit
absolute-speed thread:

- invisible below 0.5 kn;
- yellow fading from transparent at 0.5 kn to opaque at 3 kn;
- yellow through orange between 3 and 8 kn; and
- orange through red between 8 and 12 kn, clamped red above 12 kn.

A measured slack window is the interval where absolute speed is at or below the
configured threshold and a sign reversal occurs inside the interval. Interpolate
its threshold crossings from adjacent samples. Merge touching or overlapping
visual windows into one run. Draw the curve itself in the go colour across that
run at 3.5 units—slightly wider than the base curve. Do not add endpoint dots or
an area band.

Where a slack instant has no measurable window, draw a one-unit go-colour
hairline from plot top to plot bottom at 35% opacity. A zero-width run must never
look like a usable duration.

Current maxima are context, not destinations:

- no peak dot;
- hang the absolute speed, without unit, toward the zero line;
- place a true-bearing set arrow nearest the curve; and
- use foam rather than flood/ebb hue for both value and arrow.

The event-time row contains each merged slack run's opening and every bare slack
instant. It does not contain current-maximum times. Those maxima remain magnetic
even though their exact time is not printed on the graph.

### 13.3 Schematic derived current

A derived gate uses the current geometry but represents phase only:

- draw the normalized ±1 shape with a flat neutral fill at 32% opacity;
- keep the base blue curve and past/future split;
- draw a dashed zero line;
- draw known slack instants as go-colour hairlines;
- omit the magnitude thread, speed values, set arrows, slack windows, and green
  runs; and
- expose no numeric value in the lead.

The normalized vertical shape must never be passed through the speed ramp. Doing
so would falsely claim a measured one-knot current.

## 14. Day, sun, eclipse, and sky

The day/celestial layer moves with the graph. It provides calendar and light
context without breaking the continuous timeline into pages.

For every civil day touched by the window:

- centre `Today`, `Tomorrow`, `Yesterday`, or the short weekday at station-local
  noon;
- place `MMM d` beneath it;
- draw sunrise as `↑5:24am` in sunrise ink at its true x-coordinate;
- draw sunset as `↓7:53pm` in sunset ink at its true x-coordinate; and
- place a seven-unit sun dot beneath each time.

Sunrise/sunset events are computed for the station coordinate and civil-day
bounds. A polar day may lack either event; omit missing marks without inventing a
time.

Night shading spans each sunset to the following sunrise; daylight tint spans
sunrise to sunset. Each edge fades across 0.75 hour on both sides. Shade is
clipped beneath the curve, stays full through the upper 35% of the water region,
and fades vertically to transparent at the bottom of the scrubber so it does not
end as a hard rectangle behind the time rows.

For an eclipse visible from the station, draw only a small `🌘` at greatest
eclipse on the sun-dot row. Do not add a text label or coloured band to the graph.
All eclipse contact times remain magnetic targets.

The backdrop behind the lead responds continuously to `selectedTime` and station
coordinates:

- interpolate sky colours from solar altitude;
- position sun and moon against their visible horizon spans;
- show the moon's illuminated limb and current eclipse shadow;
- reveal stars as the sky darkens; and
- switch foreground ink between light foam and deep navy for contrast.

The sky is non-interactive and accessibility-hidden. Under Reduce Motion, stars
must not twinkle; selected-time movement may still reposition the astronomical
scene because that change conveys time rather than decoration.

## 15. Accessibility and non-touch input

The intended scrubber must be usable without seeing or directly dragging the
canvas. Do not make the graph's internal decorative labels separate focus stops.

Expose one adjustable timeline control with:

- label: the track type and station context supplied by the host;
- value: full station-local date and time, lead state, magnitude/unit when known,
  and set when known;
- increment/decrement actions that move later/earlier by five minutes; and
- named actions for next and previous magnetic target when the platform supports
  custom actions.

The five-minute accessibility step is independent of device pixels and remains
usable at every viewport width. Every adjustment updates the same
`selectedTime` as touch input.

Expose commentary and Now as ordinary buttons with labels that include their
visible text. Their semantic hit targets must meet the platform minimum—44 by 44
points on iOS/web and 48 by 48 dp on Android—even when their visible capsule is
smaller.

The lead should be one combined announcement rather than separate state, value,
unit, and clock focus stops. Include the civil date and station time zone in
spoken output when crossing midnight; a bare `4:22pm` is ambiguous in a 228-hour
timeline.

Do not rely on colour alone:

- high/low have different to-bar glyphs;
- current direction has bearing arrows and compass text;
- slack is a wider run or hairline and is named in text;
- speed magnitude remains printed at maxima; and
- schematic magnitude is omitted rather than encoded only by colour.

With Reduce Motion:

- opening and programmatic travel land directly;
- decorative twinkle stops;
- pill opacity does not animate; and
- selected-time updates and the riding dot remain immediate.

Keyboard-capable web and Android implementations should map Left/Right to the
same five-minute decrement/increment, with logical direction unaffected by text
direction because the timeline itself is chronological left-to-right. Provide a
focus-visible treatment around the scrubber without moving its centreline.

## 16. Rendering and platform guidance

Use native scrolling physics where practical, with a custom-drawn continuous
strip inside it. The product contract depends on direct manipulation and
momentum, not on a particular widget class.

### iOS reference

The reference uses a horizontal `UIScrollView` hosting a tiled SwiftUI `Canvas`.
The scroll delegate publishes the centre time during every offset update. A
fixed SwiftUI overlay draws the line and riding dot. A display-link drives the
opening so the selected time and sky follow every frame.

### Android

A Compose implementation can use horizontal scroll state plus `Canvas`, or a
custom scrollable modifier backed by native fling behavior. Derive selected time
from the settled and in-flight offset; do not animate only the canvas transform
while leaving semantic state behind. Use dp for logical geometry and px only at
the drawing boundary.

### Web

Prefer a native horizontal scroll container or equally native-feeling pointer +
inertia implementation. Read `scrollLeft` on animation frames and derive the
selected time from the viewport centre. Canvas or SVG are both valid; keep lead,
pills, and accessible control semantics in the DOM. Disable browser text
selection and image dragging only inside the direct-manipulation surface.

### Long-surface limits

The reference strip is 4,104 logical units wide and exceeds a single 8,192-pixel
texture on a 3× display. iOS divides it into 900-unit tiles, translates each tile
into strip coordinates, and clips before drawing.

Other platforms may tile, window, or draw vector content directly. They must not
allocate one oversized bitmap and silently lose the graph on high-density
screens. Tile boundaries must land on device pixels and must not change the time
mapping or create visible seams.

## 17. Conformance scenarios

These scenarios define the minimum behavior shared by all platforms.

### Opening and manipulation

1. **Ordinary opening:** Given a complete current window and Reduce Motion off,
   opening starts two hours behind now, reaches now in 650 ms, and ends with the
   lead time equal to the centre time.
2. **Interrupted opening:** Touching during the opening cancels it; the next drag
   begins from the touched position without jumping to now.
3. **First drag:** The first drag after opening changes the lead and riding dot
   during the gesture, before release or snap.
4. **Direction:** Dragging content left advances selected time; dragging it right
   moves selected time backward.
5. **Momentum:** A flick continues natively, updates the lead during motion, then
   evaluates the magnet once.

### Snapping and commands

6. **Near target:** Resting 30 units from a tide extreme animates to its exact
   instant.
7. **Outside capture:** Resting 46 or more units from every target remains where
   released.
8. **Already parked:** Resting within 0.5 unit of a target starts no redundant
   animation.
9. **Commentary during fling:** Activating commentary stops the fling and lands on
   the named target; no later momentum frame overwrites the request.
10. **Now during settle:** Activating Now cancels a magnetic animation, refreshes
    now, lands home, and removes the Now pill.
11. **Reduce Motion:** Opening, commentary, and Now land directly with no travel
    or opacity animation.

### Geometry and time

12. **Resize:** Rotate or resize after scrubbing. The lead time and centre time
    remain equal and unchanged.
13. **Cross midnight:** Scrubbing continuously across midnight changes the day
    chrome without discontinuity or a page transition.
14. **DST:** On a transition week, the civil day occupies 23 or 25 hours at the
    same 18-unit/hour scale; sunrise, sunset, and noon remain correct locally.
15. **Window edge:** No event label is clipped at an edge, and no direct control
    advertises a target that cannot be centred over valid data.

### Track meaning

16. **Tide turn:** At an exact high, the lead says High, the high dot sits beneath
    its hanging reading, and the commentary advances to the following event.
17. **Fast tide:** At 0.6 m/hr or faster, the line and commentary share the same
    ramp position and activating commentary goes to that run's fastest point.
18. **Measured slack window:** The curve is green only across interpolated window
    edges; the lead says Slack at the opening and changes phase at the half-open
    closing.
19. **Bare slack:** A sampled current with no measurable sub-threshold window
    draws a hairline, not a green duration.
20. **Different current peaks:** Equal speeds have equal thread colours across
    stations; a 6 kn and 12 kn peak do not both become local “maximum red.”
21. **Derived gate:** The lead has no number or bearing, the shape has neutral
    fill and no speed thread, and only known slack instants get hairlines.
22. **Past/future:** A graph with now in view has a 35%-opacity past stroke and
    full-strength future stroke split exactly at the moving absolute-now dot.

### Accessibility

23. **Adjustable value:** A non-touch increment changes selected time by five
    minutes and announces a dated, station-local lead value.
24. **Direct controls:** Commentary and Now meet semantic target sizes and expose
    their visible meaning without requiring the canvas labels.
25. **No-colour reading:** High/low, current direction, slack, magnitude, and
    schematic unknown remain distinguishable in greyscale.

## 18. Known iOS deviations from the intended contract

These are implementation gaps, not behavior to copy to another platform:

- The graph canvas is not itself an adjustable accessibility control. The iOS app
  currently relies on its lead, direct buttons, scroll-view clock value, and the
  separate event list as the accessible path.
- The scroll view's exposed value is only the selected clock, not a full dated
  state/value announcement.
- Visible pill capsules are about 30 points tall and do not yet provide an
  explicit 44-by-44 semantic target.
- Pill settle fading currently runs under Reduce Motion.
- The lead's 44-point value sits inside fixed 160-point geometry rather than
  growing the geometry with accessible text sizes.
- Long commentary can compete with the Now pill at large text sizes.

Fixing one of these should update this section and add or amend a conformance
scenario. Do not weaken the cross-platform contract to preserve an iOS gap.

## 19. Reference implementation map

The living implementation is split by responsibility:

| Concern | iOS source |
|---|---|
| Window, data, geometry, canvas, scroll host, magnet, overlay, celestial chrome | `Slackwater/TimelineStrip.swift` |
| Shared current lead and direct commentary walk | `Slackwater/CurrentLead.swift` |
| Tide lead and fast-rate commentary | `Slackwater/TideDetailView.swift` |
| Derived phase-only lead | `Slackwater/DerivedGateDetailView.swift` |
| Online sampled-current binding | `Slackwater/OnlineGateDetailView.swift` |
| Lead, commentary pill, sky state/backdrop, clock formatting | `Slackwater/Theme.swift`, `Slackwater/Palette.swift` |
| Shared strokes, fills, dots, runs, and hanging labels | `Slackwater/CurveDrawing.swift` |
| Measured slack-window predicate and merging | `Slackwater/SlackWindow.swift` |
| Tide-rate targets | `Slackwater/TideMovement.swift` |
| Pure behavior checks | `SlackwaterTests/TimelineTests.swift`, `SlackwaterTests/DetailLeadTests.swift` |
| End-to-end interaction checks | `SlackwaterUITests/DetailAndScrubTests.swift` |

Historical documents in `docs/superpowers/specs/` explain why individual
decisions changed. They are design history, not the current contract.

## 20. Maintaining this specification

Any user-visible scrubber change should update this file in the same change as
the reference implementation. At minimum, review all four consumers: tide,
harmonic current, online current, and derived gate.

When an implementation differs intentionally:

1. preserve the invariant in §2;
2. record the deviation and its reason here;
3. decide whether the platform is wrong or the shared contract should change;
4. add a conformance scenario for the decision; and
5. update other platforms from the shared decision, not by copying incidental
   framework behavior.

The shortest valid implementation is the one that uses native scrolling,
calendar, accessibility, and motion facilities while preserving this observable
contract.
