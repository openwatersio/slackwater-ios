// Slackwater — GPL v3. The render-ready value a widget entry carries: next
// event, current state, and today's render-ready curve. Pure function of
// (station, now) — deterministic, offline, engine-only.
import Foundation
import TideEngine

struct WidgetSnapshot: Equatable {
    enum CurveKind: Equatable { case tide, current, schematic }

    struct Event: Equatable {
        let time: Date
        let label: String
        let symbol: String
    }
    struct TideMovement: Equatable {
        let fraction: Double
        let rate: Double
    }
    let stationName: String
    let tz: TimeZone
    let next: Event?
    let nextHigh: Event?
    let nextLow: Event?
    let window: (start: Date, end: Date)?
    let sparkline: [Double]
    let tideMovements: [TideMovement]
    let tideRate: Double?
    let nowFraction: Double
    let curveKind: CurveKind
    let threshold: Double?
    let state: String
    let value: String

    static func == (a: Self, b: Self) -> Bool {
        a.stationName == b.stationName && a.tz == b.tz && a.next == b.next
            && a.nextHigh == b.nextHigh && a.nextLow == b.nextLow
            && a.window?.start == b.window?.start && a.window?.end == b.window?.end
            && a.sparkline == b.sparkline && a.tideMovements == b.tideMovements
            && a.tideRate == b.tideRate && a.nowFraction == b.nowFraction
            && a.curveKind == b.curveKind && a.threshold == b.threshold
            && a.state == b.state && a.value == b.value
    }

