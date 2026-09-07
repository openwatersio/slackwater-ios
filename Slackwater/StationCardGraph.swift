import SwiftUI
import TideEngine

/// The curve on a station card: one swing of history behind now and three
/// ahead, tide height or signed current speed as a line, and a dot with
/// value/time labels at each extreme. It is the card's only carrier of the
/// coming extremes, so it reads them out to VoiceOver rather than hiding.
///
/// The drawing itself — fills, line colour, slack runs, dots and hanging
/// readings — is `CurveDrawing`, shared with the detail strip, so the page
/// a card opens into is the same drawing at a larger scale. What is the
/// card's own: the four-swing window, the padded auto-fit domain, the axis
/// row's edge rules, and the VoiceOver summary.
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

    // MARK: - Tunables: every visual knob, in one place.

    /// Vertical headroom above and below the sampled range, as a fraction
    /// of it.
    private static let domainPadFraction = 0.25
    /// Strip at the bottom reserved for the time axis; the curve plots above
    /// it so a trough never runs into the labels.
    private static let axisHeight: CGFloat = 6
    /// An extreme closer than this to a card edge keeps its dot and axis
    /// time but drops its value label; every axis time — extreme or slack
    /// crossing — uses the tighter margin.
    private static let labelEdgeMargin: CGFloat = 34
    private static let axisEdgeMargin: CGFloat = 20
    private static let timeFontSize: CGFloat = 10
    /// Axis-label center height above the card bottom.
    private static let timeBaseline: CGFloat = 10

    struct Point {
        let time: Date
        let value: Double
    }

    struct Extreme {
        let time: Date
        let value: Double
        /// The bare number for the curve; the unit prints once in the card's reading.
        let valueText: String
        /// The number with its unit, for VoiceOver only.
        let spokenText: String
        let timeText: String
        /// High tide / max flood (vs low / max ebb) — picks the dot tint
        /// (teal vs amber) and the direction the reading hangs.
        let high: Bool
        /// A current extreme's set bearing. When present the pointer is the
        /// set arrow (↑ rotated to the bearing, "water goes this way")
        /// instead of the tide's to-bar arrows.
        var deg: Double? = nil
    }

    let points: [Point]
    let extremes: [Extreme]
    /// The curve spans now − `back` … now + `forward`.
    let now: Date
    /// The card's span by default. The small widget narrows it to half a
    /// swing back and one and a half ahead over the same points, so now
    /// sits a quarter in; everything outside the span is cropped, and the
    /// domain, datum line and spoken extremes follow the span, not the
    /// points.
    var back: TimeInterval = Self.backWindow
    var forward: TimeInterval = Self.forwardWindow
    private var start: Date { now.addingTimeInterval(-back) }
    private var end: Date { now.addingTimeInterval(forward) }
    /// Signed current curves keep zero in the domain so flood/ebb read as
    /// above/below the resting line.
    var includesZero = false
    /// Formats the axis times computed inside the canvas; the
    /// extremes arrive with their times already formatted.
    var tz: TimeZone = .current
    /// The usable slack windows (current-charts spec §4), computed by the
    /// builders from the SHARED `slackWindow` predicate against the
    /// effective threshold — never re-derived in the canvas (§6.1). Only
    /// signed current curves carry them.
    var windows: [WindowRun] = []
    /// Every slack instant on the curve, so the axis can print the bare
    /// instant where no run covers a slack. Only signed current curves.
    var slacks: [Date] = []
    /// A tide curve's rate of rise (m/hr), index-aligned with `points`, for
    /// the line's rate colour. Empty on a current curve, and the preview
    /// sines — the line is then plain blue.
    var rates: [Double] = []

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let xScale = size.width / (back + forward)
            // The visible water's range: the builders sample the card's full
            // span, and a narrower view must not flatten under an off-screen
            // swing.
            let visible = points.filter { $0.time >= start && $0.time <= end }.map(\.value)
            var lo = visible.min() ?? 0
            var hi = visible.max() ?? 1
            if includesZero { lo = min(lo, 0); hi = max(hi, 0) }
            let lowest = lo
            let pad = max((hi - lo) * Self.domainPadFraction, 0.001)
            lo -= pad; hi += pad

            func x(_ t: Date) -> CGFloat { t.timeIntervalSince(start) * xScale }
            let plotHeight = size.height - Self.axisHeight
            func y(_ v: Double) -> CGFloat { plotHeight * (1 - (v - lo) / (hi - lo)) }
            let nowX = x(now)

            /// Linear interpolation over the drawn samples, so a run's ends
            /// and the now dot ride the curve as rendered.
            func valueAt(_ t: Date) -> Double {
                var prev = points[0]
                for p in points {
                    if p.time >= t {
                        let span = p.time.timeIntervalSince(prev.time)
                        guard span > 0 else { return p.value }
                        let f = t.timeIntervalSince(prev.time) / span
                        return prev.value + (p.value - prev.value) * f
                    }
                    prev = p
                }
                return points[points.count - 1].value
            }

            var line = Path()
            line.move(to: CGPoint(x: x(points[0].time), y: y(points[0].value)))
            for p in points.dropFirst() {
                line.addLine(to: CGPoint(x: x(p.time), y: y(p.value)))
            }

            // The area, closed to the zero line for a current and to chart
            // datum for a tide — the same line each fill is anchored at.
            var area = line
            area.addLine(to: CGPoint(x: x(points[points.count - 1].time), y: y(0)))
            area.addLine(to: CGPoint(x: x(points[0].time), y: y(0)))
            area.closeSubpath()
            if includesZero {
                CurveDrawing.zeroFill(context, area, plotTop: 0, plotBottom: plotHeight, zeroY: y(0))
                CurveDrawing.referenceLine(context, at: y(0), width: size.width)
                CurveDrawing.currentLine(context, line,
                                         samples: points.map { (x: x($0.time), speedKn: $0.value) },
                                         nowX: nowX, width: size.width, height: size.height)
            } else {
                // The fill runs on under the axis row: the card has no plot
                // box below the curve, only the labels' clear strip.
                CurveDrawing.datumFill(context, area, plotTop: 0, plotBottom: size.height,
                                       width: size.width, datumY: y(0), lowestY: y(lowest))
                // Chart datum, when it is inside the plotted span — a curve
                // that sits well above it gets no rule pinned to an edge.
                if lo < 0 && 0 < hi {
                    CurveDrawing.referenceLine(context, at: y(0), width: size.width)
                }
                CurveDrawing.tideLine(context, line,
                                      rates: zip(points, rates).map { (x: x($0.time), rate: $1) },
                                      nowX: nowX, width: size.width, height: size.height)
            }

            for e in extremes {
                // A past extreme fades like the past line.
                let fade = e.time < now ? CurveStyle.pastLabelFade : 1.0
                let tint = (e.high ? SN.graphHigh : SN.graphLow).opacity(fade)
                let ink = SN.foam.opacity(fade)
                let dotAt = CGPoint(x: x(e.time), y: y(e.value))
                let isCurrent = e.deg != nil
                // A tide turn is the event and gets a dot; a current peak is
                // context inside its lobe and does not.
                if !isCurrent {
                    CurveDrawing.dot(context, at: dotAt, color: tint)
                }
                // The extreme's time joins the bottom axis under the axis's
                // own edge rule — the same one the slack crossing times use.
                if !isCurrent, dotAt.x >= Self.axisEdgeMargin,
                   dotAt.x <= size.width - Self.axisEdgeMargin {
                    context.draw(Text(e.timeText)
                                    .font(.system(size: Self.timeFontSize).monospacedDigit())
                                    .fontWeight(.medium)
                                    .foregroundStyle(ink),
                                 at: CGPoint(x: dotAt.x, y: size.height - Self.timeBaseline))
                }
                // An extreme hugging the card edge keeps its dot and axis
                // time but drops its value label — a shifted label detaches
                // from its dot and reads as belonging to the wrong spot.
                guard dotAt.x >= Self.labelEdgeMargin,
                      dotAt.x <= size.width - Self.labelEdgeMargin else { continue }
                // The reading hangs off the turn toward the plot middle with
                // its pointer nearest the dot (current-charts §15.1). The set
                // arrow wears the reading's ink, not a direction colour. No
                // unit: the card's reading states it once.
                CurveDrawing.hangLabel(context, at: dotAt, toward: e.high ? 1 : -1,
                                       value: e.valueText,
                                       glyph: e.deg.map { .set(deg: $0) } ?? .toBar(high: e.high),
                                       tint: isCurrent ? ink : tint, ink: ink,
                                       valueFontSize: CurveStyle.hangValueFontSize)
            }

            // Slack: each run is a REAL sub-path of the curve (interpolated
            // endpoints), computed by the builders from the SHARED
            // slackWindow predicate — never re-derived here.
            let segs = windows.filter { $0.end > $0.start }.map { w -> Path in
                var seg = Path()
                seg.move(to: CGPoint(x: x(w.start), y: y(valueAt(w.start))))
                for p in points where p.time > w.start && p.time < w.end {
                    seg.addLine(to: CGPoint(x: x(p.time), y: y(p.value)))
                }
                seg.addLine(to: CGPoint(x: x(w.end), y: y(valueAt(w.end))))
                return seg
            }
            CurveDrawing.runs(context, segs, nowX: nowX, width: size.width, height: size.height)

            // The axis names each run's opening, and a bare slack only where
            // no run covers it — the same moments the detail strip prints.
            if includesZero {
                for when in currentAxisMoments(runs: windows, slacks: slacks) {
                    let cx = x(when)
                    let fade = when < now ? CurveStyle.pastLabelFade : 1.0
                    guard cx >= Self.axisEdgeMargin,
                          cx <= size.width - Self.axisEdgeMargin else { continue }
                    context.draw(Text(cardTime(when, tz))
                                    .font(.system(size: Self.timeFontSize).monospacedDigit())
                                    .fontWeight(.medium)
                                    .foregroundStyle(SN.foam.opacity(fade)),
                                 at: CGPoint(x: cx, y: size.height - Self.timeBaseline))
                }
            }

            // The "now" dot rides the curve one swing in from the left edge.
            CurveDrawing.nowDot(context, at: CGPoint(x: nowX, y: y(valueAt(now))))
        }
        .accessibilityLabel("\(Int(((back + forward) / 3600).rounded()))-hour curve")
        .accessibilityValue(extremes.filter { $0.time >= start && $0.time <= end }
            .map { "\($0.spokenText) at \($0.timeText)" }
            .joined(separator: ", "))
    }
}

