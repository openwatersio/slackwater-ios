// Slackwater — GPL v3. Widget bundle + shared timeline provider. Entries are
// precomputed half-hourly for 24h — predictions are deterministic, so the
// timeline never needs network, background refresh, or luck.
import SwiftUI
import WidgetKit

struct SlackwaterEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?   // nil: unknown/unfitted station
    let card: WidgetCard?           // the medium widget's inputs
    let premium: Bool
    let stationID: String?          // for the widget's deepLink (Task 9)
}

struct StationProvider: AppIntentTimelineProvider {
    private func entry(_ intent: StationConfigIntent, at date: Date) -> SlackwaterEntry {
        let selectedID = intent.station?.id ?? WidgetStationLoader.defaultStationID()
        let id = WidgetStationLoader.resolvedStationID(selectedID)
        let prefix: String? = switch selectedID {
        case AppGroup.currentLocationStationID: "Current Location"
        case AppGroup.nearestTideStationID: "Nearest Tide"
        case AppGroup.nearestCurrentStationID: "Nearest Current"
        default: nil
        }
        // One ChsModelStore lookup, not two: the snapshot's station and the
        // card both derive from the same loaded record.
        let record = WidgetStationLoader.loadRecord(id: id, at: date)
        let snapshot = record.map { WidgetSnapshot.build(WidgetStationLoader.station(from: $0), now: date, stationNamePrefix: prefix) }
        let card = record.map { WidgetCard.build($0, now: date, stationNamePrefix: prefix) }
        return SlackwaterEntry(date: date, snapshot: snapshot, card: card,
                               premium: AppGroup.defaults.bool(forKey: AppGroup.premiumKey),
                               stationID: id)
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
        SlackInlineWidget()
        SlackCircularWidget()
        SlackRectangularWidget()
    }
}
