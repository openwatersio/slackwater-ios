// Slackwater — GPL v3. The download queue's behaviour, mirroring the web's
// offlineSync.test.ts (proximity ordering, claim-the-head, retry) plus the two
// rules iOS adds: promotion is sticky against a later re-sort, and opening a
// failed station re-queues it.
import XCTest
@testable import Slackwater

final class ChsQueueTests: XCTestCase {
    private func job(_ id: String, _ lat: Double, _ lon: Double, current: Bool = false) -> ChsJob {
        ChsJob(id: id, name: id, region: "test", isCurrent: current, latitude: lat, longitude: lon)
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
        var q = ChsQueue([job("near", 48.43, -123.37), job("gate", 48.5, -123.5, current: true)])
        q.prioritize(lat: 48.4235, lon: -123.3705)
        // A tide port is 9 paced requests; the gate behind it adds 61 more.
        XCTAssertEqual(q.waitSeconds("near"), 9 * 2.5, accuracy: 0.01)
        XCTAssertEqual(q.waitSeconds("gate"), 9 * 2.5 + 61 * 2.5, accuracy: 0.01)
        q.set("near", .ready)
        XCTAssertEqual(q.waitSeconds("gate"), 61 * 2.5, accuracy: 0.01,
                       "a finished station no longer holds anyone up")
        XCTAssertEqual(q.waitSeconds("near"), 0)
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