/// The card's runs: one window per slack from the SHARED `slackWindow`
/// predicate against the effective threshold, merged where they touch.
func cardWindows(points: [CurrentPoint], slacks: [Date], threshold: Double = slackThresholdKn) -> [WindowRun] {
    mergeWindows(slacks.compactMap { slackWindow(points, around: $0, threshold: threshold) })
}

extension TideStationRecord {
    func cardGraph(at now: Date, imperial: Bool) -> StationCardGraph {
        cardGraph(at: now, imperial: imperial, station: engineStation)
    }

    func cardGraph(at now: Date, imperial: Bool, station s: any TidePredicting) -> StationCardGraph {
        let start = now.addingTimeInterval(-StationCardGraph.backWindow)
        let end = now.addingTimeInterval(StationCardGraph.forwardWindow)
        return StationCardGraph(
            points: s.heights(from: start, to: end, step: StationCardGraph.sampleStep)
                .map { .init(time: $0.time, value: $0.height) },
            extremes: s.extremes(from: start, to: end).map {
                .init(time: $0.time, value: $0.height,
                      valueText: formatHeight($0.height, imperial: imperial),
                      spokenText: "\(formatHeight($0.height, imperial: imperial)) \(heightUnit(imperial: imperial))",
                      timeText: cardTime($0.time, tz),
                      high: $0.kind == .high)
            },
            now: now,
            rates: s.rates(from: start, to: end, step: StationCardGraph.sampleStep).map(\.rate))
    }
}

