// Slackwater — GPL v3. Spoken answers and widget curves for nearby places.
import AppIntents
import CoreLocation
import Foundation
import SlackwaterKit
import SwiftUI

enum TideShortcutKind {
    case high, low
}

enum LocalStationKind {
    case tide, current
}

@MainActor enum LocalStationQuery {
    static func nearest(_ kind: LocalStationKind,
                        to anchor: (lat: Double, lon: Double)?, at now: Date = .now) -> WidgetRecord? {
        guard let anchor else { return nil }
        return RankedStations.near(lat: anchor.lat, lon: anchor.lon).ranked.lazy
            .filter { $0.series == (kind == .tide ? .tide : .current) }
            .filter { item in
                guard case .chsCurrent(let gate) = item, !gate.isOnline,
                      let model = ChsModelStore.loadCurrent(gate.id) else { return true }
                return !gate.isProvisional(model)
            }
            .compactMap { WidgetStationLoader.loadRecord(id: $0.id, at: now) }
            .first {
                switch (kind, $0) {
                case (.tide, .tide), (.current, .current): true
                default: false
                }
            }
    }

    static func resolve(_ kind: LocalStationKind,
                        prepareLocationRequest: () async throws -> Void) async throws -> WidgetRecord? {
        let service = LocationService.shared
        guard service.authorized else { throw ShortcutLocationError() }
        if let fix = LocationService.recentLocation(service.location) {
            return nearest(kind, to: (fix.coordinate.latitude, fix.coordinate.longitude))
        }
        try await prepareLocationRequest()
        service.request()
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            guard service.authorized else { throw ShortcutLocationError() }
            if let fix = LocationService.recentLocation(service.location) {
                return nearest(kind, to: (fix.coordinate.latitude, fix.coordinate.longitude))
            }
        }
        throw ShortcutLocationError()
    }
}

private extension AppIntent {
    @MainActor func nearbyRecord(_ kind: LocalStationKind) async throws -> WidgetRecord? {
        try await LocalStationQuery.resolve(kind) {
            guard systemContext.currentMode != .foreground else { return }
            guard systemContext.currentMode.canContinueInForeground else { throw ShortcutLocationError() }
            try await continueInForeground()
        }
    }
}

struct ShortcutLocationError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Open Slackwater and allow location to find a nearby place.", comment: "Siri response when location is denied or no fix is available.")
    }
}

func shortcutDuration(_ interval: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .full
    formatter.allowedUnits = interval >= 3_600 ? [.hour] : [.minute]
    formatter.maximumUnitCount = 1
    let rounded = interval >= 3_600
        ? max(1, (interval / 3_600).rounded()) * 3_600
        : min(59, max(1, (interval / 60).rounded())) * 60
    return formatter.string(from: rounded) ?? ""
}

private func shortcutDay(_ date: Date, relativeTo now: Date, in timeZone: TimeZone) -> String? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    if calendar.isDate(date, inSameDayAs: now) { return nil }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
       calendar.isDate(date, inSameDayAs: tomorrow) {
        return String(localized: "Tomorrow", comment: "Relative label for the next day.")
    }
    return date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated).month(.abbreviated).day())
}

private func shortcutTime(_ date: Date, relativeTo now: Date, in timeZone: TimeZone) -> String {
    let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    return [shortcutDay(date, relativeTo: now, in: timeZone), time].compactMap { $0 }.joined(separator: " · ")
}

struct TideShortcutResult {
    let extreme: TideExtreme
    let stationName: String
    let timeZone: TimeZone
    let queriedAt: Date
    let card: WidgetCard
    let detail: String

    var spoken: String {
        let wait = shortcutDuration(extreme.time.timeIntervalSince(queriedAt))
        return extreme.kind == .high
            ? String(localized: "The next high tide at \(stationName) is in about \(wait).", comment: "Spoken Siri answer. Values are place name and a localized duration such as 6 hours.")
            : String(localized: "The next low tide at \(stationName) is in about \(wait).", comment: "Spoken Siri answer. Values are place name and a localized duration such as 25 minutes.")
    }
}

@MainActor enum TideShortcutQuery {
    static func next(_ kind: TideShortcutKind, at selected: WidgetRecord?, after now: Date = .now) -> TideShortcutResult? {
        guard let selected, case .tide(let record, let engine) = selected,
              let extreme = engine.extremes(from: now, to: now.addingTimeInterval(172_800))
                .first(where: { $0.time > now && ($0.kind == .high) == (kind == .high) }) else { return nil }
        var card = WidgetCard.build(selected, now: now, through: extreme.time.addingTimeInterval(3_600))
        card.graph?.highlight = extreme.time...extreme.time
        let imperial = heightUnits() != "metric"
        let detail = "\(shortcutTime(extreme.time, relativeTo: now, in: record.tz)) · \(formatHeight(extreme.height, imperial: imperial)) \(heightUnit(imperial: imperial))"
        return .init(extreme: extreme, stationName: record.name, timeZone: record.tz,
                     queriedAt: now, card: card, detail: detail)
    }

}

struct SlackWindowShortcutResult {
    let slack: CurrentEvent
    let start: Date
    let end: Date
    let stationName: String
    let timeZone: TimeZone
    let queriedAt: Date
    let card: WidgetCard
    let hasOpeningBoundary: Bool
    let hasClosingBoundary: Bool

