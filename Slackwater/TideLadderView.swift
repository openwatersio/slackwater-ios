// Slackwater — GPL v3. The ladder, drawn. See TideLadder.swift for what it is
// and what it deliberately leaves out.
import SwiftUI

/// Nudge overlapping label centres apart while their rules stay at true
/// height. `ys` must be sorted ascending (top of the gauge first); the result
/// is the same count, same order, each at least `minGap` from its neighbour
/// and inside `span`.
///
/// Two passes: down from the top, then back up when the last one has been
/// pushed past the bottom. That settles the handful of rows here without
/// iterating to a fixed point.
///
/// ponytail: when the rungs need more room than the gauge has, they are spread
/// evenly and the spacing stops being true. That is the honest failure, and
/// the alternative — clipping — hides rungs entirely. It takes a real cluster
/// to reach: the gauge scales to its own rungs, so only rungs bunched INSIDE
/// their span crowd, never a narrow station. Give the gauge more height before
/// reaching for anything cleverer.
func dodgedLabelYs(_ ys: [CGFloat], minGap: CGFloat, in span: ClosedRange<CGFloat>) -> [CGFloat] {
    guard ys.count > 1 else { return ys.map { min(max($0, span.lowerBound), span.upperBound) } }
    let needed = CGFloat(ys.count - 1) * minGap
    let room = span.upperBound - span.lowerBound
    guard needed <= room else {
        let step = room / CGFloat(ys.count - 1)
        return ys.indices.map { span.lowerBound + CGFloat($0) * step }
    }

    var out = ys.map { min(max($0, span.lowerBound), span.upperBound) }
    for i in out.indices.dropFirst() {
        out[i] = max(out[i], out[i - 1] + minGap)
    }
    if out[out.count - 1] > span.upperBound {
        out[out.count - 1] = span.upperBound
        for i in out.indices.dropLast().reversed() {
            out[i] = min(out[i], out[i + 1] - minGap)
        }
    }
    return out
}

struct TideLadderView: View {
    let rungs: [LadderRung]
    let imperial: Bool
    let tz: TimeZone
    var onJump: ((Date) -> Void)? = nil
    /// Tall enough that nine rows clear `labelGap` at the default text size,
    /// which is where `dodgedLabelYs` stops telling the truth about spacing.
    ///
    /// The scale zooms to the rungs, so a narrow station is not the problem —
    /// Hundsmühlen's 4 cm envelope fills the gauge exactly as Port Isaac's 15 m
    /// one does, and the labelled values carry the difference. What crowds is
    /// a CLUSTER inside the span: at Friday Harbor five rungs share the top
    /// fifth while the bottom half is one open reach of water. That crowding
    /// is the reading, and the height it costs is what keeps it legible.
    var gaugeHeight: CGFloat = 400

    /// The label block sits above its rule rather than on it.
    private let labelLift: CGFloat = 8
    private let labelGap: CGFloat = 16
    private let gutter: CGFloat = 10

    /// Heights are padded by a tenth of the span so the top and bottom rungs
    /// are not drawn on the frame's edge. The pad is a FRACTION, never a floor
    /// in metres: 374 bundled stations have an envelope under half a metre and
    /// a fixed 5 cm pad would squeeze Hundsmühlen's 4 cm ladder into the middle
    /// third of the gauge. The absolute floor is only the degenerate case where
    /// every rung sits on the same water and there is no span to divide by.
    private var scale: (lo: Double, hi: Double) {
        let heights = rungs.map(\.height)
        let lo = heights.min() ?? 0, hi = heights.max() ?? 1
        let pad = hi > lo ? (hi - lo) * 0.1 : 0.05
        return (lo - pad, hi + pad)
    }

