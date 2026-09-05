# Card Graph Shared Drawing Plan

**Goal:** The station card's curve (list card, card face, medium and small widgets) draws by the detail strip's rules: a tide fill anchored at chart datum that fades to the lowest trough when datum is out of reach, a tide line coloured by the tide-rate ramp, a current fill that is blue on both sides of zero with a dashed zero line, a blue current line with the speed-ramp thread down its middle, and slack runs as one haloed green segment with no end dots. One set of drawing helpers serves both canvases, so they cannot drift again.

**Architecture:** Share the primitives, not the canvas. `TimelineCanvas` (tiled, fixed-point geometry, day chrome, thinned axis) and `StationCardGraph` (one small frame, a padded auto-fit domain, edge-margin axis) differ in everything except how pixels are laid down, and a single canvas would need a geometry abstraction neither surface wants. So: a new `Slackwater/CurveDrawing.swift`, the drawing counterpart to `CurveStyle`: an `enum CurveDrawing` namespace of static functions that take a `GraphicsContext` first, plus two pure stop builders in the same namespace. An enum namespace and not a `GraphicsContext` extension because that is how this repo shares vocabulary (`SN`, `CurveStyle`, `Timeline`, `SunMoon`), and because `CurveDrawing.datumFill(ctx, …)` says at the call site which helpers are ours. Everything takes already-mapped geometry (paths, the y of zero or datum, plot top and bottom, the x of now). No `Date`, no engine types, no `TimelineData`, no `Timeline`. Both canvases call it. The file joins the widget target's explicit source list.

**Spec:** `docs/superpowers/specs/2026-09-04-detail-graph-hero.md` ("The strip" drawing rules and the card-graph follow-up), and the detail strip as built in `Slackwater/TimelineStrip.swift` (`drawTide`, `drawCurrent`, the card-look primitives).

## Constraints

- **Widget target.** `project.yml`'s `SlackwaterWidgets` sources are an explicit list that includes `Palette.swift`, `SlackWindow.swift`, `TideMovement.swift`, `StationCardGraph.swift` and `StationCardFace.swift` but not `TimelineStrip.swift`. A shared helper cannot reference `Timeline`, `TimelineData` or `TimelineGeo`. Widget-safe ramp inputs: `currentSpeedRampAnchorsKn` and `widgetSpeedRampT` (`SlackWindow.swift`), `tideMovementRampAnchorsMHr` (`TideMovement.swift`), `SN.speedColour` (`Palette.swift`). `Timeline.rampT(forTideRateMHr:)` and its private `rampT(_:anchors:)` live in the strip file and are not widget-safe; `widgetSpeedRampT` is the same arithmetic written a second time.
- **No schematic cards.** Every card passes real samples or `graph: nil` (`WidgetSnapshot`, `ChsGateCardView`). The card needs no `speedsAreSchematic`; the detail keeps its steel fill for derived gates.
- **Source-scanning tests** that pin the current drawing, each of which must be retargeted rather than deleted:
  - `TimelineTests.testTideTrackUsesCardFillAndRateColouredLine` reads `drawTide`'s body (from `private func drawTide(` to `private func deg(`) for `SN.graphLine.opacity(CurveStyle.fillOpacity)`, `fadeStop`, `SN.graphLow.opacity(0)` and `tideRateStops(`.
  - `ColourAndFormTests.testCurrentTrackDoesNotSpeakDirectionInColour` reads `drawCurrent`'s body up to the first line that is exactly four spaces and a brace, bans `SN.flood`/`SN.ebb`/`SN.rising`/`SN.falling`/`SN.leaf`, and requires the body to stay over 40 lines. Extraction shrinks it.
  - `ColourAndFormTests.testChartAndPillsAgreeOnHighLow` (line 136) requires the literal `(high ? SN.graphHigh : SN.graphLow)` in `TimelineStrip.swift`. Compute the tint at the call site and pass a `Color` to the helper.
  - `ColourAndFormTests.testColourLiteralsLiveInTheme` allows `Color(hex:` only in `Palette.swift`, `Theme.swift`, `TimelineStrip.swift`. The new file uses `SN` tokens only.
  - `TypeScaleTests.testNumericFormattersAreMonospacedDigit` lists `StationCardGraph.swift:cardGraph`, `TimelineStrip.swift:drawTide` and `drawCurrent` as known indirections. Helpers take pre-formatted strings, so nothing new is needed as long as the `formatHeight(`/`formatSpeed(` calls stay in those functions within four lines of `.monospacedDigit()`.
  - `SlackWindowTests` tests `windowDotOpacities`, whose only caller is the card's end dots.
  - `WidgetSnapshotTests.testMediumWidgetRendersTheStationCard` counts `SN.go` pixels on a 364×170 render at scale 1 and asserts more than 100. Today two haloed end dots contribute about 40 of those; the run's stroke is the rest.
- **Compile check builds the appex too** (CLAUDE.md `build-for-testing` under `lockf -t 0`). Screenshot the list card, the tide and current details, and the medium widget before running the suite; the suite waits for the final pass.

## Design

### The shared file

