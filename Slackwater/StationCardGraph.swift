import SwiftUI
import SlackwaterKit

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
nonisolated struct StationCardGraph: View {
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
    /// An extreme closer than this to a card edge keeps its dot and axis
    /// time but drops its value label; every axis time — extreme or slack
    /// crossing — uses the tighter margin.
    private static let labelEdgeMargin: CGFloat = 34
    /// The canvas bleeds 3pt past the card on each side, so this keeps a time 21pt inside the card.
    private static let axisEdgeMargin: CGFloat = 24
    /// About one printed time's width, so neighbours never print over each other.
    private static let axisMinGap: CGFloat = 48
    /// How far a hanging reading reaches from its dot: the value's center plus half its 16pt line.
    private static let hangReach = CurveStyle.hangOffset + CurveStyle.hangValueGap + 8
    private static let timeFontSize: CGFloat = 10
    /// Axis-label center height above the card bottom.
    private static let timeBaseline: CGFloat = 10
    /// The height digits actually fill, as a fraction of their point size.
    /// Overlap is judged on ink: line boxes carry leading, and would call a
    /// reading crowded that visibly clears the time below it.
    private static let digitInk: CGFloat = 0.72

    /// The ink of a reading hanging below `dot`, as `CurveDrawing.hangLabel`
    /// places it: the pointer, and the value beyond it when there is one.
    static func hangingInk(below dot: CGPoint, valueWidth: CGFloat?) -> CGRect {
        let hang = dot.y + CurveStyle.hangOffset
        let glyphInk = CurveStyle.hangGlyphFontSize * digitInk
        let pointer = CGRect(x: dot.x - CurveStyle.hangGlyphFontSize / 2,
                             y: hang - CurveStyle.hangGlyphGap - glyphInk / 2,
                             width: CurveStyle.hangGlyphFontSize, height: glyphInk)
        guard let valueWidth else { return pointer }
        let valueInk = CurveStyle.hangValueFontSize * digitInk
        return pointer.union(CGRect(x: dot.x - valueWidth / 2, y: hang + CurveStyle.hangValueGap - valueInk / 2,
                                    width: valueWidth, height: valueInk))
    }

    /// The ink of an axis time `width` wide, centred at `x` on a card `height` tall.
    static func axisTimeInk(at x: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        let inkHeight = timeFontSize * digitInk
        return CGRect(x: x - width / 2, y: height - timeBaseline - inkHeight / 2, width: width, height: inkHeight)
    }

    struct Point {
        let time: Date
        let value: Double
    }

    struct Extreme {
        let time: Date
        let value: Double
        /// The bare number for the curve; the unit prints once in the card's reading.
        let valueText: String?
        /// The number with its unit, for VoiceOver only.
        let spokenText: String
        let timeText: String
        /// High tide / velocity crest (vs low / trough) — picks the tide dot tint and the reading's side.
        let high: Bool
        /// A current extreme's set bearing. When present the pointer is the
        /// set arrow (↑ rotated to the bearing, "water goes this way")
        /// instead of the tide's to-bar arrows.
        var deg: Double? = nil
        /// A derived gate knows flood versus ebb, but has no compass bearing.
        var flow: DerivedPhase? = nil
        var isCurrent: Bool { deg != nil || flow != nil }
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
    /// The slack inside each window (`slackCoreThresholdKn`), from the same
    /// predicate: the card's green, and its reading's Slack.
    var cores: [WindowRun] = []
    /// Every slack instant in the span. One no slack run covers draws as the shortest slack stroke at its instant; a derived gate's draw as dots, on the zero line.
    var slacks: [Date] = []
    /// A normalized phase shape, never a speed measurement.
    var speedsAreSchematic = false
    /// A tide curve's rate of rise (m/hr), index-aligned with `points`, for
    /// the line's rate colour. Empty on a current curve, and the preview
    /// sines — the line is then plain blue.
    var rates: [Double] = []
    var showsReadings = true
    var showsTimes = true
    var showsNow = true
    var highlight: ClosedRange<Date>? = nil
    // Compact widgets need a separate lane for times below the curve and its dots.
    var timeLabelSpace: CGFloat = 6

    /// The card's reading says Slack inside the slack it measures, as the detail lead does. A
    /// short slack's green stroke is wider than its time: the mark is the moment, the reading the water.
    func isSlack(at t: Date) -> Bool {
        readsSlack(at: t, runs: cores, slacks: slacks)
    }

    /// One time per mark, under the mark at the card's own scale: each drawn window's opening, and each slack mark outside one.
    static func axisMoments(_ windows: [WindowRun], cores: [WindowRun], slacks: [Date], pointsPerHour: CGFloat) -> [Date] {
        slackAxisMoments(windows: windows, cores: cores, slacks: slacks, pointsPerHour: pointsPerHour)
    }

    /// Keep the reading on its preferred side unless it would land on the identity rows or axis times.
    static func hangToward(dotY: CGFloat, high: Bool, plotHeight: CGFloat) -> CGFloat {
        if high { return dotY + hangReach > plotHeight ? -1 : 1 }
        return dotY - hangReach < 0 ? 1 : -1
    }

    /// The axis times the card prints, in time order: clear of both edges, and each at least a
    /// time's width after the last one kept.
    static func thinAxisMoments(_ moments: [Date], x: (Date) -> CGFloat, width: CGFloat) -> [Date] {
        var kept: [Date] = []
        for t in moments.sorted() {
            let at = x(t)
            guard at >= axisEdgeMargin, at <= width - axisEdgeMargin else { continue }
            if let last = kept.last, at - x(last) < axisMinGap { continue }
            kept.append(t)
        }
        return kept
    }

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
            let plotHeight = max(0, size.height - timeLabelSpace)
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

            // Slack: each run is a REAL sub-path of the curve (interpolated
            // endpoints), computed by the builders from the SHARED
            // slackWindow predicate — never re-derived here.
            func segments(_ runs: [WindowRun]) -> [Path] {
                runs.map { w -> Path in
                    var seg = Path()
                    seg.move(to: CGPoint(x: x(w.start), y: y(valueAt(w.start))))
                    for p in points where p.time > w.start && p.time < w.end {
                        seg.addLine(to: CGPoint(x: x(p.time), y: y(p.value)))
                    }
                    seg.addLine(to: CGPoint(x: x(w.end), y: y(valueAt(w.end))))
                    return seg
                }
            }
            let segs = segments(windows)
            let bare = speedsAreSchematic ? [] : bareSlacks(slacks, runs: cores).filter { $0 >= start && $0 <= end }
            let coreSegs = segments(slackStrokes(cores: cores, bare: bare, pointsPerHour: xScale * 3600))

            // The area, closed to the zero line for a current and to chart
            // datum for a tide — the same line each fill is anchored at.
            var area = line
            area.addLine(to: CGPoint(x: x(points[points.count - 1].time), y: y(0)))
            area.addLine(to: CGPoint(x: x(points[0].time), y: y(0)))
            area.closeSubpath()
            if includesZero {
                CurveDrawing.zeroFill(context, area, plotTop: 0, plotBottom: plotHeight, zeroY: y(0))
                if !speedsAreSchematic {
                    CurveDrawing.referenceLine(context, at: y(0), width: size.width)
                    CurveDrawing.currentLine(context, line,
                                             slackRuns: segs + coreSegs,
                                             samples: points.map { (x: x($0.time), speedKn: $0.value) },
                                             nowX: nowX, width: size.width, height: size.height)
                } else {
                    CurveDrawing.strokeSplitAtNow(context, line, with: .color(SN.graphLine),
                                                  nowX: nowX, width: size.width, height: size.height)
                }
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

            // The axis row: each tide turn's time under its dot, and for a
            // current each drawn window's opening, or a slack mark only where
            // no drawn window covers it — the same moments the detail strip
            // prints. One edge rule for all of them.
            // A tide turn arrives with its time already formatted.
            var axisMoments: [(time: Date, text: String?)] = []
            if showsTimes {
                axisMoments += extremes.filter { $0.deg == nil && $0.flow == nil }.map { ($0.time, $0.timeText) }
                if includesZero {
                    axisMoments += Self.axisMoments(windows, cores: cores, slacks: slacks,
                                                    pointsPerHour: xScale * 3600).map { ($0, nil) }
                }
            }
            let keptAxisTimes = Self.thinAxisMoments(axisMoments.map(\.time), x: x, width: size.width)
            let axisTimes = axisMoments
                .filter { keptAxisTimes.contains($0.time) }
                .map { moment in
                    let fade = moment.time < now ? CurveStyle.pastLabelFade : 1.0
                    let text = context.resolve(Text(moment.text ?? cardTime(moment.time, tz))
                        .font(.system(size: Self.timeFontSize).monospacedDigit())
                        .fontWeight(.medium)
                        .foregroundStyle(SN.foam.opacity(fade)))
                    let at = CGPoint(x: x(moment.time), y: size.height - Self.timeBaseline)
                    return (text: text, at: at,
                            ink: Self.axisTimeInk(at: at.x, width: text.measure(in: size).width, height: size.height))
                }

            for e in extremes {
                // A past extreme fades like the past line.
                let fade = e.time < now ? CurveStyle.pastLabelFade : 1.0
                let tint = (e.high ? SN.graphHigh : SN.graphLow).opacity(fade)
                let ink = SN.foam.opacity(fade)
                let dotAt = CGPoint(x: x(e.time), y: y(e.value))
                let isCurrent = e.isCurrent
                // A tide turn is the event and gets a dot; a current peak is context and does not.
                if !isCurrent {
                    CurveDrawing.dot(context, at: dotAt, color: tint)
                }
                // An extreme hugging the card edge keeps its dot and axis
                // time but drops its value label — a shifted label detaches
                // from its dot and reads as belonging to the wrong spot.
                guard showsReadings, dotAt.x >= Self.labelEdgeMargin,
                      dotAt.x <= size.width - Self.labelEdgeMargin else { continue }
                // So does a reading that would hang onto an axis time: a
                // shallow turn on a short card sits too low for it. The whole
                // reading counts, pointer and value — on a turn low enough,
                // the value hangs past the row and the pointer lands on it.
                if Self.hangToward(dotY: dotAt.y, high: e.high, plotHeight: plotHeight) > 0 {
                    let valueWidth = e.valueText.map {
                        context.resolve(Text($0)
                            .font(.system(size: CurveStyle.hangValueFontSize, weight: .semibold).monospacedDigit()))
                            .measure(in: size).width
                    }
                    let reading = Self.hangingInk(below: dotAt, valueWidth: valueWidth)
                    if axisTimes.contains(where: { $0.ink.intersects(reading) }) { continue }
                }
                // The card's reading carries the unit; the set arrow shares the value's ink (current-charts §15.1).
                let glyph: HangGlyph = if let flow = e.flow {
                    .flow(flood: flow == .flood)
                } else if let deg = e.deg {
                    .set(deg: deg)
                } else {
                    .toBar(high: e.high)
                }
                CurveDrawing.hangLabel(context, at: dotAt,
                                       toward: Self.hangToward(dotY: dotAt.y, high: e.high, plotHeight: plotHeight),
                                       value: e.valueText, glyph: glyph,
                                       tint: isCurrent ? ink : tint, ink: ink,
                                       valueFontSize: CurveStyle.hangValueFontSize)
            }

            CurveDrawing.windows(context, segs, nowX: nowX, width: size.width, height: size.height)
            CurveDrawing.runs(context, coreSegs, nowX: nowX, width: size.width, height: size.height)

            for time in axisTimes { context.draw(time.text, at: time.at) }

            // A schematic shape has no speed to draw a slack along, so its slack is a dot on the zero line.
            if speedsAreSchematic {
                for when in bareSlacks(slacks, runs: cores) where when >= start && when <= end {
                    CurveDrawing.dot(context, at: CGPoint(x: x(when), y: y(0)), color: SN.go)
                }
            }

            if let highlight {
                let left = x(highlight.lowerBound), right = x(highlight.upperBound)
                if right > left {
                    context.fill(Path(CGRect(x: left, y: 0, width: right - left, height: plotHeight)),
                                 with: .color(SN.slackWindow.opacity(0.12)))
                }
                var guides = Path()
                for time in Set([highlight.lowerBound, highlight.upperBound]) {
                    let at = x(time)
                    guides.move(to: CGPoint(x: at, y: 0))
                    guides.addLine(to: CGPoint(x: at, y: plotHeight))
                }
                context.stroke(guides, with: .color(SN.foam.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if highlight.lowerBound == highlight.upperBound {
                    let at = CGPoint(x: left, y: y(valueAt(highlight.lowerBound)))
                    context.stroke(Path(ellipseIn: CGRect(x: at.x - 7, y: at.y - 7, width: 14, height: 14)),
                                   with: .color(SN.foam), lineWidth: 2)
                }
            }

            // The "now" dot rides the curve one swing in from the left edge.
            if showsNow { CurveDrawing.nowDot(context, at: CGPoint(x: nowX, y: y(valueAt(now)))) }
        }
        .accessibilityLabel("\(Int(((back + forward) / 3600).rounded()))-hour curve")
        .accessibilityValue(extremes.filter { $0.time >= start && $0.time <= end }
            .map { "\($0.spokenText) at \($0.timeText)" }
            .joined(separator: ", "))
    }
}

extension DerivedGateRecord {
    func cardGraph(at now: Date) -> StationCardGraph {
        let start = now.addingTimeInterval(-StationCardGraph.backWindow)
        let end = now.addingTimeInterval(StationCardGraph.forwardWindow)
        let slacks = engineGate.slacks(from: start.addingTimeInterval(-StationCardGraph.swing),
                                       to: end.addingTimeInterval(StationCardGraph.swing))
        var points: [StationCardGraph.Point] = []
        var t = start
        while t <= end {
            points.append(.init(time: t, value: engineGate.schematicSigned(at: t, slacks: slacks)))
            t = t.addingTimeInterval(StationCardGraph.sampleStep)
        }
        let extremes = zip(slacks, slacks.dropFirst()).compactMap { pair -> StationCardGraph.Extreme? in
            let (a, b) = pair
            let time = a.time.addingTimeInterval(b.time.timeIntervalSince(a.time) / 2)
            guard time >= start, time <= end else { return nil }
            let value = engineGate.schematicSigned(at: time, slacks: slacks)
            let flow = engineGate.phase(at: time, slacks: slacks)
            return .init(time: time, value: value, valueText: nil,
                         spokenText: flow.word, timeText: cardTime(time, gate.tz),
                         high: flow == .flood, flow: flow)
        }
        return StationCardGraph(points: points, extremes: extremes, now: now,
                                includesZero: true, tz: gate.tz,
                                slacks: slacks.map(\.time).filter { $0 >= start && $0 <= end },
                                speedsAreSchematic: true)
    }
}

/// The card's runs: one window per slack from the SHARED `slackWindow`
/// predicate against the effective threshold, merged where they touch.
func cardWindows(points: [CurrentPoint], slacks: [Date], threshold: Double = slackThresholdKn) -> [WindowRun] {
    mergeWindows(slacks.compactMap { slackWindow(points, around: $0, threshold: threshold) })
}

/// The slack inside the card's windows at `threshold`, measured the same way.
func cardCores(points: [CurrentPoint], slacks: [Date], threshold: Double = slackThresholdKn) -> [WindowRun] {
    cardWindows(points: points, slacks: slacks, threshold: slackCoreThresholdKn(threshold))
}

func cardSpeed(_ points: [CurrentPoint], at time: Date) -> Double? {
    guard let first = points.first, let last = points.last,
          time >= first.time, time <= last.time else { return nil }
    guard let i = points.firstIndex(where: { $0.time >= time }), i > 0 else { return first.speed }
    let a = points[i - 1], b = points[i]
    let fraction = time.timeIntervalSince(a.time) / b.time.timeIntervalSince(a.time)
    return a.speed + (b.speed - a.speed) * fraction
}

extension TideStationRecord {
    func cardGraph(at now: Date, imperial: Bool) -> StationCardGraph {
        cardGraph(at: now, imperial: imperial, station: engineStation)
    }

    func cardGraph(at now: Date, imperial: Bool, station s: any TidePredicting,
                   through requestedEnd: Date? = nil) -> StationCardGraph {
        let start = now.addingTimeInterval(-StationCardGraph.backWindow)
        let end = max(now.addingTimeInterval(StationCardGraph.forwardWindow), requestedEnd ?? now)
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
            forward: end.timeIntervalSince(now),
            tz: tz,
            rates: s.rates(from: start, to: end, step: StationCardGraph.sampleStep).map(\.rate))
    }
}

extension CurrentStationRecord {
    /// `tilde` hedges the extreme values (`~3.0 kn`) for a provisional
    /// (60-day) gate, like the reading's own tilde.
    func cardGraph(at now: Date, unit: String, tilde: Bool = false,
                   threshold: Double = slackThresholdKn) -> StationCardGraph {
        cardGraph(at: now, unit: unit, tilde: tilde, station: engineStation, threshold: threshold)
    }

    func cardGraph(at now: Date, unit: String, tilde: Bool = false,
                   station s: any CurrentPredicting, threshold: Double = slackThresholdKn,
                   through requestedEnd: Date? = nil) -> StationCardGraph {
        let start = now.addingTimeInterval(-StationCardGraph.backWindow)
        let end = max(now.addingTimeInterval(StationCardGraph.forwardWindow), requestedEnd ?? now)
        let raw = s.speeds(from: start, to: end, step: StationCardGraph.sampleStep)
        let events = s.events(from: start, to: end)
        let slackTimes = events.filter { $0.kind == .slack }.map(\.time)
        return StationCardGraph(
            points: raw.map { .init(time: $0.time, value: $0.speed) },
            extremes: events
                .filter { $0.kind != .slack }
                .map { event in
                    let before = cardSpeed(raw, at: event.time.addingTimeInterval(-StationCardGraph.sampleStep)) ?? event.speed
                    return .init(time: event.time, value: event.speed,
                                 valueText: "\(tilde ? "~" : "")\(formatSpeed(abs(event.speed), unit: unit))",
                                 spokenText: "\(tilde ? "~" : "")\(formatSpeed(abs(event.speed), unit: unit)) \(speedUnitLabel(unit))",
                                 timeText: cardTime(event.time, tz),
                                 high: maxHangToward(speed: event.speed, before: before) > 0,
                                 deg: setDegrees(signed: event.speed))
                },
            now: now,
            forward: end.timeIntervalSince(now),
            includesZero: true,
            tz: tz,
            windows: cardWindows(points: raw, slacks: slackTimes, threshold: threshold),
            cores: cardCores(points: raw, slacks: slackTimes, threshold: threshold),
            slacks: slackTimes)
    }
}

extension ChsOnlineWindow {
    func cardGraph(at now: Date, unit: String, threshold: Double = slackThresholdKn) -> StationCardGraph {
        let start = now.addingTimeInterval(-StationCardGraph.backWindow)
        let end = now.addingTimeInterval(StationCardGraph.forwardWindow)
        let tz = TimeZone(identifier: timezone) ?? .current
        let samples = points
        let raw = samples.filter { $0.time >= start && $0.time <= end }
        let events = sampleEvents(samples).filter { $0.time >= start && $0.time <= end }
        let slackTimes = events.filter { $0.kind == .slack }.map(\.time)
        return StationCardGraph(
            points: raw.map { .init(time: $0.time, value: $0.speed) },
            extremes: events
                .filter { $0.kind != .slack }
                .map { event in
                    let before = cardSpeed(samples, at: event.time.addingTimeInterval(-StationCardGraph.sampleStep)) ?? event.speed
                    return .init(time: event.time, value: event.speed,
                                 valueText: formatSpeed(abs(event.speed), unit: unit),
                                 spokenText: "\(formatSpeed(abs(event.speed), unit: unit)) \(speedUnitLabel(unit))",
                                 timeText: cardTime(event.time, tz),
                                 high: maxHangToward(speed: event.speed, before: before) > 0,
                                 deg: event.speed >= 0 ? floodDirection : ebbDirection)
                },
            now: now,
            includesZero: true,
            tz: tz,
            windows: cardWindows(points: raw, slacks: slackTimes, threshold: threshold),
            cores: cardCores(points: raw, slacks: slackTimes, threshold: threshold),
            slacks: slackTimes)
    }
}
