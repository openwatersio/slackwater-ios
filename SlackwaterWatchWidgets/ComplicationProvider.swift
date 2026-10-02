// Slackwater — GPL v3. The watch's complication timeline (#524). Entries are
// precomputed every 15 minutes for 12 hours: predictions are deterministic,
// and the dot moves visibly between them.
import WidgetKit

struct ComplicationProvider: AppIntentTimelineProvider {
    /// The families that draw the list row's card; every other family draws
    /// the complication reading. `WatchWidgetFamilyCoverageTests` checks it.
    static let cardFamilies: Set<WidgetFamily> = [.accessoryRectangular]

    private func entryBuilder(_ intent: StationConfigIntent,
                              for family: WidgetFamily) -> (Date) -> SlackwaterEntry {
        let premium = AppGroup.defaults.bool(forKey: AppGroup.premiumKey)
        let (id, prefix) = WidgetStationLoader.configured(intent.station?.id)
        let card = Self.cardFamilies.contains(family)
        // Locked: no record at all, so no station data can leak.
        let source: (Date) -> WidgetRecord? = premium ? WidgetStationLoader.recordSource(id: id) : { _ in nil }
        return { date in
            let record = source(date).flatMap { $0.isWatchSupported ? $0 : nil }
            return SlackwaterEntry(
                date: date, snapshot: nil,
                card: card ? record.map { WidgetCard.build($0, now: date, stationNamePrefix: prefix) } : nil,
                premium: premium, stationID: id,
                complication: card ? nil : record.flatMap {
                    ComplicationReading.build(WidgetStationLoader.station(from: $0), now: date)
                })
        }
    }

    // Empty, so the face editor offers the intent's own station picker
    // instead of a fixed list of presets.
    func recommendations() -> [AppIntentRecommendation<StationConfigIntent>] { [] }
    func placeholder(in context: Context) -> SlackwaterEntry {
        entryBuilder(StationConfigIntent(), for: context.family)(.now)
    }
    func snapshot(for intent: StationConfigIntent, in context: Context) async -> SlackwaterEntry {
        entryBuilder(intent, for: context.family)(.now)
    }
    func timeline(for intent: StationConfigIntent, in context: Context) async -> Timeline<SlackwaterEntry> {
        let now = Date()
        let entry = entryBuilder(intent, for: context.family)
        let entries = stride(from: 0.0, to: 12 * 3600, by: 900).map { entry(now.addingTimeInterval($0)) }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

extension WidgetRecord {
    /// Canadian online currents and derived gates wait for #523 on the watch.
    var isWatchSupported: Bool {
        switch self {
        case .tide: true
        case .current(_, let station): !(station is ChsOnlineWindow)
        case .derived: false
        }
    }
}
