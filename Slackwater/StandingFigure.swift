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
    }

    struct Level: Equatable {
        let role: Role
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
    /// The swing's own heights, sampled. The sheet supplies them; the figure
    /// never predicts.
    let points: [TidePoint]
    let latDatum: Double?
    let hatDatum: Double?
    var imperial: Bool = false

    /// The levels, top to bottom, on one scale.
    ///
    /// The span is the outermost pair present: the astronomical frame where the
    /// station has one, otherwise the fortnight's own band, which then becomes
    /// the outermost thing and fills the box rather than leaving the figure
    /// huddled in the middle of an axis nothing bounds.
    static func levels(standing: TideStanding, latDatum: Double?, hatDatum: Double?,
                       height: CGFloat, width: CGFloat = 320, imperial: Bool = false) -> [Level] {
        // The band sits inside the frame so the nesting is visible as nesting
        // rather than as four lines of equal weight.
        let band = Swift.max(width - bandInset * 2, curveInset * 3)
        let bandLow = standing.windowLowest.height
        let bandHigh = standing.windowHighest.height
        let lo = latDatum.map { Swift.min($0, bandLow) } ?? bandLow
        let hi = hatDatum.map { Swift.max($0, bandHigh) } ?? bandHigh
        let span = Swift.max(hi - lo, 0.01)
        func y(_ h: Double) -> CGFloat { height - CGFloat((h - lo) / span) * height }

        var out: [Level] = []
        if let hatDatum {
            out.append(Level(role: .absoluteHigh, y: y(hatDatum), width: width,
                             label: String(localized: "the highest water this station ever sees",
                                           comment: "Figure label for Highest Astronomical Tide."),
                             isMerged: false))
        }
        out.append(Level(role: .fortnightHigh, y: y(bandHigh), width: band,
                         label: String(localized: "the highest high of the fortnight",
                                       comment: "Figure label for the top of the surrounding month."),
                         isMerged: false))
        out.append(Level(role: .fortnightLow, y: y(bandLow), width: band,
                         label: String(localized: "the lowest low of the fortnight",
                                       comment: "Figure label for the bottom of the surrounding month."),
                         isMerged: false))
        if let latDatum {
            out.append(Level(role: .absoluteLow, y: y(latDatum), width: width,
                             label: String(localized: "the lowest water this station ever sees",
                                           comment: "Figure label for Lowest Astronomical Tide."),
                             isMerged: false))
        }
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
            out[out.count - 1] = Level(
                role: last.role, y: last.y, width: Swift.max(last.width, level.width),
                label: String(localized: "\(last.label), and \(level.label)",
                              comment: "Figure label where two levels are too close to draw apart."),
                isMerged: true)
        }
        return out
    }

    /// The swing itself, on the levels' own axis — which is the whole premise:
    /// drawn against the same scale as the frame, the curve's amplitude IS its
    /// amplitude, and a swing using a third of the fortnight occupies a third
    /// of the band. Inset horizontally so the band's lines outrun it.
    static func curvePath(_ points: [TidePoint], standing: TideStanding,
                          latDatum: Double?, hatDatum: Double?, size: CGSize) -> Path {
        let bandLow = standing.windowLowest.height
        let bandHigh = standing.windowHighest.height
        let lo = latDatum.map { Swift.min($0, bandLow) } ?? bandLow
        let hi = hatDatum.map { Swift.max($0, bandHigh) } ?? bandHigh
        let span = Swift.max(hi - lo, 0.01)
        guard let first = points.first, let last = points.last,
              last.time > first.time else { return Path() }
        let seconds = last.time.timeIntervalSince(first.time)
        let usable = Swift.max(size.width - curveInset * 2, 1)
        var path = Path()
        for (i, p) in points.enumerated() {
            let x = curveInset + usable * CGFloat(p.time.timeIntervalSince(first.time) / seconds)
            let y = size.height - CGFloat((p.height - lo) / span) * size.height
            i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
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
        role == .fortnightHigh ? SN.graphHigh : SN.graphLow
    }

    private var drawn: [Level] {
        Self.levels(standing: standing, latDatum: latDatum, hatDatum: hatDatum,
                    height: boxHeight, imperial: imperial)
    }
    private let boxHeight: CGFloat = 190

    var body: some View {
        Canvas { ctx, size in
            // Frame first, curve on top: the reader reads the curve against the
            // levels, not the levels across the curve.
            for level in Self.levels(standing: standing, latDatum: latDatum, hatDatum: hatDatum,
                                     height: size.height, width: size.width, imperial: imperial) {
                let w = Swift.min(level.width, size.width)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: level.y))
                line.addLine(to: CGPoint(x: w, y: level.y))
                // The frame is quiet and the band is inked: the band is the
                // comparison being made, the frame is the room it happens in.
                let absolute = level.role == .absoluteHigh || level.role == .absoluteLow
                ctx.stroke(line, with: .color(absolute ? SN.foam.opacity(0.3) : tint(level.role)),
                           lineWidth: absolute ? 1 : 1.8)
                var label = ctx.resolve(Text(level.label)
                    .font(.system(size: 10))
                    .foregroundStyle(absolute ? SN.foam.opacity(0.55) : tint(level.role)))
                label.shading = .color(absolute ? SN.foam.opacity(0.55) : tint(level.role))
                let high = level.role == .absoluteHigh || level.role == .fortnightHigh
                ctx.draw(label, at: CGPoint(x: w - 2, y: level.y + (high ? 9 : -9)),
                         anchor: high ? .topTrailing : .bottomTrailing)
            }
            ctx.stroke(Self.curvePath(points, standing: standing, latDatum: latDatum,
                                      hatDatum: hatDatum, size: size),
                       with: .color(SN.graphLine), lineWidth: 2.6)
        }
        .frame(height: boxHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(levels: drawn, imperial: imperial))
    }
}
