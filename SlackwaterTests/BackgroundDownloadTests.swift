// Slackwater — GPL v3.
import XCTest
@testable import Slackwater

final class BackgroundDownloadTests: XCTestCase {
    func testRestoredNearbyDownloadsRequestBackgroundProcessing() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNotNil(submission.begin(tier: .nearby, hasWork: true, isForeground: true))
    }

    func testRestoredWidestTierRequestsBackgroundProcessing() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNotNil(submission.begin(tier: .everything, hasWork: true, isForeground: true))
    }

    func testAllCurrentsCanResumeWithoutAWiderTideTier() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNotNil(submission.begin(tier: .inView, allCurrentsSelected: true,
                                         hasWork: true, isForeground: true))
    }

    func testAutomaticDownloadsDoNotRequestBackgroundProcessing() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNil(submission.begin(tier: .inView, hasWork: true, isForeground: true))
    }

    func testCompletedDownloadsDoNotRequestBackgroundProcessing() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNil(submission.begin(tier: .nearby, hasWork: false, isForeground: true))
    }

    func testBackgroundLaunchWaitsForTheUserToReturn() {
        var submission = BackgroundDownloadSubmission()
        XCTAssertNil(submission.begin(tier: .nearby, hasWork: true, isForeground: false))
        XCTAssertNotNil(submission.begin(tier: .nearby, hasWork: true, isForeground: true))
    }

    func testReturningWithATaskStillInFlightDoesNotDuplicateIt() throws {
        var submission = BackgroundDownloadSubmission()
        let id = try XCTUnwrap(submission.begin(tier: .nearby, hasWork: true, isForeground: true))
        XCTAssertNil(submission.begin(tier: .everything, hasWork: true, isForeground: true))
        XCTAssertEqual(submission.identifier, id)
    }

    func testInterruptedTaskCanBeResubmittedWithAFreshIdentifier() throws {
        var submission = BackgroundDownloadSubmission()
        let interrupted = try XCTUnwrap(submission.begin(tier: .nearby, hasWork: true, isForeground: true))
        submission.finish(interrupted)
        let resumed = try XCTUnwrap(submission.begin(tier: .nearby, hasWork: true, isForeground: true))
        XCTAssertNotEqual(resumed, interrupted)
    }

    func testLateCompletionCannotClearTheResumedTask() throws {
        var submission = BackgroundDownloadSubmission()
        let interrupted = try XCTUnwrap(submission.begin(tier: .nearby, hasWork: true, isForeground: true))
        submission.finish(interrupted)
        let resumed = try XCTUnwrap(submission.begin(tier: .nearby, hasWork: true, isForeground: true))
        submission.finish(interrupted)
        XCTAssertEqual(submission.identifier, resumed)
        XCTAssertNil(submission.begin(tier: .nearby, hasWork: true, isForeground: true))
    }
}
