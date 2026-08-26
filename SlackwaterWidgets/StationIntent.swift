// Slackwater — GPL v3. Widget configuration: Current Location followed by
// Favorites and Recents from shared defaults.
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
    private let currentLocation = StationChoice(
        id: AppGroup.currentLocationStationID, name: "Current Location")

    private func choices() -> [StationChoice] {
        let d = AppGroup.defaults
        let ids = (d.stringArray(forKey: AppGroup.favoritesKey) ?? [])
            + (d.stringArray(forKey: AppGroup.recentsKey) ?? [])
        var seen = Set<String>()
        return [currentLocation] + ids.compactMap { id in
            guard seen.insert(id).inserted, let item = StationItem.byId[id] else { return nil }
            return StationChoice(id: id, name: item.name)
        }
    }
    func entities(for identifiers: [String]) async throws -> [StationChoice] {
        identifiers.compactMap { id in
            if id == AppGroup.currentLocationStationID { return currentLocation }
            return StationItem.byId[id].map { StationChoice(id: id, name: $0.name) }
        }
    }
    func suggestedEntities() async throws -> [StationChoice] { choices() }
    func defaultResult() async -> StationChoice? { currentLocation }
}

struct StationConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Station"
    static let description = IntentDescription("Choose the station this widget shows.")
    @Parameter(title: "Station") var station: StationChoice?
}
