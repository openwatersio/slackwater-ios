// Slackwater — GPL v3. The widget deep link, round-tripped through the exact
// pair the app uses — `deepLink(forStationID:)` out, `stationID(from:)` back —
// for one id of each shape the bundled catalogs actually ship, since only the
// "/"-bearing ones exposed the `.urlPathAllowed` bug DeepLink.swift's charset
// fixes (task-9-report.md). The receiving end this pairs with is
// DeepLinkUITests, which opens the URL for real.
import XCTest
@testable import Slackwater

final class DeepLinkTests: XCTestCase {
    private func assertRoundTrips(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = try XCTUnwrap(deepLink(forStationID: id), file: file, line: line)
        let decoded = stationID(from: url)
        XCTAssertEqual(decoded, id, file: file, line: line)
        XCTAssertNotNil(StationItem.byId[decoded], "no bundled station for \(id)", file: file, line: line)
    }

    func testNoaaTideID() throws {
        try assertRoundTrips("noaa/9454616")
    }

    func testNoaaCurrentIDWithSlash() throws {
        try assertRoundTrips("current:noaa/CHB9904")
    }

    func testChsID() throws {
        try assertRoundTrips("chs-abbotts-harbour")
    }

    func testTiconID() throws {
        try assertRoundTrips("ticon/aasiaat-aas-grl-gloss")
    }

    /// The escape does not always survive the trip to `.onOpenURL`: an id whose
    /// "/" arrives resolved has to read back the same, or the lookup misses
    /// (#167).
    func testIDReadsBackWhenTheEscapeArrivesResolved() throws {
        let url = try XCTUnwrap(URL(string: "slackwater://station/noaa/9449880"))
        XCTAssertEqual(stationID(from: url), "noaa/9449880")
        XCTAssertNotNil(StationItem.byId[stationID(from: url)])
    }

    /// M2: no resolvable station — the gallery/explainer, not a dead
    /// `slackwater://station` with nothing after it.
    func testNoStationIDFallsBackToPremium() {
        XCTAssertEqual(deepLink(forStationID: nil), URL(string: "slackwater://premium"))
    }
}
