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
    private func entryBuilder(_ intent: StationConfigIntent,
                              for family: WidgetFamily) -> (Date) -> SlackwaterEntry {
        let premium = AppGroup.defaults.bool(forKey: AppGroup.premiumKey)
        let accessory = Self.accessoryFamilies.contains(family)
        let (id, prefix) = WidgetStationLoader.configured(intent.station?.id)
        let source: (Date) -> WidgetRecord? = accessory && !premium
            ? { _ in nil } : WidgetStationLoader.recordSource(id: id)
        return { date in
            let record = source(date)
            let snapshot = accessory
                ? record.map { WidgetSnapshot.build(WidgetStationLoader.station(from: $0), now: date, stationNamePrefix: prefix) }
                : nil
            let card = accessory ? nil : record.map { WidgetCard.build($0, now: date, stationNamePrefix: prefix) }
            return SlackwaterEntry(date: date, snapshot: snapshot, card: card,
                                   premium: premium, stationID: id)
        }
    }
    func placeholder(in context: Context) -> SlackwaterEntry {
        entryBuilder(StationConfigIntent(), for: context.family)(.now)
    }
    func snapshot(for intent: StationConfigIntent, in context: Context) async -> SlackwaterEntry {
        entryBuilder(intent, for: context.family)(.now)
    }
    func timeline(for intent: StationConfigIntent, in context: Context) async -> Timeline<SlackwaterEntry> {
        let now = Date()
        let entry = entryBuilder(intent, for: context.family)
        let entries = stride(from: 0.0, to: 86_400, by: 1_800)
            .map { entry(now.addingTimeInterval($0)) }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

@main
struct SlackwaterWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextEventWidget()
        DayCurveWidget()
        #if PREMIUM_ENABLED
        SlackInlineWidget()
        SlackCircularWidget()
        SlackRectangularWidget()
        #endif
    }
}
