// Slackwater — GPL v3. Printable tables: spans, day rows, night and coverage.
import XCTest
@testable import Slackwater

final class PrintableTablesTests: XCTestCase {
    let tz = TimeZone(identifier: "America/Los_Angeles")!
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }
    func day(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
    }
    func timeline(days: [TimelineDay]) -> TimelineData {
        let s = day(11, 1)
        return TimelineData(tz: tz, anchor: s, today: s, start: s, end: s.addingTimeInterval(86_400), days: days,
                            tidePoints: [], tideRates: [], tideExtremes: [], currentPoints: [],
                            currentEvents: [], snapTimes: [], slackWindows: [])
    }

    func testAWeekIsSevenLocalDaysFromTheAnchor() {
        let anchor = day(10, 29)
        let r = printRange(.week, anchor: anchor, tz: tz)
        XCTAssertEqual(r.lowerBound, anchor)
        XCTAssertEqual(r.upperBound, day(11, 5))
        XCTAssertNotEqual(r.upperBound.timeIntervalSince(r.lowerBound), 7 * 86_400)  // spans DST end Nov 1
    }
    func testAMonthIsTheAnchorsCalendarMonth() {
        let r = printRange(.month, anchor: day(11, 18), tz: tz)
        XCTAssertEqual(r.lowerBound, day(11, 1))
        XCTAssertEqual(r.upperBound, day(12, 1))
    }
    func testNovemberHasFiveWeekAnchors() {
        let r = printRange(.month, anchor: day(11, 1), tz: tz)
        XCTAssertEqual(printWeekAnchors(r, tz: tz).count, 5)
        XCTAssertEqual(printWeekAnchors(r, tz: tz).map { cal.component(.day, from: $0) }, [1, 8, 15, 22, 29])
    }

    private func entry(_ t: Date) -> ScheduleEntry { ScheduleEntry(time: t, pill: .high, value: "5 ft") }

    func testRowsOutsideCoverageAreDroppedAndTheNoteNamesEachRange() {
        let r = printRange(.month, anchor: day(11, 1), tz: tz)
        let covered = [day(11, 4)..<day(11, 11), day(11, 15)..<day(11, 18)]
        let all = (1...30).map { entry(day(11, $0, 9)) }
        let tl = timeline(days: [])
        let days = printDays(timelines: [tl], entries: { _ in all }, range: r, covered: covered, tz: tz)
        let dom = days.map { cal.component(.day, from: $0.start) }
        XCTAssertEqual(dom, [4, 5, 6, 7, 8, 9, 10, 15, 16, 17])
        let note = printCoverageNote(range: r, covered: covered, tz: tz, locale: Locale(identifier: "en_US"))
        // DateIntervalFormatter puts thin spaces (U+2009) around the en dash, as weekRangeLabel's output does.
        XCTAssertEqual(note?.replacingOccurrences(of: "\u{2009}", with: " "), "Predictions available Nov 4 – 10, Nov 15 – 17 only.")
    }
    func testDuplicatesAcrossWeekTimelinesAreDroppedAndSunTimesAttach() {
        let r = day(11, 1)..<day(11, 3)
        let rise = day(11, 1, 6, 30), set = day(11, 1, 17)
        let tl = timeline(days: [TimelineDay(offset: 0, start: day(11, 1), sunrise: rise, sunset: set,
                                             moonrise: nil, moonset: nil)])
        let e = [entry(day(11, 1, 10)), entry(day(11, 1, 10)), entry(day(11, 1, 2)), entry(day(11, 3, 1))]
        let days = printDays(timelines: [tl, tl], entries: { _ in e }, range: r, covered: nil, tz: tz)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].entries.map(\.time), [day(11, 1, 2), day(11, 1, 10)])
        XCTAssertEqual(days[0].sunrise, rise)
        XCTAssertEqual(days[0].sunset, set)
    }
    func testFullCoverageHasNoNote() {
        let r = printRange(.month, anchor: day(11, 1), tz: tz)
        XCTAssertNil(printCoverageNote(range: r, covered: nil, tz: tz))
        XCTAssertNil(printCoverageNote(range: r, covered: [r], tz: tz))
    }

    private func printDay(rise: Date?, set: Date?) -> PrintDay {
        PrintDay(start: day(11, 4), sunrise: rise, sunset: set, entries: [])
    }
    func testNightIsOutsideSunriseToSunset() {
        let d = printDay(rise: day(11, 4, 6, 40), set: day(11, 4, 17))
        XCTAssertTrue(printIsNight(day(11, 4, 5), in: d))
        XCTAssertFalse(printIsNight(day(11, 4, 12), in: d))
        XCTAssertTrue(printIsNight(day(11, 4, 20), in: d))
    }
    /// The strip pairs sun events into `sunSpans` (TimelineStrip.swift, `sunSpans`) and shades
    /// only the `!daylight` spans; a day with neither event yields no span, so it is not shaded.
    func testADayWithNoSunEventsFollowsTheStrip() {
        let d = printDay(rise: nil, set: nil)
        XCTAssertFalse(printIsNight(day(11, 4, 2), in: d))
        XCTAssertFalse(printIsNight(day(11, 4, 12), in: d))
    }
}
