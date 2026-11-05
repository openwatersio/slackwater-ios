// Slackwater — GPL v3. Printable tables: the page as HTML.
import XCTest
@testable import Slackwater

final class PrintableHTMLTests: XCTestCase {
    let tz = TimeZone(identifier: "America/Los_Angeles")!
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }
    func at(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
    }
    let link = URL(string: "https://slackwater.xyz/s/example")!

    func facts(name: String = "Seattle", datum: String? = nil) -> PrintFacts {
        PrintFacts(name: name, region: "Washington", units: "knots", datum: datum,
                   source: "NOAA 9449880", link: link)
    }
    func page(span: PrintSpan = .week, range: Range<Date>? = nil, kind: PrintKind,
              facts: PrintFacts? = nil, days: [PrintDay], nights: [Range<Date>] = [],
              covered: [Range<Date>]? = nil) -> PrintablePage {
        PrintablePage(span: span, range: range ?? at(10, 31)..<at(11, 7), tz: tz, kind: kind,
                      facts: facts ?? self.facts(), days: days, nights: nights,
                      covered: covered, printedAt: at(11, 4, 9))
    }
    func printDay(_ m: Int, _ d: Int, _ entries: [ScheduleEntry]) -> PrintDay {
        PrintDay(start: at(m, d), sunrise: at(m, d, 6, 30), sunset: at(m, d, 17, 0), entries: entries)
    }

    func testAWeekPageListsEveryEntryInLocalTime() {
        let a = ScheduleEntry(time: at(10, 31, 8, 15), pill: .slack)
        let b = ScheduleEntry(time: at(11, 1, 14, 40), pill: .flood, value: "2.1 kn", arrowDeg: 90)
        let html = printableHTML(page(kind: .current(floodDeg: 90, ebbDeg: 270),
                                      days: [printDay(10, 31, [a]), printDay(11, 1, [b])]),
                                 setFormat: "degrees")
        XCTAssertTrue(html.contains(chartTime(a.time, tz)))
        XCTAssertTrue(html.contains(chartTime(b.time, tz)))
        XCTAssertTrue(html.contains("2.1 kn"))
        XCTAssertTrue(html.contains("090°"))
        XCTAssertEqual(html.components(separatedBy: "<tr class=\"day\"").count - 1, 2)
    }

    func testTheHeaderNamesBothZoneAbbreviationsAcrossDST() {
        let html = printableHTML(page(kind: .derivedGate, days: []), setFormat: "compass")
        XCTAssertTrue(html.contains("PDT/PST"))
    }

    func testANightEntryIsShaded() {
        let early = ScheduleEntry(time: at(11, 2, 5), pill: .high, value: "6.2 ft")
        let noon = ScheduleEntry(time: at(11, 2, 12), pill: .low, value: "1.0 ft")
        let night = at(11, 2, 0)..<at(11, 2, 6)
        let html = printableHTML(page(kind: .tide(heightUnit: "ft"),
                                      days: [printDay(11, 2, [early, noon])], nights: [night]),
                                 setFormat: "compass")
        let rows = html.components(separatedBy: "<tr")
        let earlyRow = rows.first { $0.contains(chartTime(early.time, tz)) }!
        let noonRow = rows.first { $0.contains(chartTime(noon.time, tz)) }!
        XCTAssertTrue(earlyRow.hasPrefix(" class=\"night\""))
        XCTAssertFalse(noonRow.contains("night"))
    }

    /// The peak goes with the event, so the Height column never holds a time.
    func testAWeekEclipseRowCarriesItsPeakInTheEventCell() {
        let e = ScheduleEntry(time: at(11, 2, 1, 30), pill: .eclipse, value: "3:12 AM")
        let html = printableHTML(page(kind: .tide(heightUnit: "ft"), days: [printDay(11, 2, [e])]),
                                 setFormat: "compass")
        let row = html.components(separatedBy: "<tr").first { $0.contains("Lunar eclipse") }!
        XCTAssertTrue(row.contains("<td>Lunar eclipse (peak 3:12 AM)</td><td>—</td></tr>"), row)
        let solar = ScheduleEntry(time: at(11, 2, 9), pill: .solarEclipse, value: "10:05 AM")
        let gate = printableHTML(page(kind: .derivedGate, days: [printDay(11, 2, [solar])]), setFormat: "compass")
        XCTAssertTrue(gate.contains("<td>Solar eclipse (peak 10:05 AM)</td></tr>"))
    }

    func testMonthTimesHaveSpaceBetweenThemToWrapAt() {
        let a = ScheduleEntry(time: at(11, 2, 3), pill: .slack), b = ScheduleEntry(time: at(11, 2, 9), pill: .slack)
        let html = printableHTML(page(span: .month, range: at(11, 1)..<at(12, 1), kind: .derivedGate,
                                      days: [printDay(11, 2, [a, b])]), setFormat: "compass")
        XCTAssertTrue(html.contains("</span> <span class=\"t"))
        XCTAssertTrue(html.contains(".mday td + td { white-space: normal; }"))
    }

    func testAMonthPageHasOneRowPerDay() {
        let days = (1...30).map { printDay(11, $0, [ScheduleEntry(time: at(11, $0, 9), pill: .slack)]) }
        let html = printableHTML(page(span: .month, range: at(11, 1)..<at(12, 1),
                                      kind: .derivedGate, days: days), setFormat: "compass")
        XCTAssertEqual(html.components(separatedBy: "<tr class=\"mday\"").count - 1, 30)
    }

    func testATidePageShowsTheDatumAndHeights() {
        let e = ScheduleEntry(time: at(11, 2, 7), pill: .high, value: "6.2 ft")
        let html = printableHTML(page(kind: .tide(heightUnit: "ft"), facts: facts(datum: "MLLW"),
                                      days: [printDay(11, 2, [e])]), setFormat: "compass")
        XCTAssertTrue(html.contains("MLLW"))
        XCTAssertTrue(html.contains("6.2 ft"))
    }

    func testADerivedGateHasNoValueColumns() {
        let e = ScheduleEntry(time: at(11, 2, 7), pill: .slack)
        let html = printableHTML(page(kind: .derivedGate, days: [printDay(11, 2, [e])]),
                                 setFormat: "compass")
        XCTAssertFalse(html.contains("Speed"))
        XCTAssertFalse(html.contains(">Set<"))
    }

    func testTheFooterCarriesTheLinkAndDisclaimer() {
        let html = printableHTML(page(kind: .derivedGate, days: []), setFormat: "compass")
        XCTAssertTrue(html.contains(link.absoluteString))
        XCTAssertTrue(html.contains("Predictions are not observations. Not for navigation."))
    }

    func testACoverageNoteAppearsWhenShort() {
        let html = printableHTML(page(span: .month, range: at(11, 1)..<at(12, 1), kind: .derivedGate,
                                      days: [], covered: [at(11, 4)..<at(11, 11)]),
                                 setFormat: "compass")
        let normalised = html.replacingOccurrences(of: "\u{2009}", with: " ")
        XCTAssertTrue(normalised.contains("Predictions available Nov 4 – 10 only."))
        XCTAssertTrue(html.contains("<p class=\"coverage\">"))
    }

    func testNamesAreEscaped() {
        let html = printableHTML(page(kind: .derivedGate, facts: facts(name: "A & B <c>"), days: []),
                                 setFormat: "compass")
        XCTAssertTrue(html.contains("A &amp; B &lt;c&gt;"))
        XCTAssertFalse(html.contains("<c>"))
    }
}
