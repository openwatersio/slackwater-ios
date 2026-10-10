// Slackwater — GPL v3. Accessory widget labels and next event. Pure function of
// (station, now) — deterministic, offline, engine-only.
import Foundation
import SlackwaterKit

struct WidgetSnapshot: Equatable {
    enum CurveKind: Equatable { case tide, current, schematic }

    struct Event: Equatable {
        let time: Date
        let label: String
    }
    let stationName: String
    let tz: TimeZone
    let next: Event?
    let curveKind: CurveKind
    let value: String

    static func build(_ station: WidgetStation, now: Date, stationNamePrefix: String? = nil) -> WidgetSnapshot {
        // Read once, here — not per format call — so `build` stays a pure
        // function of (station, now) (H2): the setting is an input, same as
        // the other two.
        let imperial = heightUnits() != "metric"
        let speedUnit = AppGroup.defaults.string(forKey: speedUnitKey) ?? "kn"

        let tz: TimeZone
        switch station {
        case .tide(_, let z, _), .current(_, let z, _), .derived(_, let z, _): tz = z
        }

        switch station {
        case .tide(let s, _, let name):
            let name = [stationNamePrefix, name].compactMap { $0 }.joined(separator: " · ")
            let height = s.heights(from: now, to: now.addingTimeInterval(1), step: 1).first?.height ?? 0
            let extremes = s.extremes(from: now, to: now.addingTimeInterval(172_800))
                .filter { $0.time > now }
            let event = { (extreme: TideExtreme) in
                Event(time: extreme.time,
                      label: (extreme.kind == .high
                        ? String(localized: "High", comment: "Widget high-tide event label.")
                        : String(localized: "Low", comment: "Widget low-tide event label."))
                          + " \(formatHeight(extreme.height, imperial: imperial)) \(heightUnit(imperial: imperial))")
            }
            let next = extremes.first.map(event)
            return .init(stationName: name, tz: tz, next: next,
                         curveKind: .tide,
                         value: "\(formatHeight(height, imperial: imperial)) \(heightUnit(imperial: imperial))")

        case .current(let s, _, let name):
            let name = [stationNamePrefix, name].compactMap { $0 }.joined(separator: " · ")
            let signed = s.speeds(from: now, to: now.addingTimeInterval(1), step: 1).first?.speed ?? 0
            let ev = s.events(from: now, to: now.addingTimeInterval(172_800))
                .first { $0.time > now }
            let next = ev.map {
                switch $0.kind {
                case .slack: Event(time: $0.time, label: String(localized: "Slack", comment: "Widget slack-current event label."))
                case .maxFlood: Event(time: $0.time,
                                      label: String(localized: "Max flood \(formatSpeed(abs($0.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))", comment: "Widget maximum flood-current event. Values are formatted speed and compact unit."))
                case .maxEbb: Event(time: $0.time,
                                    label: String(localized: "Max ebb \(formatSpeed(abs($0.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))", comment: "Widget maximum ebb-current event. Values are formatted speed and compact unit."))
                }
            }
            return .init(stationName: name, tz: tz, next: next,
                         curveKind: .current,
                         value: "\(formatSpeed(abs(signed), unit: speedUnit)) \(speedUnitLabel(speedUnit))")

        case .derived(let s, _, let name):
            let name = [stationNamePrefix, name].compactMap { $0 }.joined(separator: " · ")
            let slacks = s.slacks(from: now, to: now.addingTimeInterval(172_800))
            let nextSlack = slacks.first { $0.time > now }
            let next = nextSlack.map {
                Event(time: $0.time, label: String(localized: "Slack", comment: "Widget slack-current event label."))
            }
            return .init(stationName: name, tz: tz, next: next,
                         curveKind: .schematic, value: "Timing only")
        }
    }
}

/// The list card's inputs, built once per timeline entry so the widget is
/// the card (current-charts §15) with no second drawing of the curve.
struct WidgetCard {
    let name: String
    let region: String
    let reading: ConditionsItem.Reading
    let graph: StationCardGraph?
    /// A derived gate's next slack, for its "Slack · time" line.
    let nextSlack: (time: Date, tz: TimeZone)?
    /// True when the region line should carry the location mark instead of
    /// its words — the Current Location entry, prefixed by the caller.
    let locationMark: Bool
    /// The window's closing when under two hours remain at the ENTRY date —
    /// WidgetKit renders every entry at delivery, so this is decided here,
    /// not in a view body. Nil otherwise: no countdown, no "> 2 hrs".
    let countdownEnd: Date?

    static func build(_ record: WidgetRecord, now: Date, stationNamePrefix: String? = nil) -> WidgetCard {
        let imperial = heightUnits() != "metric"
        let speedUnit = AppGroup.defaults.string(forKey: speedUnitKey) ?? "kn"
        let locationMark = stationNamePrefix != nil
        switch record {
        case .tide(let r, let station):
            let state = r.cardState(at: now, station: station)
            return .init(name: r.name, region: r.region,
                         reading: .tide(state, imperial: imperial),
                         graph: r.cardGraph(at: now, imperial: imperial, station: station), nextSlack: nil,
                         locationMark: locationMark, countdownEnd: nil)
        case .current(let r, let station):
            let state = r.cardState(at: now, station: station)
            let graph = r.cardGraph(at: now, unit: speedUnit, station: station)
            // Inside a window the widget counts down to the closing (§15.3),
            // decided here at the entry date — not later, at render time.
            let inside = graph.windows.first { $0.contains(now) }
            let countdownEnd = inside.flatMap { $0.end.timeIntervalSince(now) <= 7_200 ? $0.end : nil }
            return .init(name: r.name, region: r.region,
                         reading: .current(signed: state.signed, deg: r.setDegrees(signed: state.signed),
                                           unit: speedUnit, inWindow: inside != nil),
                         graph: graph, nextSlack: nil,
                         locationMark: locationMark, countdownEnd: countdownEnd)
        case .derived(let r):
            let state = r.cardState(at: now)
            return .init(name: r.gate.name, region: r.gate.region,
                         reading: .gate(state.phase), graph: nil,
                         nextSlack: state.nextSlack.map { ($0.time, r.gate.tz) },
                         locationMark: locationMark, countdownEnd: nil)
        }
    }
}
