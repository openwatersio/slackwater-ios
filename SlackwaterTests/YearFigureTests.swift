import XCTest
import SlackwaterKit
import Almanac
@testable import Slackwater

/// Section 3's figure: when this station sees its extremes, across the year.
///
/// A calendar question, so a time axis rather than a level axis. It is the one
/// section that genuinely needs the annual constituent: a ±15-day window cannot
/// say anything about a season, and a seasonless constituent set would return
/// twelve confident months that all look alike.
@MainActor final class YearFigureTests: XCTestCase {
    private let station = TideStationRecord.record(id: TideStationRecord.fridayHarborID)!
    private let at = Date(timeIntervalSince1970: 1_780_000_000)  // 2026-05-29

    /// A bounds-less station still yields twelve months: the store must not
    /// refuse to scan one. Pins the gate itself, not just the arithmetic.
    func testABoundsLessStationStillGetsItsYear() async throws {
        let chignik = try XCTUnwrap(TideStationRecord.record(id: "noaa/9458917"))
        XCTAssertNil(chignik.latDatum, "fixture station gained bounds")
        let store = TideStandingStore()
        await store.loadYear(record: chignik, around: at)
        XCTAssertEqual(store.months.count, 12, "the year was skipped for want of a datum")
    }

    private func months() -> [YearFigure.Month] {
        let w = TideStanding.yearWindow(around: at, tz: station.tz)
        let extremes = station.engineStation.extremes(from: w.start, to: w.end)
        return YearFigure.months(extremes.map { Peak(time: $0.time, magnitude: $0.height) },
                                 tz: station.tz, window: w)
    }

    /// Whole calendar months only. Six months either side of a date lands
    /// mid-month at both ends, and a half-month's extremes make a shallower
    /// envelope than the month really has — which would read as a seasonal
    /// signal that is really an artefact of where the window was cut.
    func testTwelveWholeMonths() {
        let m = months()
        XCTAssertEqual(m.count, 12)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        for month in m {
            XCTAssertEqual(cal.component(.day, from: month.start), 1)
        }
    }

    func testEachMonthBracketsItsOwnWater() {
        for month in months() {
            XCTAssertGreaterThan(month.highest, month.lowest, "\(month.start)")
        }
    }

    /// The point of the figure: the months a reader should plan around.
    func testTheBiggestAndSmallestMonthsAreIdentified() {
        let m = months()
        let widest = m.max { ($0.highest - $0.lowest) < ($1.highest - $1.lowest) }!
        XCTAssertTrue(YearFigure.standout(m).contains { $0.start == widest.start })
    }

    /// Friday Harbor's seasonal signal is real but small; the figure must not
    /// imply more than the water does.
    func testTheEnvelopeVariesAcrossTheYear() {
        let m = months()
        let spans = m.map { $0.highest - $0.lowest }
        XCTAssertGreaterThan(spans.max()! / spans.min()!, 1.05,
                             "a flat envelope means the window or the grouping is wrong")
    }

    /// The reason this section is not gated on the annual constituent.
    ///
    /// Sa and Ssa raise and lower MEAN LEVEL seasonally. Inside one month that
    /// offset applies to the month's highest high and its lowest low alike, so
    /// it cancels out of the span. What widens the range across a year is the
    /// solar and declinational structure, which every constituent set carries —
    /// so a station with no Sa or Ssa shows the same seasonal shape, and
    /// sometimes a stronger one. Chignik has no astronomical bounds and varies
    /// more across the year than Portland, which has them.
    func testTheSeasonalShapeDoesNotNeedAnAnnualConstituent() throws {
        func spread(_ id: String) throws -> Double {
            let r = try XCTUnwrap(TideStationRecord.record(id: id))
            let w = TideStanding.yearWindow(around: at, tz: r.tz)
            let m = YearFigure.months(r.engineStation.extremes(from: w.start, to: w.end)
                                          .map { Peak(time: $0.time, magnitude: $0.height) },
                                      tz: r.tz, window: w)
            let spans = m.map(\.span)
            return try XCTUnwrap(spans.max()) / XCTUnwrap(spans.min())
        }
        let chignik = try spread("noaa/9458917")   // no bounds
        let portland = try spread("noaa/8418150")  // has bounds
        XCTAssertNil(TideStationRecord.record(id: "noaa/9458917")?.latDatum)
        XCTAssertNotNil(TideStationRecord.record(id: "noaa/8418150")?.latDatum)
        XCTAssertGreaterThan(chignik, 1.1, "a bounds-less station still has a seasonal shape")
        XCTAssertGreaterThan(chignik, portland,
                             "and here a stronger one than a station that has the constituent")
    }

    func testWithoutExtremesThereAreNoMonths() {
        let w = TideStanding.yearWindow(around: at, tz: station.tz)
        XCTAssertTrue(YearFigure.months([], tz: station.tz, window: w).isEmpty)
    }

