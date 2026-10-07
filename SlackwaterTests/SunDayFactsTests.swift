import Almanac
import XCTest
@testable import Slackwater

final class SunDayFactsTests: XCTestCase {
    func testLocalDayAndEventOrder() throws {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let sea = try SunDayFacts(at: date, tz: tz, latitude: 48.5, longitude: -123)
            XCTAssertEqual(sea.interval.duration, Double(hours * 3600))
            XCTAssertEqual(sea.events.count, 9)
            XCTAssertTrue(sea.events.allSatisfy { calendar.isDate($0.time, inSameDayAs: date) })
            XCTAssertEqual(sea.orderedKinds, [.astroDawn, .nauticalDawn, .civilDawn, .rise, .transit,
                                              .set, .civilDusk, .nauticalDusk, .astroDusk])
            XCTAssertEqual(try XCTUnwrap(sea.daylight),
                           try XCTUnwrap(sea.time(.set)).timeIntervalSince(XCTUnwrap(sea.time(.rise))))
        }
    }

    func testPolarEventsAndInvalidCoordinates() throws {
        let date = ISO8601DateFormatter().date(from: "2026-06-21T00:00:00Z")!
        let facts = try SunDayFacts(at: date, tz: .gmt, latitude: 80, longitude: 0)
        XCTAssertNil(facts.time(.rise))
        XCTAssertNil(facts.time(.set))
        XCTAssertNil(facts.daylight)
        XCTAssertNotNil(facts.time(.transit))
        XCTAssertEqual(facts.orderedKinds.first, .transit)
        XCTAssertThrowsError(try SunDayFacts(at: date, tz: .gmt, latitude: 100, longitude: -123))
    }
}
