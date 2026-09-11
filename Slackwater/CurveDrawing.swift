// Slackwater — GPL v3. The curve as pixels: the strokes, fills, slack runs
// and hanging readings the station card and the detail strip both draw, so
// the page a card opens into is the same drawing at a larger scale. The
// widget extension compiles this file too, so nothing here reads a Date, an
// engine type or the strip's geometry — callers map to points first. The
// knobs live in `CurveStyle` (Palette.swift); this is what they drive.
import SwiftUI

/// The pointer under a hanging reading: the to-bar arrow for a tide turn
/// (a plain ↑ says "rising", the one thing no longer true at a high), or
/// the set arrow — ↑ rotated to the bearing, "the water goes this way" —
/// for a current peak.
enum HangGlyph {
    case toBar(high: Bool)
    case set(deg: Double)
    case flow(flood: Bool)
}

enum CurveDrawing {
    /// The past is context, the future is the forecast: `path` drawn muted
    /// left of `nowX` and at full strength right of it, split by clip. The
    /// past side fades the context's opacity rather than the colour, so a
    /// gradient shading fades with it.
    static func strokeSplitAtNow(_ ctx: GraphicsContext, _ path: Path,
                                 with shading: GraphicsContext.Shading,
                                 nowX: CGFloat, width: CGFloat, height: CGFloat,
                                 lineWidth: CGFloat = CurveStyle.lineWidth) {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        var past = ctx
        past.opacity = CurveStyle.pastLineOpacity
        past.clip(to: Path(CGRect(x: 0, y: 0, width: nowX, height: height)))
        past.stroke(path, with: shading, style: style)
        var future = ctx
        future.clip(to: Path(CGRect(x: nowX, y: 0, width: width - nowX, height: height)))
        future.stroke(path, with: shading, style: style)
    }

