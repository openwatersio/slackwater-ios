// Slackwater — GPL v3. One swing drawn at true proportion inside the fortnight
// it belongs to, inside the station's own astronomical range.
//
// #97 established that magnitude has to be absolutely scaled or it conveys
// nothing, and answered it for RATE: the strip's curve follows an absolute rate
// ramp. Range is still auto-fit away — `TimelineGeo.init` normalizes every
// curve to its own extremes, so a 0.5 m swing and a 5 m swing draw identically.
// This is the geometric answer for range, and it lives in a sheet rather than
// on the strip, which keeps it clear of the five scrubber consumers.
//
// One vertical scale carries every level, so the nesting is literal rather than
// schematic: the curve's amplitude is its real amplitude against the same axis
// as the frame, and the gaps to that frame are the numbers the captions name.
import SwiftUI
import SlackwaterKit

struct StandingFigure: View {
    /// What a drawn line stands for. The two absolute roles are absent at a
    /// station whose constituents cannot bound a year.
    enum Role: Equatable {
        case absoluteHigh, absoluteLow
        case fortnightHigh, fortnightLow
        /// The turn being judged — the only line here that is not a reference.
        case selected
    }

    struct Level: Equatable {
        let role: Role
        /// The height this line stands at, metres above chart datum. Drawn
        /// beside the line: a section drawing says what each level IS, not
        /// only what it is called.
        let metres: Double
        /// Points from the top of the box.
        let y: CGFloat
        let width: CGFloat
        let label: String
        /// This line also carries a second level that landed within
        /// `minimumSeparation` of it.
        let isMerged: Bool
    }

    /// How far the curve is inset from the band's lines, in points. The band
    /// outruns the curve on both sides so that a swing which IS the fortnight's
    /// biggest — and so touches both lines — reads as a touch rather than as a
    /// clip. That case is correct and is the strongest claim the figure makes.
    static let curveInset: CGFloat = 18
    /// Two levels closer than this on screen draw as one. A legibility
    /// threshold, so points rather than metres: at a spring fortnight that
    /// nearly reaches the station's ceiling the fortnight's high and HAT are
    /// centimetres apart, and nudging either would break the shared scale the
    /// whole figure rests on.
    static let minimumSeparation: CGFloat = 9
    /// How far the band's lines sit inside the frame's, in points.
    static let bandInset: CGFloat = 26

    let standing: TideStanding
    let latDatum: Double?
    let hatDatum: Double?
    var imperial: Bool = false

    /// The levels, top to bottom, on one scale.
    ///
    /// The span is the outermost pair present: the astronomical frame where the
    /// station has one, otherwise the fortnight's own band, which then becomes
    /// the outermost thing and fills the box rather than leaving the figure
    /// huddled in the middle of an axis nothing bounds.
    /// Room above the top line and below the bottom one for their labels,
    /// which sit beside the line and would otherwise be clipped by the card.
    static let verticalInset: CGFloat = 10

    static func levels(standing: TideStanding, latDatum: Double?, hatDatum: Double?,
                       height rawHeight: CGFloat, width: CGFloat = 320, imperial: Bool = false) -> [Level] {
        let height = Swift.max(rawHeight - verticalInset * 2, 1)
        // The band sits inside the frame so the nesting is visible as nesting
        // rather than as four lines of equal weight.
        let band = Swift.max(width - bandInset * 2, curveInset * 3)
        let bandLow = standing.windowLowest.height
        let bandHigh = standing.windowHighest.height
        let lo = latDatum.map { Swift.min($0, bandLow) } ?? bandLow
        let hi = hatDatum.map { Swift.max($0, bandHigh) } ?? bandHigh
        let span = Swift.max(hi - lo, 0.01)
        func y(_ h: Double) -> CGFloat { verticalInset + height - CGFloat((h - lo) / span) * height }

        var out: [Level] = []
        if let hatDatum {
            out.append(Level(role: .absoluteHigh, metres: hatDatum, y: y(hatDatum), width: width,
                             label: String(localized: "HAT · highest it ever gets",
                                           comment: "Figure label for Highest Astronomical Tide. Keep HAT exact."),
                             isMerged: false))
        }
        out.append(Level(role: .fortnightHigh, metres: bandHigh, y: y(bandHigh), width: band,
                         label: String(localized: "the fortnight's highest",
                                       comment: "Figure label for the top of the surrounding month."),
                         isMerged: false))
        out.append(Level(role: .fortnightLow, metres: bandLow, y: y(bandLow), width: band,
                         label: String(localized: "the fortnight's lowest",
                                       comment: "Figure label for the bottom of the surrounding month."),
                         isMerged: false))
        if let latDatum {
            out.append(Level(role: .absoluteLow, metres: latDatum, y: y(latDatum), width: width,
                             label: String(localized: "LAT · lowest it ever gets",
                                           comment: "Figure label for Lowest Astronomical Tide. Keep LAT exact."),
                             isMerged: false))
        }
        out.append(Level(role: .selected, metres: standing.selected.height,
                         y: y(standing.selected.height), width: band,
                         label: standing.selected.kind == .low
                             ? String(localized: "this low", comment: "Figure label for the selected low tide.")
                             : String(localized: "this high", comment: "Figure label for the selected high tide."),
                         isMerged: false))
        return merging(out.sorted { $0.y < $1.y })
    }