    /// The window is whole months in the STATION's zone, not the device's.
    func testTheWindowIsWholeMonthsInTheStationsZone() {
        var cal = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "Pacific/Auckland")!
        cal.timeZone = tz
        let w = TideStanding.yearWindow(around: at, tz: tz, calendar: cal)
        XCTAssertEqual(cal.component(.day, from: w.start), 1)
        XCTAssertEqual(cal.component(.day, from: w.end), 1)
        XCTAssertEqual(cal.dateComponents([.month], from: w.start, to: w.end).month, 12)
    }

    // MARK: Solstices and equinoxes

    /// Twelve synthetic months from `from`, each spanning what `spans` says,
    /// with real season dates around the same window.
    private func year(spans: [Double], from: Date = Date(timeIntervalSince1970: 1_768_435_200)) // 2026-01-15 UTC
        -> (months: [YearFigure.Month], seasons: [SeasonEvent]) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        let first = cal.date(from: cal.dateComponents([.year, .month], from: from))!
        let months = spans.enumerated().map { i, span in
            YearFigure.Month(start: cal.date(byAdding: .month, value: i, to: first)!, highest: span, lowest: 0)
        }
        let end = cal.date(byAdding: .month, value: spans.count, to: first)!
        return (months, YearFigure.seasonsAround((first, end), tz: station.tz))
    }

    /// Jan-start spans peaking in the given 1-based months.
    private func spans(peaking a: Int, _ b: Int) -> [Double] {
        (1...12).map { $0 == a || $0 == b ? 3 : 2 }
    }

    func testAStationPeakingAtTheSolsticesFollowsThem() {
        let y = year(spans: spans(peaking: 6, 12))
        XCTAssertEqual(YearFigure.follows(months: y.months, seasons: y.seasons, tz: station.tz), .solstices)
    }

    func testAStationPeakingAtTheEquinoxesFollowsThem() {
        let y = year(spans: spans(peaking: 3, 9))
        XCTAssertEqual(YearFigure.follows(months: y.months, seasons: y.seasons, tz: station.tz), .equinoxes)
    }

    /// Midway between the two pairs the caption makes no claim. May/November
    /// sits 71 days from the solstices against 112 from the equinoxes, and
    /// February/August 69 against 113: inside the 45-day band both ways.
    func testAStationPeakingBetweenMakesNoClaim() {
        let may = year(spans: spans(peaking: 5, 11))
        XCTAssertNil(YearFigure.follows(months: may.months, seasons: may.seasons, tz: station.tz))
        let feb = year(spans: spans(peaking: 2, 8))
        XCTAssertNil(YearFigure.follows(months: feb.months, seasons: feb.seasons, tz: station.tz))
    }

    /// A month either side of a turning point still follows it: April and
    /// October are under four weeks from the equinoxes and nine from the
    /// solstices.
    func testAMonthBesideATurningPointStillFollowsIt() {
        let april = year(spans: spans(peaking: 4, 10))
        XCTAssertEqual(YearFigure.follows(months: april.months, seasons: april.seasons, tz: station.tz), .equinoxes)
        let july = year(spans: spans(peaking: 1, 7))
        XCTAssertEqual(YearFigure.follows(months: july.months, seasons: july.seasons, tz: station.tz), .solstices)
    }

    /// The caption names one month, so that month must itself sit nearer the
    /// winning kind. August and December sum to solstices (55 + 6 against
    /// 38 + 84), but August is nearer the September equinox: saying "Widest
    /// around August, near the solstice" would be false, so no claim.
    func testTheNamedMonthMustFollowTheSameKindAsThePair() {
        let y = year(spans: (1...12).map { $0 == 8 ? 3.2 : $0 == 12 ? 3 : 2 })
        XCTAssertEqual(YearFigure.standout(y.months).first?.start, y.months[7].start, "August is the widest")
        XCTAssertNil(YearFigure.follows(months: y.months, seasons: y.seasons, tz: station.tz))
    }

    func testFollowsNeedsTwoStandoutMonths() {
        let y = year(spans: [3])
        XCTAssertNil(YearFigure.follows(months: y.months, seasons: y.seasons, tz: station.tz))
    }

    /// A window starting in April: April's nearest equinox is the March one
    /// just outside it. Scored against September instead (159 days), the
    /// sums would be 183 against 132 and April/October would read as
    /// solstices; scored truly they follow the equinoxes.
    func testAnEdgeMonthIsScoredAgainstTheSeasonOutsideTheWindow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        let april = cal.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        // April, …, October peak: indices 0 and 6 from an April start.
        let y = year(spans: (0..<12).map { $0 == 0 || $0 == 6 ? 3 : 2 }, from: april)
        XCTAssertEqual(YearFigure.follows(months: y.months, seasons: y.seasons, tz: station.tz), .equinoxes)
    }

    func testTheWindowHoldsFourSeasonsAndTheClassifierSeesMore() {
        let y = year(spans: spans(peaking: 6, 12))
        XCTAssertEqual(y.seasons.count, 8)
        let inside = y.seasons.filter { $0.time >= y.months.first!.start && $0.time < y.months.last!.start.addingTimeInterval(32 * 86_400) }
        XCTAssertEqual(inside.count, 4)
    }

    func testTheJuneSolsticeSitsTwoThirdsAcrossJune() throws {
        let y = year(spans: spans(peaking: 6, 12))
        let solstice = try XCTUnwrap(y.seasons.first { $0.kind == .juneSolstice && $0.time > y.months[0].start })
        let x = try XCTUnwrap(YearFigure.seasonX(solstice, months: y.months, tz: station.tz, step: 30))
        // June is index 5; 21 June at 01:24 PDT is 20.06 days into a 30-day month.
        XCTAssertEqual(x, 30 * (5 + 20.06 / 30), accuracy: 1)
    }

    func testASeasonOutsideTheMonthsHasNoX() {
        let y = year(spans: spans(peaking: 6, 12))
        let before = y.seasons.first { $0.time < y.months[0].start }!
        XCTAssertNil(YearFigure.seasonX(before, months: y.months, tz: station.tz, step: 30))
    }
}
