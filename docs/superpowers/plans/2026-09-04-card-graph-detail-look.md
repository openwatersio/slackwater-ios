# Card Graph Detail Look Plan

**Goal:** The station card's curve (list card, card face, medium and small widgets) draws by the same rules as the detail strip: a tide fill anchored at chart datum, a current fill that is blue on both sides of zero, a blue current line with a speed-ramp thread down its middle, slack runs as one haloed green segment, and a dashed zero line on currents. One set of drawing helpers serves both canvases, so the two can never drift again.

**Architecture:** A new `Slackwater/CurveDrawing.swift`, an enum namespace of free functions that take a `GraphicsContext` and already-mapped geometry (points, y of zero, plot top and bottom, x of now). No `Date`, no engine types, no `TimelineData`. Both `TimelineCanvas` and `StationCardGraph` call it. The file joins the widget target's explicit source list.

**Spec:** `docs/current-charts.md` (runs, §5.2; hang labels, §15.1) and the detail strip as built in `Slackwater/TimelineStrip.swift`.

## Constraints

- The widget target compiles an explicit file list (`project.yml`, the `SlackwaterWidgets` sources): `Palette.swift`, `SlackWindow.swift`, `StationCardGraph.swift`, `StationCardFace.swift`, `WidgetSnapshot.swift`. `TimelineStrip.swift` is not in it, so a shared helper cannot live there or reference `Timeline`, `TimelineData` or `TimelineGeo`. The widget-safe ramp entry points are `currentSpeedRampAnchorsKn` and `widgetSpeedRampT` in `SlackWindow.swift`; `Timeline.speedRampAnchorsKn` and `Timeline.rampT(forSpeedKn:)` alias them.
- The speed thread blends from the base blue to the ramp's yellow by fading `SN.speedColour(0)` in over the blue line between the first two ramp anchors (0.5 kn to 3 kn). It does not use `Color.mix`. Keep that; the widget renders the same code.
- No card ever carries schematic derived-gate data (`WidgetSnapshot` and `ChsGateCardView` pass `graph: nil`). The card needs no schematic flag; the detail keeps its own steel fill for schematic shapes.
- `TypeScaleTests.testNumericFormattersAreMonospacedDigit` scans for `formatHeight(`/`formatSpeed(` near `.monospacedDigit()`. Helpers take pre-formatted strings so no new indirection is needed.
- `ColourAndFormTests.testCurrentTrackDoesNotSpeakDirectionInColour` scopes to `drawCurrent`'s body and requires it to stay over 40 lines. Extraction shrinks it; check the count.
- `HeroChromeTests` scans every app source for material imitations. Helpers use `SN` tokens only.
- Compile check builds the appex too (CLAUDE.md `build-for-testing` under `lockf`). Screenshot the list card and the medium widget before running the suite (memory: design iteration skips tests).

## Design

Shared helpers, all in `CurveDrawing`:

- `strokeSplitAtNow(_ ctx, _ path, with shading, nowX, height, lineWidth)`: the detail's form, which fades the context's opacity left of now so a gradient shading fades too. The card adopts it in place of its two colour-only strokes.
- `punchHalo(_ ctx, at, dotRadius)` and `dot(_ ctx, at, color)`: identical in both files today.
- `speedCoreStops(_ samples: [(x: CGFloat, speedKn: Double)], width: CGFloat) -> [Gradient.Stop]`: transparent below the first anchor, `SN.speedColour(0)` fading in to the second anchor, `SN.speedColour(widgetSpeedRampT(kn))` above. One stop per sample, locations clamped to `0...1`. Pure, so it is testable apart from drawing.
- `datumFill(_ ctx, area, plotTop, plotBottom, datumY)`: blue `fillOpacity` at the top fading to clear at datum, `SN.graphLow` fading in below datum to `fillOpacity` at the bottom, the gradient spanning `min(plotTop, datumY)...max(plotBottom, datumY)` and the fill clipped to the plot.
- `zeroFill(_ ctx, area, top, zeroY, bottom)`: three blue stops, `fillOpacity` at both edges and clear at zero. Takes the true zero fraction; the detail centres zero, the card's padded domain does not.
- `runs(_ ctx, segments: [Path], nowX, height)`: every eraser first (line width plus twice `haloGap`, round caps), then each green stroke split at now. No end dots.
- `hangLabel(_ ctx, at, toward, value: String?, glyph: Glyph, tint, ink, valueFontSize)` where `Glyph` is `.toBar(high:)` or `.set(deg:)`. Glyph nearest the dot, value beyond it, offsets from `CurveStyle.hangValueGap` and `hangGlyphGap`.

