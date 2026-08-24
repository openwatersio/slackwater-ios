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
        let service = LocationService.shared
        let oldStatus = service.status
        let oldLocation = service.location
        let recents = RecentsStore.shared
        let oldIDs = recents.ids
        let oldSkip = recents.skipNextRecordID
        service.status = .denied
        service.location = nil
        recents.skipNextRecordID = nil
        defer {
            service.status = oldStatus
            service.location = oldLocation
            recents.ids.forEach { recents.remove($0) }
            oldIDs.reversed().forEach { recents.record($0) }
            recents.skipNextRecordID = oldSkip
        }

        // RecentsStore has no clear() — seed it by recording, and read back
        // through `items`, which is the accessor the app already uses.
        let pompey = try XCTUnwrap(TideStationRecord.all.first {
            $0.name == "Portsmouth" && $0.latitude > 50 && $0.longitude < 0 })
        recents.record(pompey.id)

        let last = try XCTUnwrap(RecentsStore.shared.lastOpened,
                                 "lastOpened must follow the most recent record()")
        XCTAssertEqual(last.id, pompey.id)

        // LocationService.location is nil in a test process, so the anchor
        // falls through to the last-opened station rather than to Victoria.
        let anchor = LocationService.shared.rankingAnchor
        XCTAssertEqual(anchor.lat, pompey.latitude, accuracy: 0.001,
                       "with no fix, the ranking anchor must follow the last opened station")
        XCTAssertNotEqual(anchor.lat, firstRunFix.lat, accuracy: 0.001,
                          "Victoria Harbour is the first-run value only")

    }

    /// The wedge is currents, and currents don't ship worldwide — only NOAA
    /// (US) and CHS (Canada) do. An empty currents list outside that
    /// footprint must read as "we do not have this here", never as "the
    /// water is slack" (T6).
    func testCurrentsAbsenceIsStatedNotImplied() throws {
        XCTAssertFalse(hasCurrentCoverage(latitude: 50.80, longitude: -1.11),
                       "Portsmouth, UK has no NOAA or CHS current station within reach")
        XCTAssertTrue(hasCurrentCoverage(latitude: 48.7621, longitude: -123.0520),
                      "Boundary Pass sits in the middle of Salish Sea CHS/NOAA coverage")

        let label = CardStatus.noCurrentCoverage.label.lowercased()
        XCTAssertTrue(label.contains("not available"),
                      "the label must say so in words, got \(CardStatus.noCurrentCoverage.label)")
    }

    /// A political-border reading of "coverage" (any station within some
    /// generous radius, regardless of country) is dishonest right at the
    /// borders this app's own audience actually crosses — a boat in Ensenada
    /// or Nassau is nowhere near the US bay entrance a wide radius would
    /// borrow from. Currents are hyper-local (T6 §2), so coverage has to mean
    /// "a station describing THIS water", not "a station within reach".
    func testCurrentCoverageIsNotAPoliticalBox() throws {
        // Each distance below is the real nearest-bundled-station distance,
        // measured; the bar they are measured against is `currentCoverageKm`
        // (CardStatus.swift), which they clear by 29% or more. Left as measured
        // literals on purpose — a test that recomputes the production constant
        // asserts nothing about it.
        XCTAssertFalse(hasCurrentCoverage(latitude: 32.5149, longitude: -117.0382),
                       "Tijuana MX is 25.8km from San Diego Bay Entrance — a different bay, not this one")
        XCTAssertFalse(hasCurrentCoverage(latitude: 31.8667, longitude: -116.6000),
                       "Ensenada MX is 108km from the nearest bundled station")
        XCTAssertFalse(hasCurrentCoverage(latitude: 26.5333, longitude: -78.6963),
                       "Freeport, Bahamas is 136km from the nearest bundled (US) station")
        XCTAssertFalse(hasCurrentCoverage(latitude: 23.1136, longitude: -82.3666),
                       "Havana, Cuba is 161km from the nearest bundled (US) station")
        XCTAssertFalse(hasCurrentCoverage(latitude: 25.0480, longitude: -77.3554),
                       "Nassau, Bahamas is 289km from the nearest bundled (US) station")
    }

    /// Regression for the bug this exact review caught: an earlier
    /// `hasCurrentCoverage` checked `CurrentStationRecord.all` (NOAA) only,
    /// so it reported "not available" at Seymour Narrows — a validated CHS
    /// gate the app ships a fitted model for, and one of this coast's
    /// fiercest tidal passes. A missed bundle is the same dishonest silence
    /// as a missed radius.
    func testCurrentCoverageIncludesChsGates() throws {
        let seymourNarrows = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.id == "chs-seymour-narrows" })
        XCTAssertTrue(hasCurrentCoverage(latitude: seymourNarrows.latitude, longitude: seymourNarrows.longitude),
                      "Seymour Narrows is itself a bundled CHS current gate")
    }
}
