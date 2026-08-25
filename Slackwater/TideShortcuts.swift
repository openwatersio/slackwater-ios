// Slackwater — GPL v3. Offline, voice-first answers for the selected local tide station.
import AppIntents
import Foundation
import TideEngine

enum TideShortcutKind {
    case high, low
}

struct TideShortcutResult {
    let extreme: TideExtreme
    let stationName: String
    let timeZone: TimeZone

    var spoken: String {
        let imperial = AppGroup.defaults.string(forKey: unitsKey) != "metric"
        let kind = extreme.kind == .high ? "high" : "low"
        let time = extreme.time.formatted(Date.FormatStyle(
            date: .complete, time: .shortened, timeZone: timeZone))
        let height = formatHeight(extreme.height, imperial: imperial)
        return "The next \(kind) tide at \(stationName) is \(time), at \(height) \(imperial ? "feet" : "metres")."
    }
}

enum TideShortcutQuery {
    static func next(_ kind: TideShortcutKind, at selected: WidgetStation? = nil,
                     after now: Date = .now) -> TideShortcutResult? {
        let station = selected ?? defaultTideStation()
        guard case .tide(let engine, let tz, let name) = station else { return nil }
        let extreme = engine.extremes(from: now, to: now.addingTimeInterval(172_800))
            .first { $0.time > now && ($0.kind == .high) == (kind == .high) }
        return extreme.map { TideShortcutResult(extreme: $0, stationName: name, timeZone: tz) }
    }

    private static func defaultTideStation() -> WidgetStation? {
        let defaults = AppGroup.defaults
        let ids = (defaults.stringArray(forKey: AppGroup.favoritesKey) ?? [])
            + (defaults.stringArray(forKey: AppGroup.recentsKey) ?? [])
            + [TideStationRecord.fridayHarborID]
        return ids.lazy.compactMap(WidgetStationLoader.load).first {
            if case .tide = $0 { return true }
            return false
        }
    }
}

struct NextLowTideIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Low Tide"
    static let description = IntentDescription("Get the next low tide at your local Slackwater station.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = TideShortcutQuery.next(.low)?.spoken
            ?? "Slackwater couldn't find a tide prediction for your local station."
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

struct NextHighTideIntent: AppIntent {
    static let title: LocalizedStringResource = "Next High Tide"
    static let description = IntentDescription("Get the next high tide at your local Slackwater station.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = TideShortcutQuery.next(.high)?.spoken
            ?? "Slackwater couldn't find a tide prediction for your local station."
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

struct SlackwaterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextLowTideIntent(), phrases: [
            "When is the next low tide in \(.applicationName)",
            "What time is the next low tide in \(.applicationName)",
            "When is low tide in \(.applicationName)"
        ], shortTitle: "Next Low Tide", systemImageName: "arrow.down.to.line")
        AppShortcut(intent: NextHighTideIntent(), phrases: [
            "When is the next high tide in \(.applicationName)",
            "What time is the next high tide in \(.applicationName)",
            "When is high tide in \(.applicationName)"
        ], shortTitle: "Next High Tide", systemImageName: "arrow.up.to.line")
    }
}
