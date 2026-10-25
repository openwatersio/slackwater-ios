# Slackwater scrubber — living product specification

Status: normative, living document

This document defines the Slackwater detail scrubber as a product and interaction contract. It is the source of truth for reimplementing the scrubber on iOS, Android, and the web. Platform code may use different scrolling, drawing, and animation APIs, but a person should perceive the same control and get the same answer from it.

The current iOS implementation is the reference implementation. Exact iOS values are recorded here as reference tokens so another implementation can reproduce the same rhythm. Requirements use **must**, recommendations use **should**, and iOS implementation details are labelled as such.

[`current-charts.md`](current-charts.md) defines the domain rules for a tidal-current chart. This document wins for the scrubber's composition, motion, and visible marks if an older design note disagrees with it.

## 1. Scope

The scrubber is the complete, time-linked composition containing:

1. the lead reading above the graph;
2. the commentary pill and conditional Now pill;
3. the fixed reading line and riding dot;
4. one horizontally moving tide or current graph;
5. graph-owned event times, day labels, dates, sunrise and sunset marks, and eclipse mark; and
6. the sky backdrop, which starts at the top of the page behind the station header and lead, and runs down to the plot floor; it is shown only while a timeline exists.

The following are deliberately outside this specification because they are separate surfaces or are under active development:

- the multi-day event list or schedule;
- day disclosure and list-row highlighting;
- the week-range bar and date picker;
- range, next-maximum, and Moon summary tiles;
- station header, favourite control, navigation, provenance, and related-station links; and
- loading, download, and error cards shown instead of the scrubber.

This specification covers their selection handoff to the scrubber. Date taps open the picker. A picked day moves the selection to its station-local noon, unless the selection already lies inside `Timeline.window(anchor:)` for that day (48 hours before its midnight through 180 hours after), in which case it stays. Shared links and schedule-row and sheet jumps land on their exact instant. Each of these moves the strip by the rule in §8. The schedule follows a settled selection (§4.2). Their remaining layout and behavior are defined in [`detail.md`](detail.md).

## 2. Product idea

The scrubber is a continuous timeline moving beneath a stationary reader.

The vertical reading line is fixed at the exact horizontal centre of the viewport. The graph, event annotations, clock times, and day chrome move together under it. The instant beneath that line is the selected time. The lead reading, sky, riding dot, and direct controls all describe that same instant.

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

The control shows exactly one water track. A tide detail scrubs tide. A predicted-current detail (harmonic, subordinate, or fitted on the device) or an online-current detail scrubs current speed. A derived gate scrubs a schematic current phase. Tide and current must never share one scrubber.

## 3. Conceptual anatomy

The fixed and moving layers are distinct:

```text
FIXED TO VIEWPORT

                 state + direction
                   large reading
                    local date + time

 [Now when needed]  [commentary]  [Now when needed]
                         │
                         │ fixed reading line
                         ● riding dot

MOVES HORIZONTALLY AS ONE CONTINUOUS STRIP

  event labels ─────── curve ─────── event labels
  absolute event times
  sunrise / day + date / sunset
```

Only one Now pill is ever present. It occupies the side toward which “now” lies; the two positions above illustrate the alternatives.

A derived gate has no speed, so it omits the large reading; its state and glyph sit directly above the local date and time.

The riding dot is always shown. The reading line appears only while the strip is at rest and a commentary is showing (§11); after a press or the "Set an alert" action on a host with alerts, its extension below the plot shows until the selection moves to another minute (§6.5.1).

The layers, back to front, are:

1. the time-dependent sky;
2. opaque water ground under the curve;
3. tide/current fill and daylight/night shading;
4. reference line, curve, event runs, labels, and the absolute-now dot;
5. day and celestial chrome;
6. the fixed reading line and riding dot;
7. glass pills; and
8. lead reading.

The lead and the pill row occupy separate vertical bands and must not overlap.

The sky, graph, and overlay form one visual scene even when a platform renders them with separate views.

## 4. Time model

### 4.1 Three different times

An implementation must keep these concepts separate:

| Name | Meaning | What it drives |
|---|---|---|
| `anchor` | Station-local midnight of the schedule week | Schedule and day metadata; fixed-window geometry for online currents |
| `now` | The live reference instant captured for this scrubber session | Opening destination, past/future treatment, absolute-now dot, and Now pill |
| `selectedTime` | The instant under the fixed centreline | Lead, sky, riding dot, commentary, and accessible value |

The selection is home when it lies within 200 seconds (one logical unit at 18 units per hour) of `now`, and scrubbed away beyond that.

The reference implementation samples `now` when the detail opens, when Now is activated, and whenever the scene becomes active again, including after a brief inactive state such as Control Center or the app switcher. On foreground return, compare the selection with the old `now` using the 200-second home threshold. If it was home, refresh `now` and return the selection and schedule to the current instant using the ordinary Now movement. If it was scrubbed away, refresh only `now`; preserve the selected instant and planning position. Foreground return must not replay the opening motion.

`now` never advances on a timer while the view stays open. A long-open detail can show a slightly stale now marker; resampling on foreground return covers the real case.

Every detail takes the Today, Tomorrow, and Yesterday day labels from the session `now`, the same instant that places the absolute-now dot: each chunk publish and each fixed-window build labels its days from it. Refreshing `now` (Now, or a foreground return whether home or scrubbed away) relabels the days when the refreshed `now` falls on a different station-local day, so the labels and the now dot always agree.

The watch place page follows the same `now` sampling and settle re-anchor rules, counting a raised wrist as a foreground return. It opens directly on now, without the opening motion.

All visible civil-time language uses the station's time zone, never the device's time zone. Horizontal geometry uses elapsed time. A daylight-saving transition therefore produces a 23- or 25-hour civil day while the curve remains continuous.

Anything meaning “calendar day,” “midnight,” or “noon” must use a calendar in the station's time zone. It must not be implemented as a multiple of 86,400 seconds.

### 4.2 Loaded window and schedule

Constituent-backed tide and current details (harmonic, subordinate, or fitted on the device) and derived-gate details extend continuously in both directions. They compute seven-calendar-day chunks in the station's time zone and keep a sliding set around the selection. Scrolling across a chunk boundary must preserve the selected instant, momentum, samples, event marks, and day/night shading. A merged window must contain only contiguous data; missing chunks must never become a flat or fabricated curve.

The iOS reference prepares two chunks on each side of the selected chunk and ordinarily publishes at most three on each side. Appending on the right may happen during motion. Prepending or evicting on the left changes the coordinate origin, so it waits until dragging, momentum, the opening, every animated move (§8), and settling are quiet. Repeated backward flings can temporarily reach the loaded edge; the strip stops there until a quiet moment permits extension. Memory and mounted drawing surfaces remain bounded during ordinary settled use: iOS keeps the published chunks plus one each side, and mounts only the 900-unit drawing tiles in view plus one each side.

Chunks are counted in seven-day steps from the schedule anchor in force when the store starts, not from a calendar-week boundary: ordinarily the station-local midnight of the day the detail opened, the linked day when a shared link opens the detail outside today's window, and the current schedule anchor when a refined model or a new slack threshold rebuilds the store. The first build synchronously covers 48 hours either side of the opening instant. An explicit jump (picker, Now, or shared link) synchronously builds half a viewport either side of its target and publishes at once, without waiting for a quiet moment. When a publish moves the window's start, the strip first shifts its offset so the same instant stays under the centreline, then moves to the jump's target by §8.

A Canadian tide preview exists only when every gap between its downloaded samples is 30 minutes or less and every sample is finite; a single longer gap rejects the whole preview, which is never trimmed to a contiguous run. It must never extend, extrapolate, or offer a date outside those samples. A preview is shown only while its samples cover the current instant; its strip spans exactly those samples, its schedule stays anchored on today, and it never re-anchors on settle. The week bar and date taps offer no picker. Now and every selection are clamped into the samples.

The additional-download notice retains the station’s progress meter and available-through date while the remaining model downloads, centred below the scrubber and above the summary cards, and adds a reconnect, failure, or retry line as the download state requires. Its generic accuracy explanation is shared with current gates that already have usable early models; on a current gate the notice shows the provisional headline in amber instead of an available-through date. Download and status notices must never write over the scrubber. When the full tide model lands, the handoff waits until the strip is quiet, then starts the continuous store around the selected instant without navigating away or replaying the opening motion.

Official online-current details remain bounded by downloaded coverage. Their displayed window is defined by `Timeline.window(anchor:)`:

```text
windowStart = anchor - 48 hours
windowEnd   = anchor + 180 hours
duration    = 228 elapsed hours
```

The online detail only shows its scrubber when a stored block covers this whole window. Picking another week may require a fetch. Missing coverage uses the loading or honesty state, never extrapolated current values. The online detail never re-anchors on settle. Every selection stays within its fixed window: drags stop at its edges, and every programmatic move clamps to them (§8).

Every advertised target should have half a viewport of valid content on both sides. Continuous details meet this by building data around each target. The online window pads 12 hours past its schedule week, which is enough for a phone-width viewport. Where a viewport is wider than its window allows, including at either end of a Canadian tide preview, every programmatic move (§8) clamps to the content edge and shows the time actually under the centreline, never an unreachable target. Explicit picker and shared-link destinations must have their data ready before centring; a first build for a shared link uses the linked instant rather than the ordinary opening destination.

The schedule remains seven local calendar days anchored independently of the continuous strip. After a selection stays unchanged for 600 ms outside `Timeline.window(anchor:)`, the three continuous details re-anchor the schedule to the selected local day without moving the graph. The 48-hour look-back belongs to the existing anchor and does not trigger this re-anchor. Now restores the schedule to today's station-local midnight.

### 4.3 Horizontal mapping

Use a constant horizontal scale across the entire strip:

```text
pointsPerHour = 18 logical units
x(time)       = elapsedHours(windowStart, time) * pointsPerHour
time(x)       = windowStart + (x / pointsPerHour) hours
selectedTime  = time(scrollOffset + viewportWidth / 2)
```

One logical unit means one iOS point, one Android density-independent pixel, or one CSS pixel before device-pixel scaling. At 18 units/hour, a 390-unit phone shows about 21.7 hours. The online detail's 228-hour window is 4,104 units wide; continuous details use the current merged window's start and duration.

