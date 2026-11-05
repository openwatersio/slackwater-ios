// Slackwater — GPL v3. Printable tables: the PDF the sheet previews and shares, and the online gate's stored source.
import PDFKit
import XCTest
@testable import Slackwater

@MainActor
final class PrintableSheetTests: XCTestCase {
    func testThePDFHoldsThePageOnPaperOfTheLocalesSize() throws {
        let rows = (1...200).map { "<tr><td>Row \($0)</td></tr>" }.joined()
        let html = "<!doctype html><html><body><h1>Friday Harbor</h1><table>\(rows)</table></body></html>"
        let doc = try XCTUnwrap(PDFDocument(data: printablePDF(html: html)))
        XCTAssertGreaterThan(doc.pageCount, 1, "two hundred rows fit on one page")
        let text = try XCTUnwrap(doc.string)
        XCTAssertTrue(text.contains("Friday Harbor"), "the PDF has no text: \(text.prefix(80))")
        XCTAssertTrue(text.contains("Row 200"), "the last row was cut off")
        let size = try XCTUnwrap(doc.page(at: 0)).bounds(for: .mediaBox).size
        if Locale.current.measurementSystem == .us {
            XCTAssertEqual(size, CGSize(width: 612, height: 792))
        } else {
            XCTAssertEqual(size.width, 595.28, accuracy: 0.5)
            XCTAssertEqual(size.height, 841.89, accuracy: 0.5)
        }
    }

    func testAnOnlineGatePrintsEveryStoredBlockOnce() throws {
        func block(_ start: Double, _ count: Int) -> ChsOnlineWindow {
            let times = (0..<count).map { start + Double($0) * 900 }
            return ChsOnlineWindow(stationID: "chs-x", iwlsName: "x", timezone: "America/Vancouver",
                                   fetchedAt: Date(timeIntervalSince1970: start),
                                   start: Date(timeIntervalSince1970: times.first!),
                                   end: Date(timeIntervalSince1970: times.last!),
                                   floodDirection: 90, ebbDirection: 270,
                                   times: times, speeds: times.map { _ in 1 })
        }
        // The second block overlaps the first by two samples and sits before it in the store.
        let first = block(0, 10), second = block(8 * 900, 10)
        let merged = try XCTUnwrap(onlinePrintable([second, first]))
        XCTAssertEqual(merged.points.count, 18)
        XCTAssertEqual(merged.points.map(\.time), merged.points.map(\.time).sorted())
        XCTAssertEqual(merged.covered.count, 2)
        XCTAssertNil(onlinePrintable([]))
    }

    // MARK: - Page counts

    private let tz = TimeZone(identifier: "America/Los_Angeles")!
    private let letter = CGSize(width: 612, height: 792)
    private let a4 = CGSize(width: 595.28, height: 841.89)

    private func day(_ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c.date(from: DateComponents(year: 2026, month: 11, day: d))!
    }

    private func tideEntries(_ tl: TimelineData) -> [ScheduleEntry] {
        tl.tideExtremes
            .filter { tl.scheduleRange.contains($0.time) }
            .map { ScheduleEntry(time: $0.time, pill: $0.kind == .high ? .high : .low,
                                 value: "\(formatHeight($0.height, imperial: true)) ft") }
            .sorted { $0.time < $1.time }
    }

    private func tideConfig() throws -> PrintableConfig {
        let friday = try XCTUnwrap(TideStationRecord.record(id: TideStationRecord.fridayHarborID))
        return PrintableConfig(source: .computed(.tide(friday)), kind: .tide(heightUnit: "ft"),
                               facts: PrintFacts(name: "Friday Harbor", region: "WA", units: "feet", datum: "MLLW",
                                                 source: "NOAA 9449880",
                                                 link: URL(string: "https://slackwater.xyz/s/noaa-9449880")),
                               entries: tideEntries)
    }

    private func currentConfig() throws -> PrintableConfig {
        let rec = try XCTUnwrap(CurrentStationRecord.all.first { $0.name == "Deception Pass (Narrows)" })
        let flood = rec.floodDirection, ebb = rec.ebbDirection
        return PrintableConfig(source: .computed(.current(rec, threshold: defaultSlackThresholdKn)),
                               kind: .current(floodDeg: flood, ebbDeg: ebb),
                               facts: PrintFacts(name: rec.name, region: rec.region, units: "knots", datum: nil,
                                                 source: "NOAA", link: URL(string: "https://slackwater.xyz/s/x")),
                               entries: { scheduleEntries($0, floodDeg: flood, ebbDeg: ebb, speedUnit: "kn") })
    }