    /// Collapse any run of levels within `minimumSeparation` into the outermost
    /// of them, carrying both labels. The merged line keeps the wider width, so
    /// a frame that has absorbed a band line still reads as the frame.
    private static func merging(_ sorted: [Level]) -> [Level] {
        var out: [Level] = []
        for level in sorted {
            guard let last = out.last, abs(last.y - level.y) < minimumSeparation else {
                out.append(level)
                continue
            }
            // The selected turn never loses its identity to a merge: it is the
            // one line the reader came here to find.
            let keep = level.role == .selected ? level : last
            out[out.count - 1] = Level(
                role: keep.role, metres: keep.metres, y: keep.y,
                width: Swift.max(last.width, level.width),
                // Only the surviving level's own name. Spelling both out makes
                // a run-on that overflows the column, and when the survivor is
                // the selected turn the caption beneath already says the rest.
                label: keep.label, isMerged: true)
        }
        return out
    }

    /// One measured difference, drawn the way a section drawing measures one:
    /// extension lines out to a chain, ticks at each end, the value sitting on
    /// it. `isOverall` is the outer chain — everything this station does.
    struct Dimension: Equatable {
        let fromY: CGFloat
        let toY: CGFloat
        let metres: Double
        let label: String
        let isOverall: Bool
        /// The gap the caption leads with. Drawn as ONE segment so the number a
        /// reader acts on is a measurement off the picture rather than a
        /// separate calculation that can drift from it.
        let isHeadline: Bool
    }

    /// The chain, bottom to top. Members are the station's floor and ceiling,
    /// the selected turn, and the fortnight line on the FAR side of it — the
    /// near-side one is left as a reference line, because putting a tick there
    /// would split the headline gap in two and the caption's number would stop
    /// being a thing you can measure off the drawing.
    ///
    /// Empty without bounds: there is nothing absolute to measure against, and
    /// a chain drawn off the fortnight alone would imply one.
    static func dimensions(standing: TideStanding, latDatum: Double?, hatDatum: Double?,
                           height rawHeight: CGFloat, width: CGFloat = 320, imperial: Bool) -> [Dimension] {
        guard let latDatum, let hatDatum else { return [] }
        let height = Swift.max(rawHeight - verticalInset * 2, 1)
        let low = standing.selected.kind == .low
        let bandLow = standing.windowLowest.height
        let bandHigh = standing.windowHighest.height
        let lo = Swift.min(latDatum, bandLow), hi = Swift.max(hatDatum, bandHigh)
        let span = Swift.max(hi - lo, 0.01)
        func y(_ h: Double) -> CGFloat { verticalInset + height - CGFloat((h - lo) / span) * height }

        let far = low ? bandHigh : bandLow
        let members = ([latDatum, standing.selected.height, far, hatDatum]).sorted()
        // The headline runs from the selected turn to its own end: under a low
        // the floor — how much water could still go away — and under a high the
        // ceiling, which is the clearance question.
        let headlineEnd = low ? latDatum : hatDatum
        var out: [Dimension] = []
        for (a, b) in zip(members, members.dropFirst()) where b - a > 0.0005 {
            let isHeadline = (a == headlineEnd && b == standing.selected.height)
                || (b == headlineEnd && a == standing.selected.height)
            out.append(Dimension(fromY: y(a), toY: y(b), metres: b - a,
                                 label: dimensionLabel(b - a, imperial),
                                 isOverall: false, isHeadline: isHeadline))
        }
        out.append(Dimension(fromY: y(latDatum), toY: y(hatDatum), metres: hatDatum - latDatum,
                             label: dimensionLabel(hatDatum - latDatum, imperial),
                             isOverall: true, isHeadline: false))
        return out
    }

    /// Spoken in full: a drawing may never be the only carrier of meaning
    /// (WCAG 1.4.1), which #97 wrote down for the magnitude ramp and holds
    /// here for the same reason.
    static func summary(levels: [Level], imperial: Bool) -> String {
        levels.map(\.label).joined(separator: ". ")
    }

