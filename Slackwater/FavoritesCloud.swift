// Slackwater — GPL v3. Favourites follow the user between devices (#134):
// iCloud key-value storage, one key per starred station.
import Foundation

/// Cross-device favourites.
///
/// **One key per starred station** — `slackwater.fav.<id>` holding the stamp it
/// was starred, never one key holding the whole array. KVS resolves conflicts
/// last-writer-wins *per key* with no merge hook: it hands you the changed key
/// names and a reason code, you read the winning value, and you never see the
/// side that lost. The list under a single key therefore makes every edit on
/// one device conflict with every edit on the other and demands hand-written
/// union code. Split per station the problem dissolves: star Dodd on the phone
/// and Porlier on the iPad and both survive untouched; order falls out of the
/// stamps (a *global* star order, better than the per-device insertion order it
/// replaces); and the only real conflict left — star vs. unstar of the same
/// station at once — is exactly what per-key LWW resolves the way a human
/// expects. The 1024-key ceiling is not a favourites problem.
///
/// CloudKit would buy real 3-way merge against a common ancestor, at the cost
/// of a whole persistence stack, for a conflict this key layout doesn't have.
enum FavoritesCloud {
    static let prefix = "slackwater.fav."

    /// Nil under test. The `-resetFavorites` / `-seedFavorites` UI-test hooks
    /// and the unit-test host must never read or write a real iCloud store:
    /// the simulator's KVS outlives the run, so one seeded test would leak its
    /// stars into the next one's "clean" launch.
    static let store: NSUbiquitousKeyValueStore? = {
        let args = CommandLine.arguments
        // -noCloudSync is on every UI-test launch; the two favourites hooks are
        // belt and braces for a launch that sets launchArguments directly.
        if args.contains("-noCloudSync") { return nil }
        if args.contains("-resetFavorites") || args.contains("-seedFavorites") { return nil }
        if NSClassFromString("XCTestCase") != nil { return nil }
        return .default
    }()

    /// The starred ids and their stamps, out of `dictionaryRepresentation`.
    /// Takes the dictionary rather than the store so it is testable without
    /// iCloud.
    static func stamps(_ raw: [String: Any]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (key, value) in raw where key.hasPrefix(prefix) {
            guard let stamp = (value as? NSNumber)?.doubleValue else { continue }
            out[String(key.dropFirst(prefix.count))] = stamp
        }
        return out
    }

    /// Render order: oldest star first, so the list reads the way today's
    /// per-device insertion order does. Ties break on id — equal stamps are
    /// possible (a seeded upgrade, a restored backup) and an unstable sort
    /// would reshuffle the list on every launch.
    static func order(_ stamps: [String: Double]) -> [String] {
        stamps.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }.map(\.key)
    }

    /// The whole reconcile as a value, so the path that can lose a user's
    /// stars is testable without an iCloud account: what the list becomes, and
    /// what this device still owes the cloud.
    ///
    /// Once migrated the cloud's key set *is* the list — an unstar on the other
    /// device arrives as a missing key, and there is no other way to see it.
    /// The cost is that an emptied store empties this device too; the guard is
    /// the account-change path in `FavoritesStore`, which re-seeds rather than
    /// adopts when iCloud hands us a different (usually empty) store.
    static func reconcile(local: [String], cloud: [String: Double],
                          migrated: Bool, now: Double) -> (ids: [String], writes: [String: Double]) {
        guard !migrated else { return (order(cloud), [:]) }
        let writes = seed(local: local, cloud: cloud, now: now)
        return (order(cloud.merging(writes) { mine, _ in mine }), writes)
    }

    /// The one-time upgrade: stars this device made before it had a cloud copy.
    /// They keep their local order and land *after* everything already in the
    /// cloud, so whichever device upgrades second appends rather than
    /// interleaving into a history it never saw. Ids the cloud already knows
    /// are left alone — re-stamping them would drag another device's older
    /// star to the end of the list.
    static func seed(local: [String], cloud: [String: Double], now: Double) -> [String: Double] {
        var stamp = max(now, (cloud.values.max() ?? 0) + 1)
        var out: [String: Double] = [:]
        for id in local where cloud[id] == nil && out[id] == nil {
            out[id] = stamp
            stamp += 1
        }
        return out
    }
}