The mapping and its inverse must round-trip. During direct manipulation, the reading is derived from the actual centre position. When the strip settles on a stop or lands on an explicit target, the reading shows that stop's exact instant, even if rendering quantizes the offset by less than a device pixel; the accessibility value always reads the actual offset. The difference must stay under one logical unit.

## 5. Reference geometry and type

These are the current iOS logical-unit values. Preserve them on phone-sized surfaces. A wider surface may reveal more time; it must not stretch the time scale or move the selected time away from centre.

| Token | Value | Purpose |
|---|---:|---|
| `pointsPerHour` | 18 | Horizontal time scale |
| `topPad` | 160 | Clear scene for lead and pills; scales with the platform's large-title text size, and every row below moves with it |
| `pillTop` | 124 | Top of the pill row (`topPad - 36`) |
| `plotTop` | 170 | Top of tide/current plot |
| `plotBottom` | 320 | Bottom of tide/current plot |
| `eventTimeY` | 338 | Absolute event-time row |
| `dayY` | 364 | Day names and sunrise/sunset times |
| `dateY` | 381 | Calendar date under the day name |
| `sunDotY` | 378 | Sunrise/sunset dots and eclipse glyph |
| `stripHeight` | 396 | Bottom of graph-owned chrome plus margin |

The fixed reading line begins at `topPad` and ends at `plotBottom` (§11). The lead is centred on the viewport centreline and overlaid in the top pad; it does not consume horizontal strip width.

Reference typography:

| Content | iOS reference |
|---|---|
| Lead value | 44, medium, rounded, tabular digits, scaled with the large title |
| Lead unit | title level 2, light |
| Lead state | footnote; the word medium, its glyph and set point semibold |
| Lead time | caption, tabular digits |
| Pill text | caption, semibold, tabular digits, capped at the first accessibility size |
| Turn/peak value | 18, semibold, tabular digits |
| Event time | 12, medium, tabular digits |
| Day name | 13, semibold |
| Date | 10, medium, monospaced |
| Sunrise/sunset time | 11, medium, monospaced |
| Eclipse glyph | 6.5 |

Graph labels stay fixed to graph geometry rather than scaling independently. The lead and interactive controls participate in the platform's accessible text sizing: the lead value and `topPad` grow with the large title, and the pills stop growing at the first accessibility size.

The watch strip uses a top pad of 8 and a plot depth of 52, and ends 10 units below the event-time row; it draws no day, date, or sun row.

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

The state names are conceptual. A platform does not need an enum if its native scroll APIs already expose the same transitions.

### 6.2 Opening

On an ordinary opening at now:

1. Position the centreline at `now - 2 hours`.
2. Move linearly through time to `now` over 650 ms.
3. Recompute the selected time, lead, riding dot, and sky on every display frame.
4. Finish exactly on `now`, not merely near it.

The motion is an affordance: it teaches that the graph moves beneath a fixed reader without adding instructional copy.

The opening is one-shot. An initial selection within two seconds of `now - 2 hours` is the ordinary opening; any other initial selection, such as a linked moment or a picked week, is centred directly without the opening. A drag cancels the opening when panning starts, a tap when it is recognized at finger lift, and a press above the day row on a host with alerts (§6.5.1) when it is recognized after its half second; a touch-down alone does not. A host request (§8) cancels it too and moves to its own target. A drag continues from where the strip was grabbed, and a tap or press then acts as in §6.5. A press on the day row does nothing and leaves the opening running.

With Reduce Motion enabled, skip the opening motion and land directly on now. If publishing that selection must wait until layout completes, intervening view updates and resizes preserve the pending destination; a newer request or drag takes priority. The watch place page opens directly on now with no opening motion.

### 6.3 Direct manipulation and momentum

The graph must track a horizontal drag one-to-one:

- content moving left selects a later time;
- content moving right selects an earlier time;
- `selectedTime` updates during the drag, not only when it ends;
- the lead, sky, and riding dot update in the same rendered frame; and
- releasing with velocity continues with the platform's native-feeling horizontal momentum.

A loaded edge is a hard stop. A drag or fling stops there with no rubber-band overscroll, so the centre never passes the first or last loaded instant and the selected time never runs past the data. The magnet evaluates as usual when the strip comes to rest against an edge. The iOS reference turns off `UIScrollView`'s bounce and keeps its default deceleration rate.

The full strip height is the direct-manipulation surface, except, while the strip is at rest, where the commentary and Now pills sit; a drag, tap, or press that starts on a resting pill goes to the pill. The lead takes no touches, so a drag or tap that starts on its text reaches the strip beneath it. There is no separate grab handle and no visible native scrollbar. Taps select a time or open the date picker (§6.5). Pinch zoom and variable time scale are not part of this control; horizontal scale remains 18 logical units/hour.

The scrubber commonly sits inside a vertically scrolling page. Use native gesture arbitration or directional locking so a clearly vertical gesture scrolls the page and a clearly horizontal gesture scrubs time. Do not add a full-screen drag recognizer that steals vertical navigation or an edge-back gesture.

There is no haptic tick for ordinary samples or magnetic targets in the reference behavior. The watch is the exception: the Digital Crown's own per-detent ticks are off, and one light haptic plays when a settle moves onto a magnetic target, because a wrist has no finger on glass to feel the landing. A rest already within half a unit of a target takes its exact instant with no haptic.

### 6.4 Rest and pill visibility

A rest begins after `selectedTime` has not changed for 450 ms. In the reference appearance, the pills and the conditional reading line then fade in over 200 ms. Any new selected-time change disables their hit testing immediately and fades them out over the same 200 ms.

The riding dot and lead never disappear during movement. Those are the feedback that makes direct manipulation legible.

When Reduce Motion is enabled, the pills and line appear and disappear without animation. They are still hidden during movement and restored at rest after 450 ms, as without Reduce Motion.

### 6.5 Taps

A tap anywhere above the day row (the top pad, including the lead, outside the resting pills, the plot, or the event-time row) brings the tapped instant to the centreline. If a magnetic target is strictly within 4.5 units (15 minutes) of the tap, use the nearest target instead. Otherwise use the exact tapped time. The tap then moves the strip by §8: it clamps to a reachable scroll offset and derives the final selected instant from that offset, so the lead and curve agree at loaded edges.

In the day/date/sun row, a sunrise or sunset tap centres that event; a date tap opens the host's date picker. Where the host cannot change dates (a Canadian tide preview), a date tap stops motion and opens nothing. The iOS hit-test split is halfway between `eventTimeY` and `dayY` (351 units). Below it, the nearest sunrise, sunset, or date anchor wins; ties select the date. A date's anchor is where its label is drawn: the daylight midpoint, or station-local noon where the day has no daylight to centre on (§14).

Every tap stops opening motion, momentum, a ride, and an earlier settle before acting. Opening the date picker must stop motion even though it does not select another instant. A time tap rides to its target like any other programmatic move and marks the strip busy for the chunk store until it lands; Reduce Motion or travel below 0.5 unit lands directly.

#### 6.5.1 Press and hold

On a strip whose host can alert, a press held anywhere above the day row (the top pad, the plot, or the event-time row) resolves like a tap (the magnet within 4.5 units, else the exact instant), stops opening motion, momentum, and any settle, parks that instant on the centreline immediately with no settling animation, gives a medium haptic, and tells the host the strip was pressed. Like a tap, it clamps to a reachable offset and reads the parked instant back from it. The host's alert line under the strip names the parked moment, and the strip extends its reading line from the plot floor to the strip's bottom edge, toward that line (docs/alerts.md §7.1). The alert line keeps naming the parked moment, and the reading-line extension below the plot stays, after the finger lifts, until the selection moves to a different minute. The reading line above the plot still follows §11. A press on the day/date/sun row does nothing: that row belongs to the date picker's tap. The tap recognizer waits for the press to fail, so a press held and then lifted does not also scrub, and a press lifted before its half second is an ordinary tap with no added delay. VoiceOver reaches the same thing without a held gesture: the strip's custom actions carry "Set an alert" beside "Next event" and "Previous event", which hands the centreline moment to the host and opens its alert sheet in one step, since there is no line to go and find. Like a press, it also switches the alert line to the parked moment and extends the reading line below the plot until the selection moves to a different minute. Only a strip whose host can alert carries the press and the "Set an alert" action. On a host with nothing to alert on (an online gate, or a CHS tide station still in preview), the strip has neither: a held touch parks nothing and gives no haptic, and VoiceOver offers only "Next event" and "Previous event". A CHS tide preview gains both when its model lands, on the same strip.

## 7. Magnetic settling

The magnet runs only after a person-driven scroll comes fully to rest:

- immediately after a drag that has no momentum; or
- after momentum finishes.

It does not pull during a drag, and it does not repeatedly quantize free scrubbing.

Find the snap target whose x-coordinate is closest to the viewport centre. Snap when its distance is strictly less than 4.5 logical units. At 18 units/hour, the capture radius is 15 minutes: wide enough that a landing a hair off an event takes the event, narrow enough that a moment between two close events stays choosable, which a press needs because it names an alert's moment. Schedule-list rows and the next- and previous-event actions land exactly on their event, so the magnet does not have to. A tap on an event-time label is an ordinary plot tap: it takes the event only within 4.5 units of the event's own x. A target within half a logical unit starts no animation, but `selectedTime` still takes the target's exact instant. A target past the reachable range lands at the nearest reachable centre and reads the time there, as every move does (§8). If two targets are exactly equidistant, choose the earlier one for deterministic behavior.

The reference target set is the sorted, de-duplicated union of all applicable in-window moments:

- tide high and low extrema;
- the fastest-rate instant of each tide run that reaches the rate-warning scale;
- current maxima and slack instants;
- the opening and closing of each merged measured slack window drawn as a stroke (§13.2);
- the opening and closing of each merged measured slack run, or for a short run (§13.2) its centre alone, which replaces the slack instant and any other event inside the run;
- sunrise and sunset;
- greatest eclipse of each lunar eclipse that has a contact or its greatest eclipse above the station's horizon, and of each locally visible solar eclipse, but none of their other contacts; and
- derived-gate slack instants.

