import SwiftUI
import TideEngine

/// The curve on a station card: one swing of history behind now and three
/// ahead, tide height or signed current speed as a line, and a dot with
/// value/time labels at each extreme. It is the card's only carrier of the
/// coming extremes, so it reads them out to VoiceOver rather than hiding.
struct StationCardGraph: View {
    /// One extreme-to-extreme swing: half the M2 semidiurnal period (12.42 h).
    static let swing: TimeInterval = (12.42 / 2) * 3600
    /// Four swings total, weighted toward the future — the past is context,
    /// the forecast is the point.
    static let backWindow: TimeInterval = 1.5 * swing
    static let forwardWindow: TimeInterval = 2.5 * swing
    static let window: TimeInterval = backWindow + forwardWindow
    /// Sampling interval for the builders' point series.
    static let sampleStep: TimeInterval = 600

    /// Shorthands for the theme's curve tokens (SN doc comment: the Neaps
    /// dark-mode palette, full saturation for the card's hero element).
    private static let line = SN.graphLine
    private static let high = SN.graphHigh
    private static let low = SN.graphLow

    // MARK: - Tunables: every visual knob, in one place.

    /// Vertical headroom above and below the sampled range, as a fraction
    /// of it.
    private static let domainPadFraction = 0.25
    /// Strip at the bottom reserved for the time axis; the curve plots above
    /// it so a trough never runs into the labels.
    private static let axisHeight: CGFloat = 6
    private static let lineWidth: CGFloat = 2.5
    /// The area gradient at full intensity…
    private static let fillOpacity = 0.5
    /// …and the tide fill's floor at the card bottom.
    private static let tideFillFloor = 0.05
    /// The dotted zero/datum reference lines.
    private static let referenceLineOpacity = 0.35
    private static let referenceLineDash: [CGFloat] = [1, 3]
    /// How close (in data units — metres) a low must come to chart datum
    /// before the datum line appears on a tide card.
    private static let nearDatum = 0.1
    /// The line left of now, and the labels of moments already passed.
    private static let pastLineOpacity = 0.35
    private static let pastLabelFade = 0.45
    /// Extreme and slack dots; the now dot is its own size.
    private static let dotRadius: CGFloat = 2.5
    private static let nowDotDiameter: CGFloat = 7
    /// The background-punched ring beyond a dot's edge.
    private static let haloGap: CGFloat = 2.5
    /// An extreme closer than this to a card edge keeps its dot but drops
    /// its labels; slack axis times use their own, tighter margin.
    private static let labelEdgeMargin: CGFloat = 34
    private static let axisEdgeMargin: CGFloat = 20
    /// The pointer icon's distance from the value on the band.
    private static let pointerOffset: CGFloat = 18
    private static let valueFontSize: CGFloat = 13
    private static let pointerFontSize: CGFloat = 13
    private static let tideTimeFontSize: CGFloat = 10
    private static let slackTimeFontSize: CGFloat = 9
    /// Axis-label center height above the card bottom.
    private static let tideTimeBaseline: CGFloat = 10
    private static let slackTimeBaseline: CGFloat = 8

    struct Point {
        let time: Date
        let value: Double
    }

    struct Extreme {
        let time: Date
        let value: Double
        let valueText: String
        let timeText: String
        /// High tide / max flood (vs low / max ebb) — picks the label color
        /// (teal vs amber) and the pointer direction.
        let high: Bool
        /// A current extreme's set bearing. When present the pointer is the
        /// app's CompassArrow (↑ rotated to the bearing, "water goes this
        /// way") instead of the tide high/low arrows.
        var deg: Double? = nil
    }

    let points: [Point]
    let extremes: [Extreme]
    /// The curve spans now − `backWindow` … now + `forwardWindow`.
    let now: Date
    /// Signed current curves keep zero in the domain so flood/ebb read as
    /// above/below the resting line.
    var includesZero = false
    /// Formats the slack-crossing times computed inside the canvas; the
    /// extremes arrive with their times already formatted.
    var tz: TimeZone = .current

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let start = now.addingTimeInterval(-Self.backWindow)
            let xScale = size.width / Self.window
            var lo = points.map(\.value).min() ?? 0
            var hi = points.map(\.value).max() ?? 1
            if includesZero { lo = min(lo, 0); hi = max(hi, 0) }
            // The water's own range, before display padding — "does the tide
            // actually get near datum" is judged against this, not the
            // padded domain.
            let sampledLo = lo
            let pad = max((hi - lo) * Self.domainPadFraction, 0.001)
            lo -= pad; hi += pad