extension CurrentStationRecord {
    /// `tilde` hedges the extreme values (`~3.0 kn`) for a provisional
    /// (60-day) gate, like the reading's own tilde.
    func cardGraph(at now: Date, unit: String, tilde: Bool = false) -> StationCardGraph {
        cardGraph(at: now, unit: unit, tilde: tilde, station: engineStation)
    }

    func cardGraph(at now: Date, unit: String, tilde: Bool = false,
                   station s: any CurrentPredicting) -> StationCardGraph {
        let start = now.addingTimeInterval(-StationCardGraph.backWindow)
        let end = now.addingTimeInterval(StationCardGraph.forwardWindow)
        let raw = s.speeds(from: start, to: end, step: StationCardGraph.sampleStep)
        let events = s.events(from: start, to: end)
        let slackTimes = events.filter { $0.kind == .slack }.map(\.time)
        return StationCardGraph(
            points: raw.map { .init(time: $0.time, value: $0.speed) },
            extremes: events
                .filter { $0.kind != .slack }
                .map {
                    .init(time: $0.time, value: $0.speed,
                          valueText: "\(tilde ? "~" : "")\(formatSpeed(abs($0.speed), unit: unit))",
                          spokenText: "\(tilde ? "~" : "")\(formatSpeed(abs($0.speed), unit: unit)) \(speedUnitLabel(unit))",
                          timeText: cardTime($0.time, tz),
                          high: $0.kind == .maxFlood,
                          deg: setDegrees(signed: $0.speed))
                },
            now: now,
            includesZero: true,
            tz: tz,
            windows: cardWindows(points: raw, slacks: slackTimes),
            slacks: slackTimes)
    }
}

extension ChsOnlineWindow {
    func cardGraph(at now: Date, unit: String) -> StationCardGraph {
        let start = now.addingTimeInterval(-StationCardGraph.backWindow)
        let end = now.addingTimeInterval(StationCardGraph.forwardWindow)
        let tz = TimeZone(identifier: timezone) ?? .current
        let raw = points.filter { $0.time >= start && $0.time <= end }
        let events = sampleEvents(points).filter { $0.time >= start && $0.time <= end }
        let slackTimes = events.filter { $0.kind == .slack }.map(\.time)
        return StationCardGraph(
            points: raw.map { .init(time: $0.time, value: $0.speed) },
            extremes: events
                .filter { $0.kind != .slack }
                .map {
                    .init(time: $0.time, value: $0.speed,
                          valueText: formatSpeed(abs($0.speed), unit: unit),
                          spokenText: "\(formatSpeed(abs($0.speed), unit: unit)) \(speedUnitLabel(unit))",
                          timeText: cardTime($0.time, tz),
                          high: $0.kind == .maxFlood,
                          deg: $0.speed >= 0 ? floodDirection : ebbDirection)
                },
            now: now,
            includesZero: true,
            tz: tz,
            windows: cardWindows(points: raw, slacks: slackTimes),
            slacks: slackTimes)
    }
}
