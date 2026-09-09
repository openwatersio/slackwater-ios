// Slackwater — GPL v3. Widget configuration: the location-following entries,
// then Favorites and Recents from shared defaults, as picker sections.
//
// Compiled into BOTH the app and the widget extension, as Apple's
// configurable-widget sample does, so the containing app registers the
// entity too. In the SIMULATOR the configured station always resolves to
// nil: linkd cannot read a simulator process's team id, the App Intents
// runtime then cannot build the entity identifier ("StationChoice is not a
// registered AppEntity identifier" in the log), and every widget shows the
// default station. Verify the picker on a device.
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
    private let locator: CatalogFileLocator
    private let defaults: UserDefaults
    private let currentLocation = StationChoice(
        id: AppGroup.currentLocationStationID, name: "Any Station")
    /// Any Station's series-narrowed siblings: follow the fix, but to the
    /// nearest station that measures tide (or current) specifically —
    /// otherwise a fix beside a tide gauge makes every widget a tide widget.
    /// All three read under the "Nearest Station" section header, which
    /// carries the "nearest" for them.
    private let nearestTide = StationChoice(
        id: AppGroup.nearestTideStationID, name: "Tide Station")
    private let nearestCurrent = StationChoice(
        id: AppGroup.nearestCurrentStationID, name: "Current Station")
    private var sentinels: [StationChoice] { [currentLocation, nearestTide, nearestCurrent] }

    init() {
        self.init(locator: .shared, defaults: AppGroup.defaults)
    }

    init(locator: CatalogFileLocator, defaults: UserDefaults = AppGroup.defaults) {
        self.locator = locator
        self.defaults = defaults
    }

    /// The picker's grouping, as plain data the tests can read: the
    /// location-following entries, then Favorites, then Recents — a starred
    /// station stays under Favorites, never repeated under Recents. Empty
    /// sections don't render.
    func sectionedChoices() -> [(title: String, items: [StationChoice])] {
        var seen = Set<String>()
        func resolve(_ key: String) -> [StationChoice] {
            (defaults.stringArray(forKey: key) ?? []).compactMap { id in
                guard seen.insert(id).inserted,
                      let item = StationItem.widgetItem(id: id, locator: locator) else { return nil }
                return StationChoice(id: id, name: item.name)
            }
        }
        return [(title: "Nearest Station", items: sentinels),
                (title: "Favorites", items: resolve(AppGroup.favoritesKey)),
                (title: "Recents", items: resolve(AppGroup.recentsKey))]
            .filter { !$0.items.isEmpty }
    }
    func entities(for identifiers: [String]) async throws -> [StationChoice] {
        identifiers.compactMap { id in
            if let sentinel = sentinels.first(where: { $0.id == id }) { return sentinel }
            return StationItem.widgetItem(id: id, locator: locator)
                .map { StationChoice(id: id, name: $0.name) }
        }
    }
    func suggestedEntities() async throws -> IntentItemCollection<StationChoice> {
        IntentItemCollection(sections: sectionedChoices().map { section in
            IntentItemSection(LocalizedStringResource(stringLiteral: section.title),
                              items: section.items)
        })
    }
    func defaultResult() async -> StationChoice? { currentLocation }
}

struct StationConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Station"
    static let description = IntentDescription("Choose the station this widget shows.")
    @Parameter(title: "Station") var station: StationChoice?
}
