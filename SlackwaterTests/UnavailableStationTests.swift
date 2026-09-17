import XCTest
@testable import Slackwater

/// Stations we know about and may never serve (issue #401). The generator's
/// own invariants are asserted on the artefact in `tools/gen-tides.test.mjs`;
/// these are the two things only the app can check — that the bundle decodes,
/// and that the rings and the real pins cannot be confused for each other.
final class UnavailableStationTests: XCTestCase {
    /// `bundled` is a `preconditionFailure` on a missing or undecodable file,
    /// so this crashes rather than fails if the resource ever falls out of the
    /// target. That is the intended behaviour — it is the same contract every
    /// other catalog has — and the test is here to make it crash in CI rather
    /// than on someone's first launch.
    func testTheBundleDecodes() {
        XCTAssertFalse(UnavailableStation.all.isEmpty)
        XCTAssertEqual(UnavailableStation.all.count, UnavailableStation.byId.count,
                       "duplicate id in unavailable-stations.json")
    }

    /// The tap routing's whole premise: `handleTap` asks `StationItem.byId`
    /// first and only falls through to `UnavailableStation.byId`. An id in
    /// both would be a ring that can never be reached — or, worse, a station
    /// whose card the user opens expecting tides.
    func testNoUnavailableStationSharesAnIdWithARealOne() {
        let live = Set(StationItem.all.map(\.id))
        let collisions = UnavailableStation.all.map(\.id).filter(live.contains)
        XCTAssertEqual(collisions, [])
    }

    /// The other direction of the same confusion: a tombstone for a station
    /// that HAS shipped and stopped is `StationTombstone`, and it says
    /// something different ("withdrawn" rather than "we have no right to it").
    func testNoUnavailableStationIsAlsoATombstone() {
        let removed = Set(StationTombstone.all.map(\.id))
        XCTAssertEqual(UnavailableStation.all.map(\.id).filter(removed.contains), [])
    }

    /// Every field the card interpolates, on every row — the card builds one
    /// sentence out of `source` and `license`, and a blank either side of it
    /// renders as a dangling " publishes it under ".
    func testEveryRowCanFillItsCard() {
        for station in UnavailableStation.all {
            XCTAssertFalse(station.name.isEmpty, station.id)
            XCTAssertFalse(station.region.isEmpty, station.id)
            XCTAssertFalse(station.license.isEmpty, station.id)
            XCTAssertFalse(station.source.isEmpty, station.id)
            XCTAssertTrue((-90...90).contains(station.latitude), station.id)
            XCTAssertTrue((-180...180).contains(station.longitude), station.id)
        }
    }

    /// Issue #401's own example: the nearest station Slackwater may ship to
    /// Gijon is Santander, 154 km east, which is why that stretch of the Bay
    /// of Biscay reads as broken rather than as unlicensed.
    func testGijonIsTombstoned() throws {
        let gijon = try XCTUnwrap(UnavailableStation.all.first { $0.name == "Gijon" })
        XCTAssertEqual(gijon.region, "Asturias")
        XCTAssertEqual(gijon.license, "cc-by-nc-4.0")
        let nearest = try XCTUnwrap(StationItem.nearest(.tide, toLat: gijon.latitude,
                                                        lon: gijon.longitude))
        XCTAssertGreaterThan(nearest.km, 50)
    }
}