Animate a magnetic settle with the platform's standard short scroll animation, then assign `selectedTime` to the exact target when the animation completes. This final assignment prevents interpolation or pixel rounding from leaving an event readout a few seconds off its own time. With Reduce Motion enabled, a magnetic settle lands directly on its target.

## 8. Programmatic movement and interruption

The direct scrubber controls may request an exact target. A direct-control target is not subject to the 4.5-unit capture radius.

Every move made for code rather than a finger follows one rule: commentary, Now, foreground return at home, the first-run tour, plot and sun taps, presses, accessibility steps and actions, the date picker, shared links, schedule rows, Sun sheet event links, and sheet jumps.

1. The newest request wins. It cancels the opening motion, a hinge follow, momentum (without first accepting another momentum frame), an animated ride, and a magnetic settle, and forgets their destinations.
2. The target clamps to a reachable content offset, and the selected instant is read back from that offset: the requested instant when it can sit under the centreline, otherwise the instant at the nearest reachable centre.
3. When the travel is at least half a logical unit and at most seven elapsed days, and Reduce Motion is off, the strip animates to the target and parks `selectedTime` on the exact landed instant at completion. Otherwise it lands directly, without compressing weeks into a short animation. Presses and accessibility steps and actions always land directly (§6.5.1, §15). A move that starts from an offset outside newly published data, such as after a picked week replaced the window, also lands directly.
4. Every animated move marks the strip busy for the chunk store while it runs, so a left-edge publish never lands mid-animation (§4.2).

A host moves the strip only by an explicit request. Commentary, Now, foreground return, the picker, shared links, schedule rows, Sun sheet event links, sheet jumps, the first-run tour, and a Canadian tide preview's clamp into its samples each set the selection and raise a request together. A selection that changes without a request never starts an animated move and never interrupts one, so scroll feedback during a ride cannot cancel it: a rendered selection can trail the current offset, and the destination remains the requested instant until the animation finishes or a newer request or a drag interrupts it. A quiet strip resyncs to such a selection directly, as described below.

A finger that is still down retains control. A request that arrives during an active drag waits; when the finger lifts, it replaces the drag's momentum and moves by the rule above, and a newer request replaces a waiting one. On the first-run tour, a drag on the stars step advances the tour on its first frame, so the moon step's ride starts when that finger lifts. On the tour's stars step, any selection change from 600 ms after the tour's ride begins advances the tour.

The tour enables its stars and moon steps only when their target instants lie within the loaded prediction interval. A finite Canadian tide preview skips a sky step whose target falls beyond its downloaded bounds. The enabled steps stay fixed for that tour run when a completed model widens the interval.

When nothing is moving and no request is waiting, but the offset and the selection disagree by more than one unit, the strip lands directly on the selection without animation.

When the viewport width changes—rotation, split screen, or browser resize—recompute the offset so the existing `selectedTime` remains under the new centreline. Cancel momentum or a magnetic settle if needed. The resize must not change `selectedTime`, replay the opening, or briefly publish the wrong centre value.

On a foldable whose posture change rebuilds the page (iPhone Duo), the rebuilt strip returns to the selected moment, or to refreshed now if it was home. The detail keeps the chosen schedule anchor and loads data around that moment, so a moment far from now is loaded when the strip lands. A schedule that was in view stays in view after the rebuild (detail §4). While the hinge opens, the strip starts up to six hours past that moment and scrubs back to it in step with the hinge, landing exactly on it at flat or when the hinge rests for 0.25 s. Closing to the cover screen, or Reduce Motion, lands directly. Until the hinge moves past the angle the rebuilt strip first saw, the follow waits 1 s for it before landing; the follow eases toward the hinge and snaps once it is within a minute of the moment.

## 9. Fixed lead reading

The lead is the primary textual answer for the selected instant. It stays centred above the graph and updates continuously while scrubbing.

Its anatomy is:

1. state word followed by a state/direction glyph;
2. one large value and a lighter unit, when magnitude is known; and
3. station-local selected date and clock time.

The lead prints the station-local date and clock without a weekday or relative day word: the locale's abbreviated month and day, a fixed ` · `, then the locale's hour and minute. Date order, month names, clock cycle, and meridiem follow the platform locale; the ` · ` separator is not localized. A figure space pads a one-digit hour when the locale uses one, keeping the centred tabular clock stable as it crosses 9:59 to 10:00. Other graph clocks use the same localized time style without the date or padding.

The lead is a centred column overlaid at the top of the strip, and it takes no touches (§6.3): 12 units of top padding, then the state row (word and glyph 6 apart; set arrow and set 4 apart), the value row, then the date and time row, with 4 units between rows. The eyebrow row is footnote semibold. Its state word is medium weight at 85% of the chrome ink. The value, its unit, and the clock line use the chrome ink at full opacity, except that a provisional value and its unit use the attention colour (§9.2). The clock line is caption size with tabular digits.

VoiceOver reads the lead as one combined element: the state word, the set (compass point or bearing) on a measured current outside slack, the value without a provisional `~` (§9.2), and the unit. The eyebrow glyph is hidden from VoiceOver, because the word and the set already say what it shows and a set arrow's symbol name is its unrotated one. The date and clock are its value, with the padding figure space removed.

### 9.1 Tide lead

The tide value is the engine-exact height at `selectedTime`, not the graph's ten-minute interpolation. A CHS tide preview, which has no engine model, interpolates linearly between its fetched samples. Format feet to one fractional digit or metres to two using the locale's decimal separator. A height prints without a sign only when it rounds to zero at that precision, below 0.05 ft or 0.005 m in magnitude, so −0.04 m prints as `-0.04` and −0.004 m as `0.00`. The compact unit symbols remain `ft` and `m` in every locale.

Within one second of an extreme, the state is `High` or `Low` with `arrow.up.to.line` or `arrow.down.to.line`. Otherwise the state is `Rising` or `Falling` with `arrow.up.right` or `arrow.down.right`. Direction comes from the next extreme (rising toward a high), or from the sign of the sampled rate on a CHS tide preview, and defaults to rising when no later extreme is loaded.

Glyph colour:

- high/rising uses the high teal;
- low/falling uses the low amber; and
- while the absolute rate is at least 0.6 m/hr, the glyph takes the fast-tide commentary's ink instead: the rate-ramp colour lifted toward white for the sky behind the pill row (§10.1).

### 9.2 Measured-current lead

The value is the absolute speed at `selectedTime`; the phase carries its sign. Predicted stations (harmonic, subordinate, or fitted) use an engine-exact value. Online sampled currents use linear interpolation through the displayed series. Format all supported speed units to one fractional digit using the locale's decimal separator; a speed prints without a sign only when it rounds to zero, below 0.05 in the display unit. The nautical unit symbols `kn`, `km/h`, and `m/s` remain unchanged across locales.

The state is:

- `Slack` while `selectedTime` lies in a measured slack run (§13.2), including its opening but excluding its closing, or within one second of a slack no run covers, where the magnet parks on that slack's mark; never elsewhere, however slow the water, and never merely inside a slack window, where the water is still flooding or ebbing;
- `Max flood` or `Max ebb` within one second of that maximum; or
- `Flooding` / `Ebbing` otherwise.

Outside slack, show a true-bearing arrow (`arrow.up` rotated to the bearing) and the set as one of 16 compass points, or as a three-digit true bearing (`225°`) when the person chooses degrees in Settings. Every reading of the set, spoken or shown, follows that choice; the station's fixed flood and ebb bearings in Station details stay in degrees true. Positive velocity selects the station's flood bearing; negative velocity selects its ebb bearing. In slack, use the slack glyph (`arrow.right.and.line.vertical.and.arrow.left`) instead of claiming a set. The set arrow and its set use the flood colour or ebb colour by direction, and the slack glyph uses the go colour.

A provisional model prefixes numeric values and water commentary events with `~` in visible text, and uses the attention colour for the value, its unit, and the whole set group (arrow and set, or the slack glyph). Sunrise and sunset commentary never receives a provisional prefix. VoiceOver never reads the `~`, which it would speak as the word “tilde”: the lead, the strip's value, and the commentary's accessible label omit it, and the provisional notice under the strip (§4.2) says the reading is approximate. Provenance is outside this spec.

### 9.3 Derived-gate lead

A derived gate knows phase and slack times but no speed or set bearing. Its lead contains the state (`Flooding`, `Ebbing`, or `Slack`), a glyph (`arrow.forward` for flooding, `arrow.backward` for ebbing, or the slack glyph) in the flood, ebb, or go colour, and selected time. It must not display a numeric value, unit, compass point, or true-bearing arrow. VoiceOver reads the phase word, with the date and clock as the value; the glyph is hidden from VoiceOver as in §9, and there is no number or unit to read.

The lead reads `Slack` within 12 minutes of a derived slack. Otherwise it reads `Flooding` when the next slack is a high-water slack and `Ebbing` when it is a low-water slack. Past the last slack it reads the phase that follows it: ebb after a high-water slack, flood after a low-water slack. With no derived slacks loaded it reads `Slack`.

### 9.4 Watch reading

The watch place page has no lead card. Its top line is the place name, prefixed with `location.fill` when the place was chosen from the wearer's location, or the dated clock while the selection is away from now. Its reading row is the value, unit, and set, then a tide arrow or the current phase word. The watch treats a stop within 200 seconds as reached, reads heights and current speeds from the ten-minute interpolation, has no `Max` or window-based slack states and no provisional `~`, and shows a next-event line instead of a commentary pill. The next-event line names the first tide high or low, or the first current slack or maximum, at least 200 seconds ahead; it never names sunrise, sunset, slack-window edges, fast-rate points, or eclipse contacts. It gives the event word, its value and unit when known, ` · `, and its clock. On a derived gate the watch shows no value, unit, or set, and reads the phase from the schematic shape with the 0.15 threshold, so `Slack` spans roughly 17 minutes either side of a slack on a six-hour half-cycle rather than §9.3's 12 minutes.

## 10. Commentary and Now pills

Both controls use compact, capsule-shaped translucent material with caption semibold, tabular text. Pill text stops growing at the first accessibility text size so commentary and Now share one row. “Glass” describes the visual role—legible interactive chrome floating above a changing sky—not a requirement to use an Apple-only material.

