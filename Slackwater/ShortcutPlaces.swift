// Slackwater — GPL v3. Searchable Siri places, separate from widget location presets.
import AppIntents
import Foundation

func shortcutDateInterval(_ date: Date, in timeZone: TimeZone,
                          inputCalendar: Calendar = .current) -> DateInterval? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    // A date-only parameter carries the phone's midnight; keep its selected day at the destination.
    var input = Calendar(identifier: .gregorian)
    input.timeZone = inputCalendar.timeZone
    let components = input.dateComponents([.year, .month, .day], from: date)
    guard let local = calendar.date(from: components) else { return nil }
    return calendar.dateInterval(of: .day, for: local)
}

enum ShortcutPlaceQuery {
    static func accepts(_ item: StationItem, kind: LocalStationKind) -> Bool {
        guard item.series == (kind == .tide ? .tide : .current) else { return false }
        if case .chsGate = item { return false }
        return true
    }

    static func matches(_ query: String, kind: LocalStationKind, preferredIDs: [String] = [],
                        near anchor: (lat: Double, lon: Double)? = nil) -> [StationItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        var priority: [String: Int] = [:]
        for id in preferredIDs where priority[id] == nil { priority[id] = priority.count }
        return StationItem.all.compactMap { item -> (item: StationItem, rank: Int, priority: Int, km: Double)? in
            guard accepts(item, kind: kind), let rank = item.searchRank(query) else { return nil }
            let matchRank = item.name.lowercased() == query ? -1 : rank
            return (item, matchRank, priority[item.id] ?? .max,
                    anchor.map { item.km(fromLat: $0.lat, lon: $0.lon) } ?? 0)
        }.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.km != $1.km { return $0.km < $1.km }
            if $0.item.name != $1.item.name { return $0.item.name < $1.item.name }
            if $0.item.region != $1.item.region { return $0.item.region < $1.item.region }
            return $0.item.id < $1.item.id
        }.map(\.item)
    }

    @MainActor private static func context(defaults: UserDefaults) -> (ids: [String], anchor: (lat: Double, lon: Double)?) {
        let service = LocationService.shared
        let fix = service.authorized ? LocationService.recentLocation(service.location) : nil
        let anchor = fix.map { (lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
        var localIDs: [String] = []
        if let anchor {
            let (ranked, places) = RankedStations.near(lat: anchor.lat, lon: anchor.lon)
            localIDs = StationItem.heroItems(ranked: ranked, lat: anchor.lat, lon: anchor.lon)
                .map { places.shown($0.id) }
        }
        return (StationSuccessors.remap(localIDs
            + (defaults.stringArray(forKey: AppGroup.favoritesKey) ?? [])
            + (defaults.stringArray(forKey: AppGroup.recentsKey) ?? [])), anchor)
    }

    @MainActor static func resolveMatches(_ query: String, kind: LocalStationKind,
                                         defaults: UserDefaults = AppGroup.defaults) -> [StationItem] {
        let context = context(defaults: defaults)
        let ranked = matches(query, kind: kind, preferredIDs: context.ids, near: context.anchor)
        // A matching place from the person's list is an explicit preference; leave other ambiguity to Siri.
        if let first = ranked.first, context.ids.contains(first.id) { return [first] }
        return ranked
    }

    static func timeZone(_ item: StationItem) -> TimeZone {
        switch item {
        case .tide(let s), .current(let s): s.tz
        case .chs(let s): s.tz
        case .chsGate(let s): s.tz
        case .chsCurrent(let s): s.tz
        }
    }

    static func usable(_ item: StationItem) -> Bool {
        guard case .chsCurrent(let gate) = item, !gate.isOnline,
              let model = ChsModelStore.loadCurrent(gate.id) else { return true }
        return !gate.isProvisional(model)
    }

    static func record(id: String, kind: LocalStationKind, on date: Date? = nil,
                       at now: Date = .now) throws -> WidgetRecord {
        guard let item = StationItem.widgetItem(id: id), accepts(item, kind: kind), usable(item),
              let record = WidgetStationLoader.loadRecord(id: id,
                at: date.flatMap { shortcutDateInterval($0, in: timeZone(item))?.start } ?? now) else {
            throw ShortcutPlaceError(name: StationItem.widgetItem(id: id)?.name ?? id)
        }
        return record
    }

    @MainActor static func suggestions(kind: LocalStationKind) -> [StationItem] {
        let ids = context(defaults: AppGroup.defaults).ids
        var seen = Set<String>()
        let preferred = ids.compactMap { id -> StationItem? in
            guard seen.insert(id).inserted, let item = StationItem.widgetItem(id: id),
                  accepts(item, kind: kind) else { return nil }
            return item
        }
        return preferred + StationItem.all.filter { accepts($0, kind: kind) && seen.insert($0.id).inserted }
    }
}

struct ShortcutPlaceError: LocalizedError {
    let name: String
    var errorDescription: String? {
        String(localized: "Predictions for \(name) aren't available for this request. Open Slackwater to check this place.", comment: "Siri failure for an explicitly selected place with no usable saved prediction. Value is the place name.")
    }
}

struct TideShortcutPlace: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tide place"
    static let defaultQuery = TideShortcutPlaceQuery()
    let id: String
    let name: String
    let region: String
    init(_ item: StationItem) { id = item.id; name = item.name; region = item.region }
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)", subtitle: "\(region)") }
}

struct TideShortcutPlaceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [TideShortcutPlace] {
        identifiers.compactMap { StationItem.widgetItem(id: $0) }
            .filter { ShortcutPlaceQuery.accepts($0, kind: .tide) }.map(TideShortcutPlace.init)
    }
    func entities(matching string: String) async throws -> [TideShortcutPlace] {
        await ShortcutPlaceQuery.resolveMatches(string, kind: .tide).map(TideShortcutPlace.init)
    }
    func suggestedEntities() async throws -> [TideShortcutPlace] {
        await ShortcutPlaceQuery.suggestions(kind: .tide).map(TideShortcutPlace.init)
    }
}

struct CurrentShortcutPlace: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Current place"
    static let defaultQuery = CurrentShortcutPlaceQuery()
    let id: String
    let name: String
    let region: String
    init(_ item: StationItem) { id = item.id; name = item.name; region = item.region }
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)", subtitle: "\(region)") }
}

struct CurrentShortcutPlaceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CurrentShortcutPlace] {
        identifiers.compactMap { StationItem.widgetItem(id: $0) }
            .filter { ShortcutPlaceQuery.accepts($0, kind: .current) }.map(CurrentShortcutPlace.init)
    }
    func entities(matching string: String) async throws -> [CurrentShortcutPlace] {
        await ShortcutPlaceQuery.resolveMatches(string, kind: .current).map(CurrentShortcutPlace.init)
    }
    func suggestedEntities() async throws -> [CurrentShortcutPlace] {
        await ShortcutPlaceQuery.suggestions(kind: .current).map(CurrentShortcutPlace.init)
    }
}
