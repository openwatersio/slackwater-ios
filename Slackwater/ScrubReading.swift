// Slackwater — GPL v3. The watch card's words at a scrub time: state,
// reading and the next event, read off the loaded timeline (#522).
import Foundation
import SlackwaterKit

struct ScrubReading: Equatable {
    let title: String
    let value: String?
    let unit: String?
    let symbol: String?
    let next: String?

    /// Within this of an event, the scrub is on it: the magnet parks exactly,
    /// the Crown lands within a few seconds.
    private static let onEvent: TimeInterval = 60

    static func at(_ t: Date, in data: TimelineData, imperial: Bool, speedUnit: String) -> ScrubReading {
        if data.hasTide {
            let turn = data.tideExtremes.first { abs($0.time.timeIntervalSince(t)) < onEvent }
            let next = data.tideExtremes.first { $0.time.timeIntervalSince(t) >= onEvent }
            let rising = next.map { $0.kind == .high } ?? true
            let title = turn.map(extremeName)
                ?? (rising ? String(localized: "Rising", comment: "Rising-tide state.")
                           : String(localized: "Falling", comment: "Falling-tide state."))
            let symbol = turn.map { $0.kind == .high ? "arrow.up.to.line" : "arrow.down.to.line" }
                ?? (rising ? "arrow.up.right" : "arrow.down.right")
            return ScrubReading(title: title,
                                value: formatHeight(data.heightAt(t), imperial: imperial),
                                unit: heightUnit(imperial: imperial), symbol: symbol,
                                next: next.map { tideLine($0, data, imperial) })
        }
        let v = data.velocityAt(t)
        let next = data.currentEvents.first { $0.time.timeIntervalSince(t) >= onEvent }
        let schematic = data.speedsAreSchematic
        return ScrubReading(title: currentPhase(signed: v).word,
                            value: schematic ? nil : formatSpeed(abs(v), unit: speedUnit),
                            unit: schematic ? nil : speedUnitLabel(speedUnit), symbol: nil,
                            next: next.map { currentLine($0, data, speedUnit) })
    }

    /// The sheet's list: the events after `t` on its local day.
    static func todaysEvents(after t: Date, in data: TimelineData,
                             imperial: Bool, speedUnit: String) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = data.tz
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: t)) ?? t
        if data.hasTide {
            return data.tideExtremes.filter { $0.time > t && $0.time < end }.map { tideLine($0, data, imperial) }
        }
        return data.currentEvents.filter { $0.time > t && $0.time < end }.map { currentLine($0, data, speedUnit) }
    }

    private static func extremeName(_ e: TideExtreme) -> String {
        e.kind == .high ? String(localized: "High", comment: "High-tide event label.")
                        : String(localized: "Low", comment: "Low-tide event label.")
    }

    private static func tideLine(_ e: TideExtreme, _ data: TimelineData, _ imperial: Bool) -> String {
        "\(extremeName(e)) \(formatHeight(e.height, imperial: imperial)) \(heightUnit(imperial: imperial)) · \(cardTime(e.time, data.tz))"
    }

    private static func currentLine(_ e: CurrentEvent, _ data: TimelineData, _ speedUnit: String) -> String {
        let time = cardTime(e.time, data.tz)
        switch e.kind {
        case .slack:
            return "\(String(localized: "Slack", comment: "Current phase: water is near zero speed.")) · \(time)"
        case .maxFlood, .maxEbb:
            let name = e.kind == .maxFlood
                ? String(localized: "Max flood", comment: "Maximum flood-current event label.")
                : String(localized: "Max ebb", comment: "Maximum ebb-current event label.")
            if data.speedsAreSchematic { return "\(name) · \(time)" }
            return "\(name) \(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit)) · \(time)"
        }
    }
}
