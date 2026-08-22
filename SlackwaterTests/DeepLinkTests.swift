// Slackwater — GPL v3. The widget deep link's percent-encoding, round-tripped
// through URL.pathComponents exactly as `.onOpenURL` decodes it (M3) — one id
// of each shape the bundled catalogs actually ship, since only the "/"-
// bearing ones exposed the `.urlPathAllowed` bug DeepLink.swift's charset
// fixes (task-9-report.md).
import XCTest
@testable import Slackwater

final class DeepLinkTests: XCTestCase {
    private func assertRoundTrips(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = try XCTUnwrap(deepLink(forStationID: id), file: file, line: line)
        let decoded = try XCTUnwrap(url.pathComponents.dropFirst().first, file: file, line: line)
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

    /// M2: no resolvable station — the gallery/explainer, not a dead
    /// `slackwater://station` with nothing after it.
    func testNoStationIDFallsBackToPremium() {
        XCTAssertEqual(deepLink(forStationID: nil), URL(string: "slackwater://premium"))
    }
}
