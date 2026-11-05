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
}
