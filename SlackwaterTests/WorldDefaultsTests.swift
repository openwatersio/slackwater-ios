// Slackwater — GPL v3.
// World coverage: the app must not assume the user is in the Salish Sea.
// Bryan opened it in the Solent and got a Vancouver Island camera and a Near
// Me list ranked from Victoria Harbour.

import CoreLocation
import XCTest
@testable import Slackwater

final class WorldDefaultsTests: XCTestCase {
    func testCachedLocationMustBeRecentAndValid() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = CLLocation(coordinate: .init(latitude: 48.42, longitude: -123.37),
                                altitude: 0, horizontalAccuracy: 100, verticalAccuracy: 100,
                                timestamp: now.addingTimeInterval(-599))
        let stale = CLLocation(coordinate: recent.coordinate,
                               altitude: 0, horizontalAccuracy: 100, verticalAccuracy: 100,
                               timestamp: now.addingTimeInterval(-601))
        let invalid = CLLocation(coordinate: recent.coordinate,
                                 altitude: 0, horizontalAccuracy: -1, verticalAccuracy: 100,
                                 timestamp: now)

        XCTAssertEqual(LocationService.recentLocation(recent, now: now), recent)
        XCTAssertNil(LocationService.recentLocation(stale, now: now))
        XCTAssertNil(LocationService.recentLocation(invalid, now: now))
    }

    func testNearestWidgetStationCacheChangesOnlyWhenStationChanges() throws {
        let d = UserDefaults(suiteName: #function)!
        defer { d.removePersistentDomain(forName: #function) }
        let portsmouth = try XCTUnwrap(TideStationRecord.all.first {
            $0.name == "Portsmouth" && $0.latitude > 50 && $0.longitude < 0
        })

        XCTAssertTrue(LocationService.cacheNearestWidgetStation(
            lat: portsmouth.latitude, lon: portsmouth.longitude, defaults: d))
        XCTAssertEqual(d.string(forKey: AppGroup.currentLocationStationKey),
                       portsmouth.id)
        XCTAssertFalse(LocationService.cacheNearestWidgetStation(
            lat: portsmouth.latitude, lon: portsmouth.longitude, defaults: d))

        // The same fix caches the series-narrowed siblings, each of its own
        // series — the nearest tide station here IS the any-series answer.
        XCTAssertEqual(d.string(forKey: AppGroup.nearestTideStationKey), portsmouth.id)
        let nearestCurrent = try XCTUnwrap(d.string(forKey: AppGroup.nearestCurrentStationKey))
        XCTAssertEqual(StationItem.byId[nearestCurrent]?.series, .current)
    }

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
}
