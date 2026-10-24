// Slackwater — GPL v3. Which station the tour teaches on.
import XCTest
import CoreLocation
@testable import Slackwater

final class TourStationTests: XCTestCase {
    func testPicksNanaimoRatherThanAFartherBundledStation() {
        XCTAssertEqual(tourStationID(near: CLLocationCoordinate2D(latitude: 49.1659, longitude: -123.9401)),
                       "chs-nanaimo-harbour")
    }

    func testPicksVictoriaForAVictoriaFix() {
        XCTAssertEqual(tourStationID(near: CLLocationCoordinate2D(latitude: 48.42, longitude: -123.37)),
                       "chs-victoria")
    }

    func testPicksSeattleForASeattleFix() {
        XCTAssertEqual(tourStationID(near: CLLocationCoordinate2D(latitude: 47.60, longitude: -122.34)),
                       "noaa/9447130")
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

    @MainActor func testALinkReservesTheTourBeforeCanadianPredictionsArrive() {
        let coach = TourCoach()
        coach.replay()
        coach.handOff(to: "noaa/9447130")
        coach.begin(on: "chs-nanaimo-harbour", starsAvailable: true, moonAvailable: true)
        XCTAssertNil(coach.step, "late predictions must not claim a tour handed to a link")
        coach.begin(on: "noaa/9447130", starsAvailable: true, moonAvailable: true)
        XCTAssertEqual(coach.station, "noaa/9447130")
        XCTAssertEqual(coach.step, .read)
    }
}
