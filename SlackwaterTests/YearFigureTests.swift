import XCTest
import SlackwaterKit
@testable import Slackwater

/// Section 3's figure: when this station sees its extremes, across the year.
///
/// A calendar question, so a time axis rather than a level axis. It is the one
/// section that genuinely needs the annual constituent: a ±15-day window cannot
/// say anything about a season, and a seasonless constituent set would return
/// twelve confident months that all look alike.
final class YearFigureTests: XCTestCase {
    private let station = TideStationRecord.record(id: TideStationRecord.fridayHarborID)!
    private let at = Date(timeIntervalSince1970: 1_780_000_000)  // 2026-05-29

    private func months() -> [YearFigure.Month] {
        let w = TideStanding.yearWindow(around: at, tz: station.tz)
        let extremes = station.engineStation.extremes(from: w.start, to: w.end)
        return YearFigure.months(extremes, tz: station.tz, window: w)
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
