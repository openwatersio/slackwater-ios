// Slackwater — GPL v3.
// World coverage: the app must not assume the user is in the Salish Sea.
// Bryan opened it in the Solent and got a Vancouver Island camera and a Near
// Me list ranked from Victoria Harbour.

import XCTest
@testable import Slackwater

final class WorldDefaultsTests: XCTestCase {

    /// Friday Harbor was pinned to the head of the station list. That is a
    /// home-water courtesy that reads as a bug from anywhere else.
    func testStationListIsNotPinnedToOneStation() throws {
        let all = TideStationRecord.all
        // 2,500 is `gen-tides.mjs`'s own floor on `stations.json` — a sanity
        // check against a broken filter, not a tautology of today's exact
        // count (its comment: "keeps the floor a sanity check ... not a
        // tautology of today's exact count"). Reusing it here means this test
        // moves with the generator's own contract instead of hard-coding a
        // snapshot of the current bundle size, which would just re-fail the
        // next time the data set is legitimately trimmed or grown. Far above
        // the pre-world-coverage 1,473 US+Canada count either way.
        XCTAssertGreaterThan(all.count, 2500, "world bundle expected")
        XCTAssertNotEqual(all.first?.id, "noaa/9449880",
                          "Friday Harbor must no longer be pinned to the head of the list")
    }

    /// The regression this exists for: `StationItem.all` (`CurrentStation.swift`)
    /// is the list the app actually renders — search, Near Me, the map pin
    /// source — and it had its OWN independent Friday-Harbor pin, structurally
    /// identical to `TideStationRecord.all`'s but a separate implementation.
    /// The test above only asserts the tide-record layer underneath; this one
    /// asserts the thing the UI shows, not its neighbour.
    func testUIStationListIsNotPinnedToOneStation() throws {
        XCTAssertGreaterThan(StationItem.all.count, 2500, "world bundle expected")
        XCTAssertNotEqual(StationItem.all.first?.id, "noaa/9449880",
                          "Friday Harbor must no longer be pinned to the head of the UI's own list")
    }

    /// The no-fix fallback must come from what the user last opened, and only
    /// fall back to a fixed coordinate on a genuinely first run.
    @MainActor
    func testFallbackAnchorPrefersTheLastOpenedStation() throws {
        // RecentsStore has no clear() — seed it by recording, and read back
        // through `items`, which is the accessor the app already uses.
        let pompey = try XCTUnwrap(TideStationRecord.all.first {
            $0.name == "Portsmouth" && $0.latitude > 50 && $0.longitude < 0 })
        RecentsStore.shared.record(pompey.id)

        let last = try XCTUnwrap(RecentsStore.shared.lastOpened,
                                 "lastOpened must follow the most recent record()")
        XCTAssertEqual(last.id, pompey.id)

        // LocationService.location is nil in a test process, so the anchor
        // falls through to the last-opened station rather than to Victoria.
        let anchor = try XCTUnwrap(LocationService.shared.rankingAnchor)
        XCTAssertEqual(anchor.lat, pompey.latitude, accuracy: 0.001,
                       "with no fix, the ranking anchor must follow the last opened station")
        XCTAssertNotEqual(anchor.lat, firstRunFix.lat, accuracy: 0.001,
                          "Victoria Harbour is the first-run value only")
    }
}
