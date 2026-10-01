// Slackwater — GPL v3. What a watch-only wearer sees in the list (#521).
import XCTest
@testable import Slackwater

final class BrowseGroupsTests: XCTestCase {
    private let victoria = (lat: 48.4284, lon: -123.3656)

    private func isCanadian(_ item: StationItem) -> Bool {
        switch item {
        case .chs, .chsGate, .chsCurrent: true
        case .tide, .current: false
        }
    }

    private var anyCanadianID: String {
        get throws { try XCTUnwrap(StationItem.all.first(where: isCanadian)).id }
    }

    func testNoFixShowsNoLocationGroups() {
        let g = BrowseGroups(fix: nil, favoriteIds: [TideStationRecord.fridayHarborID],
                             recentIds: ["current:PUG1515"], fitted: [])
        XCTAssertTrue(g.hero.isEmpty)
        XCTAssertTrue(g.nearby.isEmpty)
        XCTAssertEqual(g.favorites, [TideStationRecord.fridayHarborID])
    }

    /// Location off still gets places, ranked around the fallback anchor, but
    /// never a My Location card claiming the wearer is there.
    func testNoFixRanksNearbyAroundTheFallback() throws {
        let harbor = try XCTUnwrap(StationItem.byId[TideStationRecord.fridayHarborID])
        let g = BrowseGroups(fix: nil, fallback: (harbor.latitude, harbor.longitude),
                             favoriteIds: [], recentIds: [], fitted: [])
        XCTAssertTrue(g.hero.isEmpty)
        XCTAssertEqual(g.nearby.count, 4)
        XCTAssertEqual(g.nearby.first?.id, harbor.id)
    }

    func testVictoriaFixOffersNoUnfittedCanadianStation() {
        let g = BrowseGroups(fix: victoria, favoriteIds: [], recentIds: [], fitted: [])
        XCTAssertFalse(g.hero.isEmpty)
        XCTAssertEqual(g.nearby.count, 4)
        XCTAssertFalse((g.hero + g.nearby).contains(where: isCanadian))
    }

    func testAFittedCanadianPortCanBeNearby() throws {
        let port = try XCTUnwrap(StationItem.all.first {
            if case .chs = $0 { $0.name == "Victoria" } else { false }
        })
        let g = BrowseGroups(fix: (port.latitude, port.longitude),
                             favoriteIds: [], recentIds: [], fitted: [port.id])
        XCTAssertEqual(g.hero.first?.id, port.id)
    }

    func testUnfittedCanadianFavoriteIsHiddenNotRemoved() throws {
        let id = try anyCanadianID
        let g = BrowseGroups(fix: nil, favoriteIds: [id, TideStationRecord.fridayHarborID],
                             recentIds: [], fitted: [])
        // Hidden, and not handed to the "Place removed" row either.
        XCTAssertEqual(g.favorites, [TideStationRecord.fridayHarborID])
    }

    func testFavoriteMissingFromTheBundleKeepsItsRow() {
        let g = BrowseGroups(fix: nil, favoriteIds: ["noaa/0000000"], recentIds: [], fitted: [])
        XCTAssertEqual(g.favorites, ["noaa/0000000"])
    }

    func testRecentsDropHiddenAndMissingPlaces() throws {
        let id = try anyCanadianID
        let g = BrowseGroups(fix: nil,
                             favoriteIds: [],
                             recentIds: [id, "noaa/0000000", TideStationRecord.fridayHarborID],
                             fitted: [])
        XCTAssertEqual(g.recents.map(\.id), [TideStationRecord.fridayHarborID])
    }

    func testAFavoriteThatIsMyLocationShowsOnce() throws {
        let hero = try XCTUnwrap(
            BrowseGroups(fix: victoria, favoriteIds: [], recentIds: [], fitted: []).hero.first)
        let g = BrowseGroups(fix: victoria, favoriteIds: [hero.id], recentIds: [hero.id], fitted: [])
        XCTAssertEqual(g.hero.first?.id, hero.id)
        XCTAssertFalse(g.favorites.contains(hero.id))
        XCTAssertFalse(g.recents.contains { $0.id == hero.id })
    }

    /// Point Wilson has three current stations by one name; the phone shows
    /// the nearest one (`StationGroups`), and so does the watch.
    func testNamesakesShowOnce() {
        let g = BrowseGroups(fix: (48.1501, -122.7454), favoriteIds: [], recentIds: [], fitted: [])
        let places = (g.hero + g.nearby).map(\.placeKey)
        XCTAssertEqual(places.count, Set(places).count, "\(places)")
    }

    func testSearchHidesUnfittedCanadianPlaces() throws {
        let port = try XCTUnwrap(StationItem.all.first {
            if case .chs = $0 { $0.name == "Victoria" } else { false }
        })
        XCTAssertFalse(StationItem.searchResolvable("victoria", near: victoria, fitted: [])
            .contains { $0.id == port.id })
        XCTAssertTrue(StationItem.searchResolvable("victoria", near: victoria, fitted: [port.id])
            .contains { $0.id == port.id })
    }
}
