// Slackwater — GPL v3. Offline, voice-first answers for the selected local tide station.
import AppIntents
import Foundation
import TideEngine

enum TideShortcutKind {
    case high, low
}

enum LocalStationKind {
    case tide, current
}

@MainActor enum LocalStationQuery {
    static func nearest(_ kind: LocalStationKind,
                        to anchor: (lat: Double, lon: Double)) -> WidgetStation? {
        RankedStations.near(lat: anchor.lat, lon: anchor.lon).ranked.lazy
            .compactMap { WidgetStationLoader.load(id: $0.id) }
            .first {
                switch (kind, $0) {
                case (.tide, .tide), (.current, .current): true
                default: false
                }
            }
    }
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

@MainActor enum TideShortcutQuery {
    static func next(_ kind: TideShortcutKind, at selected: WidgetStation? = nil,
                     after now: Date = .now) -> TideShortcutResult? {
        let station = selected ?? LocalStationQuery.nearest(
            .tide, to: LocationService.shared.rankingAnchor)
        guard case .tide(let engine, let tz, let name) = station else { return nil }
        let extreme = engine.extremes(from: now, to: now.addingTimeInterval(172_800))
            .first { $0.time > now && ($0.kind == .high) == (kind == .high) }
        return extreme.map { TideShortcutResult(extreme: $0, stationName: name, timeZone: tz) }
    }

}

struct SlackWindowShortcutResult {
    let slack: CurrentEvent
    let start: Date
    let end: Date
    let stationName: String
    let timeZone: TimeZone
    let queriedAt: Date

    var spoken: String {
        let style = Date.FormatStyle(date: .complete, time: .shortened, timeZone: timeZone)
        let window = "The next slack window at \(stationName) is from \(start.formatted(style)) "
            + "to \(end.formatted(style))"
        if start <= queriedAt { return window + " and is open now." }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return window + ", and starts "
            + relative.localizedString(for: start, relativeTo: queriedAt) + "."
    }
}

@MainActor enum SlackWindowShortcutQuery {
    static func next(at selected: WidgetStation? = nil,
                     after now: Date = .now) -> SlackWindowShortcutResult? {
        let station = selected ?? LocalStationQuery.nearest(
            .current, to: LocationService.shared.rankingAnchor)
        guard case .current(let engine, let tz, let name) = station,
              let slack = engine.events(from: now, to: now.addingTimeInterval(172_800))
                .first(where: { $0.time > now && $0.kind == .slack }) else { return nil }
        let points = engine.speeds(from: slack.time.addingTimeInterval(-21_600),
                                   to: slack.time.addingTimeInterval(21_600), step: 600)
        guard let window = slackWindow(points, around: slack.time,
                                       threshold: slackThresholdKn) else { return nil }
        return .init(slack: slack, start: window.start, end: window.end,
                     stationName: name, timeZone: tz, queriedAt: now)
    }
}

struct NextLowTideIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Low Tide"
    static let description = IntentDescription("Get the next low tide at your local Slackwater station.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await TideShortcutQuery.next(.low)?.spoken
            ?? "Slackwater couldn't find a tide prediction for your local station."
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

struct NextHighTideIntent: AppIntent {
    static let title: LocalizedStringResource = "Next High Tide"
    static let description = IntentDescription("Get the next high tide at your local Slackwater station.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await TideShortcutQuery.next(.high)?.spoken
            ?? "Slackwater couldn't find a tide prediction for your local station."
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

struct NextSlackWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Slack Window"
    static let description = IntentDescription("Get the next slack window at your nearest current station.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await SlackWindowShortcutQuery.next()?.spoken
            ?? "Slackwater couldn't find a slack window for your nearest current station."
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
        AppShortcut(intent: NextSlackWindowIntent(), phrases: [
            "When is the next slack window in \(.applicationName)"
        ], shortTitle: "Next Slack Window", systemImageName: "water.waves")
    }
}
