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

    func testJmaCreditKeepsTheSourceEditingAndGaugePositionNotices() {
        let notice = tideSourceNotice(chartDatum: "CD", source: "Japan Meteorological Agency")
        XCTAssertTrue(notice.hasPrefix("CD chart datum. "), notice)
        XCTAssertTrue(notice.contains("data.jma.go.jp/gmd/kaiyou/db/tide/suisan/station2026.php"), notice)
        XCTAssertTrue(notice.contains("Public Data License 1.0"), notice)
        XCTAssertTrue(notice.contains("digital.go.jp/resources/open_data/public_data_license_v1.0"), notice)
        XCTAssertTrue(notice.contains("CC BY 4.0: creativecommons.org/licenses/by/4.0/"), notice)
        XCTAssertTrue(notice.contains("Edited by Open Waters: constituent names, units and phases converted; tidal datums derived."), notice)
        XCTAssertTrue(notice.contains("TICON-4 (Hart-Davis, Dettmering, Seitz, 2025; doi.org/10.17882/109129), CC BY 4.0."), notice)
    }

    func testOtherSourceNoticeIsUnchanged() {
        XCTAssertEqual(tideSourceNotice(chartDatum: "LAT", source: "Kartverket"),
                       "LAT chart datum. Harmonic constants from Kartverket.")
    }
}
