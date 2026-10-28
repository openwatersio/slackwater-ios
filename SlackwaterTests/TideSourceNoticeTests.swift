// Slackwater — GPL v3. Transformed data keeps its source and editing notice.
import XCTest
@testable import Slackwater

final class TideSourceNoticeTests: XCTestCase {
    func testDmiCreditNamesTheFittedPredictionsAndLicense() {
        let notice = tideSourceNotice(chartDatum: "LAT", source: "Danish Meteorological Institute")
        XCTAssertTrue(notice.hasPrefix("LAT chart datum. "), notice)
        XCTAssertTrue(notice.contains("fitted from Danish Meteorological Institute (DMI) predictions"), notice)
        XCTAssertTrue(notice.contains("CC BY 4.0"), notice)
        XCTAssertFalse(notice.contains("Harmonic constants from"), notice)
    }

    func testJhodCreditKeepsTheEditingNoticeAndTerms() {
        let notice = tideSourceNotice(chartDatum: "DL", source: "Japan Coast Guard, Hydrographic and Oceanographic Department")
        XCTAssertTrue(notice.hasPrefix("DL chart datum. "), notice)
        XCTAssertTrue(notice.contains("Government Standard Terms of Use 2.0"), notice)
        XCTAssertTrue(notice.contains("www1.kaiho.mlit.go.jp/copyright.html"), notice)
        XCTAssertTrue(notice.contains("Edited by Open Waters: constituent names, units and phases converted; tidal datums derived."), notice)
    }

    func testOtherSourceNoticeIsUnchanged() {
        XCTAssertEqual(tideSourceNotice(chartDatum: "LAT", source: "Kartverket"),
                       "LAT chart datum. Harmonic constants from Kartverket.")
    }
}
