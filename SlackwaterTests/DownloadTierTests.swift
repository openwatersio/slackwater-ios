// Slackwater — GPL v3. Tiers are stopping points on one distance-sorted
// queue, and the cohort is what makes the in-view tier a fixed set rather
// than a moving target.
import XCTest
@testable import Slackwater

final class DownloadTierTests: XCTestCase {
    private let victoria = (lat: 48.4284, lon: -123.3656)

    private func job(_ id: String, _ lat: Double, _ lon: Double) -> ChsJob {
        ChsJob(id: id, name: id, region: "test", isCurrent: false,
               latitude: lat, longitude: lon, fitDays: 60)
    }

    func testInViewAdmitsOnlyTheCohort() {
        let inside = job("a", 48.43, -123.37)
        let outside = job("b", 48.44, -123.38)
        let cohort: Set<String> = ["a"]
        XCTAssertTrue(DownloadTier.inView.admits(inside, from: victoria, cohort: cohort))
        XCTAssertFalse(DownloadTier.inView.admits(outside, from: victoria, cohort: cohort),
                       "proximity must not smuggle a station into the automatic tier")
    }

    func testNearbyAdmitsInsideTwentyFiveKilometresAndTheCohort() {
        let close = job("close", 48.50, -123.40)          // ~9 km
        let far = job("far", 49.28, -123.12)              // ~95 km, Vancouver
        XCTAssertTrue(DownloadTier.nearby.admits(close, from: victoria, cohort: []))
        XCTAssertFalse(DownloadTier.nearby.admits(far, from: victoria, cohort: []))
        XCTAssertTrue(DownloadTier.nearby.admits(far, from: victoria, cohort: ["far"]),
                      "a station already on screen stays admitted at every tier")
    }

    func testEverythingAdmitsOutToTheExistingRadius() {
        let reachable = job("reachable", 49.28, -123.12)   // ~95 km, Vancouver
        let halifax = job("halifax", 44.6488, -63.5752)
        XCTAssertTrue(DownloadTier.everything.admits(reachable, from: victoria, cohort: []))
        XCTAssertFalse(DownloadTier.everything.admits(halifax, from: victoria, cohort: []),
                       "the widest tier still stops at the existing radius")
    }

    func testNearbyRadiusIsTwentyFive() {
        XCTAssertEqual(DownloadTier.nearbyRadiusKm, 25)
    }

    func testTiersAdvanceThroughBothOffers() {
        XCTAssertEqual(DownloadTier.inView.next, .nearby)
        XCTAssertEqual(DownloadTier.nearby.next, .everything)
        XCTAssertNil(DownloadTier.everything.next)
    }

    func testCohortIsCapturedOnceAndIgnoresLaterReRanking() {
        var cohort = DownloadCohort()
        XCTAssertTrue(cohort.capture(ids: ["a", "b"], heroID: "a"))
        XCTAssertEqual(cohort.ids, ["a", "b"])

        // A fix moves a few metres: same place, list re-ranks, cohort holds.
        XCTAssertFalse(cohort.capture(ids: ["b", "a", "c"], heroID: "a"))
        XCTAssertEqual(cohort.ids, ["a", "b"],
                       "fix jitter must not grow the automatic tier")
    }

