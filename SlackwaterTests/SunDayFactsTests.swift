import Almanac
import XCTest
@testable import Slackwater

final class SunDayFactsTests: XCTestCase {
    func testSunNavigationCrossesDaysAndSkipsTheSelectedEvent() throws {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let nextDay = cal.date(byAdding: .day, value: 1, to: start)!
        let rise = start.addingTimeInterval(8 * 3600)
        let set = start.addingTimeInterval(18 * 3600)
        let nextRise = nextDay.addingTimeInterval(7 * 3600)
        let days = [TimelineDay(offset: 0, start: start, sunrise: rise, sunset: set,
                                moonrise: nil, moonset: nil),
                    TimelineDay(offset: 1, start: nextDay, sunrise: nextRise, sunset: nil,
                                moonrise: nil, moonset: nil)]
        let card = SunSummaryState(days: days.reversed(), at: set, tz: tz)
        XCTAssertEqual(card.day?.start, start)
        XCTAssertEqual(card.previous?.time, rise)
        XCTAssertEqual(card.next?.time, nextRise)
        XCTAssertEqual(card.next?.isRise, true)
        let tomorrow = SunSummaryState(days: days, at: nextDay, tz: tz)
        XCTAssertEqual(tomorrow.day?.start, nextDay)
        XCTAssertEqual(tomorrow.previous?.time, set)
        XCTAssertEqual(tomorrow.next?.time, nextRise)
        let polar = SunSummaryState(days: [], at: start, tz: tz)
        XCTAssertNil(polar.previous)
        XCTAssertNil(polar.next)
        XCTAssertNil(polar.day)
    }

    func testSunNavigationChangesThroughTheSelectedDay() throws {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8))!
        let days = try (-1...1).map { offset in
            let start = calendar.date(byAdding: .day, value: offset, to: today)!
            let facts = try SunDayFacts(at: start, tz: tz, latitude: 48.5, longitude: -123)
            return TimelineDay(offset: offset, start: start, sunrise: facts.time(.rise),
                               sunset: facts.time(.set), solarNoon: facts.time(.transit),
                               moonrise: nil, moonset: nil)
        }
        for (hour, previousDay, previousRise, nextDay, nextRise) in [
            (5, 0, false, 1, true),
            (12, 1, true, 1, false),
            (22, 1, false, 2, true)
        ] {
            let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today)!
            let state = SunSummaryState(days: days, at: at, tz: tz)
            XCTAssertEqual(state.previous?.time,
                           previousRise ? days[previousDay].sunrise : days[previousDay].sunset)
            XCTAssertEqual(state.previous?.isRise, previousRise)
            XCTAssertEqual(state.next?.time, nextRise ? days[nextDay].sunrise : days[nextDay].sunset)
            XCTAssertEqual(state.next?.isRise, nextRise)
        }
    }

    func testSunCardDaylightMatchesThePopupAcrossDST() throws {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        for (month, date) in [(3, 8), (11, 1)] {
            let start = calendar.date(from: DateComponents(year: 2026, month: month, day: date))!
            let facts = try SunDayFacts(at: start, tz: tz, latitude: 48.5, longitude: -123)
            let day = TimelineDay(offset: 0, start: start, sunrise: facts.time(.rise),
                                  sunset: facts.time(.set), moonrise: nil, moonset: nil)
            let state = SunSummaryState(days: [day], at: start, tz: tz)
            XCTAssertEqual(try XCTUnwrap(state.daylight), try XCTUnwrap(facts.daylight))
        }
        let polar = TimelineDay(offset: 0, start: Date(), sunrise: nil, sunset: nil,
                                moonrise: nil, moonset: nil)
        XCTAssertNil(SunSummaryState(days: [polar], at: polar.start, tz: tz).daylight)
    }

    func testSunOrbitUsesExactDistancesAndNearestApsidesAcrossYears() throws {
        let at = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00Z")!
        let facts = try SunOrbitFacts(at: at)
        XCTAssertEqual(facts.distanceKm, try sunPosition(at).distanceAu * 149_597_870.7,
                       accuracy: 0.01)
        XCTAssertEqual(facts.perihelion.kind, .perihelion)
        XCTAssertEqual(facts.aphelion.kind, .aphelion)
        XCTAssertGreaterThan(facts.perihelion.time, at)
        XCTAssertLessThan(facts.aphelion.time, at)
        XCTAssertLessThan(facts.perihelion.distanceKm, facts.aphelion.distanceKm)
        let events = try earthApsides(
            from: ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!,
            to: ISO8601DateFormatter().date(from: "2028-01-01T00:00:00Z")!)
        for event in [facts.perihelion, facts.aphelion] {
            let expected = try XCTUnwrap(events.first { $0.time == event.time })
            XCTAssertEqual(event.distanceKm, expected.distanceKm)
        }
        let near = try SunOrbitFacts(at: facts.perihelion.time)
        XCTAssertEqual(near.angle, 0, accuracy: 0.0001)
        let far = try SunOrbitFacts(at: facts.aphelion.time)
        XCTAssertEqual(abs(far.angle), .pi, accuracy: 0.02)
    }

    func testSunOrbitAtSupportedRangeEdges() throws {
        for date in ["1950-01-01T00:00:00Z", "2100-12-31T23:59:00Z"] {
            let facts = try SunOrbitFacts(at: ISO8601DateFormatter().date(from: date)!)
            XCTAssertTrue(facts.angle.isFinite)
            XCTAssertGreaterThan(facts.distanceKm, 147_000_000)
        }
    }

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
