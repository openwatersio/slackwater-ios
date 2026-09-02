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
    /// How close (in data units — metres) a low must come to chart datum
    /// before the datum line appears on a tide card.
    private static let nearDatum = 0.1
    /// An extreme closer than this to a card edge keeps its dot and axis
    /// time but drops its value label; every axis time — extreme or slack
    /// crossing — uses the tighter margin.
    private static let labelEdgeMargin: CGFloat = 34
    private static let axisEdgeMargin: CGFloat = 20
    private static let timeFontSize: CGFloat = 10
    /// Axis-label center height above the card bottom.
    private static let timeBaseline: CGFloat = 10
    /// The pointer glyph's distance from the value on the band. One consumer
    /// (this card), so it lives here rather than on the shared CurveStyle.
    private static let pointerOffset: CGFloat = 18
    private static let valueFontSize: CGFloat = 15
    private static let pointerFontSize: CGFloat = 15

    struct Point {
        let time: Date
        let value: Double
    }

    struct Extreme {
        let time: Date
        let value: Double
        let valueText: String
        let timeText: String
        /// High tide / max flood (vs low / max ebb) — picks the dot and
        /// pointer tint (teal vs amber) and the pointer direction.
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
                context.stroke(path, with: .color(SN.foam.opacity(CurveStyle.referenceLineOpacity)),
                               style: StrokeStyle(lineWidth: 1, dash: CurveStyle.referenceLineDash))
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
                        .init(color: Self.line.opacity(CurveStyle.fillOpacity), location: 0),
                        .init(color: Self.line.opacity(0), location: zeroStop),
                        .init(color: Self.low.opacity(0), location: zeroStop),
                        .init(color: Self.low.opacity(CurveStyle.fillOpacity), location: 1),
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)))
            } else {
                // A tide's intensity is the water level itself, so the fade
                // stays vertical (Neaps TideGraphChart): strongest at the
                // surface, easing toward the bottom.
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [Self.line.opacity(CurveStyle.fillOpacity),
                                      Self.line.opacity(CurveStyle.tideFillFloor)]),
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
            past.stroke(line, with: .color(Self.line.opacity(CurveStyle.pastLineOpacity)),
                        lineWidth: CurveStyle.lineWidth)
            var future = context
            future.clip(to: Path(CGRect(x: nowX, y: 0,
                                        width: size.width - nowX, height: size.height)))
            future.stroke(line, with: .color(Self.line), lineWidth: CurveStyle.lineWidth)

            // A halo that truly matches the background: erase the line and
            // fill in a ring around each dot (destinationOut punches through
            // to whatever is behind the Canvas) rather than painting a guess
            // at the card color over them.
            func punchHalo(at p: CGPoint, dotRadius: CGFloat) {
                let radius = dotRadius + CurveStyle.haloGap
                var eraser = context
                eraser.blendMode = .destinationOut
                eraser.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                                   width: radius * 2, height: radius * 2)),
                            with: .color(.black))
            }

            func dot(at p: CGPoint, color: Color) {
                punchHalo(at: p, dotRadius: CurveStyle.dotRadius)
                context.fill(Path(ellipseIn: CGRect(x: p.x - CurveStyle.dotRadius,
                                                    y: p.y - CurveStyle.dotRadius,
                                                    width: CurveStyle.dotRadius * 2,
                                                    height: CurveStyle.dotRadius * 2)),
                             with: .color(color))
            }

            for e in extremes {
                // A past extreme fades like the past line.
                let fade = e.time < now ? CurveStyle.pastLabelFade : 1.0
                let tint = (e.high ? Self.high : Self.low).opacity(fade)
                let text = SN.foam.opacity(fade)
                let dotAt = CGPoint(x: x(e.time), y: y(e.value))
                let isCurrent = e.deg != nil
                if !isCurrent {
                    dot(at: dotAt, color: tint)
                }
                // The extreme's time joins the bottom axis under the axis's
                // own edge rule — the same one the slack crossing times use.
                if !isCurrent, dotAt.x >= Self.axisEdgeMargin,
                   dotAt.x <= size.width - Self.axisEdgeMargin {
                    context.draw(Text(e.timeText)
                                    .font(.system(size: Self.timeFontSize).monospacedDigit())
                                    .fontWeight(.medium)
                                    .foregroundStyle(text),
                                 at: CGPoint(x: dotAt.x, y: size.height - Self.timeBaseline))
                }
                // An extreme hugging the card edge keeps its dot and axis
                // time but drops its value label — a shifted label detaches
                // from its dot and reads as belonging to the wrong spot.
                guard dotAt.x >= Self.labelEdgeMargin,
                      dotAt.x <= size.width - Self.labelEdgeMargin else { continue }
                // The values form one rail across the vertical middle, with
                // each extreme's icon on the dot's side of its number —
                // above for high/flood, below for low/ebb.
                let labelX = dotAt.x
                // The band rides the zero line on a signed curve — flood and
                // ebb rarely peak equally, so zero is not the canvas middle.
                let bandY = includesZero ? baseY : plotHeight / 2
                if let deg = e.deg {
                    // The SF Symbol, not the "↑" text glyph — a text arrow
                    // at the same point size renders visibly smaller.
                    let pointerAt = CGPoint(x: labelX,
                                            y: bandY + (e.high ? -Self.pointerOffset : Self.pointerOffset))
                    var rotated = context
                    rotated.translateBy(x: pointerAt.x, y: pointerAt.y)
                    rotated.rotate(by: .degrees(deg))
                    rotated.draw(Text(Image(systemName: "arrow.up"))
                                    .font(.system(size: Self.pointerFontSize, weight: .bold))
                                    .foregroundStyle(tint),
                                 at: .zero)
                }
                context.draw(Text(e.valueText)
                                .font(.system(size: Self.valueFontSize, weight: .bold).monospacedDigit())
                                .foregroundStyle(text),
                             at: CGPoint(x: labelX, y: bandY))
            }

            // Slack: the line itself turns the go colour for each window's
            // duration — the run computed by the builders from the SHARED
            // slackWindow predicate, never re-derived here — wearing the
            // same halo the dots wear. Each run is a REAL sub-path of the
            // curve (interpolated endpoints), stroked round-capped: the
            // wider round-capped eraser under it is what leaves a rounded
            // clear seam at both ends instead of a slanted clip cut.
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
            for w in windows {
                guard w.end > w.start else { continue }
                var seg = Path()
                seg.move(to: CGPoint(x: x(w.start), y: y(valueAt(w.start))))
                for p in points where p.time > w.start && p.time < w.end {
                    seg.addLine(to: CGPoint(x: x(p.time), y: y(p.value)))
                }
                seg.addLine(to: CGPoint(x: x(w.end), y: y(valueAt(w.end))))

                var eraser = context
                eraser.blendMode = .destinationOut
                eraser.stroke(seg, with: .color(.black),
                              style: StrokeStyle(lineWidth: CurveStyle.lineWidth + CurveStyle.haloGap * 2,
                                                 lineCap: .round))
                // The past/future fade still splits by clip — an opacity
                // seam mid-run, never a shape cut. Clips reach one stroke
                // width past the ends so they can't shave the round caps.
                func strokeGo(from a: CGFloat, to b: CGFloat, opacity: Double) {
                    guard b > a else { return }
                    var c = context
                    c.clip(to: Path(CGRect(x: a, y: 0, width: b - a, height: size.height)))
                    c.stroke(seg, with: .color(SN.go.opacity(opacity)),
                             style: StrokeStyle(lineWidth: CurveStyle.lineWidth, lineCap: .round))
                }
                let x0 = x(w.start), x1 = x(w.end)
                strokeGo(from: x0 - CurveStyle.lineWidth, to: min(x1 + CurveStyle.lineWidth, nowX),
                         opacity: CurveStyle.pastLineOpacity)
                strokeGo(from: max(x0 - CurveStyle.lineWidth, nowX), to: x1 + CurveStyle.lineWidth,
                         opacity: 1)

                // The run's opening gets the only dot on a current curve: it
                // is the moment the axis time below names (spec §4 rule 7).
                let fade = w.start < now ? CurveStyle.pastLabelFade : 1.0
                dot(at: CGPoint(x: x0, y: y(valueAt(w.start))), color: SN.go.opacity(fade))
            }

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
            if let nowValue = points.min(by: {
                abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now))
            })?.value {
                let nowDot = CGPoint(x: x(now), y: y(nowValue))
                let r = CurveStyle.nowDotDiameter / 2
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

/// The card's runs: one window per slack from the SHARED `slackWindow`
/// predicate against the effective threshold, merged where they touch.
func cardWindows(points: [CurrentPoint], slacks: [Date], threshold: Double = slackThresholdKn) -> [WindowRun] {
    mergeWindows(slacks.compactMap { slackWindow(points, around: $0, threshold: threshold) })
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
        let raw = s.speeds(from: start, to: end, step: StationCardGraph.sampleStep)
        let events = s.events(from: start, to: end)
        let slackTimes = events.filter { $0.kind == .slack }.map(\.time)
        return StationCardGraph(
            points: raw.map { .init(time: $0.time, value: $0.speed) },
            extremes: events
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
                          valueText: "\(formatSpeed(abs($0.speed), unit: unit)) \(speedUnitLabel(unit))",
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
