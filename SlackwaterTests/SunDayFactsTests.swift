import Almanac
import XCTest
@testable import Slackwater

final class SunDayFactsTests: XCTestCase {
    func testLocalDayAndEyeHeight() throws {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let sea = try SunDayFacts(at: date, tz: tz, latitude: 48.5, longitude: -123, eyeHeight: 0)
            let deck = try SunDayFacts(at: date, tz: tz, latitude: 48.5, longitude: -123, eyeHeight: 10)
            XCTAssertEqual(sea.interval.duration, Double(hours * 3600))
            XCTAssertEqual(sea.events.count, 9)
            XCTAssertTrue(sea.events.allSatisfy { calendar.isDate($0.time, inSameDayAs: date) })
            XCTAssertEqual(sea.dip, 0)
            XCTAssertLessThan(deck.dip, 0)
            XCTAssertLessThan(try XCTUnwrap(deck.time(.rise)), try XCTUnwrap(sea.time(.rise)))
            XCTAssertGreaterThan(try XCTUnwrap(deck.time(.set)), try XCTUnwrap(sea.time(.set)))
            for kind: SunEventKind in [.civilDawn, .civilDusk, .nauticalDawn, .nauticalDusk, .astroDawn, .astroDusk, .transit] {
                XCTAssertEqual(try XCTUnwrap(deck.time(kind)).timeIntervalSince1970,
                               try XCTUnwrap(sea.time(kind)).timeIntervalSince1970, accuracy: 1)
            }
            XCTAssertGreaterThan(try XCTUnwrap(deck.daylight), try XCTUnwrap(sea.daylight))
        }
    }

    func testPolarEventsAndInvalidHeight() throws {
        let date = ISO8601DateFormatter().date(from: "2026-06-21T00:00:00Z")!
        let facts = try SunDayFacts(at: date, tz: .gmt, latitude: 80, longitude: 0, eyeHeight: 0)
        XCTAssertNil(facts.time(.rise))
        XCTAssertNil(facts.time(.set))
        XCTAssertNil(facts.daylight)
        XCTAssertNotNil(facts.time(.transit))
        XCTAssertThrowsError(try SunDayFacts(at: date, tz: .gmt, latitude: 48.5, longitude: -123, eyeHeight: -1))
    }
}
