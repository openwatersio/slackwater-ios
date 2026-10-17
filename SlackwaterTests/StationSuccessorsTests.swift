// Slackwater — GPL v3. Saved station ids follow their station when a release
// swaps the record a gauge ships as (station-successors.json).
//
// Every test uses a fixture map: an old id that no longer ships moving to a
// station that does. The bundled map is only as full as the data history.
import XCTest
@testable import Slackwater

@MainActor final class StationSuccessorsTests: XCTestCase {
    /// Two retired records of real bundled stations: Wellington moving to
    /// Friday Harbor stands in for a TICON record replaced by LINZ's.
    private let old = "ticon/retired-fixture"
    private let otherOld = "ticon/retired-twin-fixture"
    private let new = TideStationRecord.fridayHarborID
    private var map: [String: String] { [old: new, otherOld: new] }

    // MARK: - The map itself

    func testResolveMovesOnlyADepartedID() {
        XCTAssertEqual(StationSuccessors.resolve(old, in: map), new)
        XCTAssertEqual(StationSuccessors.resolve("noaa/9447130", in: map), "noaa/9447130")
    }

    func testRemapKeepsOrderAndNamesEachStationOnce() {
        XCTAssertEqual(StationSuccessors.remap(["a", old, "b", otherOld, new], in: map), ["a", new, "b"])
        let once = StationSuccessors.remap(["a", old, "b"], in: map)
        XCTAssertEqual(StationSuccessors.remap(once, in: map), once, "running twice changes nothing")
    }

    func testTheBundledMapOnlyNamesStationsThatShipOrAreTombstoned() {
        for (from, to) in StationSuccessors.bundled {
            XCTAssertNil(StationItem.byId[from], "\(from) still ships")
            XCTAssertTrue(StationItem.byId[to] != nil || StationTombstone.byId[to] != nil, "\(from) → \(to), which is nowhere")
        }
    }

    // MARK: - Favorites

    func testFavoritesMoveInPlace() {
        let store = FavoritesStore.shared
        let original = store.ids
        defer { restore(store, original) }

        restore(store, ["chs-victoria", old, "noaa/9447130"])
        store.migrate(map)
        XCTAssertEqual(store.ids, ["chs-victoria", new, "noaa/9447130"], "the successor keeps the slot")
        XCTAssertEqual(AppGroup.defaults.stringArray(forKey: AppGroup.favoritesKey), store.ids, "persisted")

        store.migrate(map)
        XCTAssertEqual(store.ids, ["chs-victoria", new, "noaa/9447130"], "running twice changes nothing")
    }

    func testAFavoriteAlreadyStarredUnderItsSuccessorIsNotDuplicated() {
        let store = FavoritesStore.shared
        let original = store.ids
        defer { restore(store, original) }

        restore(store, [new, old, otherOld])
        store.migrate(map)
        XCTAssertEqual(store.ids, [new])
    }

    /// Another device, still on an older build, can star the old id after this
    /// one migrated. The cloud copy moves too, with the old star's stamp so the
    /// station keeps its place in the global order.
    func testCloudStarsMoveWithTheirStamp() {
        let moved = FavoritesCloud.migrate(["noaa/9447130": 1, old: 2, "chs-victoria": 3], successors: map)
        XCTAssertEqual(moved.stamps, ["noaa/9447130": 1, new: 2, "chs-victoria": 3])
        XCTAssertEqual(moved.writes, [new: 2])
        XCTAssertEqual(moved.removals, [old])
        XCTAssertEqual(FavoritesCloud.order(moved.stamps), ["noaa/9447130", new, "chs-victoria"])
    }

    func testCloudKeepsTheEarlierStarWhenBothIDsAreStarred() {
        let moved = FavoritesCloud.migrate([new: 5, old: 2, otherOld: 9], successors: map)
        XCTAssertEqual(moved.stamps, [new: 2])
        XCTAssertEqual(moved.writes, [new: 2])
        XCTAssertEqual(Set(moved.removals), [old, otherOld])
        let again = FavoritesCloud.migrate(moved.stamps, successors: map)
        XCTAssertEqual(again.stamps, moved.stamps)
        XCTAssertTrue(again.writes.isEmpty && again.removals.isEmpty, "running twice changes nothing")
    }

    /// The first-upgrade merge: this device's migrated list seeds a cloud that
    /// another device migrated too, and the station appears once.
    func testMigratedCloudMergesWithMigratedLocalStars() {
        let cloud = FavoritesCloud.migrate([old: 10], successors: map).stamps
        let local = StationSuccessors.remap([old, "chs-victoria"], in: map)
        let merged = FavoritesCloud.reconcile(local: local, cloud: cloud, migrated: false, now: 100)
        XCTAssertEqual(merged.ids, [new, "chs-victoria"])
        XCTAssertNil(merged.writes[new], "the cloud already has it")
    }

    // MARK: - Recents

    func testRecentsMove() {
        let store = RecentsStore.shared
        let original = store.ids
        defer { setRecents(original) }

        setRecents([old, "noaa/9447130", new])
        store.migrate(map)
        XCTAssertEqual(store.ids, [new, "noaa/9447130"])
        XCTAssertEqual(AppGroup.defaults.stringArray(forKey: AppGroup.recentsKey), store.ids)
        store.migrate(map)
        XCTAssertEqual(store.ids, [new, "noaa/9447130"])
    }