`CurveDrawing.swift`, `enum CurveDrawing`. Every helper is a static function; the ones that draw take the context first. Nothing takes anything it could compute from a `Date`.

- `CurveDrawing.strokeSplitAtNow(ctx, path, with: shading, nowX:, width:, height:, lineWidth:)`: the detail's form. Past is a clip to `0..<nowX` with the context's opacity at `CurveStyle.pastLineOpacity`, so a gradient shading fades with it; future is the complementary clip at full strength. The card adopts it in place of its two colour-only strokes and its per-run `strokeGo`.
- `CurveDrawing.punchHalo(ctx, at:, dotRadius:)` and `CurveDrawing.dot(ctx, at:, color:)`: identical in both files today.
- `CurveDrawing.nowDot(ctx, at:)`: the paper dot in its halo. Identical in both files today.
- `CurveDrawing.referenceLine(ctx, at:, width:)`: the dashed foam rule. Identical in both files today.
- `CurveDrawing.tideRateStops(rates: [(x: CGFloat, rate: Double)], width:)`: moved from the strip file, taking x already mapped instead of a `Date` and an `x(_:)` closure. Base blue under the ramp floor, the tide-rate ramp above it. Needs a widget-safe ramp: one `rampT(_:anchors:)` free function in `SlackWindow.swift`, with `widgetSpeedRampT` and `Timeline.rampT(forTideRateMHr:)` both delegating to it. The `TimelineTests` rate-stop tests keep passing through the new signature.
- `CurveDrawing.tideLine(ctx, line, rates:, nowX:, width:, height:)`: `tideRateStops` as a stroke through `strokeSplitAtNow`, plain blue when there are no rates.
- `CurveDrawing.speedCoreStops(samples: [(x: CGFloat, speedKn: Double)], width:)`: the thread. Clear below the first anchor, `SN.speedColour(0)` fading in to the second, `SN.speedColour(widgetSpeedRampT(kn))` above. One stop per sample, locations clamped to `0...1`, a single sample doubled so the gradient has two stops. Pure, so it is testable apart from drawing. The detail's inline `coreColour` closure becomes this.
- `CurveDrawing.currentLine(ctx, line, samples:, nowX:, width:, height:)`: the blue line at `CurveStyle.lineWidth`, then `speedCoreStops` at `CurveStyle.speedCore` on top, both through `strokeSplitAtNow`.
- `CurveDrawing.datumFill(ctx, area, plotTop:, plotBottom:, datumY:, fadeY:)`: blue at `fillOpacity` at the top fading to clear at `fadeY`; when `fadeY == datumY` amber fades in below it to `fillOpacity` at the bottom, otherwise the fill stays clear below `fadeY`. The gradient spans `min(plotTop, fadeY)...max(plotBottom, fadeY)`, clipped to the plot. The caller decides `fadeY` (datum when the series reaches it, else the y of the lowest sample), which is the strip's rule today.
- `CurveDrawing.zeroFill(ctx, area, plotTop:, plotBottom:, zeroY:)`: blue at `fillOpacity` away from zero, clear at zero, symmetric about zero. The gradient spans `zeroY ± max(zeroY - plotTop, plotBottom - zeroY)` rather than the plot box, so a card whose domain is lopsided (a 3 kn flood against a 1 kn ebb) intensifies at the same rate per point on both sides. The detail centres zero, so it is pixel-identical there.
- `CurveDrawing.runs(ctx, segments: [Path], nowX:, width:, height:)`: every eraser first (line width plus twice `haloGap`, round caps), then each green stroke through `strokeSplitAtNow`. No end dots.
- `CurveDrawing.hangLabel(ctx, at:, toward:, value: String?, glyph: HangGlyph, tint:, ink:, valueFontSize:)` with `enum HangGlyph { case toBar(high: Bool), set(deg: Double) }`. Glyph nearest the dot, value beyond it, offsets from `CurveStyle.hangOffset`, `hangValueGap`, `hangGlyphGap`. The caller passes the formatted string, so the mono-digit scan sees the formatter where it is today.

Card-specific and untouched: the swing window and `domainPadFraction`, `axisHeight`, `timeBaseline`, the two edge margins, the `cardTime` axis row, the VoiceOver summary. Detail-specific: tiling, day chrome, `thinnedAxisTimes`, the magnet, the schematic steel fill and the bare-slack hairline.

Glyphs stay as they are on both surfaces: text `⤒`/`⤓` for tide turns, the SF Symbol `arrow.up` rotated for a current's set.

### What changes on the card

