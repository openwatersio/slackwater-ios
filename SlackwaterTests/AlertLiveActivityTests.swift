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
}