    private func y(_ height: Double, in h: CGFloat) -> CGFloat {
        let (lo, hi) = scale
        return h * CGFloat((hi - height) / (hi - lo))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            MonoLabel(text: heightUnit(imperial: imperial), color: SN.foam.opacity(0.4))
            gauge
        }
    }

    private var gauge: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let ruleYs = rungs.map { y($0.height, in: h) }
            // The label wants to sit above its rule; dodge from there, so a row
            // that never collides lands exactly where it was asked to.
            let labelYs = dodgedLabelYs(ruleYs.map { $0 - labelLift },
                                        minGap: labelGap,
                                        in: 0...max(h - labelGap, 0))
            ZStack(alignment: .topLeading) {
                water(in: geo.size)
                swingBar(ruleYs: ruleYs, in: h)
                ForEach(Array(rungs.enumerated()), id: \.element.id) { i, rung in
                    rule(rung, width: geo.size.width).offset(y: ruleYs[i])
                    leader(from: ruleYs[i], to: labelYs[i] + labelLift)
                    row(rung).offset(y: labelYs[i] - labelGap / 2)
                }
            }
        }
        .frame(height: gaugeHeight)
    }

    // MARK: - Water

    /// Fills from the water's own line down, on the strip's terms: blue above
    /// chart datum fading to nothing at it, amber below, both vanishing on the
    /// same line so a low under datum reads as "less water than the chart
    /// shows" with no seam. `CurveDrawing.datumFill` is the original; this is
    /// the same two hues on a rectangle rather than under a curve, and the two
    /// must not drift apart — a reader sees them on the same page.
    private func water(in size: CGSize) -> some View {
        let nowY = rungs.first { $0.kind == .now }.map { y($0.height, in: size.height) } ?? size.height
        let datumY = min(max(y(0, in: size.height), nowY), size.height)
        let cross = size.height > nowY ? (datumY - nowY) / (size.height - nowY) : 1
        // A band rather than a point: the strip fades both hues to nothing on
        // the datum line because a curve bounds its fill, but a bare column
        // faded to nothing reads as "no water here" across the very span that
        // holds the most. Blending across a band keeps the column continuous
        // and still changes its character exactly where the heavy datum rule
        // is drawn.
        let band = 0.07
        return LinearGradient(stops: [
            .init(color: SN.graphLine.opacity(CurveStyle.fillOpacity), location: 0),
            .init(color: SN.graphLine.opacity(0.2), location: max(cross - band, 0.001)),
            .init(color: SN.graphLow.opacity(0.2), location: min(cross + band, 0.999)),
            .init(color: SN.graphLow.opacity(CurveStyle.fillOpacity * 0.7), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(width: size.width, height: max(size.height - nowY, 0))
        .offset(y: nowY)
    }

    /// The swing the centerline stands in, as an extent — the plate's "height
    /// of tide" bracket. It says at a glance how much of the station's whole
    /// envelope today's water actually moves through.
    @ViewBuilder
    private func swingBar(ruleYs: [CGFloat], in h: CGFloat) -> some View {
        let ys = zip(rungs, ruleYs).filter { $0.0.kind == .swing }.map(\.1)
        if let top = ys.min(), let bottom = ys.max(), bottom > top {
            Capsule()
                .fill(LinearGradient(colors: [SN.graphHigh, SN.graphLow],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 3, height: bottom - top)
                .offset(x: 0, y: top)
                .opacity(0.8)
        }
    }

    // MARK: - Rules and rows

    private func stroke(_ kind: LadderRung.Kind) -> (Color, CGFloat, [CGFloat]) {
        switch kind {
        case .now:    return (.white, 2, [])
        case .datum:  return (SN.foam.opacity(0.5), 1.5, [])
        case .plane:  return (SN.foam.opacity(0.22), 1, [])
        case .record: return (SN.foam.opacity(0.3), 1, CurveStyle.referenceLineDash)
        case .swing:  return (SN.foam.opacity(0.18), 1, [2, 3])
        }
    }

    private func rule(_ rung: LadderRung, width: CGFloat) -> some View {
        let (colour, lineWidth, dash) = stroke(rung.kind)
        return Path { p in
            p.move(to: CGPoint(x: gutter, y: 0))
            p.addLine(to: CGPoint(x: width, y: 0))
        }
        .stroke(colour, style: StrokeStyle(lineWidth: lineWidth, dash: dash))
        .frame(height: lineWidth)
    }

    /// Drawn only when the label has been pushed off its rule, so a displaced
    /// row still points at the water it describes rather than quietly lying
    /// about its height.
    @ViewBuilder
    private func leader(from ruleY: CGFloat, to labelY: CGFloat) -> some View {
        if abs(ruleY - labelY) > 1.5 {
            Path { p in
                p.move(to: CGPoint(x: gutter + 3, y: min(ruleY, labelY)))
                p.addLine(to: CGPoint(x: gutter + 3, y: max(ruleY, labelY)))
            }
            .stroke(SN.foam.opacity(0.2), lineWidth: 1)
        }
    }

    private func nameColour(_ kind: LadderRung.Kind) -> Color {
        switch kind {
        case .now, .datum: return .white
        case .swing:       return SN.foam.opacity(0.9)
        case .record:      return SN.foam.opacity(0.75)
        case .plane:       return SN.foam.opacity(0.6)
        }
    }

    private func row(_ rung: LadderRung) -> some View {
        HStack(spacing: 6) {
            Text(rung.name)
                .font(.caption.weight(rung.kind == .now ? .semibold : .regular))
                .foregroundStyle(nameColour(rung.kind))
            // The acronym never stands alone: it annotates the words, and a
            // reader who does not know it has already read the row.
            if let code = rung.code {
                Text(code)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(SN.foam.opacity(0.35))
            }
            if rung.jump != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(SN.foam.opacity(0.4))
            }
            Spacer(minLength: 8)
            // Bare numbers: the unit is stated once above the gauge. Nine
            // repetitions of "ft" is noise in a column whose whole job is
            // letting the eye run down it.
            Text(formatHeight(rung.height, imperial: imperial))
                .font(.caption.monospacedDigit())
                .foregroundStyle(rung.kind == .now ? .white : SN.foam.opacity(0.8))
        }
        .padding(.leading, gutter + 8)
        .frame(height: labelGap)
        .contentShape(Rectangle())
        .onTapGesture { if let t = rung.jump { onJump?(t) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rung.name), \(formatHeight(rung.height, imperial: imperial)) \(heightUnit(imperial: imperial))")
        .accessibilityAddTraits(rung.jump != nil ? .isButton : [])
        .accessibilityIdentifier("ladder-\(rung.name.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}
