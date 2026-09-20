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
                       .working(done: 1, total: 2))
    }

    func testStripAsksOnceTheCohortIsSettled() {
        let (cohort, queue) = settledQueue()
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: false, remaining: 14),
                       .asking(count: 14))
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

    func testStripDoesNotAskAgainOnceAWiderTierIsAccepted() {
        let (cohort, queue) = settledQueue()
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .nearby,
                                          declined: false, remaining: 14),
                       .absent,
                       "the question belongs to the in-view tier only")
    }
}