    /// A halo that truly matches whatever is behind the canvas: erase a ring
    /// around the dot (destinationOut punches through the fill and the night
    /// bands alike) rather than paint a guess at the ground colour.
    static func punchHalo(_ ctx: GraphicsContext, at p: CGPoint, dotRadius: CGFloat) {
        let radius = dotRadius + CurveStyle.haloGap
        var eraser = ctx
        eraser.blendMode = .destinationOut
        eraser.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(.black))
    }

    /// A turn's dot in its halo.
    static func dot(_ ctx: GraphicsContext, at p: CGPoint, color: Color) {
        punchHalo(ctx, at: p, dotRadius: CurveStyle.dotRadius)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - CurveStyle.dotRadius, y: p.y - CurveStyle.dotRadius,
                                        width: CurveStyle.dotRadius * 2, height: CurveStyle.dotRadius * 2)),
                 with: .color(color))
    }

    /// The paper now dot, riding the curve.
    static func nowDot(_ ctx: GraphicsContext, at p: CGPoint) {
        let r = CurveStyle.nowDotDiameter / 2
        punchHalo(ctx, at: p, dotRadius: r)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .color(SN.paper))
    }

    /// The dotted datum/zero reference line, full width.
    static func referenceLine(_ ctx: GraphicsContext, at y: CGFloat, width: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: width, y: y))
        ctx.stroke(path, with: .color(SN.foam.opacity(CurveStyle.referenceLineOpacity)),
                   style: StrokeStyle(lineWidth: 1, dash: CurveStyle.referenceLineDash))
    }

    // MARK: Fills

    /// The tide fill, anchored at chart datum: blue at `fillOpacity` at the
    /// top fading to clear at datum, amber (`SN.graphLow`) fading in below it
    /// so a low under datum reads as "less water than the chart shows" with
    /// no seam at the crossing — both hues vanish on the same line. When the
    /// series never reaches datum — its lowest trough sits higher on screen
    /// than the datum line, so `lowestY < datumY` with y growing downward —
    /// the fade ends at that trough instead, so the fill is clear where the
    /// plot is clipped rather than half-strong at a hard edge. `area` is the
    /// curve closed to the datum line; the fill is clipped to the plot box.
    static func datumFill(_ ctx: GraphicsContext, _ area: Path,
                          plotTop: CGFloat, plotBottom: CGFloat, width: CGFloat,
                          datumY: CGFloat, lowestY: CGFloat) {
        let datumInReach = lowestY >= datumY
        let fadeY = datumInReach ? datumY : lowestY
        let top = min(plotTop, fadeY), bottom = max(plotBottom, fadeY)
        let fadeStop = (fadeY - top) / (bottom - top)
        var stops = [
            Gradient.Stop(color: SN.graphLine.opacity(CurveStyle.fillOpacity), location: 0),
            Gradient.Stop(color: SN.graphLine.opacity(0), location: fadeStop),
        ]
        if datumInReach {
            stops.append(.init(color: SN.graphLow.opacity(0), location: fadeStop))
            stops.append(.init(color: SN.graphLow.opacity(CurveStyle.fillOpacity), location: 1))
        } else {
            stops.append(.init(color: SN.graphLine.opacity(0), location: 1))
        }
        var plot = ctx
        plot.clip(to: Path(CGRect(x: 0, y: plotTop, width: width, height: plotBottom - plotTop)))
        plot.fill(area, with: .linearGradient(Gradient(stops: stops),
                                              startPoint: CGPoint(x: 0, y: top),
                                              endPoint: CGPoint(x: 0, y: bottom)))
    }

    /// The current fill, anchored at zero: clear at slack and intensifying
    /// outward, blue in both directions — the set arrows and the schedule
    /// pills carry flood against ebb; the fill only says how far from slack
    /// the water is. Symmetric about zero even when the plot is not: the
    /// gradient spans the larger half either side, so a 3 kn flood against a
    /// 1 kn ebb intensifies at the same rate per point on both sides.
    static func zeroFill(_ ctx: GraphicsContext, _ area: Path,
                         plotTop: CGFloat, plotBottom: CGFloat, zeroY: CGFloat) {
        let half = max(zeroY - plotTop, plotBottom - zeroY)
        ctx.fill(area, with: .linearGradient(
            Gradient(stops: [
                .init(color: SN.graphLine.opacity(CurveStyle.fillOpacity), location: 0),
                .init(color: SN.graphLine.opacity(0), location: 0.5),
                .init(color: SN.graphLine.opacity(CurveStyle.fillOpacity), location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: zeroY - half),
            endPoint: CGPoint(x: 0, y: zeroY + half)))
    }

    // MARK: Lines

    /// Stroke stops for the tide line: base blue under the ramp floor, the
    /// absolute tide-rate ramp above it, so a fast run climbs yellow to red
    /// toward its fastest point and back. Locations are width fractions.
    static func tideRateStops(_ rates: [(x: CGFloat, rate: Double)], width: CGFloat) -> [Gradient.Stop] {
        guard width > 0, !rates.isEmpty else { return [] }
        let stops = rates.map { p -> Gradient.Stop in
            let r = abs(p.rate)
            let colour = r < tideMovementRampAnchorsMHr[0]
                ? SN.graphLine
                : SN.speedColour(rampT(r, anchors: tideMovementRampAnchorsMHr))
            return Gradient.Stop(color: colour, location: min(max(p.x / width, 0), 1))
        }
        return stops.count == 1 ? [stops[0], Gradient.Stop(color: stops[0].color, location: 1)] : stops
    }

    /// Stroke stops for the speed thread: clear below the ramp's first
    /// anchor, its yellow fading in to the second, the absolute ramp above —
    /// so a 6 kn peak is threaded the same colour on every station. One stop
    /// per sample; locations are width fractions.
    static func speedCoreStops(_ samples: [(x: CGFloat, speedKn: Double)], width: CGFloat) -> [Gradient.Stop] {
        guard width > 0, !samples.isEmpty else { return [] }
        let riseFrom = currentSpeedRampAnchorsKn[0], riseTo = currentSpeedRampAnchorsKn[1]
        let stops = samples.map { s -> Gradient.Stop in
            let kn = abs(s.speedKn)
            let colour = kn < riseTo
                ? SN.speedColour(0).opacity(max(0, (kn - riseFrom) / (riseTo - riseFrom)))
                : SN.speedColour(widgetSpeedRampT(kn))
            return Gradient.Stop(color: colour, location: min(max(s.x / width, 0), 1))
        }
        return stops.count == 1 ? [stops[0], Gradient.Stop(color: stops[0].color, location: 1)] : stops
    }

    /// The tide line, coloured by the rate of rise. Plain blue when there
    /// are no rates to colour it by.
    /// ponytail: one stop per sample (~1,400 across the strip). Thin to
    /// every Nth sample if the canvas ever stalls on an iPad.
    static func tideLine(_ ctx: GraphicsContext, _ line: Path,
                         rates: [(x: CGFloat, rate: Double)],
                         nowX: CGFloat, width: CGFloat, height: CGFloat) {
        let stops = tideRateStops(rates, width: width)
        let shading: GraphicsContext.Shading = stops.isEmpty
            ? .color(SN.graphLine)
            : .linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: width, y: 0))
        strokeSplitAtNow(ctx, line, with: shading, nowX: nowX, width: width, height: height)
    }

    /// The current line: blue, with the speed thread down its middle at
    /// `CurveStyle.speedCore`. Its own strokes leave room for the slack run's
    /// end caps without cutting the fill or sky below them.
    static func currentLine(_ ctx: GraphicsContext, _ line: Path,
                            slackRuns: [Path] = [],
                            samples: [(x: CGFloat, speedKn: Double)],
                            nowX: CGFloat, width: CGFloat, height: CGFloat) {
        var track = ctx
        let bounds = Path(CGRect(x: 0, y: 0, width: width, height: height))
        let capWidth = CurveStyle.runWidth + CurveStyle.haloGap * 2
        for run in slackRuns {
            let body = run.strokedPath(.init(lineWidth: CurveStyle.runWidth, lineCap: .butt))
            let round = run.strokedPath(.init(lineWidth: capWidth, lineCap: .round))
            let butt = run.strokedPath(.init(lineWidth: capWidth, lineCap: .butt))
            track.clip(to: bounds.subtracting(body))
            track.clip(to: bounds.subtracting(round.subtracting(butt)))
        }
        strokeSplitAtNow(track, line, with: .color(SN.graphLine), nowX: nowX, width: width, height: height)
        let stops = speedCoreStops(samples, width: width)
        guard !stops.isEmpty else { return }
        strokeSplitAtNow(track, line,
                         with: .linearGradient(Gradient(stops: stops),
                                               startPoint: .zero, endPoint: CGPoint(x: width, y: 0)),
                         nowX: nowX, width: width, height: height, lineWidth: CurveStyle.speedCore)
    }

    // MARK: Marks

    /// The slack runs: the line itself turns the go colour along each
    /// segment. No end dots: a run is one mark, and its opening time goes on
    /// the axis.
    static func runs(_ ctx: GraphicsContext, _ segments: [Path],
                     nowX: CGFloat, width: CGFloat, height: CGFloat) {
        for seg in segments {
            strokeSplitAtNow(ctx, seg, with: .color(SN.go), nowX: nowX, width: width, height: height,
                             lineWidth: CurveStyle.runWidth)
        }
    }

    /// A reading hanging off a turn or peak in the direction `toward`
    /// (+1 down, −1 up — toward the plot's middle): the glyph nearest the
    /// dot in `tint`, the value beyond it in `ink`. Either may be absent.
    static func hangLabel(_ ctx: GraphicsContext, at p: CGPoint, toward: CGFloat,
                          value: String?, glyph: HangGlyph?, tint: Color, ink: Color,
                          valueFontSize: CGFloat) {
        let cy = p.y + toward * CurveStyle.hangOffset
        if let value {
            ctx.draw(Text(value)
                        .font(.system(size: valueFontSize, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ink),
                     at: CGPoint(x: p.x, y: cy + toward * CurveStyle.hangValueGap), anchor: .center)
        }
        let glyphAt = CGPoint(x: p.x, y: cy - toward * CurveStyle.hangGlyphGap)
        switch glyph {
        case .toBar(let high):
            ctx.draw(Text(high ? "⤒" : "⤓")
                        .font(.system(size: CurveStyle.hangGlyphFontSize, weight: .semibold))
                        .foregroundStyle(tint),
                     at: glyphAt, anchor: .center)
        case .set(let deg):
            // The SF Symbol, not the "↑" text glyph: a text arrow at the
            // same point size renders visibly smaller.
            ctx.drawLayer { l in
                l.translateBy(x: glyphAt.x, y: glyphAt.y)
                l.rotate(by: .degrees(deg))
                l.draw(Text(Image(systemName: "arrow.up"))
                        .font(.system(size: CurveStyle.hangGlyphFontSize, weight: .bold))
                        .foregroundStyle(tint),
                       at: .zero, anchor: .center)
            }
        case .flow(let flood):
            ctx.draw(Text(Image(systemName: flood ? "arrow.forward" : "arrow.backward"))
                        .font(.system(size: CurveStyle.hangGlyphFontSize, weight: .bold))
                        .foregroundStyle(tint),
                     at: glyphAt, anchor: .center)
        case nil:
            break
        }
    }
}