    static func build(
        _ station: WidgetStation, now: Date, stationNamePrefix: String? = nil
    ) -> WidgetSnapshot {
        // Read once, here — not per format call — so `build` stays a pure
        // function of (station, now) (H2): the setting is an input, same as
        // the other two.
        let imperial = AppGroup.defaults.string(forKey: unitsKey) != "metric"
        let speedUnit = AppGroup.defaults.string(forKey: speedUnitKey) ?? "kn"

        var cal = Calendar(identifier: .gregorian)
        let tz: TimeZone
        switch station {
        case .tide(_, let z, _), .current(_, let z, _), .derived(_, let z, _): tz = z
        }
        cal.timeZone = tz
        let dayStart = cal.startOfDay(for: now)
        // A calendar day, not 86_400s — 23/25 hours across a DST transition.
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let dayLength = dayEnd.timeIntervalSince(dayStart)
        let nowFraction = min(1, max(0, now.timeIntervalSince(dayStart) / dayLength))

        func normalize(_ values: [Double]) -> [Double] {
            guard let lo = values.min(), let hi = values.max(), hi > lo else {
                return values.map { _ in 0.5 }
            }
            return values.map { ($0 - lo) / (hi - lo) }
        }

        switch station {
        case .tide(let s, _, let name):
            let name = [stationNamePrefix, name].compactMap { $0 }.joined(separator: " · ")
            let heights = s.heights(from: dayStart, to: dayEnd, step: 900).map(\.height)
            let height = s.heights(from: now, to: now.addingTimeInterval(1), step: 1).first?.height ?? 0
            let extremes = s.extremes(from: now, to: now.addingTimeInterval(172_800))
                .filter { $0.time > now }
            let event = { (extreme: TideExtreme) in
                Event(time: extreme.time,
                      label: (extreme.kind == .high ? "High" : "Low")
                          + " \(formatHeight(extreme.height, imperial: imperial)) \(heightUnit(imperial: imperial))",
                      symbol: extreme.kind == .high ? "arrow.up" : "arrow.down")
            }
            let next = extremes.first.map(event)
            let nextHigh = extremes.first { $0.kind == .high }.map(event)
            let nextLow = extremes.first { $0.kind == .low }.map(event)
            let movements = tideFlowArrows(s.rates(from: dayStart, to: dayEnd, step: 900))
                .map { TideMovement(fraction: $0.time.timeIntervalSince(dayStart) / dayLength,
                                    rate: $0.rate) }
                .filter { (0...1).contains($0.fraction) }
            let rate = s.rateOfChange(at: now)
            return .init(stationName: name, tz: tz, next: next,
                         nextHigh: nextHigh, nextLow: nextLow, window: nil,
                         sparkline: normalize(heights), tideMovements: movements,
                         tideRate: rate, nowFraction: nowFraction,
                         curveKind: .tide, threshold: nil,
                         state: extremes.first?.kind == .high ? "Rising" : "Falling",
                         value: "\(formatHeight(height, imperial: imperial)) \(heightUnit(imperial: imperial))")

        case .current(let s, _, let name):
            let name = [stationNamePrefix, name].compactMap { $0 }.joined(separator: " · ")
            let pts = s.speeds(from: dayStart, to: dayEnd, step: 900)
            let signed = s.speeds(from: now, to: now.addingTimeInterval(1), step: 1).first?.speed ?? 0
            let ev = s.events(from: now, to: now.addingTimeInterval(172_800))
                .first { $0.time > now }
            var window: (Date, Date)?
            if let ev, ev.kind == .slack {
                let windowPts = s.speeds(from: ev.time.addingTimeInterval(-21_600),
                                         to: ev.time.addingTimeInterval(21_600))
                window = slackWindow(windowPts, around: ev.time, threshold: slackThresholdKn)
            }
            let next = ev.map {
                switch $0.kind {
                case .slack: Event(time: $0.time, label: "Slack", symbol: "minus")
                case .maxFlood: Event(time: $0.time,
                                      label: "Max flood \(formatSpeed(abs($0.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                                      symbol: "arrow.up.right")
                case .maxEbb: Event(time: $0.time,
                                    label: "Max ebb \(formatSpeed(abs($0.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                                    symbol: "arrow.down.right")
                }
            }
            return .init(stationName: name, tz: tz, next: next,
                         nextHigh: nil, nextLow: nil, window: window,
                         sparkline: pts.map(\.speed), tideMovements: [], tideRate: nil,
                         nowFraction: nowFraction,
                         curveKind: .current, threshold: slackThresholdKn,
                         state: currentPhase(signed: signed).word,
                         value: "\(formatSpeed(abs(signed), unit: speedUnit)) \(speedUnitLabel(speedUnit))")

        case .derived(let s, _, let name):
            let name = [stationNamePrefix, name].compactMap { $0 }.joined(separator: " · ")
            // Backward pad comfortably over one semidiurnal period (~12h25m):
            // schematicSigned reads 0 before slacks[0], so an unpadded fetch
            // starting at dayStart leaves the sparkline flat from midnight to
            // the day's first slack. Forward range is unchanged — the
            // next-slack search only ever looks past `now`, which is always
            // >= dayStart, so the extra early slacks can't leak into it.
            let backPad = 13.0 * 3600
            let slacks = s.slacks(from: dayStart.addingTimeInterval(-backPad),
                                  to: now.addingTimeInterval(172_800))
            let nextSlack = slacks.first { $0.time > now }
            let next = nextSlack.map {
                Event(time: $0.time, label: "Slack", symbol: "minus")
            }
            // Explicit instants across the real day length, not the engine's
            // floor/ceil-to-step bucketing — the only way to keep this at
            // exactly 97 samples on a 23/25-hour DST day.
            let step = dayLength / 96
            let samples = (0...96).map {
                s.schematicSigned(at: dayStart.addingTimeInterval(Double($0) * step),
                                  slacks: slacks)
            }
            // No window for a derived gate — a window measured off a schematic
            // shape would be fiction (TimelineData precedent).
            return .init(stationName: name, tz: tz, next: next,
                         nextHigh: nil, nextLow: nil, window: nil,
                         sparkline: samples, tideMovements: [], tideRate: nil,
                         nowFraction: nowFraction,
                         curveKind: .schematic, threshold: nil,
                         state: s.phase(at: now, slacks: slacks).word,
                         value: "Timing only")
        }
    }
}