### 10.1 Commentary

The commentary pill is centred on the reading line. It names what is important next and is also a command to move there.

Countdowns floor to whole minutes and never go below zero:

```text
under 60 minutes: 28m
60 minutes or more: 3h 28m
```

The compact `h` and `m` countdowns are fixed chart notation. VoiceOver uses localized full-duration words, floored to whole minutes like the visual label, omitting zero units (`1h 0m` is read as one hour), and reading under a minute as zero minutes.

The visual label uses the same selected-time-relative order at now and while planning away from now. It contains no sentence glue:

```text
High ↑ 28m
Low ↓ 3h 28m
Slack →|← 1h 12m
Max flood → 28m
Sunset ☀︎↓ 2h 5m
```

The marks above represent SF Symbols, not translated glyphs, drawn between the label and the countdown in the text colour, 4 units from each:

| Stop | Symbol |
| --- | --- |
| High, Low | `arrow.up`, `arrow.down` |
| Slack | `arrow.right.and.line.vertical.and.arrow.left` |
| Flood, Max flood | `arrow.forward` |
| Ebb, Max ebb | `arrow.backward` |
| Sunrise, Sunset | `sunrise`, `sunset` |

Fast-tide commentary has no symbol.

The accessible button label preserves the complete relationship and uses localized full-duration units, for example `High tide in 28 minutes` or `Maximum ebb current in 42 minutes`, and never carries a provisional `~` (§9.2). The decorative symbol is hidden from accessibility.

All four phone consumers compare the next water stop with sunrise and sunset and name whichever occurs first. Every candidate, water or sun, is the first stop more than one second after the selection, so landing on a stop advances the pill, and it must lie between the first and last drawn sample: water events kept beyond the strip for event search and sun events from day chrome beyond the data never count. Missing polar sun events contribute no candidate. The label and tap destination must name the same stop, and activation moves there by §8. When a sun event and a water stop share an instant, the sun event is named. The fast-tide rate warning below takes precedence over this chronological choice. Commentary is absent when there is no applicable later target.

#### Tide commentary

Ordinarily name the next extreme (`High …` or `Low …`) or an earlier `Sunrise …` or `Sunset …`.

When the absolute tide rate, linearly interpolated from the ten-minute rate series, reaches 0.6 m/hour, commentary instead explains the warm-coloured curve at the selected instant:

```text
Rising 0.60 m/hr
Falling 5.2 ft/hr
```

Tint this text, and the lead glyph above it, with the rate-ramp colour lifted toward white: at least a quarter of the way, then in 5% steps until it reaches 4.5:1 contrast against the sky's horizon colour composited over the canvas at the sky's opacity (§14), the brightest ground the pill row can sit on. The ramp's red end is unreadable against a sunrise. Where no step reaches 4.5:1, the ink is white. It has no countdown, and its accessible label is the visible text. Activating it moves forward to the fastest-rate point of the current rising or falling run, before its next high or low tide. Once within one second of that peak or past it, activation moves directly to that high or low tide, even when sunrise or sunset comes first. The rate remains visible while the tide is fast. A peak from another run or outside the drawn samples is never a target.

#### Current commentary

Walk strictly forward—more than one second after `selectedTime`—through these significant stops:

1. a drawn slack window's opening, named `Slack window`;
2. a merged measured slack run's opening, named `Slack`;
3. the window's closing, named `Slack window` with the closing glyph; and
4. `Max flood` and `Max ebb`.

A slack run's closing is not a stop: the window goes on around it. A short slack run (§13.2) is one stop instead: its centre, named `Slack`. A slack inside a run is never a stop of its own: its run's opening, or a short run's centre, names it. A slack no run covers is one stop at its own instant, named `Slack`, and parked on that instant the lead says `Slack` (§9.2). A window too short to draw has no stops; the slack inside it does. When a window and its slack run open together, which happens when the slack-window speed is under the slack speed, the one stop is named `Slack`.

The `Slack window` stop uses the slack glyph in the visual label and is spoken `Slack window`. The closing stop shows the same words, so the pill is no wider than the opening's, and uses `arrow.left.and.line.vertical.and.arrow.right`; the glyph tells the two apart. It is spoken `Slack window closes`. With the slack-window speed off there are no windows, so the commentary walks slack and the maxima alone. When a bare slack coincides with a window's closing, the stop is named `Slack`. A window ending at the sampled series boundary has no measured closing and must not invent one. Activating the pill moves to the stop it names. Once parked on a stop, the pill names the following stop rather than pointing to itself.

The next current stop competes with sunrise and sunset. A derived gate compares its next slack instant with the sun events; it never offers a current maximum.

### 10.2 Now

Show Now only when:

```text
abs(selectedTime - now) > 1 / pointsPerHour hours
```

At the reference scale this is 200 seconds. The threshold is one visible unit: smaller round-trip error means the centreline has not visibly moved.

The pill sits at the outer edge on the side where now lies:

- selected in the future: `← Now` on the left;
- selected in the past: `Now →` on the right.

The pill row is inset 16 units from each viewport edge. Now uses the `arrow.left` or `arrow.right` symbol 4 units from the word, and is announced `Return to now`. It appears only when the host supplies a return action. On the watch, Now is an `xmark` toolbar button labelled `Now`, shown behind the same 200-second test.

The arrow is both instruction and spatial truth. Activating Now refreshes the reference `now`, ensures its data window is active, and moves that instant beneath the centreline. After landing, the pill disappears.

Now moves by §8, so it wins over the opening, momentum, a ride, or a magnetic animation. Because both pills are hidden and inert while the strip moves (§6.4), this matters for requests that arrive while the strip coasts: a scene reactivation that returns to now, and a schedule-row tap, which goes to its own event.

## 11. Fixed centre overlay

The overlay is not part of the horizontally moving content.

The riding dot is always visible and always sits at:

```text
x = viewportWidth / 2
y = graphY(valueAt(selectedTime))
```

Use a white 13-unit dot with a four-unit, 90%-white glow for tide, and a white 10-unit dot with a three-unit glow of the same colour for current and derived current. The larger tide dot keeps its presence against the rate-coloured tide line. The watch marks the selection with a 14-unit ring instead: a 3-unit white stroke over a canvas-colour fill, with no glow, for tide and current alike, and it draws no reading line.

At rest, a one-unit white line at 18% opacity runs from `topPad`, 6 units below the pill capsules, to the plot floor. Show it only when commentary exists; the riding dot alone carries the selection when there is no commentary. It fades with the pills. After a press, or VoiceOver's "Set an alert" action, parks a moment (§6.5.1), the line also runs from the plot floor to the bottom of the strip, with or without commentary, until the selection moves to a different minute. A host with nothing to alert on has neither the press nor the action, so it never draws the extension. The line must not intercept input.

Do not confuse the riding dot with the graph's absolute-now dot:

- the riding dot is fixed to the viewport and marks `selectedTime`;
- the absolute-now dot is drawn into the moving graph and marks `now`: a 7-unit paper dot with a halo gap, drawn only when now lies inside the loaded window; and
- the two coincide when the scrubber is home.

## 12. Shared graph rules

### 12.1 Samples and interpolation

The reference harmonic series is sampled every ten minutes. Official online series may arrive every fifteen minutes. Draw a continuous polyline through the samples and linearly interpolate the riding-dot position between them.

Prediction generation across the window, event finding, slack-window calculation, sun/moon event searches, and eclipse searches happen when the timeline is built, not on each scrub frame. A scrub frame may interpolate values, calculate the current sky, and evaluate the engine at the single selected instant for the tide and predicted-current leads (§9.1, §9.2), but must not rebuild the week.

### 12.2 Past and future

Split every curve stroke and overlaid run at the absolute-now x-coordinate:

- past stroke opacity: 35%;
- future stroke opacity: 100%; and
- past event-mark and event-label opacity: 45% of the future value.

“Event mark” and “event label” here mean a water turn's dot, a peak or turn's hanging value and glyph, a short slack run's mark or the mark of a slack no run covers (§13.2), a derived-gate slack dot, and an axis time. Day names, dates, sunrise/sunset chrome, and eclipse context do not fade merely because their instant is in the past.

If now is before the window, all content is future. If now is after it, all content is past.

Draw a seven-unit paper (`#FCFCFC`) absolute-now dot on the curve only when now lies inside the loaded window. Punch a 2.5-unit clear halo beyond its edge so it remains legible over fills and day/night shading. Turn-dot, derived-gate slack-dot, and now-dot halos erase everything already drawn on the strip beneath them (fills, shading, and curve), so the sky behind the strip shows through the ring and the curve is broken around each dot.

### 12.3 Reference marks and labels

The base curve is 2.5 units wide with round caps and joins. Dashed reference lines are one unit wide at 35% foam opacity with a `[1, 3]` dash pattern. They span the whole strip width and draw above fills and shading, beneath the curve.

A tide high's reading hangs below its dot and a low's above it, whatever the turn's height; a max flood's reading hangs below its peak and a max ebb's above it, toward the zero line. Each is centred on the event's x. The glyph sits nearest the curve and the value beyond it: the glyph's centre is 15 units from the turn or peak (23 − 8) and the value's centre 30 units (23 + 7). The glyph is 12 units, semibold for a to-bar glyph and bold for a set arrow; the value is 18 units semibold with tabular digits.

Absolute event times have one home: the event-time row beneath the plot, in foam at 70% opacity. Sort candidate times first. If the next label would fall less than 64 horizontal units after the last retained label, keep the earlier label and omit the later one. The event still exists and remains magnetic.

Do not draw any event mark, hanging reading, or event time within 1.5 hours (27 units) of either edge of the loaded window: turn dots, turn and peak readings, derived-gate slack dots, and every event time. The margin is half the widest of those labels, so an event near an edge is left out whole rather than cut by the edge; edge clipping makes a valid event look broken. The event still exists and remains magnetic. Slack windows, slack runs, including a short run's mark and the mark of a slack no run covers, the curve, and the now dot draw to the edge.

### 12.4 Colour tokens

These sRGB values are the portable reference palette:

