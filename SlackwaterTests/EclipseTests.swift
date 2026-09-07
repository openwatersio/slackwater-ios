// Slackwater — GPL v3. The 2026-08-28 partial is the fixture throughout: it is
// Almanac's own pinned regression case (umbral magnitude ~0.93, visible at peak
// from Victoria, not from Athens), and Friday Harbor sits in the same sky.
import Almanac
import SwiftUI
import UIKit
import XCTest
@testable import Slackwater

final class EclipseTests: XCTestCase {
    static let victoria = try! Observer(latitudeDeg: 48.42, longitudeDeg: -123.37)
    /// The not-visible fixture, and it is not a coin flip: the whole event
    /// falls in Perth's daylight on the day of the full moon, and a full moon
    /// is below the horizon while the sun is up.
    static let perth = try! Observer(latitudeDeg: -31.95, longitudeDeg: 115.86)

    let friday = TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!

    private func utc(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    /// The eclipse's local day at the station, as an anchor.
    private func anchor(_ iso: String, _ tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.startOfDay(for: utc(iso))
    }

    // MARK: - The window search

    func testTheWindowFindsThe2026PartialAndDescribesIt() throws {
        let found = lunarEclipses(from: utc("2026-08-25T00:00:00Z"),
                                  to: utc("2026-08-31T00:00:00Z"),
                                  observer: Self.victoria)
        XCTAssertEqual(found.count, 1)
        let e = try XCTUnwrap(found.first)
        XCTAssertEqual(e.kind, .partial)
        XCTAssertEqual(e.start, e.eclipse.u1)
        XCTAssertEqual(e.contacts,
                       [e.eclipse.p1, e.eclipse.u1!, e.peak, e.eclipse.u4!, e.eclipse.p4])
        XCTAssertEqual(e.contacts, e.contacts.sorted())
        XCTAssertTrue(e.anyContactVisible)
    }

    func testAnEclipseNobodyHereCanSeeIsDropped() {
        let found = lunarEclipses(from: utc("2026-08-25T00:00:00Z"),
                                  to: utc("2026-08-31T00:00:00Z"),
                                  observer: Self.perth)
        XCTAssertTrue(found.isEmpty, "Perth is in daylight for the whole event")
    }

    func testShadowIsZeroOutsideAndPeaksAtTheUmbralMagnitude() throws {
        let e = try XCTUnwrap(lunarEclipses(from: utc("2026-08-25T00:00:00Z"),
                                            to: utc("2026-08-31T00:00:00Z"),
                                            observer: Self.victoria).first)
        XCTAssertEqual(e.shadow(at: e.eclipse.p1.addingTimeInterval(-60)), 0)
        XCTAssertEqual(e.shadow(at: e.eclipse.p4.addingTimeInterval(60)), 0)
        // A penumbral leg is a dimming, not a bite.
        XCTAssertEqual(e.shadow(at: e.eclipse.p1.addingTimeInterval(60)), 0)
        XCTAssertEqual(e.shadow(at: e.peak), e.eclipse.magUmbral, accuracy: 0.001)
        XCTAssertEqual(e.shadow(at: try XCTUnwrap(e.eclipse.u1)), 0, accuracy: 0.001)
        XCTAssertEqual(e.shadow(at: try XCTUnwrap(e.eclipse.u4)), 0, accuracy: 0.001)

        let u1 = try XCTUnwrap(e.eclipse.u1)
        let half = u1.addingTimeInterval(e.peak.timeIntervalSince(u1) / 2)
        XCTAssertGreaterThan(e.shadow(at: half), 0)
        XCTAssertLessThan(e.shadow(at: half), e.eclipse.magUmbral)

        XCTAssertTrue(e.underway(at: e.peak))
        XCTAssertTrue(e.underway(at: e.eclipse.p1))
        XCTAssertFalse(e.underway(at: e.eclipse.p4.addingTimeInterval(60)))
    }

    func testAQuietMonthHasNoEclipse() {
        // October 2026 carries a full moon and no lunar eclipse; the next one
        // after 2026-08-28 is in 2027.
        XCTAssertTrue(lunarEclipses(from: utc("2026-10-01T00:00:00Z"),
                                    to: utc("2026-10-31T00:00:00Z"),
                                    observer: Self.victoria).isEmpty)
    }
}