- **Tide fill** goes from a top-to-bottom fade to `datumFill`. The card keeps its `sampledLo` (the unpadded minimum) to choose `fadeY`.
- **Datum line** draws when datum is inside the padded domain, the detail's rule, in place of the card's `nearDatum` 0.1 m test. With 25% padding a low within about a third of the range of datum now shows the rule. This is a visible change on more cards than today; the alternative is to keep `nearDatum` as a card-only knob. The plan takes the detail's rule so the two agree; revert to `nearDatum` if the list screenshot shows rules pinned near the bottom of quiet stations.
- **Tide line** takes `tideRateStops` through `strokeSplitAtNow`. `TideStationRecord.cardGraph` adds `s.rates(from:to:step:)` alongside `heights`, index-aligned as the detail already relies on; `StationCardGraph` gains a `rates: [Double]` parallel to `points`, empty for currents and previews. Empty rates fall back to the plain blue stroke.
- **Current fill** goes from flood-blue over ebb-amber to `zeroFill`. `SN.graphLow` leaves the card's current fill; the turn dots keep it.
- **Zero line** on current cards, drawn under the curve before the stroke, as the detail does.
- **Current line** is base blue at `CurveStyle.lineWidth`, then `speedCoreStops` at `CurveStyle.speedCore` on top. About 150 samples over the four-swing window. The card's `points` are already in knots; `ChsOnlineWindow.cardGraph` passes fetched knots too.
- **Slack runs** through `runs(...)`. The `windowDotOpacities` calls, the `strokeGo` closure and the per-run eraser go. `windowDotOpacities` loses its last caller and is deleted with its `SlackWindowTests` test.
- **Now dot** stays on the nearest sample. The card's `valueAt` interpolation exists for the run endpoints; switching the now dot to it is a one-line improvement the detail already makes, taken while the code is open.
- **Dots and hang labels** on the helpers. Past fade, edge margins and the tint choice stay at the call site.

## Tasks

- [x] **1. Ramp consolidation.** Add `rampT(_:anchors:)` to `SlackWindow.swift`; `widgetSpeedRampT` and `Timeline.rampT` call it; delete the private copy in `Timeline`. `WidgetSnapshotTests.testWidgetCurrentColourUsesTheAbsoluteSpeedRamp` and the `TimelineTests` ramp tests are the check. Compile.
- [x] **2. `CurveDrawing.swift`** with the helpers above, one doc comment each stating what it draws. Add it to the widget source list in `project.yml`, `xcodegen generate`, compile. No call sites yet.
- [x] **3. Detail canvas on the helpers.** `drawTide` and `drawCurrent` call `datumFill`, `zeroFill`, `tideRateStops`, `speedCoreStops`, `runs`, `dot`, `nowDot`, `referenceLine`, `hangLabel`, `strokeSplitAtNow`; delete the private copies once nothing calls them. Pixel-identical by construction. Screenshot the tide and current details and compare against the branch before the change.
- [x] **4. Retarget the strip scans** so they pass against step 3: `testTideTracksShareTheDatumFillAndRateColouredLine` asserts `CurveDrawing.datumFill(` and `CurveDrawing.tideLine(` in `drawTide` and in the card, and the `fadeStop`/`SN.graphLow.opacity(0)` stops in `CurveDrawing.swift`; `testCurrentTrackDoesNotSpeakDirectionInColour` drops or lowers its 40-line floor and adds `CurveDrawing.swift` to the banned-token scan.
- [x] **5. Card tide**: `datumFill`, the datum-line rule, `rates` on the graph and the builder, the rate-coloured stroke. Screenshot the list.
- [x] **6. Card current**: `zeroFill`, the zero line, the base stroke plus the thread. Screenshot the list and the medium widget; the 2 pt thread on a 2.5 pt line is the thing to judge.
- [x] **7. Card runs** without end dots; delete `windowDotOpacities` and its test. Re-open the `widget-medium-170` attachment from `testMediumWidgetRendersTheStationCard` and read the go-pixel count; if it falls under 100, lower the floor with the arithmetic in the comment (stroke width times the widest window's length in points), not by widening the tolerance.
- [x] **8. Card dots and hang labels** on the helpers; delete the card's local `punchHalo`, `dot`, `referenceLine` and the `Self.line/high/low` shorthands.
- [x] **9. Tests for the card.** The `drawTide` scan covers `StationCardGraph.swift` too. Extend the banned-token scan to the card's `body`. Add a pure `speedCoreStops` test beside the ramp tests: locations sorted in `0...1`, clear below the first anchor, two peaks of different speed give different hottest stops, empty and single-sample inputs are safe. The screenshots are the `zeroFill` check: `WidgetSnapshotTests` attaches the medium widget for the longest slack window, the fastest current, and tide cards under and above datum.
- [x] **10. Full suite** on iPhone 17, then the list, card face, medium and small widget screenshots.

## Risks

- A missed `project.yml` entry breaks only the widget build, at compile time. Step 2 catches it.
- A 2 pt thread on a 2.5 pt line at card scale may read as a recolour rather than a thread. The knob is `CurveStyle.speedCore`, shared with the detail; if the card needs its own, it becomes a helper parameter with the card passing a thinner value.
- The datum-line rule change shows the dashed rule on more cards. Judged from the list screenshot; the fallback is the card's `nearDatum` test, kept as a card-only knob.
- The card's 25% padding makes the datum gradient cover a taller range than the detail's 6%. Expected; the fade is anchored at the same line.
- Per-sample gradient stops (two gradients per card, ~150 stops each) multiply by cards per widget family. Cheap; the `ponytail:` thinning note in the detail applies if a widget timeline ever stalls.
- The go-pixel floor in the medium widget test may drop under 100 without end dots. Step 7 reads the count rather than guessing.
