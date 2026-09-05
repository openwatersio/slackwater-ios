# The graph is the hero

*Design spec, 2026-09-04. The station detail shared by `TideDetailView`, `CurrentDetailView`, `OnlineGateDetailView` and `DerivedGateDetailView`, and the waiting page `ChsDetailView` shows while a CHS station downloads. Supersedes the 2026-08-03 anatomy.*

## Why

A station page answers four questions: how much water is there now, which way is it going, when does it turn, and is anything about it out of the ordinary. The graph already holds all four, so the page is built around it. Nothing floats over the curve except the reading it is centred on, and every other surface (tiles, schedule, footer) is context under it.

## Anatomy

Top to bottom, one scrolling column on the canvas ground:

1. **Header** (`DetailHeader`): glass back and favorite circles, the station name in `.title`, the region in `.caption`. Tapping the name opens the discovery map focused on the station. No map on the page.
2. **Lead** (`LeadCard`): an eyebrow, the value, the time, centred over the strip's top pad. The eyebrow is the state word in sentence case at `.footnote` medium with a tinted glyph after it: "Rising ↗", "Flooding → ESE", "Max ebb → S", "Slack ⇥⇤". The value is `.system(size: 44)` rounded with its unit in `.title2` light. The time is `.caption` foam at 0.55. Malibu Rapids, a shape-only gate with no knots, shows eyebrow and time with no value.
3. **Pill row**: two glass buttons (`.buttonStyle(.glass)`, capsule). The commentary sits on the reading line and names the next event: "Low in 28m" while the reading is now, "Ebb 3h 28m later" once scrubbed away. Tapping scrubs to it. It fades while the strip moves and returns after 450 ms of rest. The Now pill appears only when the reading has left now, at the edge on the side now is: "← Now" left when scrubbed forward, "Now →" right when scrubbed back.
4. **Strip** (`TimelineScrubStrip`): the 228-hour window panning under a fixed centerline. A faint reading line runs from the pill row to the plot's foot; the riding dot marks the scrub.
5. **Axis rows**, below the plot in the card graph's order: event times, then the day row with day labels, sunrise and sunset, and the moon.
6. **Tiles** (`SummaryTiles`): a primary tile and the Moon tile. Tides show "Range" with the swing and its direction ("low to high"). Currents show "Next max" with the speed and "Flood at 2:14pm". Derived gates show the Moon tile alone.
7. **Schedule**: the rolling week, as before.
8. **Footer**: provenance, per station kind.

## The strip

Geometry is fixed points (`TimelineGeo`): a 160pt pad the lead and pills sit over, the pill row's top at pad minus 36, the plot from 170 to 320, the time row 18 below the plot, the day row 26 below that, the sun row 14 below that. Chart labels are fixed size by the chart spec's rule; the lead's text is not, which is the first follow-up.

Drawing rules, which the card graph adopts in the follow-up below:

- **Tide fill** anchors at chart datum: blue at `fillOpacity` at the top fading to clear at datum, amber (`SN.graphLow`) fading in below it. When the week never reaches datum, the fade ends at its lowest trough instead, so the fill is clear where the plot is clipped. The dashed datum line draws when datum is inside the plotted span.
- **Current fill** is blue on both sides of zero, `fillOpacity` at the extremes and clear at the zero line, with a dashed zero line. A schematic gate's shape takes a flat steel fill because its magnitude is unmeasured.
- **Current line** is `SN.graphLine` at 2.5pt with a 2pt thread down its middle carrying the absolute speed ramp: clear below 0.5 kn, the ramp's yellow fading in to 3 kn, then yellow through orange to red on the shared anchors. A 6 kn peak is the same colour at every station.
- **Slack runs** are one green (`SN.go`) segment per run inside a clear halo punched by a wider round-capped eraser. No end dots. The tide line keeps its rate ramp.
- **Night and day bands** fade to nothing above the plot, behind the lead, and below it, behind the axis rows.
- **Turn and peak labels** hang toward the plot's middle with the glyph nearest the dot and the value beyond it, at 18pt. Adjacent axis times closer than a label's width drop the later one.
- **Colour**: high and low are teal and amber (`SN.graphHigh`, `SN.graphLow`) on the chart, the schedule pills and the lead glyph. Flood and ebb are blue and amber on the pills and the lead glyph; the fill does not carry direction. Green means only slack. Yellow through red means only speed.
- **Time** prints as "4:22pm" everywhere: axis, sun row, lead, schedule, tiles.

## Scrubbing

The strip's `UIScrollView` drives `scrubTime`; the magnet snaps to the nearest stop within 46pt after a settle. A pill tap bumps a token the scrubber watches, stops any fling, and rides the magnet's animated path to the target, parking exactly on it when the animation ends; Reduce Motion lands directly. Any other external scrub (a schedule row) stops a coasting strip and jumps.

## Shared pieces

