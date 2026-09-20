// Slackwater — GPL v3. Widget bundle + shared timeline provider. Entries are
// precomputed half-hourly for 24h — predictions are deterministic, so the
// timeline never needs network, background refresh, or luck.
import SwiftUI
import WidgetKit

struct StationProvider: AppIntentTimelineProvider {
    /// The lock-screen families, which render from `snapshot`. Everything else
    /// this bundle ships is a home-screen family and renders from `card`
    /// (HomeWidgets.swift). Must match the `supportedFamilies` of the three
    /// widgets in AccessoryWidgets.swift — `WidgetFamilyCoverageTests` checks it.
    private static let accessoryFamilies: Set<WidgetFamily> =
        [.accessoryInline, .accessoryCircular, .accessoryRectangular]

    /// Build only what this family draws. A snapshot and a card each cost a
    /// full day of harmonic evaluation, and every widget reads exactly one of
    /// them — so building both was half of a 48-entry timeline thrown away.
    /// A locked accessory draws neither and needs no station record at all.
    private func entry(_ intent: StationConfigIntent, at date: Date,
                       for family: WidgetFamily) -> SlackwaterEntry {
        let premium = AppGroup.defaults.bool(forKey: AppGroup.premiumKey)
        let accessory = Self.accessoryFamilies.contains(family)
        let selectedID = intent.station?.id ?? WidgetStationLoader.defaultStationID()
        let id = WidgetStationLoader.resolvedStationID(selectedID)
        let prefix: String? = switch selectedID {
        case AppGroup.currentLocationStationID: "Current Location"
        case AppGroup.nearestTideStationID: "Nearest Tide"
        case AppGroup.nearestCurrentStationID: "Nearest Current"
        default: nil
        }
        let record = accessory && !premium ? nil : WidgetStationLoader.loadRecord(id: id, at: date)
        let snapshot = accessory
            ? record.map { WidgetSnapshot.build(WidgetStationLoader.station(from: $0), now: date, stationNamePrefix: prefix) }
            : nil
        let card = accessory ? nil : record.map { WidgetCard.build($0, now: date, stationNamePrefix: prefix) }
        return SlackwaterEntry(date: date, snapshot: snapshot, card: card,
                               premium: premium, stationID: id)
    }
    func placeholder(in context: Context) -> SlackwaterEntry {
        entry(StationConfigIntent(), at: .now, for: context.family)
    }
    func snapshot(for intent: StationConfigIntent, in context: Context) async -> SlackwaterEntry {
        entry(intent, at: .now, for: context.family)
    }
    func timeline(for intent: StationConfigIntent, in context: Context) async -> Timeline<SlackwaterEntry> {
        let now = Date()
        let entries = stride(from: 0.0, to: 86_400, by: 1_800)
            .map { entry(intent, at: now.addingTimeInterval($0), for: context.family) }
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
