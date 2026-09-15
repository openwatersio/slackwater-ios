// Slackwater — GPL v3. The download queue's behaviour, mirroring the web's
// offlineSync.test.ts (proximity ordering, claim-the-head, retry) plus the two
// rules iOS adds: promotion is sticky against a later re-sort, and opening a
// failed station re-queues it.
import XCTest
@testable import Slackwater

final class ChsQueueTests: XCTestCase {
    func testOnlyNamedCausesArePermanent() {
        XCTAssert(ChsError.isPermanent(ChsError.permanent("no IWLS station serves wlp")))
        XCTAssertFalse(ChsError.isPermanent(ChsError.transient("HTTP 503")))
        XCTAssertFalse(ChsError.isPermanent(URLError(.timedOut)))
        XCTAssertFalse(ChsError.isPermanent(NSError(domain: NSPOSIXErrorDomain, code: 54)))
        XCTAssertFalse(ChsError.isPermanent(DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "IWLS served nonsense"))))
    }

    func testServiceKeepsAReadableFailureReason() {
        XCTAssertEqual(ChsFitService.reason(ChsError.permanent("no station")), "no station")
        XCTAssertEqual(ChsFitService.reason(ChsError.transient("HTTP 503")), "HTTP 503")
        XCTAssertEqual(ChsFitService.reason(ChsError.networkDisabled), "no connection")
    }

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

    func testRowStatusSaysWhatIsHappening() {
        var q = ChsQueue([job("a", 48.4, -123.3)])
        XCTAssertEqual(rowStatus(q.job("a")!, online: true, at: t0), "Waiting")

        q.set("a", .downloading)
        q.setProgress("a", done: 12, total: 31)
        XCTAssertEqual(rowStatus(q.job("a")!, online: true, at: t0), "Downloading · 12 of 31")

        q.deferRetry("a", error: "dropped", at: t0)
        XCTAssertEqual(rowStatus(q.job("a")!, online: true, at: t0), "Retrying in 1 min")

        q.set("a", .failed)
        q.note("a", error: "IWLS serves no wlp here")
        XCTAssertEqual(rowStatus(q.job("a")!, online: true, at: t0),
                       "Unavailable · IWLS serves no wlp here")

        q.set("a", .ready)
        XCTAssertEqual(rowStatus(q.job("a")!, online: true, at: t0), "Available offline")
    }

    func testRetryingSortsWithQueuedWork() {
        XCTAssertEqual(downloadSortRank(.retrying, remainingDays: nil),
                       downloadSortRank(.queued, remainingDays: nil))
        XCTAssertLessThan(downloadSortRank(.retrying, remainingDays: nil),
                          downloadSortRank(.failed, remainingDays: nil))
    }

    func testRetryingCardStatusReadsAsWorkInProgress() {
        let status = CardStatus.retrying
        XCTAssertEqual(status.label, "Retrying")
        XCTAssertEqual(status.tint, SN.foam.opacity(0.85))
        XCTAssert(status.showsPlaceholder)
        XCTAssert(status.accessibilityLabel.contains("on its own"))
    }

    func testOnlineGateCardUsesTheServiceFetchState() {
        XCTAssertEqual(onlineGateStatus(nil, online: true, state: .fetching), .downloading)
        XCTAssertEqual(onlineGateStatus(nil, online: true,
                                        state: .deferred(t0.addingTimeInterval(60))), .retrying)
        XCTAssertEqual(onlineGateStatus(nil, online: true, state: .failed("no data")), .failed)
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

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func testADeferredJobIsSkippedUntilItsClockRunsOut() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.set("near", .downloading)
        q.deferRetry("near", error: "HTTP 503", at: t0)

        XCTAssertEqual(q.job("near")?.status, .pending)
        XCTAssertEqual(q.job("near")?.attempts, 1)
        XCTAssertEqual(q.job("near")?.lastError, "HTTP 503")
        XCTAssertEqual(q.nextPending(at: t0)?.id, "mid")
        XCTAssertEqual(q.nextPending(at: t0.addingTimeInterval(61))?.id, "near")
        XCTAssertEqual(q.deferred(at: t0), 1)
        XCTAssertEqual(q.deferred(at: t0.addingTimeInterval(61)), 0)
    }

    func testBackoffDoublesToAFifteenMinuteCeiling() {
        XCTAssertEqual(ChsQueue.backoff(attempts: 1), 60)
        XCTAssertEqual(ChsQueue.backoff(attempts: 2), 120)
        XCTAssertEqual(ChsQueue.backoff(attempts: 3), 240)
        XCTAssertEqual(ChsQueue.backoff(attempts: 4), 480)
        XCTAssertEqual(ChsQueue.backoff(attempts: 5), 900)
        XCTAssertEqual(ChsQueue.backoff(attempts: 50), 900)
    }

    func testAJobCarriesProgressForItsCurrentAttempt() {
        var q = queue()
        q.set("near", .downloading)
        q.setProgress("near", done: 3, total: 11)
        XCTAssertEqual(q.job("near")?.done, 3)
        XCTAssertEqual(q.job("near")?.total, 11)
        q.deferRetry("near", error: "dropped", at: t0)
        XCTAssertEqual(q.job("near")?.done, 0)
    }

    func testTheEstimateScalesWithObservedRequestTime() {
        let port = job("port", 48.4, -123.3)
        XCTAssertEqual(port.estimatedSeconds(perRequest: 10),
                       port.estimatedSeconds(perRequest: 2.5) * 4,
                       accuracy: 0.001)
    }

    func testEarliestRetryIsTheNextJobDue() {
        var q = queue()
        q.set("far", .downloading)
        q.deferRetry("far", error: "dropped", at: t0)
        q.set("near", .downloading)
        q.deferRetry("near", error: "dropped", at: t0.addingTimeInterval(30))
        XCTAssertEqual(q.earliestRetry(after: t0), t0.addingTimeInterval(60))
        XCTAssertNil(q.earliestRetry(after: t0.addingTimeInterval(120)))
    }

    func testPromoteReconnectAndRetryNowClearTheRightFailures() {
        var q = queue()
        q.set("far", .downloading)
        q.deferRetry("far", error: "dropped", at: t0)
        q.promote("far")
        XCTAssertNil(q.job("far")?.retryAfter)
        XCTAssertEqual(q.job("far")?.attempts, 0)

        q.set("mid", .downloading)
        q.deferRetry("mid", error: "dropped", at: t0)
        q.set("near", .failed)
        q.clearBackoffs()
        XCTAssertNil(q.job("mid")?.retryAfter)
        XCTAssertEqual(q.job("near")?.status, .failed)

        q.retryNow()
        XCTAssertEqual(q.job("near")?.status, .pending)
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

    @MainActor
    func testAutoFitTakesEverythingInReachWithTheBudgetedNineStillFirst() {
        let victoria = (lat: 48.4235, lon: -123.3705)
        let full = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon, constrained: false)
        let near = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon, constrained: true)

        XCTAssertEqual(near.count, ChsFitService.autoFitPorts + ChsFitService.autoFitGates)
        XCTAssertGreaterThan(full.count, near.count)
        XCTAssertEqual(Array(full.prefix(near.count)).map(\.id), near.map(\.id))
        XCTAssert(full.allSatisfy {
            distanceKm($0.latitude, $0.longitude, victoria.lat, victoria.lon)
                <= ChsFitService.autoFitRadiusKm
        })
        XCTAssertEqual(Set(full.map(\.id)).count, full.count)

        let tail = Array(full.dropFirst(near.count))
        let firstPort = tail.firstIndex { !$0.isCurrent } ?? tail.count
        let lastGate = tail.lastIndex { $0.isCurrent } ?? -1
        XCTAssertLessThan(lastGate, firstPort)
        XCTAssert(ChsFitService.autoFitSet(lat: 42.3601, lon: -71.0589,
                                           constrained: false).isEmpty)
    }

    @MainActor
    func testOnlinePrefetchAlsoTakesEverythingInReachUnlessConstrained() {
        let full = ChsFitService.autoPrefetchGates(lat: 48.4235, lon: -123.3705,
                                                   constrained: false)
        let near = ChsFitService.autoPrefetchGates(lat: 48.4235, lon: -123.3705,
                                                   constrained: true)
        XCTAssertGreaterThan(full.count, near.count)
        XCTAssertEqual(near.count, ChsFitService.autoFitGates)
        XCTAssertEqual(Array(full.prefix(near.count)).map(\.id), near.map(\.id))
    }

    @MainActor
    func testAnOnlineGateFailureIsRememberedAndDeferred() throws {
        let service = ChsFitService.shared
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.isOnline })
        service.resetOnlineStateForTesting()
        XCTAssertEqual(service.onlineState(gate.id), .idle)

        service.noteOnlineFailure(gate.id, error: "dropped", permanent: false, at: t0)
        XCTAssertEqual(service.onlineState(gate.id, at: t0),
                       .deferred(t0.addingTimeInterval(60)))
        XCTAssertEqual(service.onlineState(gate.id, at: t0.addingTimeInterval(61)), .idle)

        service.noteOnlineFailure(gate.id, error: "no flood axis", permanent: true, at: t0)
        XCTAssertEqual(service.onlineState(gate.id, at: t0.addingTimeInterval(3600)),
                       .failed("no flood axis"))
    }

    func testPromotingAFailedStationRequeuesIt() {
        var q = queue()
        q.set("far", .failed)
        q.promote("far")
        XCTAssertEqual(q.status("far"), .pending)
        XCTAssertEqual(q.nextPending()?.id, "far")
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
        XCTAssertEqual(q.nextPending()?.id, "near")
        q.set("near", .downloading)
        XCTAssertEqual(q.nextPending()?.id, "mid", "a claimed job is never handed out twice")
        q.set("mid", .ready)
        q.set("far", .failed)
        XCTAssertNil(q.nextPending(), "a failed job stays failed until it is retried")
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
        q.retryNow()
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
        XCTAssertEqual(fast.estimatedSeconds(), 21 * 2.5, accuracy: 0.01)   // 10 chunks × 2 + metadata
        XCTAssertEqual(full.estimatedSeconds(), 63 * 2.5, accuracy: 0.01)   // 31 chunks × 2 + metadata
    }

    func testPromotionReordersPendingWorkWithoutInterruptingTheActiveJob() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.set("near", .downloading)
        q.promote("far")
        XCTAssertEqual(q.status("near"), .downloading)
        XCTAssertEqual(q.nextPending()?.id, "far")
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
