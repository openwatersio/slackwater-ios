// Slackwater — GPL v3. The report mail a footer menu item mints: the body
// carries enough for a reader to reconstruct what the reporter saw, and the
// mailto survives the characters a station name can legally contain.
import XCTest
@testable import Slackwater

final class ReportProblemTests: XCTestCase {
    private let station = "noaa/9447130"
    private let tz = TimeZone(identifier: "America/Los_Angeles")!
    private let now = Date(timeIntervalSince1970: 1_789_000_000)  // 2026-09-08 PDT

    func testBodyCarriesStationAndMoment() {
        let body = reportBody(kind: .height, stationID: station, scrubTime: nil, now: now, tz: tz)
        XCTAssertTrue(body.contains(station), body)
        XCTAssertTrue(body.contains(reportMoment(now, tz)), body)
        XCTAssertTrue(body.contains("App: "), body)
    }

    /// A scrubbed-away strip reports the moment on screen, not the clock.
    func testScrubbedMomentWins() {
        let scrub = now.addingTimeInterval(36 * 3_600)
        let body = reportBody(kind: .height, stationID: station, scrubTime: scrub, now: now, tz: tz)
        XCTAssertTrue(body.contains(reportMoment(scrub, tz)), body)
        XCTAssertFalse(body.contains(reportMoment(now, tz)), body)
    }

    /// The link is the share button's, so the report reproduces the exact view.
    func testBodyCarriesShareLink() throws {
        let scrub = now.addingTimeInterval(36 * 3_600)
        let link = try XCTUnwrap(detailShareURL(stationID: station, scrubTime: scrub, now: now, tz: tz))
        let body = reportBody(kind: .location, stationID: station, scrubTime: scrub, now: now, tz: tz)
        XCTAssertTrue(body.contains(link.absoluteString), body)
    }

    func testSubjectIsTheKind() throws {
        for kind in ReportKind.allCases {
            let url = try XCTUnwrap(reportMailURL(kind: kind, stationID: station,
                                                  scrubTime: nil, now: now, tz: tz))
            let subject = try XCTUnwrap(queryValue("subject", in: url))
            XCTAssertEqual(subject, kind.rawValue)
        }
    }

    func testMailtoAddressAndDecodableBody() throws {
        let url = try XCTUnwrap(reportMailURL(kind: .metadata, stationID: station,
                                              scrubTime: nil, now: now, tz: tz))
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertEqual(url.absoluteString.contains("mailto:\(supportEmail)?"), true)
        let body = try XCTUnwrap(queryValue("body", in: url))
        XCTAssertEqual(body, reportBody(kind: .metadata, stationID: station,
                                        scrubTime: nil, now: now, tz: tz))
        XCTAssertTrue(body.contains("\n"), "newlines must survive the round trip")
    }

    /// A station name with an ampersand must not truncate the body — the whole
    /// reason the encoding charset is narrower than `urlQueryAllowed`.
    func testAmpersandInBodySurvives() throws {
        let raw = "Wreck & Ruin?a=b+c"
        let encoded = try XCTUnwrap(raw.addingPercentEncoding(
            withAllowedCharacters: {
                var set = CharacterSet.urlQueryAllowed
                set.remove(charactersIn: "&=?+")
                return set
            }()))
        let url = try XCTUnwrap(URL(string: "mailto:\(supportEmail)?body=\(encoded)"))
        XCTAssertEqual(queryValue("body", in: url), raw)
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    /// The app has one clock, so the mail prints the same 12-hour time the
    /// detail does — a 24-hour moment line here would be a second one
    /// (`TimelineTests.testNoSourceFileSpellsATwentyFourHourPattern`).
    func testMomentPrintsTheAppsClockWithYearAndZone() {
        XCTAssertEqual(reportMoment(Date(timeIntervalSince1970: 1_789_605_360), tz),
                       "Sep 16, 2026 · 5:36pm PDT")
    }

    // -- the unavailable-station report (issue #401) --------------------------

    /// The regression this guards: `reportBody` resolved its name through
    /// `StationItem.byId` alone, which misses an unavailable id by
    /// construction, so the mail named the raw upstream id instead of the port.
    func testUnavailableReportNamesTheStation() throws {
        let gijon = try XCTUnwrap(UnavailableStation.all.first { $0.name == "Gijon" })
        let body = reportBody(kind: .unavailable, stationID: gijon.id,
                              scrubTime: nil, now: now, tz: tz)
        XCTAssertTrue(body.contains("Station: Gijon (\(gijon.id))"), body)
    }

    /// There are no predictions here, so there is no moment to report — and a
    /// mail that prints one invites the reader to look at a curve that does
    /// not exist.
    func testUnavailableReportCarriesNoMoment() throws {
        let gijon = try XCTUnwrap(UnavailableStation.all.first { $0.name == "Gijon" })
        let body = reportBody(kind: .unavailable, stationID: gijon.id,
                              scrubTime: nil, now: now, tz: tz)
        XCTAssertFalse(body.contains("Moment:"), body)
        XCTAssertFalse(body.contains(reportMoment(now, tz)), body)
        // The three water kinds still carry theirs.
        for kind in [ReportKind.location, .metadata, .height] {
            let other = reportBody(kind: kind, stationID: station, scrubTime: nil, now: now, tz: tz)
            XCTAssertTrue(other.contains("Moment:"), "\(kind) lost its moment")
        }
    }

    /// The prompt asks for what this page actually needs. Asking someone
    /// standing at an unserved harbour "what was the water doing" gets a
    /// confused answer or none.
    func testUnavailablePromptAsksForAContactNotAReading() {
        XCTAssertTrue(ReportKind.unavailable.prompt.contains("licensed"),
                      ReportKind.unavailable.prompt)
        XCTAssertFalse(ReportKind.unavailable.prompt.contains("water was doing"),
                       ReportKind.unavailable.prompt)
    }

    /// The footer menu sits on stations that work, where "I can help with an
    /// unavailable station" is nonsense beside "Tide height looks wrong".
    func testTheFooterMenuDoesNotOfferTheUnavailableKind() {
        XCTAssertFalse(ReportKind.menuCases.contains(.unavailable))
        XCTAssertEqual(ReportKind.menuCases.count, ReportKind.allCases.count - 1)
    }

    /// A station with no published slug mints no link, so the mail must still
    /// be well-formed without one.
    func testUnavailableReportMintsAMailto() throws {
        let gijon = try XCTUnwrap(UnavailableStation.all.first { $0.name == "Gijon" })
        let url = try XCTUnwrap(reportMailURL(kind: .unavailable, stationID: gijon.id,
                                              scrubTime: nil, now: now, tz: tz))
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:\(supportEmail)?"), url.absoluteString)
        XCTAssertFalse(url.absoluteString.contains("Link: "), url.absoluteString)
    }
}