`ScrubDetailScaffold` owns the column and passes the timeline to `card` and `links`. `LeadCard` is the lead for all four details. `CurrentLead` computes a current's eyebrow, value, commentary stops and next max from a timeline plus the velocity under the centerline; `CurrentScrubCard` wires it to the strip for the harmonic and online-gate details. `SummaryTiles` and `Commentary` live in `Theme.swift`.

## Follow-ups

- **Dynamic Type for the lead.** The value is fixed at 44pt while its eyebrow and time scale, inside a fixed 160pt pad. Derive the pad and the pill row's top from the lead's measured height. The chart spec's fixed-size rule covers chart labels, not this text.
- **Pill height.** The commentary and Now pills are about 30pt tall, under the 44pt target. The large control size read too heavy over the chart; revisit if taps miss in use.
- **Long commentary at accessibility sizes** can overlap the Now pill; the row is a bare stack. Reserve the pill's width or move to a second row past a size threshold.
- **Commentary under Reduce Motion.** The settle fade ignores the setting, and hiding the pill mid-scrub is content loss, not just motion. Consider keeping it visible and only suppressing taps.
- **Gloss words.** "Incoming" and "outgoing" reach no screen; `CurrentPhase.gloss` and `DerivedPhase.gloss` survive for one unit test. Either give them a home the reader will meet (the lead's VoiceOver label is the cheapest; the provenance footer sits under a week of schedule rows and is not it) or retire them with `PhaseGlossTests.testGlossWords`.
- **Card graph** on the same drawing rules: the section below.
- **Pre-existing test failures** reproduced on `main`: the two online-gate date-picker tests, the two map frame-budget timings on iPad, and the live download-promotion test. They need an issue.

## Follow-up: the card graph on the same rules

The station card's curve (`StationCardGraph`, used by the list card, the card face and the widgets) draws its own way today: a top-to-bottom tide fade, a flood-blue and ebb-amber current fill, a plain blue line, and slack runs with haloed end dots. Bringing it onto the rules above is one PR.

**Architecture.** A new `Slackwater/CurveDrawing.swift`, an enum namespace of free functions taking a `GraphicsContext` and already-mapped geometry: points, the y of zero or datum, the plot's top and bottom, the x of now. No `Date`, no engine types, no `TimelineData`. Both canvases call it. The widget target compiles an explicit source list in `project.yml` that includes `Palette.swift`, `SlackWindow.swift`, `StationCardGraph.swift` and `WidgetSnapshot.swift` but not `TimelineStrip.swift`, so the helpers cannot live in the strip file or reference `Timeline`; the widget-safe ramp entry points are `currentSpeedRampAnchorsKn` and `widgetSpeedRampT` in `SlackWindow.swift`.

**Helpers.** `strokeSplitAtNow` in the detail's form, which fades the context's opacity left of now so a gradient shading fades too. `punchHalo` and `dot`, identical in both files today. `speedCoreStops(samples, width)`, pure and testable: clear below the first anchor, the ramp's yellow fading in to the second, the ramp above, one stop per sample. `datumFill` and `zeroFill` taking the true zero fraction, since the card's padded domain does not centre zero. `runs(segments, nowX)`: every eraser first, then each green stroke, no end dots. `hangLabel` with a `.toBar(high:)` or `.set(deg:)` glyph. Card-specific and untouched: the swing window and padding, the axis row and its edge margins, the nearest-sample now dot, the VoiceOver summary. Glyphs stay as they are on both surfaces.

**Steps**, each compiling alone: add the file and the `project.yml` entry, then `xcodegen generate`; re-point the detail canvas at the helpers, pixel-identical by construction; card tide fill to `datumFill`, keeping the near-datum dashed line; card current fill to `zeroFill`; card line to base blue plus the `CurveStyle.speedCore` thread; the dashed zero line on current cards; card runs without end dots, which orphans `windowDotOpacities` in `SlackWindow.swift` and its `SlackWindowTests` test, both deleted; card dots and hang labels on the helpers; full suite, then the list, card face, medium and small widget screenshots.

**Tests.** `TimelineTests.testTideTrackUsesCardFillAndRateColouredLine` scans `drawTide` for literals; retarget it to the helper call and mirror it on `StationCardGraph.swift`. Extend `ColourAndFormTests.testCurrentTrackDoesNotSpeakDirectionInColour`'s banned-token scan to the card's canvas. Add a pure `speedCoreStops` test: locations sorted in `0...1`, clear below the first anchor, two peaks of different speed give different hottest stops, empty and zero-width inputs are safe. `WidgetSnapshotTests.testMediumWidgetRendersTheStationCard` counts `SN.go` pixels and must stay over its floor without end dots. `TypeScaleTests.testNumericFormattersAreMonospacedDigit` needs no new indirection if helpers take pre-formatted strings.

**Risks.** A missed `project.yml` entry breaks only the widget build, at compile time. A 2pt thread on a 2.5pt line at card scale may read as a recolour; judge from the medium widget screenshot, the knob is `CurveStyle.speedCore`, shared with the detail. The card's `domainPadFraction` pads more than the detail's span, so a datum gradient covers a taller range there; expected. Per-sample gradient stops are cheap at the card's ~150 samples.
