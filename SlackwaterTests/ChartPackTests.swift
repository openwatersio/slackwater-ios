// Slackwater — GPL v3. The chart-pack tier logic (offline-chart-packs spec
// §4): grid arithmetic and the desired-pack set. Pure functions only — the
// MLNOfflineStorage reconcile is exercised on-device, not here.
import XCTest
@testable import Slackwater

final class ChartPackTests: XCTestCase {

    // MARK: - Grid arithmetic

    func testTileMathMatchesKnownSlippyCoordinates() {
        // Deception Pass, the values the spike measured with.
        XCTAssertEqual(ChartGrid.tileX(lon: -122.643, z: 5), 5)
        XCTAssertEqual(ChartGrid.tileY(lat: 48.406, z: 5), 11)
        XCTAssertEqual(ChartGrid.tileX(lon: -122.643, z: 12), 652)
        XCTAssertEqual(ChartGrid.tileY(lat: 48.406, z: 12), 1416)
        // Edges clamp instead of indexing off the grid.
        XCTAssertEqual(ChartGrid.tileX(lon: 180, z: 5), 31)
        XCTAssertEqual(ChartGrid.tileY(lat: -90, z: 5), 31)
        XCTAssertEqual(ChartGrid.tileY(lat: 90, z: 5), 0)
    }

    func testCellBoundsInvertTileMath() {
        let b = ChartGrid.cellBounds(x: 5, y: 11, z: 5)
        // A point strictly inside the bounds maps back to the same cell.
        let midLat = (b.s + b.n) / 2, midLon = (b.w + b.e) / 2
        XCTAssertEqual(ChartGrid.tileX(lon: midLon, z: 5), 5)
        XCTAssertEqual(ChartGrid.tileY(lat: midLat, z: 5), 11)
        XCTAssertLessThan(b.s, b.n)
        XCTAssertLessThan(b.w, b.e)
    }

    func testNeighborhoodIsNineCellsAndWrapsTheAntimeridian() {
        let salish = ChartGrid.neighborhood(lat: 48.4, lon: -122.6, z: 5)
        XCTAssertEqual(salish.count, 9)
        XCTAssertTrue(salish.contains(ChartGrid.Cell(x: 5, y: 11, z: 5)))
        // A fix on the antimeridian wraps x rather than walking off the grid.
        let fiji = ChartGrid.neighborhood(lat: -17.5, lon: 179.9, z: 5)
        XCTAssertEqual(fiji.count, 9)
        XCTAssertTrue(fiji.contains { $0.x == 0 }, "x must wrap 31 → 0 across the antimeridian")
        // At the pole the clamped row collapses; the set just gets smaller.
        let arctic = ChartGrid.neighborhood(lat: 85.0, lon: 0, z: 5)
        XCTAssertLessThanOrEqual(arctic.count, 9)
        XCTAssertGreaterThanOrEqual(arctic.count, 6)
    }

    // MARK: - The desired-pack set (spec §4 table)

    func testTiersStackWithoutOverlappingZoomRanges() throws {
        let packs = desiredChartPacks(fix: (lat: 48.4, lon: -122.6),
                                      stations: [(id: "9447130", lat: 47.6, lon: -122.3)])
        let world = try XCTUnwrap(packs.first { $0.key == "world" })
        XCTAssertEqual(world.minZoom, 0)
        XCTAssertEqual(world.maxZoom, 4)
        for area in packs.filter({ $0.key.hasPrefix("area/") }) {
            XCTAssertEqual(area.minZoom, 5, "\(area.key) re-downloads the world tier's zooms")
            XCTAssertEqual(area.maxZoom, 8)
        }
        for station in packs.filter({ $0.key.hasPrefix("station/") }) {
            XCTAssertEqual(station.minZoom, 9, "\(station.key) re-downloads the area tier's zooms")
            XCTAssertEqual(station.maxZoom, 12)
        }
    }

    func testStarredStationKeepsItsAreaCellAliveWithoutAFix() {
        // No fix at all: the starred station still gets its area cell and its
        // detail pack — the boat sailed away, the chart stays.
        let packs = desiredChartPacks(fix: nil, stations: [(id: "x", lat: 48.406, lon: -122.643)])
        XCTAssertEqual(packs.filter { $0.key.hasPrefix("area/") }.count, 1)
        XCTAssertTrue(packs.contains { $0.key == "area/5/5/11" })
        XCTAssertTrue(packs.contains { $0.key == "station/x" })
        XCTAssertTrue(packs.contains { $0.key == "world" })
    }

    func testFixAloneMakesWorldPlusNineCellsAndNoStationPacks() {
        let packs = desiredChartPacks(fix: (lat: 48.4, lon: -122.6), stations: [])
        XCTAssertEqual(packs.filter { $0.key.hasPrefix("area/") }.count, 9)
        XCTAssertTrue(packs.filter { $0.key.hasPrefix("station/") }.isEmpty)
        XCTAssertEqual(packs.count, 10)
    }

    func testTwoStationsInOneCellShareTheAreaPack() {
        // Deception Pass and Seattle sit in the same z5 cell.
        let packs = desiredChartPacks(fix: nil,
                                      stations: [(id: "a", lat: 48.406, lon: -122.643),
                                                 (id: "b", lat: 47.6, lon: -122.3)])
        XCTAssertEqual(packs.filter { $0.key.hasPrefix("area/") }.count, 1)
        XCTAssertEqual(packs.filter { $0.key.hasPrefix("station/") }.count, 2)
    }

    func testStationBoxIsTwentyKilometresAndInsideMercator() throws {
        let packs = desiredChartPacks(fix: nil, stations: [(id: "x", lat: 48.406, lon: -122.643)])
        let box = try XCTUnwrap(packs.first { $0.key == "station/x" })
        // ±20 km of latitude is ±0.18°; longitude widens with latitude.
        XCTAssertEqual(box.north - box.south, 2 * 20.0 / 111.0, accuracy: 0.01)
        XCTAssertGreaterThan(box.east - box.west, box.north - box.south,
                             "the box must widen its longitude at 48°N, not ship a squashed disc")
        // A polar station must clamp, not hand Mercator an impossible bound.
        let polar = desiredChartPacks(fix: nil, stations: [(id: "p", lat: 85.0, lon: 0)])
        let pbox = try XCTUnwrap(polar.first { $0.key == "station/p" })
        XCTAssertLessThanOrEqual(pbox.north, ChartGrid.maxLat)
    }
}