    func testCohortIsRecapturedWhenThePlaceChanges() {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["a", "b"], heroID: "a")
        XCTAssertTrue(cohort.capture(ids: ["x", "y"], heroID: "x"),
                      "a new nearest station is a new place and a new question")
        XCTAssertEqual(cohort.ids, ["x", "y"])
    }

    func testCohortIsSettledOnlyWhenEveryMemberIsDone() {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["a", "b"], heroID: "a")

        var queue = ChsQueue([job("a", 48.43, -123.37), job("b", 48.44, -123.38)])
        XCTAssertFalse(cohort.settled(in: queue))

        queue.set("a", .ready)
        XCTAssertFalse(cohort.settled(in: queue))

        // Failed counts as done: another attempt gets the same answer, and the
        // user should not be held at "downloading" by a station that cannot.
        queue.set("b", .failed)
        XCTAssertTrue(cohort.settled(in: queue))
    }

    func testJobsAddedAfterCaptureDoNotUnsettleTheCohort() {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["a"], heroID: "a")
        var queue = ChsQueue([job("a", 48.43, -123.37)])
        queue.set("a", .ready)
        XCTAssertTrue(cohort.settled(in: queue))

        queue.add(job("later", 49.0, -123.0))
        XCTAssertTrue(cohort.settled(in: queue),
                      "accepting a wider tier must not re-open the question")
    }

    func testAnEmptyCohortIsNotSettled() {
        let cohort = DownloadCohort()
        XCTAssertFalse(cohort.settled(in: ChsQueue()),
                       "nothing captured yet is not the same as finished")
    }

    func testCohortSettlesEvenWhenSomeStationsAreNotDownloadable() {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["chs-a", "noaa-b"], heroID: "chs-a")
        var queue = ChsQueue([job("chs-a", 48.43, -123.37)])
        XCTAssertFalse(cohort.settled(in: queue))
        queue.set("chs-a", .ready)
        XCTAssertTrue(cohort.settled(in: queue),
                      "a NOAA station has no CHS job and can never be downloading")
    }

    func testCohortWithNoHeroRecapturesWhenTheListChanges() {
        var cohort = DownloadCohort()
        XCTAssertTrue(cohort.capture(ids: ["a", "b"], heroID: nil))
        XCTAssertFalse(cohort.capture(ids: ["b", "a"], heroID: nil),
                       "the same set in a different order is not a change")
        XCTAssertTrue(cohort.capture(ids: ["c", "d"], heroID: nil),
                      "with no hero, a genuinely different list is a new cohort")
        XCTAssertEqual(cohort.ids, ["c", "d"])
    }

    private func settledQueue() -> (DownloadCohort, ChsQueue) {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["a"], heroID: "a")
        var queue = ChsQueue([job("a", 48.43, -123.37)])
        queue.set("a", .ready)
        return (cohort, queue)
    }

    func testStripWorksWhileTheCohortIsDownloading() {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["a", "b"], heroID: "a")
        var queue = ChsQueue([job("a", 48.43, -123.37), job("b", 48.44, -123.38)])
        queue.set("a", .ready)
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: false, remaining: 14),
                       .working(done: 1, total: 2, progress: 5))

        queue.set("b", .downloading)
        queue.setProgress("b", done: 5, total: 10)
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: false, remaining: 14),
                       .working(done: 1, total: 2, progress: 7.5))
    }

    func testStripAsksOnceTheCohortIsSettled() {
        let (cohort, queue) = settledQueue()
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: false, remaining: 14),
                       .asking(count: 14))
    }

    func testStripStaysVisibleForANonCohortDownloadAtTheInViewTier() {
        let (cohort, settled) = settledQueue()
        var queue = settled
        queue.add(job("detail", 48.44, -123.38))
        queue.set("detail", .downloading)
        queue.setProgress("detail", done: 5, total: 10)

        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: false, remaining: 14),
                       .working(done: 1, total: 2, progress: 7.5))
    }

    func testRestoredWiderTierShowsAnActiveQueueWithoutACohort() {
        let cohort = DownloadCohort()
        var queue = ChsQueue([job("restored", 48.44, -123.38)])
        queue.set("restored", .downloading)
        queue.setProgress("restored", done: 5, total: 10)

        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .nearby,
                                          declined: false, remaining: 14),
                       .working(done: 0, total: 1, progress: 5))
    }

    func testStripIsAbsentWhenDeclined() {
        let (cohort, queue) = settledQueue()
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: true, remaining: 14),
                       .absent)
    }

    func testStripIsAbsentWithNothingLeftToOffer() {
        let (cohort, queue) = settledQueue()
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: false, remaining: 0),
                       .absent)
    }

    func testStripAsksForEverythingOnceNearbyIsSettled() {
        let (cohort, queue) = settledQueue()
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .nearby,
                                          declined: false, remaining: 14),
                       .asking(count: 14))
    }

    func testStripStaysVisibleWhileNearbyDownloads() {
        let (cohort, settled) = settledQueue()
        var queue = settled
        queue.add(job("b", 48.44, -123.38))
        queue.set("b", .downloading)
        queue.setProgress("b", done: 5, total: 10)
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .nearby,
                                          declined: false, remaining: 14),
                       .working(done: 1, total: 2, progress: 7.5))
    }

    func testStripEndsAfterTheWidestTier() {
        let (cohort, queue) = settledQueue()
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .everything,
                                          declined: false, remaining: 14),
                       .absent)
    }

    func testStripCountsOnlineGatesLikeTheLiveActivity() {
        let (cohort, settled) = settledQueue()
        var queue = settled
        queue.add(job("b", 48.44, -123.38))
        let online = OnlineDownloads(ready: 6, total: 6, requestsCompleted: 6, requestsRemaining: 0)
        let requests = queue.requestProgress
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, online: online, tier: .nearby,
                                          declined: false, remaining: 14),
                       .working(done: 7, total: 8, progress: (requests.completed + 6) / (requests.total + 6) * 10),
                       "the strip and the Live Activity must show the same numbers")
    }

    func testStripWorksForOnlineOnlyDownloads() {
        let (cohort, queue) = settledQueue()
        let online = OnlineDownloads(ready: 0, total: 2, requestsCompleted: 0, requestsRemaining: 4,
                                     active: true, inFlight: true)
        guard case let .working(done, total, _) = downloadStripState(
            cohort: cohort, queue: queue, online: online, tier: .everything, declined: false, remaining: 0)
        else { return XCTFail("an online fetch in flight is a download, so the strip shows it") }
        XCTAssertEqual(done, 1)
        XCTAssertEqual(total, 3)
    }

    func testStripSaysWaitingWhenOnlyARetryRemains() {
        let (cohort, settled) = settledQueue()
        var queue = settled
        queue.add(job("b", 48.44, -123.38))
        queue.deferRetry("b", error: "HTTP 503")
        guard case let .waiting(done, total, _) = downloadStripState(
            cohort: cohort, queue: queue, tier: .nearby, declined: false, remaining: 14)
        else { return XCTFail("a backoff with nothing downloading is a stall, and the strip must say why") }
        XCTAssertEqual(done, 1)
        XCTAssertEqual(total, 2)

        let deferredGate = OnlineDownloads(total: 1, requestsRemaining: 2, active: true, inFlight: true, deferred: true)
        guard case .waiting = downloadStripState(
            cohort: cohort, queue: settled, online: deferredGate, tier: .nearby, declined: false, remaining: 14)
        else { return XCTFail("an online gate's backoff stalls the count the same way") }
    }

    func testStripKeepsCountingWhileARetryWaitsBehindOtherWork() {
        let (cohort, settled) = settledQueue()
        var queue = settled
        queue.add(job("b", 48.44, -123.38))
        queue.add(job("c", 48.45, -123.39))
        queue.deferRetry("b", error: "HTTP 503")
        guard case .working = downloadStripState(
            cohort: cohort, queue: queue, tier: .nearby, declined: false, remaining: 14)
        else { return XCTFail("a job due next is not a stall, even before the run claims it") }
        queue.set("c", .downloading)
        guard case .working = downloadStripState(
            cohort: cohort, queue: queue, tier: .nearby, declined: false, remaining: 14)
        else { return XCTFail("while anything downloads the count is moving, so it is the thing to show") }

        let fetching = OnlineDownloads(total: 1, requestsRemaining: 2, active: true, inFlight: true, moving: true)
        var waiting = settled
        waiting.add(job("b", 48.44, -123.38))
        waiting.deferRetry("b", error: "HTTP 503")
        XCTAssertFalse(DownloadCount(queue: waiting, online: fetching).waitingToRetry,
                       "an online fetch in progress is also movement")
    }

    func testOfflineOnlineGatesDoNotHideTheOffer() {
        let (cohort, queue) = settledQueue()
        let waiting = OnlineDownloads(ready: 0, total: 4, requestsCompleted: 0, requestsRemaining: 8,
                                      active: true, inFlight: false)
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, online: waiting, tier: .inView,
                                          declined: false, remaining: 14),
                       .asking(count: 14),
                       "gates waiting for signal keep the background task alive, but nothing is downloading")
    }

    func testWorkingCounterOnlyIncludesDownloadableStations() {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["chs-a", "noaa-b"], heroID: "chs-a")
        let queue = ChsQueue([job("chs-a", 48.43, -123.37)])
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: false, remaining: 5),
                       .working(done: 0, total: 1, progress: 0),
                       "the NOAA station has no job, so it is outside the queue counter")
    }

    @MainActor
    func testAutoFitSetStopsAtTheActiveTier() {
        let cohort: Set<String> = []
        let inView = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon,
                                              tier: .inView, cohort: cohort)
        XCTAssertTrue(inView.isEmpty,
                      "with nothing captured the automatic tier downloads nothing")

        let nearby = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon,
                                              tier: .nearby, cohort: cohort)
        let everything = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon,
                                                  tier: .everything, cohort: cohort)
        XCTAssertGreaterThan(nearby.count, 0)
        XCTAssertGreaterThan(everything.count, nearby.count,
                             "the widest tier has no ceiling")
        XCTAssertTrue(nearby.allSatisfy {
            distanceKm($0.latitude, $0.longitude, victoria.lat, victoria.lon)
                <= DownloadTier.nearbyRadiusKm
        })
    }

    @MainActor
    func testTheCohortIsDownloadedAtTheAutomaticTier() {
        let all = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon,
                                           tier: .everything, cohort: [])
        guard let first = all.first else { return XCTFail("no CHS candidates bundled") }
        let inView = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon,
                                              tier: .inView, cohort: [first.id])
        XCTAssertEqual(inView.map(\.id), [first.id])
    }
}