| Role | Hex | Meaning |
|---|---|---|
| Deep ink | `#00183C` | Text on schedule pills; the sky's chrome ink is always white (§14) |
| Canvas | `#05122A` | Water/page ground |
| Foam | `#E4F0E4` | Primary light ink |
| Graph line | `#38BDF8` | Base water curve, and a measured current's slack window |
| High | `#2DD4BF` | Tide high |
| Low | `#FBBF24` | Tide low, and the tide fill below chart datum |
| Flood | `#4A9FD8` | Flood set glyph and derived flood glyph in the lead, and the schedule's flood pill |
| Ebb | `#E8A33D` | Ebb set glyph and derived ebb glyph in the lead, and the schedule's ebb pill |
| Go | `#88B868` | A measured slack run, the mark of a slack no run covers, and a derived gate's known slack instant |
| Beyond window | `#F5C96B` | A measured current's curve outside its slack windows; the magnitude ramp's first stop |
| Neutral unknown | `#5888A8` | Unknown or unavailable state: map pin, unavailable-station card and page, Unfavorite swipe action |
| Sun | `#F0C860` | Sunrise/sunset dot |
| Sunrise label | `#F0D890` | Every sunrise and sunset time, on the strip, in schedule day headers, and in the sun sheet, which also uses it for dawn and dusk; the symbol, not the colour, tells sunrise from sunset |
| Night | `#00101F` | Night shading beneath the curve (70%) |
| Daylight tint | `#A8CAE0` | Daylight shading beneath the curve (8%) |
| Paper | `#FCFCFC` | Absolute-now dot |
| Attention | `#EF6F4A` | Provisional or exceptional state, not alarm |
| Eclipse umbra | `#6B2A18` | Eclipse-only copper, drawn at 94% |

Inside the graph, green is reserved for slack evidence: a measured slack run or slack instant and its direct state, or a derived gate's known slack instant, which has no speed to measure a duration from. It must not identify a station type, rising tide, weak water without a reversal, the slack window around a slack, or generic success there. The same hex is also the app's leaf accent outside the graph: section labels, controls, card strokes, and the schedule's selected-row bar.

The magnitude ramp contains no green:

| Normalized position | Hex | Physical anchor |
|---:|---|---:|
| 0 | `#F5C96B` | 0.5 kn current / 0.6 m/hr tide rate |
| 1/3 | `#F5C96B` | 3 kn / 1.0 m/hr |
| 2/3 | `#E8763C` | 8 kn / 1.5 m/hr |
| 1 | `#C93A32` | 12 kn / 1.8 m/hr |

Interpolate piecewise in sRGB and clamp beyond the ends. Geometry auto-fits per station; magnitude colour remains absolute so equal speeds mean equal colours.

## 13. Track variants

### 13.1 Tide

Fit tide heights around the midpoint of the fitted range, using half that range multiplied by 1.06 as the padded half-span and a nonzero floor. The initial fit uses loaded data; continuous browsing follows the visible-span governor in §16.

Draw in this order:

1. opaque canvas colour from the curve to the plot floor;
2. low amber below chart datum, clipped to the plot;
3. daylight/night shading clipped beneath the curve;
4. a dashed chart-datum line when zero lies inside the fitted span;
5. the rate-coloured curve;
6. high/low marks and hanging readings;
7. absolute event times; and
8. the absolute-now dot.

Water above chart datum has no fill: between the curve and the plot floor there is only the opaque water ground, so day and night shading lies on the same dark sea on a tide strip as on a current strip. Where the curve lies below datum, low amber fills the area between datum and the curve, clear at datum and rising to 50% at the bottom of the plot. That area lies above the curve, over the sky, not over the opaque water ground. If the loaded series never reaches datum, draw no fill. Station cards draw a different tide fill: graph blue above datum as well as the amber below it.

The tide curve is base graph blue while `abs(rate) < 0.6 m/hr`. At and above that floor it follows the absolute rate ramp in §12.4: from 0.6 to 1.0 m/hr the line is solid ramp yellow, and the step from blue is softened only by the gradient between adjacent samples. The past/future opacity split applies on top of the gradient.

Each high or low gets:

- a five-unit diameter dot with a 2.5-unit clear outer halo, high teal or low amber;
- its height without a unit, since the lead owns the unit, in foam;
- a to-bar glyph nearest the dot, the `arrow.up.to.line` SF Symbol for a high and `arrow.down.to.line` for a low, in the dot's colour; and
- its local time in the event-time row.

The arrow-to-bar means “arrives and stops.” A plain up arrow must not label a high, because rising is precisely what has ended.

### 13.2 Measured current

Fit symmetrically around zero using the largest absolute speed in the fitted range (floored at 0.01 kn) multiplied by 1.05. Speeds map to ±(half the plot height − 3 units); a speed beyond the fitted maximum clamps to that edge. Continuous predicted-current browsing (harmonic, subordinate, or fitted) follows the visible-span governor in §16; online currents fit the samples inside their fixed window. The zero line stays at the vertical middle so equal flood and ebb magnitudes occupy equal heights.

Draw in this order:

1. opaque canvas colour from the curve to the plot floor;
2. a zero-anchored blue fill;
3. daylight/night shading beneath the curve;
4. the dashed zero reference line;
5. the base curve and its magnitude thread;
6. measured slack windows: each window drawn as a stroke, and none shorter than a turn dot;
7. measured slack marks over them: each slack run a stroke, stretched to the shortest slack stroke when shorter than a turn dot, and the shortest slack stroke at each slack no run covers;
8. drawn window openings, and the time of each slack mark outside every drawn window;
9. derived-gate slack dots and peak readings; and
10. the absolute-now dot.

The fill lies beneath the curve only, as on a tide chart: in each flood lobe, the area between the curve and the zero line, graph blue at 50% at the top of the plot fading to clear at zero. An ebb lobe has no fill, because its curve-to-zero area lies above the curve, over the sky. The gradient spans the larger half of the plot, so its rate per unit does not depend on how strong the flood is against the ebb.

Draw the curve in the beyond-window yellow at 2.5 units: everywhere the water is over the slack-window speed. Down its middle, draw a two-unit absolute-speed thread:

- invisible below 0.5 kn;
- yellow fading from transparent at 0.5 kn to opaque at 3 kn;
- yellow through orange between 3 and 8 kn; and
- orange through red between 8 and 12 kn, clamped red above 12 kn.

An online sampled series derives its events from the samples. A slack falls at an exact-zero sample or at the linear crossing between opposite-sign samples. A maximum is the largest-magnitude sample of each signed run, without interpolation; the partial runs at the series ends also yield a maximum at their largest sample. Events are kept up to six hours beyond the fixed window.

A measured slack window is measured around each slack instant on the drawn samples. A predicted station takes the instant from the engine's event search and measures on its chunk's ten-minute samples plus six hours either side. An online current takes the instant from the sample-derived events above and measures on its 15-minute samples inside the fixed window. When one of the two samples bracketing the slack is at or below the configured threshold (an exact-zero sample always is), the window extends to the interpolated threshold crossings on each side and clamps to the loaded series. When both bracketing samples are above the threshold but have opposite signs, the straight line between them crosses the ±threshold band, and the window runs from where that line enters the band to where it leaves it, so a reversal inside the series always has a window. Either way the window holds its own slack instant: where the event search puts the slack outside the interpolated edges, the window widens to it. A measured slack run is measured the same way around the same slack instant, at the slack speed: `slackKn`, 0.15 kn, or the slack-window threshold where that is lower. A slack run therefore lies inside its window, and a window set under the slack speed is a slack run throughout. The closing edge is excluded from slack coverage: a slack exactly at a slack run's closing keeps a dot, its own time, and its own magnetic target, including when the closing is the final loaded sample. A slack outside the sampled series, or between two above-threshold samples of the same sign, has no window and no slack run; a slack whose water never gets under the slack speed, such as a rotary station's minimum, has a window but no slack run. Either way it still has a mark: the same shortest slack stroke as a short run, centred on the slack's own instant, which is its one magnetic target, commentary stop (§10.1), and event time. Every slack therefore has a mark, and every mark is a line. Merge touching or overlapping windows into one window, and touching or overlapping slack runs into one run. Draw the curve itself in graph blue across each window at 3.5 units, slightly wider than the base curve, then in the go colour across each slack run over it. The base yellow curve and speed thread must be absent under either stroke, including the faded past section. Leave a small break around each round end cap of a window, and of a slack run with no window around it, against the yellow curve, using a 2.5-unit halo gap, without erasing the underlying fill or sky. A slack run joins its window's blue stroke with no break: green against blue is not the deuteranopia pair, and a break at every colour change reads as a dashed line. Yellow, blue, and green then read in order: over the limit, under it, and slack. Do not outline the whole run, add endpoint dots, or add an area band. Each window's and each slack run's opening and closing is magnetic, except for one drawn as a dot.

A merged slack run narrower than a turn dot's five-unit diameter is a short run. It draws as the shortest slack stroke: a six-unit go-colour stroke along the curve, centred on the run's midpoint in time, so slack is always a line and never a dot. A merged window that narrow is not drawn at all, and has no magnetic targets, commentary stops, or event times of its own; the slack mark inside it stands for it. At 18 units an hour that is a window shorter than about 17 minutes. The shortest slack stroke draws like any slack run: over the window's blue with no break, or with its end gaps where it meets the yellow curve. A run's true length at that size would read as a blot rather than a duration, and the stretch is drawing only: the run's measured edges are unchanged. Decide this from the run's duration at the strip's 18 units an hour, with the same width test the drawing uses, so data code never needs the drawn geometry. A short run is one moment: its centre is the run's only magnetic target (§7), commentary stop (§10.1), and event time, and it replaces the slack instant inside it. Station cards stretch the same way at their own scale.

Current maxima are drawn as context rather than as marks:

- no peak dot;
- hang the absolute speed, without unit, toward the zero line;
- place a true-bearing set arrow nearest the curve; and
- use foam rather than flood/ebb hue for both value and arrow.

The event-time row contains each drawn window's opening, and each slack mark outside every drawn window: a slack run's opening, or for a short run its centre, and the instant of each slack no run covers. It does not contain current-maximum times. Those maxima remain magnetic even though their exact time is not printed on the graph.

