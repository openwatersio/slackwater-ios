// Slackwater — GPL v3. The render-ready value a widget entry carries: next
// event, its slack window, and today's normalized curve. Pure function of
// (station, now) — deterministic, offline, engine-only.
import Foundation
import TideEngine

struct WidgetSnapshot: Equatable {
    struct Event: Equatable {
        let time: Date
        let label: String
        let symbol: String
    }
    let stationName: String
    let tz: TimeZone
    let next: Event?
    let window: (start: Date, end: Date)?
    let sparkline: [Double]
    let nowFraction: Double

    static func == (a: Self, b: Self) -> Bool {
        a.stationName == b.stationName && a.tz == b.tz && a.next == b.next
            && a.window?.start == b.window?.start && a.window?.end == b.window?.end
            && a.sparkline == b.sparkline && a.nowFraction == b.nowFraction
    }

    static func build(_ station: WidgetStation, now: Date) -> WidgetSnapshot {
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
            let heights = s.heights(from: dayStart, to: dayEnd, step: 900).map(\.height)
            let ext = s.extremes(from: now, to: now.addingTimeInterval(172_800))
                .first { $0.time > now }
            let next = ext.map {
                Event(time: $0.time,
                      label: ($0.kind == .high ? "High" : "Low")
                          + " \(formatHeight($0.height, imperial: imperial)) \(heightUnit(imperial: imperial))",
                      symbol: $0.kind == .high ? "arrow.up" : "arrow.down")
            }
            return .init(stationName: name, tz: tz, next: next, window: nil,
                         sparkline: normalize(heights), nowFraction: nowFraction)

        case .current(let s, _, let name):
            let pts = s.speeds(from: dayStart, to: dayEnd, step: 900)
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
            return .init(stationName: name, tz: tz, next: next, window: window,
                         sparkline: normalize(pts.map { abs($0.speed) }),
                         nowFraction: nowFraction)

        case .derived(let s, _, let name):
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
                abs(s.schematicSigned(at: dayStart.addingTimeInterval(Double($0) * step),
                                      slacks: slacks))
            }
            // No window for a derived gate — a window measured off a schematic
            // shape would be fiction (TimelineData precedent).
            return .init(stationName: name, tz: tz, next: next, window: nil,
                         sparkline: normalize(samples), nowFraction: nowFraction)
        }
    }
}
