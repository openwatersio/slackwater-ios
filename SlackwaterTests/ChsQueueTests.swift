// Slackwater — GPL v3. The download queue's behaviour, mirroring the web's
// offlineSync.test.ts (proximity ordering, claim-the-head, retry) plus the two
// rules iOS adds: promotion is sticky against a later re-sort, and opening a
// failed station re-queues it.
import XCTest
@testable import Slackwater

final class ChsQueueTests: XCTestCase {
    func testDownloadPriorityOrdersActivityThenUrgency() {
        let states: [(String, ManagedDownloadState, Int?)] = [
            ("permanent", .permanent, nil),
            ("valid-20", .available, 20),
            ("expired", .expired, 0),
            ("not-downloaded", .notDownloaded, nil),
            ("queued", .queued, nil),
            ("valid-5", .available, 5),
            ("failed", .failed, nil),
            ("expiring", .available, 2),
            ("downloading", .downloading, nil),
        ]

        XCTAssertEqual(states.enumerated().sorted {
            let left = downloadSortRank($0.element.1, remainingDays: $0.element.2)
            let right = downloadSortRank($1.element.1, remainingDays: $1.element.2)
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element.0),
        ["downloading", "queued", "expired", "not-downloaded", "failed", "expiring",
         "valid-5", "valid-20", "permanent"])
        XCTAssert(downloadIsReady(.permanent))
        XCTAssert(downloadIsReady(.available))
        XCTAssertFalse(downloadIsReady(.expired))
        XCTAssertFalse(downloadIsReady(.failed))
    }
    private func job(_ id: String, _ lat: Double, _ lon: Double,
                     current: Bool = false, days: Double = 60) -> ChsJob {
        ChsJob(id: id, name: id, region: "test", isCurrent: current,
               latitude: lat, longitude: lon, fitDays: days)
    }

    /// Victoria-ish origin, and three stations at increasing distance.
    private func queue() -> ChsQueue {
        ChsQueue([job("far", 50.5, -126.9), job("near", 48.43, -123.37), job("mid", 49.3, -123.1)])
    }