            func x(_ t: Date) -> CGFloat { t.timeIntervalSince(start) * xScale }
            let plotHeight = size.height - Self.axisHeight
            func y(_ v: Double) -> CGFloat { plotHeight * (1 - (v - lo) / (hi - lo)) }

            var line = Path()
            line.move(to: CGPoint(x: x(points[0].time), y: y(points[0].value)))
            for p in points.dropFirst() {
                line.addLine(to: CGPoint(x: x(p.time), y: y(p.value)))
            }

            func referenceLine(at lineY: CGFloat) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: lineY))
                path.addLine(to: CGPoint(x: size.width, y: lineY))
                context.stroke(path, with: .color(SN.foam.opacity(Self.referenceLineOpacity)),
                               style: StrokeStyle(lineWidth: 1, dash: Self.referenceLineDash))
            }

            // The area fill, closed to the zero line for signed curves and
            // to the card bottom for tides.
            let baseY = includesZero ? y(0) : size.height
            var area = line
            area.addLine(to: CGPoint(x: x(points[points.count - 1].time), y: baseY))
            area.addLine(to: CGPoint(x: x(points[0].time), y: baseY))
            area.closeSubpath()
            if includesZero {
                // Distance from the zero line IS speed, so the gradient is
                // vertical and ANCHORED AT ZERO: transparent at slack,
                // intensifying outward — flood blue above, ebb amber below.
                // A shallow lobe near slack sits entirely in the transparent
                // zone; a max reaches into the intense one. Both hues vanish
                // at the same line, so there is no seam at a crossing.
                let zeroStop = baseY / size.height
                context.fill(area, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Self.line.opacity(Self.fillOpacity), location: 0),
                        .init(color: Self.line.opacity(0), location: zeroStop),
                        .init(color: Self.low.opacity(0), location: zeroStop),
                        .init(color: Self.low.opacity(Self.fillOpacity), location: 1),
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)))
                // The slack datum, dotted like Neaps' zero reference line —
                // and the one mark that says "current, not tide" at a glance.
                referenceLine(at: baseY)
            } else {
                // A tide's intensity is the water level itself, so the fade
                // stays vertical (Neaps TideGraphChart): strongest at the
                // surface, easing toward the bottom.
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [Self.line.opacity(Self.fillOpacity),
                                      Self.line.opacity(Self.tideFillFloor)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)))
                // Chart datum, but only when the water actually gets near
                // it: most curves sit entirely above zero, and forcing the
                // datum into view would flatten them. When a low dips toward
                // or under datum the line appears where it matters.
                if sampledLo <= Self.nearDatum {
                    referenceLine(at: y(0))
                }
            }

            // The past is context, the future is the forecast: the line
            // draws muted left of now and at full strength to the right,
            // split by clipping the same path both ways.
            let nowX = x(now)
            var past = context
            past.clip(to: Path(CGRect(x: 0, y: 0, width: nowX, height: size.height)))
            past.stroke(line, with: .color(Self.line.opacity(Self.pastLineOpacity)),
                        lineWidth: Self.lineWidth)
            var future = context
            future.clip(to: Path(CGRect(x: nowX, y: 0,
                                        width: size.width - nowX, height: size.height)))
            future.stroke(line, with: .color(Self.line), lineWidth: Self.lineWidth)

            // A halo that truly matches the background: erase the line and
            // fill in a ring around each dot (destinationOut punches through
            // to whatever is behind the Canvas) rather than painting a guess
            // at the card color over them.
            func punchHalo(at p: CGPoint, dotRadius: CGFloat) {
                let radius = dotRadius + Self.haloGap
                var eraser = context
                eraser.blendMode = .destinationOut
                eraser.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                                   width: radius * 2, height: radius * 2)),
                            with: .color(.black))
            }

            func dot(at p: CGPoint, color: Color) {
                punchHalo(at: p, dotRadius: Self.dotRadius)
                context.fill(Path(ellipseIn: CGRect(x: p.x - Self.dotRadius,
                                                    y: p.y - Self.dotRadius,
                                                    width: Self.dotRadius * 2,
                                                    height: Self.dotRadius * 2)),
                             with: .color(color))
            }

            for e in extremes {
                // A past extreme fades like the past line.
                let fade = e.time < now ? Self.pastLabelFade : 1.0
                let tint = (e.high ? Self.high : Self.low).opacity(fade)
                let text = SN.foam.opacity(fade)
                let dotAt = CGPoint(x: x(e.time), y: y(e.value))
                let isCurrent = e.deg != nil
                // Tide extremes are moments (a dot on the curve, a time on
                // the axis). A current extreme is just the peak of a run of
                // moving water — the slack dots already mark the moments
                // that matter — so it keeps only its value and set arrow.
                if !isCurrent {
                    dot(at: dotAt, color: tint)
                }
                // An extreme hugging the card edge keeps its dot but drops
                // its labels — a shifted label detaches from its dot and
                // reads as belonging to the wrong spot.
                guard dotAt.x >= Self.labelEdgeMargin,
                      dotAt.x <= size.width - Self.labelEdgeMargin else { continue }
                // The values form one rail across the vertical middle, with
                // each extreme's icon on the dot's side of its number —
                // above for high/flood, below for low/ebb.
                let labelX = dotAt.x
                // The band rides the zero line on a signed curve — flood and
                // ebb rarely peak equally, so zero is not the canvas middle.
                let bandY = includesZero ? baseY : size.height / 2
                let pointerAt = CGPoint(x: labelX,
                                        y: bandY + (e.high ? -Self.pointerOffset : Self.pointerOffset))
                if let deg = e.deg {
                    // Current extreme: the set arrow (CompassArrow's idea,
                    // ↑ rotated to the bearing), not the tide high/low mark.
                    // The SF Symbol, not the "↑" text glyph — a text arrow
                    // at the same point size renders visibly smaller than
                    // the sibling arrow.up.to.line symbol.
                    var rotated = context
                    rotated.translateBy(x: pointerAt.x, y: pointerAt.y)
                    rotated.rotate(by: .degrees(deg))
                    rotated.draw(Text(Image(systemName: "arrow.up"))
                                    .font(.system(size: Self.pointerFontSize, weight: .bold))
                                    .foregroundStyle(tint),
                                 at: .zero)
                } else {
                    context.draw(Text(Image(systemName: e.high ? "arrow.up.to.line" : "arrow.down.to.line"))
                                    .font(.system(size: Self.pointerFontSize, weight: .bold))
                                    .foregroundStyle(tint),
                                 at: pointerAt)
                }
                context.draw(Text(e.valueText)
                                .font(.system(size: Self.valueFontSize, weight: .bold).monospacedDigit())
                                .foregroundStyle(text),
                             at: CGPoint(x: labelX, y: bandY))
                if !isCurrent {
                    context.draw(Text(e.timeText)
                                    .font(.system(size: Self.tideTimeFontSize).monospacedDigit())
                                    .fontWeight(.medium)
                                    .foregroundStyle(text),
                                 at: CGPoint(x: labelX, y: size.height - Self.tideTimeBaseline))
                }
            }

            // Slack: a green dot at each zero crossing (interpolated between
            // the bracketing samples) — the moment this app is named after,
            // in the green the SLACK pill already speaks
            // (testSlackIsGreenWhereverItAppears).
            if includesZero {
                for i in 1..<points.count {
                    let a = points[i - 1], b = points[i]
                    guard (a.value < 0) != (b.value < 0) else { continue }
                    let f = a.value / (a.value - b.value)
                    let cx = x(a.time) + (x(b.time) - x(a.time)) * f
                    let when = a.time.addingTimeInterval(
                        b.time.timeIntervalSince(a.time) * TimeInterval(f))
                    let fade = when < now ? Self.pastLabelFade : 1.0
                    dot(at: CGPoint(x: cx, y: baseY), color: SN.go.opacity(fade))
                    // Its time joins the bottom axis; the green dot above it
                    // already says slack.
                    guard cx >= Self.axisEdgeMargin,
                          cx <= size.width - Self.axisEdgeMargin else { continue }
                    context.draw(Text(cardTime(when, tz))
                                    .font(.system(size: Self.slackTimeFontSize).monospacedDigit())
                                    .foregroundStyle(SN.foam.opacity(fade)),
                                 at: CGPoint(x: cx, y: size.height - Self.slackTimeBaseline))
                }
            }

            // The "now" dot rides the curve one swing in from the left edge.
            if let nowValue = points.min(by: {
                abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now))
            })?.value {
                let nowDot = CGPoint(x: x(now), y: y(nowValue))
                let r = Self.nowDotDiameter / 2
                punchHalo(at: nowDot, dotRadius: r)
                context.fill(Path(ellipseIn: CGRect(x: nowDot.x - r, y: nowDot.y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(SN.paper))
            }
        }
        .accessibilityLabel("\(Int((Self.window / 3600).rounded()))-hour curve")
        .accessibilityValue(extremes.map { "\($0.valueText) at \($0.timeText)" }
            .joined(separator: ", "))
    }
}

