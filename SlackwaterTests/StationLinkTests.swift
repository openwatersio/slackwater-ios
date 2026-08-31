// Slackwater — GPL v3. The shared station link — `https://slackwater.xyz/<kind>/
// <slug>[/<instant>]` — parsed by `stationLink(from:)`. Mostly a test of what it
// *refuses*: this runs on every URL the app is handed, and anything it accepts
// it also claims, so a link it half-understands swallows a URL the browser
// should have shown.
import XCTest
@testable import Slackwater

final class StationLinkTests: XCTestCase {
    private func link(_ string: String) -> StationLink? {
        guard let url = URL(string: string) else { return nil }
        return stationLink(from: url)
    }

    // MARK: - Accepts

    func testTideStation() {
        XCTAssertEqual(link("https://slackwater.xyz/tides/friday-harbor"),
                       StationLink(kind: .tides, slug: "friday-harbor", instant: nil))
    }

    func testCurrentStation() {
        XCTAssertEqual(link("https://slackwater.xyz/currents/dodd-narrows"),
                       StationLink(kind: .currents, slug: "dodd-narrows", instant: nil))
    }

    /// A share sheet or link preview routinely appends one.
    func testTrailingSlash() {
        XCTAssertEqual(link("https://slackwater.xyz/currents/dodd-narrows/"),
                       StationLink(kind: .currents, slug: "dodd-narrows", instant: nil))
    }

    /// The kind is not decoration: a tide and a current station may hold the
    /// same slug, and only the path tells them apart.
    func testSameSlugInBothKindsIsTwoDifferentLinks() {
        XCTAssertEqual(link("https://slackwater.xyz/tides/dodd-narrows")?.kind, .tides)
        XCTAssertEqual(link("https://slackwater.xyz/currents/dodd-narrows")?.kind, .currents)
    }

    // MARK: - The instant

    /// Written in the station's own offset, so it survives the receiver being
    /// somewhere else. 14:30-07:00 is 21:30 UTC wherever it is read.
    func testInstantIsAnAbsoluteMoment() {
        let parsed = link("https://slackwater.xyz/currents/dodd-narrows/2026-08-30T14:30-07:00")
        XCTAssertEqual(parsed?.slug, "dodd-narrows")
        XCTAssertEqual(parsed?.instant, Date(timeIntervalSince1970: 1_788_125_400))
    }

    /// The web writes minute precision; accept seconds rather than guess which
    /// a future writer uses.
    func testInstantWithSeconds() {
        let parsed = link("https://slackwater.xyz/tides/everett/2026-08-30T14:30:00-07:00")
        XCTAssertEqual(parsed?.instant, Date(timeIntervalSince1970: 1_788_125_400))
    }

    /// A bare station link means "now", which is what sharing an unscrubbed
    /// view means.
    func testNoInstantMeansNow() {
        XCTAssertNil(link("https://slackwater.xyz/tides/everett")?.instant)
    }

    /// Refused, not silently treated as "now". Landing someone on a different
    /// moment without saying so is the failure this format exists to prevent.
    func testUnparseableInstantIsRefused() {
        XCTAssertNil(link("https://slackwater.xyz/tides/everett/tuesday-afternoon"))
        XCTAssertNil(link("https://slackwater.xyz/tides/everett/2026-08-30"))
    }

    // MARK: - Refuses

    func testOtherHostsAreNotOurs() {
        XCTAssertNil(link("https://example.com/tides/everett"))
        XCTAssertNil(link("https://slackwater.xyz.example.com/tides/everett"))
    }

    /// The entitlement claims the apex only, so anything else must not be
    /// treated as a station link by the parser either.
    func testSubdomainsAreNotClaimed() {
        XCTAssertNil(link("https://www.slackwater.xyz/tides/everett"))
    }

    func testHttpIsNotAUniversalLink() {
        XCTAssertNil(link("http://slackwater.xyz/tides/everett"))
    }

    /// The pages that must keep opening in a browser. Claiming these would take
    /// the landing page away from the one reader most likely to share it on.
    func testSitePagesAreNotStationLinks() {
        XCTAssertNil(link("https://slackwater.xyz/"))
        XCTAssertNil(link("https://slackwater.xyz/privacy"))
        XCTAssertNil(link("https://slackwater.xyz/support"))
    }

    func testUnknownKind() {
        XCTAssertNil(link("https://slackwater.xyz/stations/everett"))
    }

    func testKindWithNoSlug() {
        XCTAssertNil(link("https://slackwater.xyz/tides"))
        XCTAssertNil(link("https://slackwater.xyz/tides/"))
    }

    func testTooManyPathComponents() {
        XCTAssertNil(link("https://slackwater.xyz/tides/everett/2026-08-30T14:30-07:00/extra"))
    }

    /// The widget's own scheme must keep going down its own path, not be
    /// mistaken for a shared link.
    func testWidgetSchemeIsNotAStationLink() {
        XCTAssertNil(link("slackwater://station/noaa%2F9449880"))
    }
}
