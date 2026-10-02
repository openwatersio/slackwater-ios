// Slackwater — GPL v3. What the watch's inline, circular and corner
// complications draw (#524): the value without its unit, the word and symbol
// for its direction, the line around now, its slack stretches, and the corner
// gauge. A pure function of (station, now), like WidgetSnapshot.
import Foundation
import SlackwaterKit

struct ComplicationReading: Equatable {
    enum Kind: Equatable { case tide, current }

    /// One point of the line: hours from now, and metres for a tide or
    /// signed knots (flood positive) for a current.
    struct Sample: Equatable { let hours: Double; let value: Double }

    /// The corner's arc. A tide runs from the low at the start to the high at
    /// the end; a current runs one swing up to the end of its next slack window.
    struct Gauge: Equatable {
        let fraction: Double
        let startText: String?
        let endText: String?
        let windowStart: Double?
        let towardEnd: Bool
    }

    let kind: Kind
    let valueText: String
    let word: String
    let symbol: String
    let samples: [Sample]
    let slackRuns: [ClosedRange<Double>]
    let gauge: Gauge?

    /// The line's reach: the circular draws ±3 h of it.
    static let span: ClosedRange<Double> = -3...10
    private static let step: TimeInterval = 600
    /// How far ahead a current's next slack window is looked for. Past this
    /// the corner draws its speed alone.
    private static let windowSearch: TimeInterval = 26 * 3600

    static func build(_ station: WidgetStation, now: Date) -> ComplicationReading? {
        let imperial = AppGroup.defaults.string(forKey: unitsKey) != "metric"
        let speedUnit = AppGroup.defaults.string(forKey: speedUnitKey) ?? "kn"
        let from = now.addingTimeInterval(span.lowerBound * 3600)
        let to = now.addingTimeInterval(span.upperBound * 3600)
        let hours = { (t: Date) in t.timeIntervalSince(now) / 3600 }

        switch station {
        case .tide(let s, _, _):
            let samples = s.heights(from: from, to: to, step: step).map { Sample(hours: hours($0.time), value: $0.height) }
            let height = s.heights(from: now, to: now.addingTimeInterval(1), step: 1).first?.height ?? 0
            let extremes = s.extremes(from: now.addingTimeInterval(-15 * 3600), to: now.addingTimeInterval(15 * 3600))
            let last = extremes.last { $0.time <= now }
            let next = extremes.first { $0.time > now }
            let rising = next.map { $0.kind == .high } ?? true
            var gauge: Gauge?
            if let last, let next {
                let lo = min(last.height, next.height), hi = max(last.height, next.height)
                gauge = Gauge(fraction: hi > lo ? min(1, max(0, (height - lo) / (hi - lo))) : 0.5,
                              startText: formatHeight(lo, imperial: imperial),
                              endText: formatHeight(hi, imperial: imperial),
                              windowStart: nil, towardEnd: rising)
            }
            return ComplicationReading(
                kind: .tide, valueText: formatHeight(height, imperial: imperial),
                word: rising ? String(localized: "Rising", comment: "Rising-tide state.")
                             : String(localized: "Falling", comment: "Falling-tide state."),
                symbol: rising ? "arrow.up" : "arrow.down",
                samples: samples, slackRuns: [], gauge: gauge)

        case .current(let s, let tz, _):
            let threshold = slackThresholdKn
            let points = s.speeds(from: from, to: now.addingTimeInterval(windowSearch), step: step)
            let samples = points.filter { $0.time <= to }.map { Sample(hours: hours($0.time), value: $0.speed) }
            let signed = s.speeds(from: now, to: now.addingTimeInterval(1), step: 1).first?.speed ?? 0
            let runs = Self.runs(points, under: threshold, hours: hours)
            let phase = currentPhase(signed: signed)
            let symbol = switch phase {
            case .flood: "arrow.up.right"
            case .ebb: "arrow.down.right"
            case .slack: "arrow.left.arrow.right"
            }
            return ComplicationReading(
                kind: .current, valueText: formatSpeed(abs(signed), unit: speedUnit),
                word: phase.word,
                symbol: symbol,
                samples: samples,
                slackRuns: runs.filter { $0.overlaps(span) },
                gauge: Self.currentGauge(runs, now: now, tz: tz))

        case .derived:
            // Derived gates are Canadian; the watch shows them nothing until #523.
            return nil
        }
    }

    /// Stretches of `points` under `threshold`, in hours from now.
    private static func runs(_ points: [CurrentPoint], under threshold: Double,
                             hours: (Date) -> Double) -> [ClosedRange<Double>] {
        var out: [ClosedRange<Double>] = []
        var start: Double?
        var last = 0.0
        for p in points {
            let h = hours(p.time)
            if abs(p.speed) < threshold { if start == nil { start = h }; last = h }
            else if let s = start { out.append(s...last); start = nil }
        }
        if let s = start { out.append(s...last) }
        return out
    }

    /// One swing of arc ending where the next slack window ends: now's dot
    /// approaches the window from the left, and sits inside it during slack.
    private static func currentGauge(_ runs: [ClosedRange<Double>], now: Date, tz: TimeZone) -> Gauge? {
        guard let window = runs.first(where: { $0.upperBound >= 0 }) else { return nil }
        let swing = StationCardGraph.swing / 3600
        let span = max(swing, window.upperBound - window.lowerBound)
        let arcStart = window.upperBound - span
        return Gauge(fraction: min(1, max(0, (0 - arcStart) / span)),
                     startText: nil,
                     endText: cardTime(now.addingTimeInterval(window.lowerBound * 3600), tz),
                     windowStart: max(0, (window.lowerBound - arcStart) / span),
                     towardEnd: true)
    }
}
