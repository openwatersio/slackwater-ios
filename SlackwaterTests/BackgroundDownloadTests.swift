// Slackwater — GPL v3.
import XCTest
@testable import Slackwater

final class BackgroundDownloadTests: XCTestCase {
    private func job(_ id: String, isCurrent: Bool) -> ChsJob {
        ChsJob(id: id, name: id, region: "test", isCurrent: isCurrent,
               latitude: 48.4, longitude: -123.4, fitDays: 60)
    }

    private func tideQueue() -> ChsQueue {
        ChsQueue([job("tide", isCurrent: false)])
    }

    func testRestoredNearbyDownloadsRequestBackgroundProcessing() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNotNil(submission.begin(tier: .nearby, queue: tideQueue(), isForeground: true))
    }

    func testRestoredWidestTierRequestsBackgroundProcessing() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNotNil(submission.begin(tier: .everything, queue: tideQueue(), isForeground: true))
    }

    func testAllCurrentsCanResumeWithoutAWiderTideTier() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNotNil(submission.begin(tier: .inView, allCurrentsSelected: true,
                                         queue: ChsQueue([job("current", isCurrent: true)]), isForeground: true))
    }

    func testAutomaticDownloadsDoNotRequestBackgroundProcessing() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNil(submission.begin(tier: .inView, queue: tideQueue(), isForeground: true))
    }

    func testCompletedCurrentsDoNotAuthorizeAutomaticTideDownloads() {
        var queue = ChsQueue([
            job("current", isCurrent: true), job("tide", isCurrent: false)
        ])
        queue.set("current", .ready)
        var submission = BackgroundDownloadSubmission()
        XCTAssertNil(submission.begin(tier: .inView, allCurrentsSelected: true,
                                      queue: queue, isForeground: true))
    }

    func testFailedCurrentsDoNotAuthorizeAutomaticTideDownloads() {
        var queue = tideQueue()
        queue.add(job("current", isCurrent: true))
        queue.set("current", .failed)
        var submission = BackgroundDownloadSubmission()
        XCTAssertNil(submission.begin(tier: .inView, allCurrentsSelected: true,
                                      queue: queue, isForeground: true))
    }

    func testDownloadingSelectedCurrentCanContinueInTheBackground() {
        var queue = ChsQueue([job("current", isCurrent: true)])
        queue.set("current", .downloading)
        var submission = BackgroundDownloadSubmission()
        XCTAssertNotNil(submission.begin(tier: .inView, allCurrentsSelected: true,
                                         queue: queue, isForeground: true))
    }

    func testSelectedOnlineCurrentsCanResumeWithoutAnyFittedWork() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNotNil(submission.begin(tier: .inView, allCurrentsSelected: true,
                                         queue: ChsQueue(), onlineActive: true, isForeground: true))
    }

    func testAutomaticOnlineCurrentsDoNotRequestBackgroundProcessing() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNil(submission.begin(tier: .inView, queue: ChsQueue(),
                                      onlineActive: true, isForeground: true))
    }

    func testCompletedDownloadsDoNotRequestBackgroundProcessing() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNil(submission.begin(tier: .nearby, queue: ChsQueue(), isForeground: true))
    }

    func testBackgroundLaunchWaitsForTheUserToReturn() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNil(submission.begin(tier: .nearby, queue: tideQueue(), isForeground: false))
        XCTAssertNotNil(submission.begin(tier: .nearby, queue: tideQueue(), isForeground: true))
    }

    func testReturningWithATaskStillInFlightDoesNotDuplicateIt() throws {
        var submission = BackgroundDownloadSubmission()
        let id = try XCTUnwrap(submission.begin(tier: .nearby, queue: tideQueue(), isForeground: true))
        XCTAssertNil(submission.begin(tier: .everything, queue: tideQueue(), isForeground: true))
        XCTAssertEqual(submission.identifier, id)
    }

    func testInterruptedTaskCanBeResubmittedWithAFreshIdentifier() throws {
        var submission = BackgroundDownloadSubmission()
        let interrupted = try XCTUnwrap(submission.begin(tier: .nearby, queue: tideQueue(), isForeground: true))
        submission.finish(interrupted)
        let resumed = try XCTUnwrap(submission.begin(tier: .nearby, queue: tideQueue(), isForeground: true))
        XCTAssertNotEqual(resumed, interrupted)
    }

    func testLateCompletionCannotClearTheResumedTask() throws {
        var submission = BackgroundDownloadSubmission()
        let interrupted = try XCTUnwrap(submission.begin(tier: .nearby, queue: tideQueue(), isForeground: true))
        submission.finish(interrupted)
        let resumed = try XCTUnwrap(submission.begin(tier: .nearby, queue: tideQueue(), isForeground: true))
        submission.finish(interrupted)
        XCTAssertEqual(submission.identifier, resumed)
        XCTAssertNil(submission.begin(tier: .nearby, queue: tideQueue(), isForeground: true))
    }
}