    private func gateConfig() throws -> PrintableConfig {
        let port = TideStationRecord(
            id: "chs-point-atkinson", name: "Point Atkinson", region: "West Vancouver",
            aliases: [], latitude: 49.337, longitude: -123.254,
            timezone: "America/Vancouver", chartDatum: "Chart", datumOffset: 3.0,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 0)])
        let info = try XCTUnwrap(ChsGateInfo.all.first { $0.id == "chs-malibu-rapids" })
        let rec = DerivedGateRecord(gate: info, port: port)
        return PrintableConfig(source: .computed(.gate(rec)), kind: .derivedGate,
                               facts: PrintFacts(name: info.name, region: info.region, units: "", datum: nil,
                                                 source: "CHS", link: URL(string: "https://slackwater.xyz/s/x")),
                               entries: { tl in
                                   tl.currentEvents.filter { tl.scheduleRange.contains($0.time) }
                                       .map { ScheduleEntry(time: $0.time, pill: .slack) }
                                       .sorted { $0.time < $1.time }
                               })
    }

    private func pdf(_ config: PrintableConfig, _ span: PrintSpan, _ paper: CGSize,
                     zone: TimeZone? = nil) throws -> PDFDocument {
        let zone = zone ?? tz
        let anchor = day(1)
        let tls = printTimelines(config.source, range: printRange(span, anchor: anchor, tz: zone),
                                 tz: zone, now: day(4))
        let page = printablePage(config, span: span, anchor: anchor, tz: zone, timelines: tls,
                                 printedAt: Date(timeIntervalSince1970: 1_793_000_000))
        return try XCTUnwrap(PDFDocument(data: printablePDF(html: printableHTML(page, setFormat: "compass"),
                                                            paper: paper)))
    }

    func testATideWeekAndMonthEachFitOnePageOnLetterAndA4() throws {
        let config = try tideConfig()
        for (name, paper) in [("Letter", letter), ("A4", a4)] {
            for span in [PrintSpan.week, .month] {
                XCTAssertEqual(try pdf(config, span, paper).pageCount, 1, "tide \(span) on \(name)")
            }
        }
    }

    func testADerivedGateWeekAndMonthEachFitOnePageOnLetterAndA4() throws {
        let config = try gateConfig()
        let zone = try XCTUnwrap(ChsGateInfo.all.first { $0.id == "chs-malibu-rapids" }?.tz)
        for (name, paper) in [("Letter", letter), ("A4", a4)] {
            for span in [PrintSpan.week, .month] {
                XCTAssertEqual(try pdf(config, span, paper, zone: zone).pageCount, 1, "gate \(span) on \(name)")
            }
        }
    }

    /// Every day's last max-ebb time and speed, the right-most text on its row, must be in the
    /// PDF whole and sit inside the printable rect. WebKit clips a table wider than the page at
    /// the printable rect's right edge, so text past it is cut off or missing.
    private func assertLastEbbsInside(_ doc: PDFDocument, _ days: [PrintDay], zone: TimeZone, paper: CGSize,
                                      _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let right = paper.width - 36
        for d in days {
            guard let last = d.entries.last(where: { $0.pill == .ebb }) else { continue }
            // The PDF's text layer has a plain space where the formatter puts a narrow no-break one.
            let text = "\(chartTime(last.time, zone)) \(last.value ?? "")".replacingOccurrences(of: "\u{202F}", with: " ")
            let found = doc.findString(text, withOptions: [])
            XCTAssertFalse(found.isEmpty, "\(label): \(text) is missing from the PDF", file: file, line: line)
            for sel in found {
                for p in sel.pages {
                    XCTAssertLessThanOrEqual(sel.bounds(for: p).maxX, right + 1,
                                             "\(label): \(text) runs past the printable rect", file: file, line: line)
                }
            }
        }
    }

    /// A busy current month: five slacks and four floods and ebbs a day in km/h, with an eclipse
    /// note widening the Day column. With every cell nowrap, the table is wider than WebKit will
    /// shrink to fit Letter's 540 pt printable width, and the Max ebb column runs off the page.
    func testABusyCurrentMonthWrapsInsideThePrintableWidth() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        func at(_ d: Int, _ h: Int, _ m: Int) -> Date {
            c.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
        }
        let days = (1...30).map { d -> PrintDay in
            var entries = [1, 6, 11, 16, 21].map { ScheduleEntry(time: at(d, $0, 10 + d), pill: .slack) }
            entries += [3, 8, 13, 18].map { ScheduleEntry(time: at(d, $0, 20 + d), pill: .flood, value: "12.3 km/h", arrowDeg: 90) }
            // Each day's last ebb carries its own speed, so the search below finds that row only.
            entries += [4, 9, 14].map { ScheduleEntry(time: at(d, $0, d), pill: .ebb, value: "11.8 km/h", arrowDeg: 270) }
            entries.append(ScheduleEntry(time: at(d, 23, d), pill: .ebb, value: "\(d + 10).8 km/h", arrowDeg: 270))
            if d == 3 { entries.append(ScheduleEntry(time: at(d, 2, 0), pill: .eclipse, value: "3:12 AM")) }
            return PrintDay(start: at(d, 0, 0), sunrise: at(d, 7, 0), sunset: at(d, 16, 45),
                            entries: entries.sorted { $0.time < $1.time })
        }
        let page = PrintablePage(span: .month, range: day(1)..<c.date(byAdding: .month, value: 1, to: day(1))!,
                                 tz: tz, kind: .current(floodDeg: 90, ebbDeg: 270),
                                 facts: PrintFacts(name: "Deception Pass (Narrows)", region: "Washington",
                                                   units: "kilometres per hour", datum: nil, source: "NOAA PUG1515",
                                                   link: URL(string: "https://slackwater.xyz/s/x")),
                                 days: days, nights: [], covered: nil,
                                 printedAt: Date(timeIntervalSince1970: 1_793_000_000))
        let doc = try XCTUnwrap(PDFDocument(data: printablePDF(html: printableHTML(page, setFormat: "compass"),
                                                               paper: letter)))
        assertLastEbbsInside(doc, days, zone: tz, paper: letter, "busy month")
    }

    /// The real Deception Pass month in km/h, on both papers.
    func testACurrentMonthInKilometresPerHourStaysInsideThePrintableWidth() throws {
        let rec = try XCTUnwrap(CurrentStationRecord.all.first { $0.name == "Deception Pass (Narrows)" })
        let flood = rec.floodDirection, ebb = rec.ebbDirection
        let config = PrintableConfig(source: .computed(.current(rec, threshold: defaultSlackThresholdKn)),
                                     kind: .current(floodDeg: flood, ebbDeg: ebb),
                                     facts: PrintFacts(name: rec.name, region: rec.region, units: "kilometres per hour",
                                                       datum: nil, source: "NOAA", link: URL(string: "https://slackwater.xyz/s/x")),
                                     entries: { scheduleEntries($0, floodDeg: flood, ebbDeg: ebb, speedUnit: "kmh") })
        let zone = rec.tz
        let tls = printTimelines(config.source, range: printRange(.month, anchor: day(1), tz: zone), tz: zone, now: day(4))
        let page = printablePage(config, span: .month, anchor: day(1), tz: zone, timelines: tls,
                                 printedAt: Date(timeIntervalSince1970: 1_793_000_000))
        for (name, paper) in [("Letter", letter), ("A4", a4)] {
            let doc = try XCTUnwrap(PDFDocument(data: printablePDF(html: printableHTML(page, setFormat: "compass"),
                                                                   paper: paper)))
            assertLastEbbsInside(doc, page.days, zone: zone, paper: paper, "Deception Pass km/h on \(name)")
        }
    }

    /// Letting month cells wrap stops WebKit shrinking a wide table to fit, so a usual current
    /// month has to fit one sheet on its own: November at Deception Pass, four slacks most days.
    func testACurrentMonthFitsOnePageOnLetterAndA4() throws {
        let config = try currentConfig()
        let zone = try XCTUnwrap(CurrentStationRecord.all.first { $0.name == "Deception Pass (Narrows)" }?.tz)
        for (name, paper) in [("Letter", letter), ("A4", a4)] {
            XCTAssertEqual(try pdf(config, .month, paper, zone: zone).pageCount, 1, "current month on \(name)")
        }
    }

    func testACurrentMonthNeverLeavesTheFooterAloneOnItsLastPage() throws {
        let config = try currentConfig()
        let zone = try XCTUnwrap(CurrentStationRecord.all.first { $0.name == "Deception Pass (Narrows)" }?.tz)
        for paper in [letter, a4] {
            let doc = try pdf(config, .month, paper, zone: zone)
            let last = try XCTUnwrap(doc.page(at: doc.pageCount - 1)?.string)
            XCTAssertTrue(last.contains("Not for navigation"), "the footer is missing from the last page")
            XCTAssertTrue(last.contains("AM") || last.contains("PM"), "the last page holds only the footer: \(last)")
        }
    }
}
