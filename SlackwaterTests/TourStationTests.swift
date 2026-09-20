// Slackwater — GPL v3. Which station the tour teaches on.
import XCTest
import CoreLocation
@testable import Slackwater

final class TourStationTests: XCTestCase {
    // Victoria BC: Canadian fix, but the nearby bundled NOAA stations need no
    // download, which is what lets the tour run during the CHS wait.
    func testPicksANearbyBundledStationForAVictoriaFix() {
        let id = tourStationID(near: CLLocationCoordinate2D(latitude: 48.42, longitude: -123.37))
        let picked = StationIndex.bundled.tides.first { $0.id == id }
        XCTAssertNotNil(picked, "the pick must name a bundled station")
        let d = CLLocation(latitude: picked!.latitude, longitude: picked!.longitude)
            .distance(from: CLLocation(latitude: 48.42, longitude: -123.37))
        XCTAssertLessThan(d, 60_000, "a Victoria fix should teach on local water")
    }

    // No fix at all — denied location, or the gate's search bypass.
    func testFallsBackToFridayHarborWithNoFix() {
        XCTAssertEqual(tourStationID(near: nil), "noaa/9449880")
    }

    // Mid-Pacific: nothing bundled within range, so the fallback holds rather
    // than teaching on a station thousands of miles away.
    func testFallsBackWhenNothingIsInRange() {
        XCTAssertEqual(tourStationID(near: CLLocationCoordinate2D(latitude: 0, longitude: -150)),
                       "noaa/9449880")
    }
}