    var detail: String? {
        if !hasClosingBoundary {
            return start > queriedAt && hasOpeningBoundary
                ? shortcutTime(start, relativeTo: queriedAt, in: timeZone) : nil
        }
        if !hasOpeningBoundary {
            return "\(String(localized: "Slack ends", comment: "Siri detail prefix before the observed local closing time of a slack window.")) · \(shortcutTime(end, relativeTo: queriedAt, in: timeZone))"
        }
        let formatter = DateIntervalFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(start, inSameDayAs: end) {
            return [shortcutDay(start, relativeTo: queriedAt, in: timeZone), formatter.string(from: start, to: end)]
                .compactMap { $0 }.joined(separator: " · ")
        }
        return "\(shortcutTime(start, relativeTo: queriedAt, in: timeZone)) – \(shortcutTime(end, relativeTo: queriedAt, in: timeZone))"
    }

    var spoken: String {
        if start <= queriedAt {
            if !hasClosingBoundary {
                return String(localized: "The slack window at \(stationName) is open now.", comment: "Spoken Siri answer when a current window is open and no closing crossing was observed.")
            }
            let remaining = shortcutDuration(end.timeIntervalSince(queriedAt))
            return String(localized: "The slack window at \(stationName) is open now, with about \(remaining) remaining.", comment: "Spoken Siri answer for an open current window. Values are place name and localized time remaining.")
        }
        let wait = shortcutDuration(start.timeIntervalSince(queriedAt))
        if !hasClosingBoundary {
            return String(localized: "The next slack window at \(stationName) starts in about \(wait).", comment: "Spoken Siri answer when the window opening is known but no closing crossing was observed. Values are place name and localized wait.")
        }
        let duration = shortcutDuration(end.timeIntervalSince(start))
        return String(localized: "The next slack window at \(stationName) starts in about \(wait) and lasts about \(duration).", comment: "Spoken Siri answer. Values are place name, localized wait until the window opens, and localized window duration.")
    }
}

@MainActor enum SlackWindowShortcutQuery {
    static func noWindow(at selected: WidgetRecord?) -> String {
        guard let selected, case .current(let record, _) = selected else {
            return String(localized: "Slackwater couldn't find a slack window for your nearest current station.", comment: "Spoken Siri failure response.")
        }
        if slackWindowIsOff(slackThresholdKn) {
            return String(localized: "Your slack window is off. Set a comfort current in Slackwater's settings to turn it on.", comment: "Spoken Siri answer when the comfort current is set to Off.")
        }
        return String(localized: "There's no slack window at \(record.name) in the next 48 hours.", comment: "Spoken Siri answer when the selected current place has predictions but no slack window in the 48-hour search. Value is the place name.")
    }

    static func next(at selected: WidgetRecord?,
                     after now: Date = .now) -> SlackWindowShortcutResult? {
        guard let selected, case .current(let record, let engine) = selected else { return nil }
        let events = engine.events(from: now.addingTimeInterval(-21_600), to: now.addingTimeInterval(172_800))
        for slack in events where slack.kind == .slack {
            let requestedEnd = slack.time.addingTimeInterval(21_600)
            let end = (engine as? ChsOnlineWindow).map { min(requestedEnd, $0.end) } ?? requestedEnd
            var card = WidgetCard.build(selected, now: now, through: end)
            guard let graph = card.graph else { continue }
            // Speech and the card must use the same sample grid and window boundaries.
            let points = graph.points.map { CurrentPoint(time: $0.time, speed: $0.value) }
            guard let window = slackWindow(points, around: slack.time, threshold: slackThresholdKn),
                  window.end > now else { continue }
            let hasOpening = window.start > points[0].time
            let hasClosing = window.end < points[points.count - 1].time
            let focus = window.start > now ? window.start : now
            card.graph?.highlight = hasOpening && hasClosing ? window.start...window.end : focus...focus
            return .init(slack: slack, start: window.start, end: window.end,
                         stationName: record.name, timeZone: record.tz, queriedAt: now, card: card,
                         hasOpeningBoundary: hasOpening, hasClosingBoundary: hasClosing)
        }
        return nil
    }
}

struct NextLowTideIntent: AppIntent {
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    static let title: LocalizedStringResource = "Next Low Tide"
    static let description = IntentDescription("Get the next low tide at your local Slackwater station.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let record = try await nearbyRecord(.tide)
        let result = TideShortcutQuery.next(.low, at: record)
        let answer = result?.spoken
            ?? String(localized: "Slackwater couldn't find a tide prediction for your local station.", comment: "Spoken Siri failure response.")
        return .result(dialog: IntentDialog(stringLiteral: answer)) {
            TideShortcutSnippetView(answer: answer, detail: result?.detail, card: result?.card)
        }
    }
}

struct NextHighTideIntent: AppIntent {
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    static let title: LocalizedStringResource = "Next High Tide"
    static let description = IntentDescription("Get the next high tide at your local Slackwater station.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let record = try await nearbyRecord(.tide)
        let result = TideShortcutQuery.next(.high, at: record)
        let answer = result?.spoken
            ?? String(localized: "Slackwater couldn't find a tide prediction for your local station.", comment: "Spoken Siri failure response.")
        return .result(dialog: IntentDialog(stringLiteral: answer)) {
            TideShortcutSnippetView(answer: answer, detail: result?.detail, card: result?.card)
        }
    }
}

struct NextSlackWindowIntent: AppIntent {
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    static let title: LocalizedStringResource = "Next Slack Window"
    static let description = IntentDescription("Get the next slack window at your nearest current station.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let record = try await nearbyRecord(.current)
        let result = SlackWindowShortcutQuery.next(at: record)
        let answer = result?.spoken
            ?? SlackWindowShortcutQuery.noWindow(at: record)
        return .result(dialog: IntentDialog(stringLiteral: answer)) {
            TideShortcutSnippetView(answer: answer, detail: result?.detail, card: result?.card)
        }
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
