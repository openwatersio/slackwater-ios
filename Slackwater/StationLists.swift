// Slackwater — GPL v3. The station list's stores and its one dedupe rule,
// shared by the phone's list and the watch's (#521).
import Foundation
import WidgetKit

// MARK: - Recently viewed stations (prototype "Recent" list, Bryan's Recents)

/// Most-recent-first, capped at 6 (prototype addRecent slice(0,6)), persisted
/// in UserDefaults. Recorded by the detail views on appear.
final class RecentsStore: ObservableObject {
    static let shared = RecentsStore()
    private static let key = AppGroup.recentsKey

    @Published private(set) var ids: [String]

    /// Armed by the regular-width auto-selection (M52) with the id of exactly
    /// the detail it opens. The pane opening itself is not the user viewing a
    /// station, and counting it would evict a real entry from the 6-slot
    /// history on every single launch. Scoped to the id — an unfitted CHS
    /// station's waiting view records nothing at all, so a bare flag would
    /// survive it and swallow the next genuinely opened station (#3). Any
    /// record attempt disarms it.
    var skipNextRecordID: String?

    private init() {
        // UI-test hook, like -resetGate: a clean no-recents first run.
        if CommandLine.arguments.contains("-resetRecents") {
            AppGroup.defaults.removeObject(forKey: Self.key)
        }
        ids = AppGroup.defaults.stringArray(forKey: Self.key) ?? []
    }

    func record(_ id: String) {
        let skip = id == skipNextRecordID
        skipNextRecordID = nil
        if skip { return }
        var next = ids.filter { $0 != id }
        next.insert(id, at: 0)
        next = Array(next.prefix(6))
        ids = next
        AppGroup.defaults.set(next, forKey: Self.key)
    }

    /// Swipe "Remove" on a Recents row (current-detail spec §9: true deletion).
    func remove(_ id: String) {
        ids.removeAll { $0 == id }
        AppGroup.defaults.set(ids, forKey: Self.key)
    }

    var items: [StationItem] { ids.compactMap { StationItem.byId[$0] } }

    /// The most recently opened station, which is the best guess at where the
    /// user is when Core Location has told us nothing.
    var lastOpened: StationItem? { items.first }
}

// MARK: - Favorites (current-detail spec §9; prototype TidesApp savedIds)

