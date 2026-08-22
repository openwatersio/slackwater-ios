// Slackwater — GPL v3. Widget configuration: pick a station. Choices come
// from Favorites then Recents (shared defaults); default is the first
// favorite — the widget works with zero configuration.
import AppIntents
import WidgetKit

struct StationChoice: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Station"
    static let defaultQuery = StationQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}

struct StationQuery: EntityQuery {
    private func choices() -> [StationChoice] {
        let d = AppGroup.defaults
        let ids = (d.stringArray(forKey: AppGroup.favoritesKey) ?? [])
            + (d.stringArray(forKey: AppGroup.recentsKey) ?? [])
        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted, let item = StationItem.byId[id] else { return nil }
            return StationChoice(id: id, name: item.name)
        }
    }
    func entities(for identifiers: [String]) async throws -> [StationChoice] {
        identifiers.compactMap { id in
            StationItem.byId[id].map { StationChoice(id: id, name: $0.name) }
        }
    }
    func suggestedEntities() async throws -> [StationChoice] { choices() }
    func defaultResult() async -> StationChoice? { choices().first }
}

struct StationConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Station"
    static let description = IntentDescription("Choose the station this widget shows.")
    @Parameter(title: "Station") var station: StationChoice?
}
