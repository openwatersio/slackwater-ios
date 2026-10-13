// Slackwater — GPL v3. Live Activity attributes and the face a context resolves to (docs/alerts.md §5.3).
import XCTest
@testable import Slackwater

final class AlertLiveActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private func attrs(end: Date? = nil, noWindow: Bool = false, water: AlertLiveActivityAttributes.Water = .current,
                       heightM: Double? = nil) -> AlertLiveActivityAttributes {
        AlertLiveActivityAttributes(key: "k", ruleID: UUID(), water: water, title: "Race Passage - Slack window",
                                    line: "2:32–3:10 PM, under 0.5 kn", event: now, end: end, noWindow: noWindow,
                                    heightM: heightM, imperial: true, tz: pacific, url: URL(string: "slackwater://station/x"))
    }

    func testTheMomentReadsInTheStationsZone() {
        // Review: the stale face formats `event` in the widget, which must use the station's
        // zone, not the phone's. 1_700_000_000 is 22:13 UTC, 2:13 PM in Los Angeles.
        let text = liveActivityMoment(attrs(water: .tide, heightM: 1), locale: Locale(identifier: "en_US"))
        XCTAssertTrue(text.contains("2:13"), text)
        XCTAssertTrue(text.contains("3.3 ft"), text)
        XCTAssertFalse(liveActivityMoment(attrs(), locale: Locale(identifier: "en_US")).contains("ft"))
    }

    func testAttributesSurviveCoding() throws {
        let a = attrs(end: now.addingTimeInterval(1_800))
        let back = try JSONDecoder().decode(AlertLiveActivityAttributes.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back.key, a.key); XCTAssertEqual(back.end, a.end); XCTAssertEqual(back.url, a.url); XCTAssertEqual(back.tz, pacific)
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
        // Review Focus 3: every pending activity is ended whatever the rules, so losing Premium
        // (an empty plan) clears them; an active one in its window is the sweep's only keeper.
        let r = LiveActivityRecord(key: "p", ruleID: UUID(), pending: true, event: now.addingTimeInterval(60), end: nil)
        XCTAssertEqual(liveActivitiesToEnd([r], liveRuleIDs: [], now: now), ["p"])
    }

    func testTheCountdownRangeNeverRunsBackwards() {
        // Review: a render after `event` with `isStale` not yet true must not trap a ClosedRange.
        let late = liveActivityCountdown(now: now.addingTimeInterval(30), event: now)
        XCTAssertEqual(late.lowerBound, now); XCTAssertEqual(late.upperBound, now)
        let early = liveActivityCountdown(now: now.addingTimeInterval(-30), event: now)
        XCTAssertEqual(early.lowerBound, now.addingTimeInterval(-30))
    }

    func testOnlyEntriesStillAheadOfTheClockAreRequested() {
        // Review: the plan filtered on the pass's start time; a slow resolve can reach the writer
        // after `fire`, and a past start must not be requested.
        func entry(fireIn seconds: TimeInterval) -> AlertEntry {
            let fire = now.addingTimeInterval(seconds)
            return AlertEntry(stationID: "a",
                              occurrence: AlertOccurrence(ruleID: UUID(), event: fire.addingTimeInterval(1_800), fire: fire),
                              copy: AlertCopy(title: "t", body: "b"), url: nil,
                              place: AlertPlace(name: "a", tz: .current))
        }
        let ahead = entry(fireIn: 60), passed = entry(fireIn: -1)
        XCTAssertEqual(liveActivityEntriesAhead([passed, ahead], of: now).map(\.occurrence.key), [ahead.occurrence.key])
    }
}