    func testPrioritizeOrdersClosestFirst() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        XCTAssertEqual(q.jobs.map(\.id), ["near", "mid", "far"])
    }

    func testPromoteJumpsToTheFrontAheadOfProximity() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.promote("far")
        XCTAssertEqual(q.jobs.map(\.id), ["far", "near", "mid"])
        XCTAssertTrue(q.isPromoted("far"))
        XCTAssertEqual(q.position("far"), 1, "the station you opened is next up")
    }

    /// The iOS-only rule: a fix landing after you opened a station must not
    /// demote it (the web re-sorts everything and would).
    func testPromotionSurvivesALaterPrioritize() {
        var q = queue()
        q.promote("far")
        q.prioritize(lat: 48.4235, lon: -123.3705)
        XCTAssertEqual(q.jobs.map(\.id), ["far", "near", "mid"])
    }

    func testFavoritesSitBetweenTheViewedStationAndNearbyStations() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.prefer(["mid", "far"])
        q.promote("near")
        XCTAssertEqual(q.jobs.map(\.id), ["near", "mid", "far"])

        q.prefer(["far", "mid"])
        XCTAssertEqual(q.jobs.map(\.id), ["near", "far", "mid"],
                       "a later iCloud reconciliation preserves the new favorite order")
    }

    @MainActor
    func testFavoriteDownloadsMapToTheirRequiredArtifacts() throws {
        let port = try XCTUnwrap(ChsStationInfo.all.first)
        let derived = try XCTUnwrap(ChsGateInfo.all.first)
        let online = try XCTUnwrap(ChsCurrentGateInfo.all.first(where: \.isOnline))
        let noaa = try XCTUnwrap(StationItem.all.first { if case .tide = $0 { true } else { false } })

        let downloads = ChsFitService.favoriteDownloads(
            [port.id, derived.id, online.id, noaa.id, derived.id])

        XCTAssertEqual(downloads.jobIDs, [port.id, derived.reference])
        XCTAssertEqual(downloads.online.map(\.id), [online.id])
    }

    func testPromotingAFailedStationRequeuesIt() {
        var q = queue()
        q.set("far", .failed)
        q.promote("far")
        XCTAssertEqual(q.status("far"), .pending)
        XCTAssertEqual(q.nextPending?.id, "far")
    }

    /// A ready station has nothing to download — promoting it would only
    /// shuffle the manager's list.
    func testPromotingAReadyStationIsANoOp() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.set("far", .ready)
        q.promote("far")
        XCTAssertEqual(q.jobs.map(\.id), ["near", "mid", "far"])
        XCTAssertFalse(q.isPromoted("far"))
    }

    func testNextPendingIsTheHeadAndSkipsClaimedOrFinishedJobs() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        XCTAssertEqual(q.nextPending?.id, "near")
        q.set("near", .downloading)
        XCTAssertEqual(q.nextPending?.id, "mid", "a claimed job is never handed out twice")
        q.set("mid", .ready)
        q.set("far", .failed)
        XCTAssertNil(q.nextPending, "a failed job stays failed until it is retried")
    }

    func testCounts() {
        var q = queue()
        XCTAssertEqual(q.total, 3)
        XCTAssertTrue(q.active)
        XCTAssertFalse(q.complete)
        q.set("near", .ready)
        q.set("mid", .ready)
        q.set("far", .failed)
        XCTAssertEqual(q.ready, 2)
        XCTAssertEqual(q.failed, 1)
        XCTAssertFalse(q.active, "nothing pending or downloading — the run is over")
        q.set("far", .ready)
        XCTAssertTrue(q.complete)
    }

    /// Web restartAll: retry the incomplete ones, leave the ready ones alone.
    func testRetryFailedRequeuesOnlyFailures() {
        var q = queue()
        q.set("near", .ready)
        q.set("mid", .failed)
        q.set("far", .failed)
        q.retryFailed()
        XCTAssertEqual(q.status("near"), .ready)
        XCTAssertEqual(q.status("mid"), .pending)
        XCTAssertEqual(q.status("far"), .pending)
    }

    /// The FTUE number: with proximity ordering the nearest station's wait is
    /// its own fetch, not the whole queue's.
    func testWaitSecondsCountsOnlyWhatIsAheadPlusItself() {
        var q = ChsQueue([job("near", 48.43, -123.37),
                          job("gate", 48.5, -123.5, current: true, days: 210)])
        q.prioritize(lat: 48.4235, lon: -123.3705)
        // A 60-day tide port is 10 paced requests; the 210-day gate behind it
        // adds 31 chunks × 2 series + 1 metadata.
        XCTAssertEqual(q.waitSeconds("near"), 10 * 2.5, accuracy: 0.01)
        XCTAssertEqual(q.waitSeconds("gate"), 10 * 2.5 + 63 * 2.5, accuracy: 0.01)
        q.set("near", .ready)
        XCTAssertEqual(q.waitSeconds("gate"), 63 * 2.5, accuracy: 0.01,
                       "a finished station no longer holds anyone up")
        XCTAssertEqual(q.waitSeconds("near"), 0)
    }

    /// M51: the window is the job's own, so a 60-day gate is roughly a third of
    /// a 210-day one — the whole reason four gates skip the provisional stage.
    func testA60DayGateCostsAThirdOfA210DayGate() {
        let fast = job("fast", 48.9, -123.3, current: true, days: 60)
        let full = job("full", 49.1, -123.8, current: true, days: 210)
        XCTAssertEqual(fast.estimatedSeconds, 21 * 2.5, accuracy: 0.01)   // 10 chunks × 2 + metadata
        XCTAssertEqual(full.estimatedSeconds, 63 * 2.5, accuracy: 0.01)   // 31 chunks × 2 + metadata
    }

    // MARK: - M51: stepping aside at a chunk boundary

    /// The whole point: a 210-day gate in flight does not make you wait 2.5 min
    /// for the station you just opened.
    func testTheRunningJobStepsAsideForAStationYouOpened() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.set("near", .downloading)
        XCTAssertFalse(q.shouldYield(running: "near"), "nobody is waiting on us")
        q.promote("far")
        XCTAssert(q.shouldYield(running: "near"), "the station the user opened is at the head, waiting")
    }

    /// Proximity alone never interrupts: only an explicit open does.
    func testAMerelyCloserStationDoesNotInterrupt() {
        var q = queue()
        q.set("far", .downloading)
        q.prioritize(lat: 48.4235, lon: -123.3705)
        XCTAssertFalse(q.shouldYield(running: "far"),
                       "a re-sort re-orders the queue; it does not throw away a download in flight")
    }

    /// Between two stations the user opened, the newest open wins — and the
    /// pair can never hand the download back and forth, because that order is
    /// strict in one direction.
    func testTheMostRecentlyOpenedStationWinsAndCannotPingPong() {
        var q = queue()
        q.promote("far")            // opened first
        q.set("far", .downloading)
        q.promote("mid")            // opened second, while `far` is in flight
        XCTAssertEqual(q.nextPending?.id, "mid", "the newest open leads the queue")
        XCTAssert(q.shouldYield(running: "far"), "an earlier open still steps aside for a later one")

        // …and once `mid` has the download, `far` waiting behind it changes nothing.
        q.set("far", .pending)
        q.set("mid", .downloading)
        XCTAssertEqual(q.nextPending?.id, "far")
        XCTAssertFalse(q.shouldYield(running: "mid"), "no thrash: the newest open is never yielded from")
    }

    func testDurationPhraseIsCoarse() {
        XCTAssertEqual(durationPhrase(22), "under a minute")
        XCTAssertEqual(durationPhrase(155), "about 3 minutes")
        XCTAssertEqual(durationPhrase(3600), "about an hour")
    }

    func testOrdinal() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22].map(ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd"])
    }
}
