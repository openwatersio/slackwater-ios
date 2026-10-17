// Slackwater — GPL v3. Where a saved station id goes once its station leaves the bundle.
import Foundation

/// Resources/station-successors.json (tools/gen-slugs.mjs): a `StationItem` id
/// that no longer ships → the bundled id the station database publishes as the
/// same station, such as a gauge whose record moved to another publisher.
///
/// Favorites, recents, alert rules and widget configurations all persist a
/// bare id, so without this a release that swaps one record of a gauge for
/// another strands everything saved under the old id. The stores move their
/// ids along it when they load, and the widget and deep-link lookups resolve
/// through it, because a widget's configuration belongs to the system and
/// cannot be rewritten. An id with no successor has a tombstone instead
/// (`StationTombstone`).
///
/// The generator follows chains and keeps entries across releases, so one
/// lookup is the whole resolution, and applying it twice changes nothing.
enum StationSuccessors {
    static let bundled: [String: String] = {
        guard let url = Bundle.main.url(forResource: "station-successors", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            // Every target bundles the file (project.yml, PortableSources). An
            // empty map moves nothing, which is today's behavior, so a release
            // build degrades rather than crashing.
            assertionFailure("station-successors.json is missing or unreadable")
            return [:]
        }
        return map
    }()

    /// The id to use now for one a device saved.
    static func resolve(_ id: String, in map: [String: String] = bundled) -> String {
        map[id] ?? id
    }

    /// A saved list with each id moved to its successor, in its order, each id
    /// once: two departed ids can share a successor, and a successor can
    /// already be in the list.
    static func remap(_ ids: [String], in map: [String: String] = bundled) -> [String] {
        var seen = Set<String>()
        return ids.map { resolve($0, in: map) }.filter { seen.insert($0).inserted }
    }
}
