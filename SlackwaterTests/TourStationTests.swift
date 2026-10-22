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

    // No fix at all — a first launch before the location prompt is answered,
    // or location denied.
    func testFallsBackToFridayHarborWithNoFix() {
        XCTAssertEqual(tourStationID(near: nil), "noaa/9449880")
    }

    // Mid-Pacific: nothing bundled within range, so the fallback holds rather
    // than teaching on a station thousands of miles away.
    func testFallsBackWhenNothingIsInRange() {
        XCTAssertEqual(tourStationID(near: CLLocationCoordinate2D(latitude: 0, longitude: -150)),
                       "noaa/9449880")
    }

    // A link that replaces the tour's first station hands the tour on. The
    // replaced detail is still mounted for a moment, and a timeline revision
    // landing there must not claim the tour back (it would then finish it on
    // its way out, and the linked station would never teach).
    @MainActor func testAHandedOffTourIsClaimedOnlyByTheLinkedStation() {
        let coach = TourCoach()
        coach.replay()
        coach.begin(on: "noaa/9449880", starsAvailable: true, moonAvailable: true)
        XCTAssertEqual(coach.station, "noaa/9449880")

        coach.handOff(to: "noaa/9447130")
        XCTAssertNil(coach.step, "the replaced station's mark must go")
        coach.begin(on: "noaa/9449880", starsAvailable: true, moonAvailable: true)
        XCTAssertNil(coach.station, "the replaced station claimed the tour back")

        coach.begin(on: "noaa/9447130", starsAvailable: true, moonAvailable: true)
        XCTAssertEqual(coach.station, "noaa/9447130")
        XCTAssertEqual(coach.step, .read)
    }
}