extension TideStationRecord {
    func cardGraph(at now: Date, imperial: Bool) -> StationCardGraph {
        let start = now.addingTimeInterval(-StationCardGraph.backWindow)
        let end = now.addingTimeInterval(StationCardGraph.forwardWindow)
        let s = engineStation
        return StationCardGraph(
            points: s.heights(from: start, to: end, step: StationCardGraph.sampleStep)
                .map { .init(time: $0.time, value: $0.height) },
            extremes: s.extremes(from: start, to: end).map {
                .init(time: $0.time, value: $0.height,
                      valueText: "\(formatHeight($0.height, imperial: imperial)) \(heightUnit(imperial: imperial))",
                      timeText: cardTime($0.time, tz),
                      high: $0.kind == .high)
            },
            now: now)
    }
}

extension CurrentStationRecord {
    /// `tilde` hedges the extreme values (`~3.0 kn`) for a provisional
    /// (60-day) gate, like the reading's own tilde.
    func cardGraph(at now: Date, unit: String, tilde: Bool = false) -> StationCardGraph {
        let start = now.addingTimeInterval(-StationCardGraph.backWindow)
        let end = now.addingTimeInterval(StationCardGraph.forwardWindow)
        let s = engineStation
        return StationCardGraph(
            points: s.speeds(from: start, to: end, step: StationCardGraph.sampleStep)
                .map { .init(time: $0.time, value: $0.speed) },
            extremes: s.events(from: start, to: end)
                .filter { $0.kind != .slack }
                .map {
                    .init(time: $0.time, value: $0.speed,
                          valueText: "\(tilde ? "~" : "")\(formatSpeed(abs($0.speed), unit: unit)) \(speedUnitLabel(unit))",
                          timeText: cardTime($0.time, tz),
                          high: $0.kind == .maxFlood,
                          deg: setDegrees(signed: $0.speed))
                },
            now: now,
            includesZero: true,
            tz: tz)
    }
}

extension ChsOnlineWindow {
    func cardGraph(at now: Date, unit: String) -> StationCardGraph {
        let start = now.addingTimeInterval(-StationCardGraph.backWindow)
        let end = now.addingTimeInterval(StationCardGraph.forwardWindow)
        let tz = TimeZone(identifier: timezone) ?? .current
        return StationCardGraph(
            points: points.filter { $0.time >= start && $0.time <= end }
                .map { .init(time: $0.time, value: $0.speed) },
            extremes: sampleEvents(points)
                .filter { $0.kind != .slack && $0.time >= start && $0.time <= end }
                .map {
                    .init(time: $0.time, value: $0.speed,
                          valueText: "\(formatSpeed(abs($0.speed), unit: unit)) \(speedUnitLabel(unit))",
                          timeText: cardTime($0.time, tz),
                          high: $0.kind == .maxFlood,
                          deg: $0.speed >= 0 ? floodDirection : ebbDirection)
                },
            now: now,
            includesZero: true,
            tz: tz)
    }
}
