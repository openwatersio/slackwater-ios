import Almanac
import XCTest
@testable import Slackwater

final class SunDayFactsTests: XCTestCase {
    func testLocalDayAndEventOrder() throws {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        // Both DST transition days: 23 and 25 hours long.
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let sea = try SunDayFacts(at: date, tz: tz, latitude: 48.5, longitude: -123)
            XCTAssertEqual(sea.interval.duration, Double(hours * 3600))
            XCTAssertEqual(sea.times.count, 15)
            XCTAssertTrue(sea.times.values.allSatisfy { calendar.isDate($0, inSameDayAs: date) })
            XCTAssertEqual(sea.ordered, [.astroDawn, .nauticalDawn, .morningBlueStart, .civilDawn,
                                         .morningBlueEnd, .rise, .morningGoldenEnd, .transit,
                                         .eveningGoldenStart, .set, .eveningBlueStart, .civilDusk,
                                         .eveningBlueEnd, .nauticalDusk, .astroDusk])
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
        XCTAssertEqual(facts.ordered.first, .transit)
        // The Sun never drops below +13°: no golden or blue edge, so no row for one.
        XCTAssertEqual(facts.ordered.count, 9)
        XCTAssertThrowsError(try SunDayFacts(at: date, tz: .gmt, latitude: 100, longitude: -123))
    }

    /// At 60° N on the solstice the Sun bottoms out near −6.6°: it crosses −4° both ways
    /// but never reaches −8°, so the blue hour has one edge each side and no −8° edges.
    func testHighLatitudeOmitsMissingEdges() throws {
        let date = ISO8601DateFormatter().date(from: "2026-06-21T00:00:00Z")!
        let facts = try SunDayFacts(at: date, tz: .gmt, latitude: 60, longitude: 0)
        XCTAssertNotNil(facts.time(.morningBlueEnd))
        XCTAssertNotNil(facts.time(.eveningBlueStart))
        XCTAssertNil(facts.time(.morningBlueStart))
        XCTAssertNil(facts.time(.eveningBlueEnd))
        XCTAssertFalse(facts.ordered.contains(.morningBlueStart))
        XCTAssertFalse(facts.ordered.contains(.eveningBlueEnd))
        XCTAssertTrue(facts.ordered.contains(.morningGoldenEnd))
        XCTAssertTrue(facts.ordered.contains(.eveningGoldenStart))
    }
}

final class SunWindowSpansTests: XCTestCase {
    private let lat = 48.5, lon = -123.0
    private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testGoldenAndBlueHoursFlankDaylight() throws {
        let from = utc("2026-06-10T00:00:00Z"), to = utc("2026-06-13T00:00:00Z")
        let day = sunWindowSpans(.daylight, from: from, to: to, lat: lat, lon: lon)
        let golden = sunWindowSpans(.goldenHour, from: from, to: to, lat: lat, lon: lon)
        let blue = sunWindowSpans(.blueHour, from: from, to: to, lat: lat, lon: lon)
        // The day's padding can open mid-evening, so pair spans by edge, not by index.
        XCTAssertGreaterThanOrEqual(day.count, 3)
        for d in day {
            let morning = try XCTUnwrap(golden.first { $0.lowerBound == d.lowerBound })
            let evening = try XCTUnwrap(golden.first { $0.upperBound == d.upperBound })
            XCTAssertLessThan(morning.upperBound, evening.lowerBound)
            let dawn = try XCTUnwrap(blue.last { $0.upperBound < d.lowerBound })
            let dusk = try XCTUnwrap(blue.first { $0.lowerBound > d.upperBound })
            XCTAssertLessThan(d.lowerBound.timeIntervalSince(dawn.upperBound), 3600)
            XCTAssertLessThan(dusk.lowerBound.timeIntervalSince(d.upperBound), 3600)
            for span in [morning, evening, dawn, dusk] {
                let minutes = span.upperBound.timeIntervalSince(span.lowerBound) / 60
                XCTAssert((10...90).contains(minutes), "\(span) is \(minutes) min")
            }
        }
    }

    func testHighLatitudeSpansFollowTheBand() {
        let from = utc("2026-06-21T00:00:00Z"), to = utc("2026-06-22T00:00:00Z")
        // 60° N: the Sun never reaches −8°, so the night's blue hour runs −4° to −4°.
        let blue = sunWindowSpans(.blueHour, from: from, to: to, lat: 60, lon: 0)
        XCTAssertFalse(blue.isEmpty)
        let night = blue.first { $0.contains(utc("2026-06-22T00:00:00Z")) }
        XCTAssertNotNil(night)
        // 80° N: the Sun stays above +6°, so neither window happens at all.
        XCTAssertEqual(sunWindowSpans(.goldenHour, from: from, to: to, lat: 80, lon: 0), [])
        XCTAssertEqual(sunWindowSpans(.blueHour, from: from, to: to, lat: 80, lon: 0), [])
        XCTAssertEqual(sunWindowSpans(.daylight, from: from, to: to, lat: 100, lon: 0), [])
    }
}