Card-specific and untouched: the swing window and domain padding, `axisHeight`, `timeBaseline`, the two edge margins, the `cardTime` axis row, the nearest-sample now dot, the VoiceOver summary. Detail-specific: tiling, day chrome, axis ticks, the magnet.

Glyphs stay as they are on both surfaces: text `⤒`/`⤓` for tide turns, the SF Symbol `arrow.up` rotated for a current's set. Switching the tide pointers to SF Symbols is a separate two-file design change.

## Tasks

- [ ] **1. `CurveDrawing.swift`** with the helpers above and doc comments stating what each draws. Add it to the widget target's source list in `project.yml`, run `xcodegen generate`, compile. No call sites yet.

- [ ] **2. Detail canvas on the helpers** (`TimelineStrip.swift`: `drawTide` fill, `drawCurrent` fill, thread, runs, dots, hang labels; delete the private `punchHalo`/`dot`/`strokeSplitAtNow` once nothing calls them). Pixel-identical by construction; screenshot the tide and current details to confirm.

- [ ] **3. Card tide fill** (`StationCardGraph.swift`): `datumFill` in place of the top-to-bottom fade. Keep the near-datum dashed line.

- [ ] **4. Card current fill**: `zeroFill`. `SN.graphLow` leaves the card's current fill; the `low` shorthand stays for the turn dots.

- [ ] **5. Card current line**: base blue at `CurveStyle.lineWidth`, then `speedCoreStops` at `CurveStyle.speedCore` on top, both through `strokeSplitAtNow`. About 150 samples over the four-swing window.

- [ ] **6. Card zero line**: the dashed `referenceLine` at `y(0)` on current cards, the same stroke the tide datum uses.

- [ ] **7. Card runs**: `runs(...)`, no end dots. `windowDotOpacities` in `SlackWindow.swift` loses its last caller; delete it with `SlackWindowTests`' test of it.

- [ ] **8. Card dots and hang labels** on the shared helpers.

- [ ] **9. Tests.** `TimelineTests.testTideTrackUsesCardFillAndRateColouredLine` asserts a literal inside `drawTide`; retarget it to the helper call and add the mirror assertion on `StationCardGraph.swift`. Extend `testCurrentTrackDoesNotSpeakDirectionInColour`'s banned-token scan to the card's canvas. Add a pure `speedCoreStops` test beside the ramp tests: locations sorted in `0...1`, clear below the first anchor, two peaks of different speed give different hottest stops, empty and zero-width inputs are safe. Re-open the `widget-medium-170` attachment from `WidgetSnapshotTests.testMediumWidgetRendersTheStationCard`; its `SN.go` pixel count drops a little without end dots and must stay over its floor.

- [ ] **10. Full suite**, then the list, card face, medium and small widget screenshots.

## Risks

- A missed `project.yml` entry breaks only the widget build, and only at compile time. Step 1 catches it.
- A 2pt thread on a 2.5pt line at card scale may read as a recolour rather than a thread. Judge from the medium widget screenshot; the knob is `CurveStyle.speedCore`, shared with the detail.
- The card's `domainPadFraction` (0.25) pads more than the detail's span, so a datum-anchored gradient covers a taller range on the card. Expected.
- Per-sample gradient stops multiply by cards per widget family. Cheap at 150 samples; the `ponytail:` thinning note in the detail applies here too.
