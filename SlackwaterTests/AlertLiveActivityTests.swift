// Slackwater — GPL v3. Live Activity attributes and the face a context resolves to (docs/alerts.md §5.3).
import XCTest
@testable import Slackwater

final class AlertLiveActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func attrs(end: Date? = nil, noWindow: Bool = false, water: AlertLiveActivityAttributes.Water = .current) -> AlertLiveActivityAttributes {
        AlertLiveActivityAttributes(key: "k", ruleID: UUID(), water: water, title: "Race Passage - Slack window",
                                    line: "2:32–3:10 PM, under 0.5 kn", event: now, end: end, noWindow: noWindow,
                                    heightM: nil, imperial: true, url: URL(string: "slackwater://station/x"))
    }

    func testAttributesSurviveCoding() throws {
        let a = attrs(end: now.addingTimeInterval(1_800))
        let back = try JSONDecoder().decode(AlertLiveActivityAttributes.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back.key, a.key); XCTAssertEqual(back.end, a.end); XCTAssertEqual(back.url, a.url)
    }

    func testTheFaceCountsDownUntilStaleThenOpensAWindow() {
        let window = attrs(end: now.addingTimeInterval(1_800))
        XCTAssertEqual(liveActivityFace(window, stale: false), .countdown)
        XCTAssertEqual(liveActivityFace(window, stale: true), .open)
    }

    func testAMomentWithoutAWindowNamesItselfWhenStale() {
        XCTAssertEqual(liveActivityFace(attrs(end: nil, water: .tide), stale: true), .moment)
        // Review Focus 5: a hairline slack has an `end` of nil and `noWindow`; never "Open".
        XCTAssertEqual(liveActivityFace(attrs(end: nil, noWindow: true), stale: true), .moment)
    }

    func testTheSweepEndsPendingPastAndOrphanedActivitiesOnly() {
        let keep = UUID(), gone = UUID()
        let records = [
            LiveActivityRecord(key: "pending", ruleID: keep, pending: true, event: now.addingTimeInterval(3_600), end: nil),
            LiveActivityRecord(key: "active-open", ruleID: keep, pending: false, event: now.addingTimeInterval(-600), end: now.addingTimeInterval(1_200)),
            LiveActivityRecord(key: "active-countdown", ruleID: keep, pending: false, event: now.addingTimeInterval(900), end: nil),
            LiveActivityRecord(key: "closed", ruleID: keep, pending: false, event: now.addingTimeInterval(-7_200), end: now.addingTimeInterval(-3_600)),
            LiveActivityRecord(key: "moment-passed", ruleID: keep, pending: false, event: now.addingTimeInterval(-60), end: nil),
            LiveActivityRecord(key: "orphan", ruleID: gone, pending: false, event: now.addingTimeInterval(-60), end: now.addingTimeInterval(1_800)),
        ]
        XCTAssertEqual(Set(liveActivitiesToEnd(records, liveRuleIDs: [keep], now: now)),
                       ["pending", "closed", "moment-passed", "orphan"])
    }

    func testLosingEveryRuleEndsEverything() {
        // Review Focus 3: no Premium means no live rules in the plan, and pending ones go.
        let r = LiveActivityRecord(key: "p", ruleID: UUID(), pending: true, event: now.addingTimeInterval(60), end: nil)
        XCTAssertEqual(liveActivitiesToEnd([r], liveRuleIDs: [], now: now), ["p"])
    }
}
