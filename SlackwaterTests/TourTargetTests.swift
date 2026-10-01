// Slackwater — GPL v3. The tour's two scrub targets, read off the timeline's
// own rise and set times rather than searched for.
import XCTest
@testable import Slackwater

final class TourTargetTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_758_000_000)  // arbitrary fixed epoch
    private func h(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }

    private func day(_ offset: Int, sunrise: Double?, sunset: Double?,
                     moonrise: Double?, moonset: Double?) -> TimelineDay {
        TimelineDay(offset: offset, start: h(Double(offset) * 24),
                    sunrise: sunrise.map(h), sunset: sunset.map(h),
                    moonrise: moonrise.map(h), moonset: moonset.map(h))
    }

    // Stars: the next sunset after now, plus an hour for real darkness.
    func testStarsTimeIsAnHourAfterTheNextSunset() {
        let days = [day(0, sunrise: 6, sunset: 20, moonrise: 22, moonset: 30)]
        XCTAssertEqual(tourStarsTime(days: days, after: h(12)), h(21))
    }

    func testStarsTimeIgnoresASunsetAlreadyPast() {
        let days = [day(0, sunrise: 6, sunset: 20, moonrise: 22, moonset: 30),
                    day(1, sunrise: 30, sunset: 44, moonrise: 46, moonset: 54)]
        XCTAssertEqual(tourStarsTime(days: days, after: h(21)), h(45))
    }

    // Midnight sun: no sunset in the window at all.
    func testStarsTimeIsNilWhenTheSunNeverSets() {
        let days = [day(0, sunrise: 6, sunset: nil, moonrise: 22, moonset: 30),
                    day(1, sunrise: nil, sunset: nil, moonrise: nil, moonset: nil)]
        XCTAssertNil(tourStarsTime(days: days, after: h(12)))
    }

    // Moon: the midpoint of the first overlap between the moon being up and
    // the sun being down.
    func testMoonTimeIsTheMidpointOfTheFirstDarkMoonSpan() {
        // dark 20→30, moon up 22→30 ⇒ overlap 22→30, midpoint 26.
        let days = [day(0, sunrise: 6, sunset: 20, moonrise: 22, moonset: 30),
                    day(1, sunrise: 30, sunset: 44, moonrise: 46, moonset: 54)]
        XCTAssertEqual(tourMoonTime(days: days, after: h(12)), h(26))
    }

    // A moon only ever up in daylight has no dark span on that day; the
    // search continues into the next one rather than giving up.
    func testMoonTimeSkipsADaytimeOnlyMoon() {
        // day 0: moon up 8→16, all inside daylight 6→20 ⇒ no overlap.
        // day 1: dark 44→54, moon up 46→52 ⇒ overlap 46→52, midpoint 49.
        let days = [day(0, sunrise: 6, sunset: 20, moonrise: 8, moonset: 16),
                    day(1, sunrise: 30, sunset: 44, moonrise: 46, moonset: 52),
                    day(2, sunrise: 54, sunset: 68, moonrise: nil, moonset: nil)]
        XCTAssertEqual(tourMoonTime(days: days, after: h(12)), h(49))
    }

    func testMoonTimeIsNilWhenTheSunNeverSets() {
        let days = [day(0, sunrise: 6, sunset: nil, moonrise: 8, moonset: 16)]
        XCTAssertNil(tourMoonTime(days: days, after: h(12)))
    }

    func testMoonTimeReturnsTheEarlierOfTwoOverlaps() {
        // Two valid dark-moon overlaps in the window, both after now.
        // day 0: dark 18→30, moon up 8→22 ⇒ overlap 18→22, midpoint 20.
        // day 1: dark 44→54, moon up 32→50 ⇒ overlap 44→50, midpoint 47.
        let days = [day(0, sunrise: 6, sunset: 18, moonrise: 8, moonset: 22),
                    day(1, sunrise: 30, sunset: 44, moonrise: 32, moonset: 50),
                    day(2, sunrise: 54, sunset: 68, moonrise: 70, moonset: 78)]
        XCTAssertEqual(tourMoonTime(days: days, after: h(12)), h(20))
    }
}