    /// The band wears the curve's own high/low inks — the pair the strip uses
    /// at a turn — because the band's two lines ARE a high and a low.
    private func tint(_ role: Role) -> Color {
        if role == .selected { return standing.selected.kind == .low ? SN.graphLow : SN.graphHigh }
        return role == .fortnightHigh ? SN.graphHigh : SN.graphLow
    }

    private var drawn: [Level] {
        Self.levels(standing: standing, latDatum: latDatum, hatDatum: hatDatum,
                    height: boxHeight, imperial: imperial)
    }
    private let boxHeight: CGFloat = 190

    var body: some View {
        // A section drawing, not a chart: every level carries its own height,
        // and the differences between them are measured rather than described.
        Canvas { ctx, size in
            // Measured against the longest label this draws: a 26-character
            // level name at 9.5pt needs about 40% of the card's width, so the
            // axis sits left of centre rather than on it.
            let axisX = size.width * 0.42
            // Far enough left that a dimension's end ticks never cross the
            // level values sitting just inboard of the axis.
            let chainX = size.width * 0.20
            let overallX = size.width * 0.07
            let levels = Self.levels(standing: standing, latDatum: latDatum, hatDatum: hatDatum,
                                     height: size.height, width: size.width, imperial: imperial)

            func write(_ s: String, _ c: Color, at p: CGPoint, _ anchor: UnitPoint, _ pt: CGFloat = 9.5) {
                // A section drawing's numbers are a column of measurements:
                // monospacedDigit() keeps them aligned as the scrub moves them.
                var t = ctx.resolve(Text(s).font(.system(size: pt).monospacedDigit()))
                t.shading = .color(c)
                ctx.draw(t, at: p, anchor: anchor)
            }

            for level in levels {
                let absolute = level.role == .absoluteHigh || level.role == .absoluteLow
                let ink = absolute ? SN.foam.opacity(0.42) : tint(level.role)
                var line = Path()
                line.move(to: CGPoint(x: axisX, y: level.y))
                line.addLine(to: CGPoint(x: axisX + size.width * 0.15, y: level.y))
                ctx.stroke(line, with: .color(ink), lineWidth: absolute ? 1.2 : 1.6)
                // Extension line back to the chains, as thin as a drafting one.
                var ext = Path()
                ext.move(to: CGPoint(x: overallX - 6, y: level.y))
                ext.addLine(to: CGPoint(x: axisX - 34, y: level.y))
                ctx.stroke(ext, with: .color(ink.opacity(0.3)), lineWidth: 0.7)
                write(level.label, ink, at: CGPoint(x: axisX + size.width * 0.165, y: level.y), .leading)
                write(dimensionLabel(level.metres, imperial), ink,
                      at: CGPoint(x: axisX - 6, y: level.y), .trailing, 10)
            }

            // The turn itself, the one thing on here that is not a reference.
            if let selected = levels.first(where: { $0.role == .selected }) {
                CurveDrawing.dot(ctx, at: CGPoint(x: axisX + 14, y: selected.y), color: tint(.selected))
            }

            for d in Self.dimensions(standing: standing, latDatum: latDatum, hatDatum: hatDatum,
                                     height: size.height, width: size.width, imperial: imperial) {
                let x = d.isOverall ? overallX : chainX
                let ink = d.isHeadline ? tint(.selected) : SN.foam.opacity(d.isOverall ? 0.5 : 0.4)
                var line = Path()
                line.move(to: CGPoint(x: x, y: d.fromY))
                line.addLine(to: CGPoint(x: x, y: d.toY))
                ctx.stroke(line, with: .color(ink), lineWidth: 0.9)
                for y in [d.fromY, d.toY] {   // the architect's slash, not an arrowhead
                    var tick = Path()
                    tick.move(to: CGPoint(x: x - 4, y: y + 4))
                    tick.addLine(to: CGPoint(x: x + 4, y: y - 4))
                    ctx.stroke(tick, with: .color(ink), lineWidth: 1.1)
                }
                // The value sits ON the dimension line, so punch the line out
                // from behind it rather than letting the two overlap.
                let mid = CGPoint(x: x, y: (d.fromY + d.toY) / 2)
                ctx.fill(Path(CGRect(x: mid.x - 19, y: mid.y - 7, width: 38, height: 14)),
                         with: .color(SN.canvas))
                write(d.label, ink.opacity(1), at: mid, .center, 9.5)
            }
        }
        .frame(height: boxHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(levels: drawn, imperial: imperial))
    }
}

/// A measurement as the drawing prints it. Its own one-line declaration so
/// TypeScaleTests' indirection key names the symbol its text walk computes —
/// `dimensions`' signature spans two lines (see WidgetSnapshot.swift:normalize).
private func dimensionLabel(_ metres: Double, _ imperial: Bool) -> String {
    formatHeight(metres, imperial: imperial)
}
