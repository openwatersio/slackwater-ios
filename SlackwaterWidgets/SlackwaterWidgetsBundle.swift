// Slackwater — GPL v3. Widget bundle + shared timeline provider. Entries are
// precomputed half-hourly for 24h — predictions are deterministic, so the
// timeline never needs network, background refresh, or luck.
import SwiftUI
import WidgetKit

struct SlackwaterEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?   // nil: unknown/unfitted station
    let premium: Bool
}

struct StationProvider: AppIntentTimelineProvider {
    private func entry(_ intent: StationConfigIntent, at date: Date) -> SlackwaterEntry {
        let id = intent.station?.id ?? WidgetStationLoader.defaultStationID()
        let snapshot = WidgetStationLoader.load(id: id)
            .map { WidgetSnapshot.build($0, now: date) }
        return SlackwaterEntry(date: date, snapshot: snapshot,
                               premium: AppGroup.defaults.bool(forKey: "slackwater.premium"))
    }
    func placeholder(in context: Context) -> SlackwaterEntry {
        entry(StationConfigIntent(), at: .now)
    }
    func snapshot(for intent: StationConfigIntent, in context: Context) async -> SlackwaterEntry {
        entry(intent, at: .now)
    }
    func timeline(for intent: StationConfigIntent, in context: Context) async -> Timeline<SlackwaterEntry> {
        let now = Date()
        let entries = stride(from: 0.0, to: 86_400, by: 1_800)
            .map { entry(intent, at: now.addingTimeInterval($0)) }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

@main
struct SlackwaterWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextEventWidget()
        DayCurveWidget()
    }
}