    // MARK: - Alerts

    func testAlertRulesMoveSoTheyKeepScheduling() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let rule = AlertRule(stationID: old, trigger: .tideExtreme(high: true))
        let untouched = AlertRule(stationID: "current:noaa/PUG1701", trigger: .slackWindowOpens)
        AlertRuleStore(defaults: defaults, successors: [:]).upsert(rule)
        AlertRuleStore(defaults: defaults, successors: [:]).upsert(untouched)

        let store = AlertRuleStore(defaults: defaults, successors: map)
        XCTAssertEqual(store.rules.map(\.stationID), [new, "current:noaa/PUG1701"])
        XCTAssertEqual(store.rules.map(\.id), [rule.id, untouched.id], "the same rules, not new ones")
        XCTAssertNotNil(WidgetStationLoader.loadRecord(id: store.rules[0].stationID), "schedulable again")

        let reread = AlertRuleStore(defaults: defaults, successors: [:])
        XCTAssertEqual(reread.rules, store.rules, "the move is persisted")
        XCTAssertEqual(AlertRuleStore(defaults: defaults, successors: map).rules, store.rules,
                       "running twice changes nothing")
    }

    // MARK: - Widgets, the watch, and deep links

    /// A widget's configured station is the system's to store, so it is
    /// resolved on read rather than rewritten.
    func testAWidgetConfiguredWithAnOldIDShowsItsSuccessor() throws {
        XCTAssertEqual(StationItem.widgetItem(id: old, successors: map)?.id, new)
        let record = try XCTUnwrap(WidgetStationLoader.loadRecord(id: old, successors: map))
        guard case .tide(let tide, _) = record else { return XCTFail("Expected tide") }
        XCTAssertEqual(tide.id, new)
        XCTAssertEqual(WidgetStationLoader.configured(old, successors: map).id, new,
                       "the entry carries the id the favorite check compares against")
    }

    func testAStationDeepLinkWithAnOldIDOpensItsSuccessor() throws {
        let url = try XCTUnwrap(URL(string: "slackwater://station/\(old)"))
        XCTAssertEqual(stationID(from: url, successors: map), new)
        XCTAssertEqual(stationID(from: url, successors: [:]), old)
    }

    // MARK: - Tombstones

    func testStationTombstonesJoinTheCHSOnes() {
        let ids = Set(StationTombstone.all.map(\.id))
        XCTAssertEqual(ids.count, StationTombstone.all.count, "no id is tombstoned twice")
        XCTAssertTrue(ids.isSuperset(of: StationTombstone.stations.map(\.id)))
    }

    /// The withdrawal copy is a statement about CHS. Any other station left
    /// because Slackwater stopped carrying it, and says so.
    func testOnlyACHSTombstoneClaimsAWithdrawal() throws {
        let chs = try XCTUnwrap(StationTombstone.byId["chs-north-galiano"])
        let other = StationTombstone(id: "ticon/sumner-fixture", name: "Sumner", region: "Canterbury",
                                     latitude: -43.57, longitude: 172.76)
        for favorite in [true, false] {
            XCTAssertTrue(RemovedStationCopy(id: chs.id, tombstone: chs, isFavorite: favorite)
                .expectation.contains("hydrographic"))
            let copy = RemovedStationCopy(id: other.id, tombstone: other, isFavorite: favorite)
            XCTAssertFalse(copy.expectation.contains("hydrographic"))
            XCTAssertFalse(copy.headline.contains("published"))
            XCTAssertEqual(copy.title, "Sumner")
        }
        let unknown = RemovedStationCopy(id: "ticon/unknown", tombstone: nil, isFavorite: true)
        XCTAssertFalse(unknown.expectation.contains("hydrographic"), "no tombstone, no claim about why")
    }

    /// "Choose another station" ranks from where the removed station was.
    func testTheChooserRanksFromTheTombstone() {
        let other = StationTombstone(id: "ticon/sumner-fixture", name: "Sumner", region: "Canterbury",
                                     latitude: -43.57, longitude: 172.76)
        let copy = RemovedStationCopy(id: other.id, tombstone: other, isFavorite: true)
        let origin = copy.origin(fallback: (lat: 48.5, lon: -123))
        XCTAssertEqual(origin.lat, -43.57)
        XCTAssertEqual(origin.lon, 172.76)
        let unknown = RemovedStationCopy(id: "x", tombstone: nil, isFavorite: true)
        XCTAssertEqual(unknown.origin(fallback: (lat: 48.5, lon: -123)).lat, 48.5)
    }

    private func setRecents(_ ids: [String]) {
        let store = RecentsStore.shared
        store.skipNextRecordID = nil
        for id in store.ids { store.remove(id) }
        for id in ids.reversed() { store.record(id) }
    }

    private func restore(_ store: FavoritesStore, _ ids: [String]) {
        for id in store.ids { store.forget(id) }
        for id in ids where !store.ids.contains(id) { store.toggle(id) }
    }
}
