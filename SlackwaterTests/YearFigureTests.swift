import XCTest
import SlackwaterKit
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
}
