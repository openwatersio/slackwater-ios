// Slackwater — GPL v3. WidgetSnapshot: next event, slack window, and a
// normalized day-curve — deterministic given (station, now).
import XCTest
@testable import Slackwater
import TideEngine

final class WidgetSnapshotTests: XCTestCase {
    var friday: WidgetStation { WidgetStationLoader.load(id: TideStationRecord.fridayHarborID)! }
    var current: WidgetStation {
        WidgetStationLoader.load(id: "current:" + CurrentStationRecord.all.first!.id)!
    }

    func testTideNextEventIsFuture() {
        let now = Date()
        let s = WidgetSnapshot.build(friday, now: now)
        XCTAssertNotNil(s.next)
        XCTAssert(s.next!.time > now)
        XCTAssert(s.next!.label.hasPrefix("High") || s.next!.label.hasPrefix("Low"))
    }

    func testCurrentNextEventAndWindow() {
        let s = WidgetSnapshot.build(current, now: Date())
        XCTAssertNotNil(s.next)
        // A slack inside the sampled day gets its 0.5 kn window attached.
        if s.next!.label == "Slack" { XCTAssertNotNil(s.window) }
    }

    func testSparklineShape() {
        let s = WidgetSnapshot.build(friday, now: Date())
        XCTAssertEqual(s.sparkline.count, 97)
        XCTAssert(s.sparkline.allSatisfy { (0.0...1.0).contains($0) })
        XCTAssert((0.0...1.0).contains(s.nowFraction))
    }

    func testDeterministic() {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        XCTAssertEqual(WidgetSnapshot.build(friday, now: now),
                       WidgetSnapshot.build(friday, now: now))
    }
}