### 13.3 Schematic derived current

A derived gate uses the current plot box with a normalized ±1 phase shape: a half-sine between consecutive derived slacks, positive (flood) after a low-water slack and negative (ebb) after a high-water slack, and zero outside the slack range.

- use the same blue fill, beneath the curve in the positive half only, fading to clear at the shape's zero crossing;
- keep the blue curve and past/future split;
- mark each known slack with a five-unit go-colour dot with a 2.5-unit clear halo on the zero line, and its thinned axis time;
- fit the loaded shape (±1 × 1.05) without the visible-span governor;
- omit the dashed zero reference line, magnitude thread, speed values, set arrows, measured slack windows, and green duration runs; and
- expose no numeric value in the lead.

The dots claim known times only. The shape's height and fill must never be interpreted as a speed or passed through the speed ramp. Only the crossings are timing claims.

## 14. Day, sun, eclipse, and sky

The day/celestial layer moves with the graph. It provides calendar and light context without breaking the continuous timeline into pages.

For every civil day touched by the window:

- centre `Today`, `Tomorrow`, `Yesterday`, or the short weekday on the daylight that the day's sunrise begins, halfway between that sunrise and the sunset that follows it; use station-local noon when the day has no sunrise or that daylight has no following sunset, so the day name never lands in the night;
- place the locale's abbreviated month and day (iOS template `MMMd`) beneath it;
- draw sunrise as the `sunrise` SF Symbol, a space, and its localized station time, in sunrise ink at its true x-coordinate;
- draw sunset as the `sunset` SF Symbol, a space, and its localized station time, also in sunrise ink (the symbol, not the colour, tells them apart) at its true x-coordinate; and
- place a seven-unit sun-colour dot centred 14 units below the day row beneath each time.

The day name is foam at 85% and the date foam at 48%, 17 units below the day name. Day names, dates, sun times, sun dots, and the eclipse glyph do not fade in the past. Day names and sun times share the day row with no collision handling, so on short days they may overprint. The day row, dates, sun dots, and eclipse glyph draw after the track, over its shading.

Sunrise/sunset events are computed for the station coordinate and civil-day bounds; when a civil day has more than one rise or set, the first of each is used. A polar day may lack either event; omit missing marks without inventing a time.

Night shading (`#00101F` at 70%) spans each sunset to the sunrise that follows it; daylight tint (`#A8CAE0` at 8%) spans each sunrise to the sunset that follows it. Pair the sun events by succession, from the time-sorted sunrises and sunsets of every day the strip holds, never by civil day: where sunset falls after local midnight (western Alaska in summer), a civil day's first sunset comes before its sunrise and closes the previous day's daylight. A sun event followed by another of the same kind, or by none, opens no band. Each band ramps linearly from transparent 0.75 hour outside its sun event to full strength 0.75 hour inside it, so the event itself sits at half strength; a band shorter than 1.5 hours ramps from transparent 0.75 hour outside each event straight to full strength at its centre. Shade is clipped beneath the curve and runs down through the time and day rows. It stays at full strength from the plot top through the first 35% of the distance from the plot top to the bottom of the strip, then fades linearly to transparent at the strip's bottom edge, so it does not end as a hard rectangle behind the time rows.

For a lunar eclipse with a contact or its greatest eclipse above the station's horizon, and for a solar eclipse reported as visible there, draw only a small `🌘` (6.5 units) at greatest eclipse on the sun-dot row. Do not add a text label or coloured band to the graph. Greatest eclipse is a magnetic target; the eclipse's other contacts are not (§7).

The backdrop behind the lead responds continuously to `selectedTime` and station coordinates:

- paint a top colour and a horizon colour interpolated linearly in sun altitude between anchors: 10° `#2F7FD4`/`#BDE3FB`, 0° `#2B4A7A`/`#F8A15F`, −6° `#17264A`/`#8D4A63`, −12° `#0B1430`/`#2A2A52`, −18° `#04060F`/`#0B1023`, held beyond both ends. The gradient runs from the top colour at the frame top to the horizon colour at the horizon, and holds the horizon colour below it;
- composite the sky over the canvas at 55% opacity with the sun at or above the horizon, rising linearly to 100% at −6°;
- map altitude at a fixed 3 units per degree, with the horizon 16 units below the plot top so curve peaks pass in front of the lowest stars; stretch a body's own rise-to-set azimuth span across the width, padded by the sun's 8-unit disc radius or half the moon's 22-unit glyph frame (11 units), so the body just clears the edge at the horizon, and use the full 360° when there is no span (polar day or night, or no day data yet);
- centre each span's frame on the meridian the body crosses: south when it culminates south of the zenith, north when it culminates north of it, as the sun and moon do on some days in the tropics. The body culminates south when its declination, read halfway between its rise and set, is south of the station's latitude. With no span, the frame faces the equator;
- hold the sun and moon in frame once they are up: with a span, clamp the body's centre to between its pad outside each edge at the horizon and twice its pad inside at 10° of altitude, easing linearly in between, so a body that is up keeps a disc radius of sky between it and the edge. A body that climbs steeply, or swings wider than its own rise and set on a pass poleward of the zenith, slides up and down the edge instead of leaving the frame. An arc that stays up through its lower culmination, as the moon does at high latitudes, is not held, because it runs round the whole horizon through both edges. Treat an arc as such when its declination, read halfway between rise and set, is within the station's colatitude of the pole, or when it lasts a day or more. Stars are not held;
- position sun and moon against the nearest complete rise-to-set horizon span, keeping that span through both crossings so the disc and halo enter and leave continuously; switch spans midway between set and the following rise, while the body is below the horizon;
- draw the sun as a 16-unit `#F0C860` disc over a 54-unit glow of the same colour at 24% opacity, blurred 12;
- draw the moon as a 20-unit phase disc in a 22-unit glyph frame, on a dark limb (`#00122C` at 92% × 18%) with a 0.75-unit white outline at 25%, over a radial glow of radius 12 + 20 × illuminated fraction, offset 4 units toward its bright limb, with a `#E6EEFF` core at 0.95 × (0.1 + 0.66 × illuminated fraction) and a `#CFE0FF` halo at 0.28 × the same factor at 45% of the radius, both multiplied by the eclipse dim and fading to clear at the edge. Outside a solar eclipse the moon fades to transparent as its centre comes within 19 units of the sun's and is fully opaque from 38 units out. While a lunar eclipse is underway the glow turns copper (`#E8B08C` core, `#D79A78` halo) and dims by 1 − 0.75 × umbral fraction − 0.25 × penumbral wash;
- show the moon's illuminated limb and current lunar eclipse shadow, with the bright limb at its angle from the zenith (Almanac's bright-limb angle less the parallactic angle). Sun and moon sit east on the right whichever way their frame faces, so they rise at the right edge and set at the left, travelling right to left as time advances, the same way the curve pans under the centreline. A frame facing south is a mirror image of the sky, so there the limb is mirrored too and keeps facing the drawn sun; facing north it is the sky as seen. When the sun's and moon's frames face opposite ways and the sun is up, the limb keeps its upward or downward lean and points across to the side the sun is drawn on, its lean across scaled by the drawn sun's horizontal offset over 40 units so it turns through vertical as the sun passes over or under the moon; with the sun down, the moon's own frame decides. The Moon card and sheet always show the limb as seen. The lunar umbra is an equal-radius copper disc that slides in from the moon's right edge and is concentric when the umbral fraction reaches 1; that fraction rises linearly from 0 at U1 to the umbral magnitude at greatest eclipse and falls back to 0 at U4, and the disc does not rotate with the bright limb. From P1 to P4 of every lunar eclipse the whole disc is also washed copper at 42% × a penumbral fraction that rises linearly from 0 at P1 to the penumbral magnitude (capped at 1) at greatest eclipse and falls back to 0 at P4; for a penumbral eclipse this wash is the only mark, and for a partial or total eclipse the umbra draws over it;
- during a solar eclipse, draw the moon over a 20-unit `#04060F` silhouette, placed along its true bearing from the sun at (8 + 11) × (1 − obscuration) units, the sun's disc radius plus half the moon glyph: just clear of the sun at first contact and concentric only at full obscuration, so a partial eclipse keeps an offset bite at its greatest. Every sky quantity (paint, opacity, stars, ink ground) is evaluated at the sun altitude pulled toward −9° by obscuration⁴, so a half-covered sun still reads as day and totality reads as deep twilight;
- reveal stars as the sky darkens: the catalogue stars of magnitude 3.5 or brighter, placed against the sun's horizon span so they slide with the bodies, but always facing the equator, so mirrored in the northern hemisphere. The field does not flip on the nights the sun's frame changes sides. Field opacity is 0 with the sun above −6° and rises linearly to 0.7 at −18°; each star is further scaled by its own altitude, from 0 at −10° to full at 40°. Radius is max(0.5, 1.6 − 0.3 × magnitude) units. Twinkle multiplies opacity by 0.86 + 0.14 × a per-star sine, so between 0.72 and 1.0, and redraws at most 8 times a second; it pauses while the field opacity is zero. No stars are drawn when the sun position is unavailable; and
- draw the lead and chrome ink in white at every sky state, because the sky paint never gets light enough to need deep navy. Coloured chrome text, such as a rate-warning tint, is lifted toward white, at least a quarter of the way and then in 5% steps, until it reaches 4.5:1 against the sky's horizon band composited over the canvas, or falls back to white.

Solar eclipse appearance is evaluated for the selected instant and station coordinate. A partial eclipse must leave a visible bite in the sun instead of looking total; the moon must not disappear into the ordinary near-sun glare fade. Solar obscuration changes the backdrop; the strip marks solar eclipses with the same glyph and greatest-eclipse snap target as lunar ones.

The sky is non-interactive and accessibility-hidden. Under Reduce Motion, stars must not twinkle; selected-time movement may still reposition the astronomical scene because that change conveys time rather than decoration.

## 15. Accessibility and non-touch input

The intended scrubber must be usable without seeing or directly dragging the canvas. Do not make the graph's internal decorative labels separate focus stops.

Expose one adjustable timeline control with:

- label: the track type, `Tide timeline` for a tide strip and `Current timeline` for a measured or derived current strip (the watch labels its strip with the station name);
- value: the lead state, then the magnitude and spoken unit when known, then the set on a measured current outside slack, then the station-local month, day, time, and time-zone abbreviation of the instant under the centreline. The phone joins the reading and the dated time with a comma. Neither speaks a provisional `~` (§9.2). The watch's value leads with the station-local month, day, time, and time-zone abbreviation, then the state, the value and spoken unit, and the set when known, joined with spaces;
- increment/decrement actions that move later/earlier by five minutes; and
- named actions for next and previous magnetic target when the platform supports custom actions (`Next event`, `Previous event`), plus `Set an alert` on a detail strip whose host can alert (§6.5.1).

The five-minute accessibility step is independent of device pixels and remains usable at every viewport width. Every adjustment updates the same `selectedTime` as touch input. Adjustments and next/previous actions are programmatic moves (§8) that always land directly with no travel and stop any opening motion; a target past the window's edge parks at the nearest reachable centre. Next and previous ignore a target within one second of the current time; with no target, the action reports failure and nothing moves. The watch strip is one adjustable element with the same five-minute steps and next/previous event actions; its steps are not clamped to the loaded span, and a next or previous action with no target does nothing without reporting failure.

Expose commentary and Now as ordinary buttons. Commentary's label must expand its compact visible copy into the complete event, relationship, and localized duration; for example, visible `High ↑ 28m` is announced as `High tide in 28 minutes`. Now is announced `Return to now`. Their semantic hit targets must meet the platform minimum—44 by 44 points on iOS/web and 48 by 48 dp on Android—even when their visible capsule is smaller. iOS sets a 44-point semantic row height; the capsules are always wider than 44 points.

The lead should be one combined announcement rather than separate state, value, unit, and clock focus stops, and it speaks its date with the clock. Its eyebrow glyph is not announced (§9). The timeline control's value always includes the civil date and the station time zone, because a clock time without its date is ambiguous in a multi-day timeline.

Do not rely on colour alone:

- high/low have different to-bar glyphs;
- current direction has bearing arrows and compass text;
- a measured slack window is a wider run, and named by the commentary; measured slack is a wider run joined to it, stretched to the shortest slack stroke for a run shorter than a turn dot or a slack with no run; derived slack is a dot; and every slack is named in text;
- speed magnitude remains printed at maxima; and
- schematic magnitude is omitted rather than encoded only by colour.

With Reduce Motion:

- opening and programmatic travel land directly;
- the magnetic settle lands directly;
- decorative twinkle stops;
- pill opacity does not animate; and
- selected-time updates and the riding dot remain immediate.

iOS does not map hardware-keyboard Left/Right to the timeline step. Keyboard-capable web and Android implementations should map Left/Right to the same five-minute decrement/increment, with logical direction unaffected by text direction because the timeline itself is chronological left-to-right. Provide a focus-visible treatment around the scrubber without moving its centreline.

## 16. Rendering and platform guidance

Use native scrolling physics where practical, with a custom-drawn continuous strip inside it. The product contract depends on direct manipulation and momentum, not on a particular widget class.

### iOS reference

The reference uses a horizontal `UIScrollView` (`TimelineScrubber.swift`) hosting a tiled SwiftUI `Canvas`. The scroll delegate publishes the centre time during scrolling. Applying an external time or a changed timeline window suppresses synchronous scroll feedback; SwiftUI already owns that selected time. Initial centring suppresses that feedback throughout layout, including the direct landing under Reduce Motion; the direct opening publishes now after layout returns. A fixed SwiftUI overlay draws the line and riding dot. The pills draw over the scroll view but cannot keep a touch from its recognizers, so the strip's tap and press recognizers decline a touch that starts on a resting pill. The lead card draws over the scroll view with hit testing off, so a touch on the lead goes straight to the strip. A display-link drives the animated opening so the selected time and sky follow every frame. On a device with a trailing status rail, the strip and sky draw on under the rail while the scroll viewport, and so the centreline, stays inside the safe area.

### watchOS