/// Starred stations, in star order, persisted on the device and in iCloud (#134).
///
/// Storage only: `ids`, `contains`, `toggle`, `forget` and `replace` are what
/// they were before the cloud existed. The App Group copy stays this device's
/// own truth — it is what the widget reads (`WidgetStationLoader
/// .defaultStationID`) and what a device without iCloud falls back to — while
/// `FavoritesCloud` carries the same list between devices.
///
/// ponytail: RecentsStore keeps the same shape and stays device-local on
/// purpose. Recents are a record of what you did on *this* device; favourites
/// are the list you curated. Sync them if that ever stops being true.
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()
    private static let key = AppGroup.favoritesKey
    /// Set once this device's list has been written out as per-station cloud
    /// keys. Until then the cloud has never heard of these stars and must be
    /// merged with rather than adopted — adopting an empty cloud is exactly
    /// how an upgrading user loses the six gates they starred.
    private static let migratedKey = "slackwater.favorites.cloudMigrated"

    @Published private(set) var ids: [String]

    private init() {
        // UI-test hook, like -resetRecents: a clean no-favorites run.
        if CommandLine.arguments.contains("-resetFavorites") {
            AppGroup.defaults.removeObject(forKey: Self.key)
        }
        // UI-test hook: `-seedFavorites a,b` starts the run with exactly those
        // ids starred. The only way to exercise a favorite whose station has
        // left the bundle (issue #91) — by construction the app can't star one,
        // and the interesting state is a device that starred it releases ago.
        if let i = CommandLine.arguments.firstIndex(of: "-seedFavorites"),
           i + 1 < CommandLine.arguments.count {
            AppGroup.defaults.set(
                CommandLine.arguments[i + 1].split(separator: ",").map(String.init), forKey: Self.key)
        }
        ids = AppGroup.defaults.stringArray(forKey: Self.key) ?? []

        // Nil under both kinds of test, so those hooks stay device-local
        // (FavoritesCloud.store).
        guard let cloud = FavoritesCloud.store else { return }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] note in self?.cloudChanged(note, cloud) }
        cloud.synchronize()
        adopt(cloud)
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if let i = ids.firstIndex(of: id) {
            ids.remove(at: i)
            unstar(id)
            // Spec §9: unfavoriting re-files to Recents, never data loss.
            RecentsStore.shared.record(id)
        } else {
            ids.append(id)
            star(id)
        }
        persist()
        // A widget's default station is "first favorite" (WidgetStationLoader
        // .defaultStationID) — starring/unstarring can change what an
        // unconfigured widget shows, so its timeline must not wait for the
        // next half-hourly tick (H1).
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// True removal, for a station that has left the bundle (issue #91).
    /// Not `toggle`: that re-files to Recents (spec §9), and a station that no
    /// longer exists is the one thing Recents cannot show.
    func forget(_ id: String) {
        guard ids.contains(id) else { return }
        ids.removeAll { $0 == id }
        unstar(id)
        persist()
    }

    /// Swap a removed station for the replacement the user picked, in place —
    /// favorites render in the order they were starred, and the replacement
    /// inherits the dead one's slot rather than jumping to the end.
    func replace(_ old: String, with new: String) {
        guard let i = ids.firstIndex(of: old) else { return }
        ids.remove(at: i)
        let inserted = !ids.contains(new)
        if inserted { ids.insert(new, at: i) }
        // The replacement inherits the dead station's *stamp* as well as its
        // slot, or the next device to sync would sort it to the end.
        let stamp = FavoritesCloud.store?.double(forKey: FavoritesCloud.prefix + old) ?? 0
        unstar(old)
        if inserted { star(new, at: stamp > 0 ? stamp : nil) }
        persist()
    }

    // MARK: - iCloud (see FavoritesCloud)

    private func persist() { AppGroup.defaults.set(ids, forKey: Self.key) }

    private func star(_ id: String, at stamp: Double? = nil) {
        FavoritesCloud.store?.set(stamp ?? Date().timeIntervalSince1970,
                                  forKey: FavoritesCloud.prefix + id)
    }

    private func unstar(_ id: String) {
        FavoritesCloud.store?.removeObject(forKey: FavoritesCloud.prefix + id)
    }

    private func cloudChanged(_ note: Notification, _ cloud: NSUbiquitousKeyValueStore) {
        // Signing in or out of iCloud hands us a different store, usually an
        // empty one. Adopting that erases a list the user can still see on this
        // device, so treat the new account as never-migrated and let this
        // device's stars seed it instead.
        if note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            == NSUbiquitousKeyValueStoreAccountChange {
            AppGroup.defaults.set(false, forKey: Self.migratedKey)
        }
        adopt(cloud)
    }

    /// Reconcile with the cloud. Everything that can lose a star lives in
    /// `FavoritesCloud.reconcile`, which is a pure function; this is its I/O.
    private func adopt(_ cloud: NSUbiquitousKeyValueStore) {
        let migrated = AppGroup.defaults.bool(forKey: Self.migratedKey)
        let (next, writes) = FavoritesCloud.reconcile(
            local: ids,
            cloud: FavoritesCloud.stamps(cloud.dictionaryRepresentation),
            migrated: migrated,
            now: Date().timeIntervalSince1970)
        for (id, stamp) in writes { cloud.set(stamp, forKey: FavoritesCloud.prefix + id) }
        if !migrated { AppGroup.defaults.set(true, forKey: Self.migratedKey) }
        guard next != ids else { return }
        ids = next
        persist()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// The one dedupe rule: each station renders in at most one group —
/// My Location > Favorites > Near Me > Recents (Bryan's M4.5 order: Recents at
/// the very bottom is the floor — a station both nearby and recent shows under
/// Near Me; Recents holds only stations not already shown above). Persisted
/// stores are untouched; exclusion is render-time only, so a station reappears
/// when it stops being the hero / a favorite / nearby.
struct ListGroups {
    let favorites: [String]
    let nearMe: [String]
    let recents: [String]

    init(heroIds: [String], favoriteIds: [String], recentIds: [String],
         rankedIds: [String], nearCount: Int) {
        favorites = favoriteIds.filter { !heroIds.contains($0) }
        var shown = Set(favorites)
        shown.formUnion(heroIds)
        nearMe = Array(rankedIds.filter { !shown.contains($0) }.prefix(nearCount))
        shown.formUnion(nearMe)
        recents = recentIds.filter { !shown.contains($0) }
    }
}
