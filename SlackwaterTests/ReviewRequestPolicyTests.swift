// Slackwater — GPL v3.
import XCTest
@testable import Slackwater

@MainActor
final class ReviewRequestPolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    override func setUp() async throws {
        suite = "ReviewRequestPolicyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }
    private func day(_ offset: Int) -> Date { start.addingTimeInterval(Double(offset) * 86_400) }
    private func record(_ offset: Int) {
        ReviewRequestPolicy(defaults: defaults).recordForecastUse(at: day(offset), calendar: calendar)
    }
    func testRequiresThreeDistinctDaysAndPersistsAcrossInstances() {
        let policy = ReviewRequestPolicy(defaults: defaults)
        XCTAssertFalse(policy.consumeRequest(version: "1.0", at: day(0)))
        record(0); record(0); record(1); record(0)
        XCTAssertFalse(policy.consumeRequest(version: "1.0", at: day(1)))
        record(2)
        XCTAssertTrue(policy.consumeRequest(version: "1.0", at: day(2)))
        XCTAssertFalse(ReviewRequestPolicy(defaults: defaults).consumeRequest(version: "1.0", at: day(200)))
    }
    func testCooldownAndVersionsBothApplyIncludingVersionRollback() {
        let policy = ReviewRequestPolicy(defaults: defaults)
        record(0); record(1); record(2)
        XCTAssertTrue(policy.consumeRequest(version: "1.0", at: day(2)))
        XCTAssertFalse(policy.consumeRequest(version: "1.1", at: day(1)))
        XCTAssertFalse(policy.consumeRequest(version: "1.1", at: day(122).addingTimeInterval(-1)))
        XCTAssertFalse(policy.consumeRequest(version: "1.0", at: day(122)))
        XCTAssertTrue(policy.consumeRequest(version: "1.1", at: day(122)))
        XCTAssertFalse(policy.consumeRequest(version: "1.0", at: day(242)))
        XCTAssertTrue(policy.consumeRequest(version: "1.2", at: day(242)))
    }
    func testCalendarDayRatherThanElapsedTwentyFourHours() {
        let policy = ReviewRequestPolicy(defaults: defaults)
        let midnight = calendar.startOfDay(for: start)
        policy.recordForecastUse(at: midnight.addingTimeInterval(-1), calendar: calendar)
        policy.recordForecastUse(at: midnight, calendar: calendar)
        XCTAssertFalse(policy.consumeRequest(version: "1", at: day(0)))
        policy.recordForecastUse(at: midnight.addingTimeInterval(86_400), calendar: calendar)
        XCTAssertTrue(policy.consumeRequest(version: "1", at: day(1)))
    }
    func testOnlyALoadedForecastVisitCreatesAnOpportunity() {
        var visit = ReviewRequestVisit()
        visit.navigationChanged(from: 0, to: 1, available: true)
        visit.navigationChanged(from: 1, to: 0, available: true)
        XCTAssertFalse(visit.pending, "waiting and unavailable pages do not qualify")
        visit.navigationChanged(from: 0, to: 1, available: true)
        visit.forecastDidLoad(visitID: visit.id, isNavigating: true, isActive: true)
        visit.navigationChanged(from: 1, to: 0, available: true)
        XCTAssertTrue(visit.pending)
        visit.navigationChanged(from: 0, to: 1, available: true)
        visit.navigationChanged(from: 1, to: 0, available: true)
        XCTAssertFalse(visit.pending, "the previous visit does not qualify this one")
    }
    func testSuppressionCancelsRatherThanDefersAnOpportunity() {
        var visit = ReviewRequestVisit()
        visit.forecastDidLoad(visitID: visit.id, isNavigating: true, isActive: true)
        visit.navigationChanged(from: 1, to: 0, available: true)
        XCTAssertTrue(visit.pending)
        visit.availabilityChanged(false)
        visit.availabilityChanged(true)
        XCTAssertFalse(visit.pending, "closing a sheet or resuming never revives the prompt")
        visit.forecastDidLoad(visitID: visit.id, isNavigating: true, isActive: true)
        visit.navigationChanged(from: 1, to: 0, available: false)
        visit.availabilityChanged(true)
        XCTAssertFalse(visit.pending, "map and removed-station path resets never arm it")
    }

    func testTestFlightAndXcodeDoNotConsumeProductionHistory() {
        let policy = ReviewRequestPolicy(defaults: defaults)
        record(0); record(1); record(2)
        XCTAssertFalse(policy.consumeRequest(version: "1", at: day(2), environment: .sandbox))
        XCTAssertFalse(policy.consumeRequest(version: "1", at: day(2), environment: .xcode))
        XCTAssertTrue(policy.consumeRequest(version: "1", at: day(2), environment: .production))
    }
    func testChangingCalendarDoesNotCountTheSameLocalDayTwice() {
        let policy = ReviewRequestPolicy(defaults: defaults)
        record(0)
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        policy.recordForecastUse(at: day(0), calendar: buddhist)
        record(1)
        XCTAssertFalse(policy.consumeRequest(version: "1", at: day(1)))
        record(2)
        XCTAssertTrue(policy.consumeRequest(version: "1", at: day(2)))
    }

    func testLateLoadAfterPopCannotQualifyTheNextWaitingVisit() {
        var visit = ReviewRequestVisit()
        visit.navigationChanged(from: 1, to: 0, available: true)
        visit.forecastDidLoad(visitID: visit.id, isNavigating: false, isActive: true)
        visit.navigationChanged(from: 0, to: 1, available: true)
        visit.navigationChanged(from: 1, to: 0, available: true)
        XCTAssertFalse(visit.pending)
    }
    func testReplacingAForecastWithAWaitingPageStartsANewVisit() {
        var visit = ReviewRequestVisit()
        visit.forecastDidLoad(visitID: visit.id, isNavigating: true, isActive: true)
        visit.beginVisit()
        visit.navigationChanged(from: 1, to: 0, available: true)
        XCTAssertFalse(visit.pending)
    }

    func testInactiveAndReplacedForecastCallbacksAreRejected() {
        var visit = ReviewRequestVisit()
        let oldID = visit.id
        XCTAssertFalse(visit.forecastDidLoad(visitID: oldID, isNavigating: true, isActive: false))
        visit.beginVisit()
        XCTAssertFalse(visit.forecastDidLoad(visitID: oldID, isNavigating: true, isActive: true))
        XCTAssertFalse(visit.forecastLoaded)
        XCTAssertTrue(visit.forecastDidLoad(visitID: visit.id, isNavigating: true, isActive: true))
        visit.navigationChanged(from: 1, to: 0, available: true)
        XCTAssertFalse(visit.forecastDidLoad(visitID: visit.id, isNavigating: false, isActive: true))
    }

}
