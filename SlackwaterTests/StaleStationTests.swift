// Slackwater — GPL v3. Stations that have left the bundle (issue #91).
//
// A favorite persists a bare id. Every other read resolves it through
// `StationItem.byId` and drops a miss, so before this the removal of a station
// was indistinguishable from the user never having starred it: no crash, no
// row, no explanation, and a dead id in UserDefaults forever.
import XCTest
@testable import Slackwater

final class StaleStationTests: XCTestCase {

    // MARK: - Tombstones

    /// The whole point of the file: an id that no longer resolves to a station
    /// still resolves to a name and a position.
    func testTombstonesNameStationsThatNoLongerShip() {
        XCTAssertGreaterThanOrEqual(StationTombstone.all.count, 28,
                                    "the 28 CHS withdrew are what this file exists for")
        for stone in StationTombstone.all {
            XCTAssertNil(StationItem.byId[stone.id],
                         "\(stone.id) is tombstoned and still shipping — one of the two is wrong")
            XCTAssertFalse(stone.name.isEmpty, "\(stone.id) has no name to render")
            XCTAssertFalse(stone.region.isEmpty, "\(stone.id) has no region line")
        }
    }

    /// Positions are what the replacement chooser measures from, so a default
    /// (0, 0) or a transposed pair would offer stations near null island.
    ///
    /// The box is northern-hemisphere WEST, not "Canada": IWLS publishes
    /// Greenland (Nuuk, Qaqortoq at -46.0, Thule) and US Great Lakes gauges
    /// (Ogdensburg NY, Peace Bridge Below at Buffalo), and three of them are
    /// tombstoned. A tighter bound fails on real data — it already did.
    func testTombstonePositionsAreNotDefaultsOrTransposed() {
        for stone in StationTombstone.all {
            XCTAssertTrue((40...85).contains(stone.latitude),
                          "\(stone.id) latitude \(stone.latitude) — transposed with longitude?")
            XCTAssertTrue((-142...(-40)).contains(stone.longitude),
                          "\(stone.id) longitude \(stone.longitude) — a default, or the wrong hemisphere?")
        }
    }

    func testAKnownWithdrawnFavoriteResolvesToItsTombstone() throws {
        let gone = try XCTUnwrap(StationTombstone.byId["chs-north-galiano"])
        XCTAssertEqual(gone.name, "North Galiano")
        XCTAssertNil(StationItem.byId[gone.id])
    }

    // MARK: - Favorites survive the removal

    func testReplaceKeepsTheDeadStationsSlot() {
        let store = FavoritesStore.shared
        let original = store.ids
        defer { restore(store, original) }

        restore(store, ["a", "chs-north-galiano", "b"])
        store.replace("chs-north-galiano", with: "c")
        XCTAssertEqual(store.ids, ["a", "c", "b"], "the replacement inherits the slot, not the end")

        // Replacing with something already starred must not duplicate it.
        restore(store, ["a", "chs-north-galiano", "b"])
        store.replace("chs-north-galiano", with: "b")
        XCTAssertEqual(store.ids, ["a", "b"])

        // Nothing to replace is a no-op, not a crash or an append.
        restore(store, ["a"])
        store.replace("missing", with: "c")
        XCTAssertEqual(store.ids, ["a"])
    }

    /// `forget` exists because `toggle` re-files to Recents (spec §9), and a
    /// station that no longer exists cannot render there either.
    func testForgetDoesNotReFileToRecents() {
        let store = FavoritesStore.shared
        let originalFavorites = store.ids
        defer { restore(store, originalFavorites) }

        restore(store, ["chs-north-galiano"])
        let recentsBefore = RecentsStore.shared.ids
        store.forget("chs-north-galiano")
        XCTAssertEqual(store.ids, [])
        XCTAssertEqual(RecentsStore.shared.ids, recentsBefore,
                       "forget must not park a dead id in Recents")
    }

    private func restore(_ store: FavoritesStore, _ ids: [String]) {
        for id in store.ids { store.forget(id) }
        for id in ids where !store.ids.contains(id) { store.toggle(id) }
    }

    // MARK: - Orphaned model files

    /// The launch scan iterates bundled candidates, never the directory, so
    /// without this a removed station's downloaded model is neither loaded nor
    /// deleted.
    func testOrphanFilesAreTheOnesNoBundledStationClaims() {
        let files: Set<String> = [
            "chs-victoria.json",            // a live port
            "chs-active-pass-current.json", // a live gate's fit
            "chs-active-pass-online.json",  // a live gate's fetched window
            "chs-north-galiano.json",       // withdrawn — orphan
            "chs-gone-current.json",        // no such gate — orphan
            "chs-gone-online.json",         // no such gate — orphan
            "notes.txt",                    // not ours, not ours to delete
        ]
        let orphans = ChsFitService.orphanFiles(
            in: files, ports: ["chs-victoria"], gates: ["chs-active-pass"])
        XCTAssertEqual(orphans,
                       ["chs-gone-current.json", "chs-gone-online.json", "chs-north-galiano.json"])
    }

    /// A gate id is not a port id: a `-current` file must be judged against the
    /// gate catalog, or every gate model on the device reads as an orphan.
    func testGateSuffixesAreCheckedAgainstTheGateCatalog() {
        let files: Set<String> = ["chs-active-pass-current.json", "chs-active-pass.json"]
        let orphans = ChsFitService.orphanFiles(in: files, ports: [], gates: ["chs-active-pass"])
        XCTAssertEqual(orphans, ["chs-active-pass.json"],
                       "the gate's fit stays; a port file for a gate-only id does not")
    }

    /// The real catalogs, so the sweep that actually runs at launch is known
    /// not to eat a live station's model.
    func testNothingBundledLooksLikeAnOrphan() {
        let ports = Set(ChsStationInfo.all.map(\.id))
        let gates = Set(ChsCurrentGateInfo.all.map(\.id))
        let files = Set(ports.map { "\($0).json" }
                        + gates.map { "\($0)-current.json" }
                        + gates.map { "\($0)-online.json" })
        XCTAssertEqual(ChsFitService.orphanFiles(in: files, ports: ports, gates: gates), [])
    }
}