The watch place page (`SlackwaterWatch/PlaceDetail.swift`) hosts `CrownScrubStrip` (`SlackwaterWatch/CrownScrubStrip.swift`), which draws the same `TimelineCanvas` under an offset driven by `digitalCrownRotation`, with no momentum code of its own: the Crown brings it. Crown sensitivity is high. The Crown's position is measured from a fixed origin at the strip's points per hour, so chunk swaps that move `data.start` do not move the selected time. When the Crown goes idle, `TimelineData.magnetTarget(nearX:)` (the phone's magnet rule) picks the landing and the page re-anchors through `Timeline.reanchor(settledAt:anchor:tz:)` after the same 600 ms rest. The Crown only scrubs: the page does not scroll vertically. The strip is clipped under its row of hours; the day and sun rows do not fit. A rescale lands directly, as under Reduce Motion, because watchOS has no display link to glide on. A Crown settle rides a snappy animation to the magnet target's exact instant (direct under Reduce Motion) and plays a light impact haptic, including under Reduce Motion; a rest already within half a unit of the target takes its exact instant directly, with no haptic. The Crown's range is the loaded span's start to end, so the centre can reach the data's very edge. Now is a bottom-bar `xmark` button in place of the list button, shown only when scrubbed away; it moves with the same snappy animation unless Reduce Motion is on or the travel exceeds seven days. The watch mounts two tiles around the centre, marks the selection with a 14-unit white ring, fits its vertical scale as if its viewport were 200 units wide (about 11 hours), and hosts tide, predicted-current (harmonic, subordinate, and fitted), and derived-gate places but not online currents. On its 52-unit plot, current peak readings hang across the zero line. The sky backdrop runs behind the reading card from the top of the screen to the plot floor, with its horizon 16 units below the plot's top.

### Android

A Compose implementation can use horizontal scroll state plus `Canvas`, or a custom scrollable modifier backed by native fling behavior. Derive selected time from the settled and in-flight offset; do not animate only the canvas transform while leaving semantic state behind. Use dp for logical geometry and px only at the drawing boundary.

### Web

Prefer a native horizontal scroll container or equally native-feeling pointer + inertia implementation. Read `scrollLeft` on animation frames and derive the selected time from the viewport centre. Canvas or SVG are both valid; keep lead, pills, and accessible control semantics in the DOM. Disable browser text selection and image dragging only inside the direct-manipulation surface.

### Long-surface limits

Even the bounded 4,104-unit strip exceeds a single 8,192-pixel texture on a 3× display. iOS draws 900-unit tiles and mounts only the visible tiles plus one tile on each side. Each tile reads its own sample range with edge context; event-time thinning and shared fill boundaries remain window-wide so labels and gradients agree across seams. A pan alone must not rebuild an unchanged canvas; only a pan that changes the mounted tile set re-hosts it. Changes to data, units, bearings, reference now, strip height, or vertical scale must invalidate it, including a replacement CHS fit or slack threshold with the same sample count.

Other platforms may tile, window, or draw vector content directly. They must not allocate one oversized bitmap and silently lose the graph on high-density screens. Tile boundaries must land on device pixels and must not change the time mapping or create visible seams.

### Vertical scale

Continuous tide and predicted-current details (harmonic, subordinate, or fitted) fit the visible time span plus one hour on each side. Preserve the current scale while the curve fits comfortably: expand when the visible reach exceeds 97% of the held half-span, and contract when the newly fitted span is below 65% of the held span. Tide fitting adds 6% padding; measured-current fitting adds 5%. The fitted span uses a viewport of at least six hours. An adopted tide fit replaces both centre and half-span. Chunk arrivals alone must not stretch the graph.

An adopted scale glides over 300 ms with smoothstep easing, carrying the drawn curve and riding dot together. A new target during the glide starts from the currently drawn scale. The glide runs at up to 60 frames per second. Reduce Motion lands directly. Online details fit their fixed loaded window; derived shapes retain their normalized scale.

## 17. Conformance scenarios

These scenarios define the minimum behavior shared by all platforms. Scenario 38 applies only where a posture change rebuilds the page.

### Opening and manipulation

1. **Ordinary opening:** Given a complete current window and Reduce Motion off, opening starts two hours behind now, reaches now in 650 ms, and ends with the lead time equal to the centre time.
2. **Interrupted opening:** A drag, tap, plot press, or host request during the opening cancels it; the drag continues from the strip's position when it began, without jumping to now.
3. **First drag:** The first drag after opening, including one that starts on the lead's text, changes the lead and riding dot during the gesture, before release or snap.
4. **Direction:** Dragging content left advances selected time; dragging it right moves selected time backward.
5. **Momentum:** A flick continues natively, updates the lead during motion, then evaluates the magnet once.

### Snapping and commands

6. **Near target:** Resting 3 units (10 minutes) from a tide extreme animates to its exact instant.
7. **Outside capture:** Resting 4.5 or more units from every target remains where released, including 40 minutes before a low.
8. **Already parked:** Resting within 0.5 unit of a target starts no redundant animation, and the lead shows the target's exact instant.
9. **Request during motion:** A commentary request issued during a fling (the visible pill is inert while the strip moves, §6.4), or a schedule-row tap during a ride or the opening, stops that motion and goes to its own target; no later momentum or ride frame overwrites the request. A request during a drag waits for the finger to lift.
10. **Now during settle:** A return to now that arrives during a magnetic animation or a ride, such as a scene reactivation (the visible pill is inert while the strip moves, §6.4), cancels the animation, refreshes now, lands home, and removes the Now pill.
11. **Reduce Motion:** Opening, commentary, Now, taps, picker, shared-link, schedule-row, and sheet selections, and a drag-end magnetic settle land directly with no travel, and the pill row appears without an opacity animation.

### Geometry and time

12. **Resize:** Rotate or resize after scrubbing. The lead time and centre time remain equal and unchanged.
13. **Cross midnight:** Scrubbing continuously across midnight changes the day chrome without discontinuity or a page transition. Where sunset falls after local midnight (western Alaska in summer), the night band runs from that sunset to the sunrise that follows it, the afternoon carries the daylight tint, and each day name sits in daylight.
14. **DST:** On a transition week, the civil day occupies 23 or 25 hours at the same 18-unit/hour scale; sunrise, sunset, and noon remain correct locally.
15. **Window edge:** No event label is clipped at an edge: an event within 1.5 hours of a loaded edge draws no mark, reading, or time. No direct control or commentary advertises a target that cannot be centred over valid data, and every programmatic move lands on a reachable centre. A drag stops at the loaded edge without overscroll.

### Track meaning

16. **Tide turn:** At an exact high, the lead says High, the high's reading hangs below its dot, and the commentary advances to the following event.
17. **Fast tide:** At 0.6 m/hr or faster, the line and commentary share the same ramp position. Activation goes forward to that run's fastest point, then directly to its high or low tide. A selection within one second of the peak, or past it, goes directly to the turn. Sunrise or sunset between the peak and turn cannot send a later tap back to the peak. The rising or falling rate remains visible while fast.
18. **Measured slack window:** The curve is yellow outside the slack windows, graph blue across interpolated window edges, and green only across the slack run inside it; the lead says Flooding or Ebbing inside the window, Slack at the slack run's opening, and changes phase at its half-open closing, and outside a slack run says Slack only within a second of a slack no run covers (§9.2). At a weak station whose window covers a maximum, the lead says Max flood or Max ebb on it.
19. **Short slack window:** A fast reversal whose bracketing samples both exceed the threshold still has a window, interpolated where the line between them crosses ±threshold; a merged window narrower than a turn dot is not drawn, and a slack run that narrow draws as the shortest slack stroke, and its centre is its event time, its only magnetic target, and its one commentary stop. A slack with no run, at a sampled-series edge, between two same-sign samples, or at a minimum that never gets under the slack speed, draws the same stroke centred on its own instant, with the same single time, target, and stop, and the lead says Slack parked on it. When the engine's slack falls just outside the line's ±threshold span, the window widens to hold it, with a separate stroke, time, magnetic target, and Slack commentary stop when the slack is exactly at the half-open closing.
20. **Different current peaks:** Equal speeds have equal thread colours across stations; a 6 kn and 12 kn peak do not both become local “maximum red.”
21. **Derived gate:** The lead has no number or bearing, the shape has blue zero-fading fill beneath its positive half only and no speed thread, and only known slack instants get green dots, each with its time in the event-time row; there is no dashed zero line.
22. **Past/future:** A graph with now in view has a 35%-opacity past stroke and full-strength future stroke split exactly at the absolute-now dot.

### Accessibility

23. **Adjustable value:** A non-touch increment changes selected time by five minutes and announces a dated, station-local lead value, with the set on a measured current outside slack and no provisional `~`; the next- and previous-event actions park exactly on a magnetic target, or at the nearest reachable centre when the target lies within half a viewport of the content edge.
24. **Direct controls:** Commentary and Now meet semantic target sizes and expose their visible meaning without requiring the canvas labels.
25. **No-colour reading:** High/low, current direction, slack, magnitude, and schematic unknown remain distinguishable in greyscale.
26. **Larger text:** At the largest accessibility size the lead value and its pad grow together, the plot and chrome rows move down without overprinting, and commentary and Now share one row.

### Continuous browsing and host integration

27. **Chunk seam:** Browse several weeks in both directions, including a DST transition. No sample gap, duplicated event, broken night band, or selected-time jump appears. Left-edge changes wait for motion to stop.
28. **Scale:** A new visible peak can expand the plot with a 300 ms glide; ordinary chunk churn leaves it stable. Curve and riding dot share each frame's scale, and Reduce Motion adopts directly.
29. **Plot tap:** A tap selects its moment or a magnetic target strictly within 4.5 units and rides to a reachable centre time, holding left-edge chunk publishes until it lands.
30. **Date or sun tap:** A tap nearer the drawn date than any sun time stops motion and opens the picker where the host can change dates; a sun tap centres that event.
31. **Sun commentary:** Sunrise or sunset wins over a later water event, has no provisional tilde, and advances after landing. Fast tide retains its rate warning.
32. **Dated lead:** Crossing midnight changes the displayed local date. A one-digit hour occupies the same clock width as a two-digit hour.
33. **Foreground return:** A home selection follows refreshed now; a selection away from the old now stays where the person left it. Either way, when the refreshed now falls on a new station-local day, the Today, Tomorrow, and Yesterday labels move with it.
34. **Far destination:** A shared link opens at its requested instant, and a picked week at station-local noon of the picked day unless the selection already lies inside that week's window, with data on both sides. A picked day, link, or Now within seven days of travel rides there; over seven days it lands without travel. Now restores the current schedule.
35. **Model replacement:** A refined CHS model or changed slack threshold refreshes the graph and readout while preserving the selected instant.
36. **Slack caps:** Window and green runs replace the underlying stroke, including in the past, and only their ends have separation gaps: a window's against the yellow curve, a green run's against the window. Fill and sky remain intact.
37. **Solar eclipse:** At a locally visible partial eclipse, the sun has a bite and the moon remains visible, and greater obscuration darkens the backdrop. The strip marks greatest eclipse with the same small `🌘` a lunar eclipse gets, and greatest eclipse is the eclipse's only magnetic target; its other contacts are not.
38. **Fold:** Unfolding after scrubbing lands on the folded instant, including one weeks from now; folding while home lands on refreshed now. Both directions keep the chosen schedule week. A schedule in the upper half of the viewport returns to view after its data loads; a glimpse at the bottom leaves the chart in view. Scrolling while data loads cancels the pending schedule restoration.

## 18. Known iOS deviations from the intended contract

This section lists implementation gaps, not behavior to copy to another platform. No gap is known in the iOS reference.

A gap found later is listed here. Fixing one should update this section and add or amend a conformance scenario. Do not weaken the cross-platform contract to preserve an iOS gap.

## 19. Reference implementation map

The living implementation is split by responsibility:

| Concern | iOS source |
|---|---|
| Window constants, timeline data and builders, magnet target, vertical geometry, tiled canvas, day/sun/eclipse chrome, schedule list | `Slackwater/TimelineStrip.swift` |
| Scroll host, opening, taps, press and hold, accessibility actions, resize and fold follow, magnet settle, fixed overlay, commentary and Now pill row, rescale glide | `Slackwater/TimelineScrubber.swift` |
| Continuous chunks, merging, scroll gate, scale governor | `Slackwater/TimelineChunks.swift` |
| Detail scaffold: date picker, alert line wiring, shared-link jump, week bar, fold restoration | `Slackwater/Theme.swift` |
| Lead card, commentary pill and stop walk, lead clock, sky state and backdrop | `Slackwater/DetailPieces.swift` |
| Colour tokens, curve style, station-local clock formatting | `Slackwater/Palette.swift` |
| Shared current lead and direct commentary walk | `Slackwater/CurrentLead.swift` |
| Tide lead and fast-rate commentary; Canadian tide preview binding and its sample model (coverage, interpolation, rates, extremes) | `Slackwater/TideDetailView.swift`, `Slackwater/ChsTidePreview.swift` |
| Predicted-current binding (harmonic, subordinate, and fitted) | `Slackwater/CurrentDetailView.swift` |
| Derived phase-only lead | `Slackwater/DerivedGateDetailView.swift` |
| Online sampled-current binding | `Slackwater/OnlineGateDetailView.swift` |
| Shared strokes, fills, dots, runs, and hanging labels | `Slackwater/CurveDrawing.swift` |
| Measured slack-window and slack-run predicate and merging, current axis moments, online sample-event derivation, speed-ramp anchors | `Slackwater/SlackWindow.swift` |
| Derived slack instants, schematic ±1 shape, derived phase rule | `swift/Sources/SlackwaterKit/DerivedSlack.swift` in the slackwater repository |
| Tide-rate targets | `Slackwater/TideMovement.swift` |
| Eclipse windows and contacts | `Slackwater/Eclipse.swift` |
| Press offer and alert line | `Slackwater/AlertOffer.swift`, `Slackwater/AlertLine.swift` |
| Watch place page and Crown strip | `SlackwaterWatch/PlaceDetail.swift`, `SlackwaterWatch/CrownScrubStrip.swift`, `Slackwater/ScrubReading.swift` |
| Pure behavior checks | `SlackwaterTests/TimelineTests.swift`, `SlackwaterTests/TimelineSnapTests.swift`, `SlackwaterTests/TimelineChunkTests.swift`, `SlackwaterTests/DetailLeadTests.swift`, `SlackwaterTests/SkyBackdropTests.swift`, `SlackwaterTests/EclipseTests.swift`, `SlackwaterTests/SlackWindowTests.swift`, `SlackwaterTests/RenderedStripTests.swift`, `SlackwaterTests/ReduceMotionTests.swift`, `SlackwaterTests/ScrubReadingTests.swift`, `SlackwaterTests/ChsTidePreviewTests.swift`, `SlackwaterTests/AlertOfferTests.swift`, `SlackwaterTests/AlertLineTests.swift`, `SlackwaterTests/DerivedGateTests.swift` |
| End-to-end interaction checks | `SlackwaterUITests/DetailAndScrubTests.swift`, `SlackwaterUITests/AlertLineUITests.swift`, `SlackwaterUITests/AccessibilityAuditTests.swift`, `SlackwaterWatchUITests/WatchUITests.swift` |

Design history and completed implementation plans belong in Git history and pull requests. This file is the maintained scrubber contract.

## 20. Maintaining this specification

Any user-visible scrubber change should update this file in the same change as the reference implementation. At minimum, review all five consumers: tide (harmonic, subordinate, and fitted on the device, including the bounded Canadian tide preview), predicted current (NOAA harmonic and subordinate stations, and fitted Canadian gates), online current, derived gate, and the watch place page (tide, predicted current, and derived gate; no online current). Every app and watch source file in §19 carries a header comment pointing here.

When an implementation differs intentionally:

1. preserve the invariant in §2;
2. record the deviation and its reason here;
3. decide whether the platform is wrong or the shared contract should change;
4. add a conformance scenario for the decision; and
5. update other platforms from the shared decision, not by copying incidental framework behavior.

The shortest valid implementation is the one that uses native scrolling, calendar, accessibility, and motion facilities while preserving this observable contract.
