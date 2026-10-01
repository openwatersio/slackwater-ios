// Slackwater — GPL v3. One snap rule for both scrub hosts (#522).
import XCTest
@testable import Slackwater

final class TimelineSnapTests: XCTestCase {
    private func friday() throws -> TimelineData {
        let record = try XCTUnwrap(TideStationRecord.record(id: TideStationRecord.fridayHarborID))
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        return TimelineData.build(tide: record, current: nil, now: at, anchor: at)
    }

    func testMagnetTargetPullsTheNearestStopInReach() throws {
        let tl = try friday()
        let stop = try XCTUnwrap(tl.snapTimes.dropFirst(3).first)
        XCTAssertEqual(tl.magnetTarget(nearX: tl.x(stop) + 20), stop)
    }

    func testMagnetTargetIgnoresStopsOutOfReach() throws {
        let tl = try friday()
        // The midpoint of the widest gap between stops is as far from any stop as it gets.
        let pairs = zip(tl.snapTimes, tl.snapTimes.dropFirst())
        let gap = try XCTUnwrap(pairs.max { $0.1.timeIntervalSince($0.0) < $1.1.timeIntervalSince($1.0) })
        let mid = (tl.x(gap.0) + tl.x(gap.1)) / 2
        XCTAssertGreaterThan(tl.x(gap.1) - mid, Timeline.magnetPts)
        XCTAssertNil(tl.magnetTarget(nearX: mid))
    }

    func testMagnetTargetIsNilWhenAlreadyParked() throws {
        let tl = try friday()
        let stop = try XCTUnwrap(tl.snapTimes.dropFirst(3).first)
        XCTAssertNil(tl.magnetTarget(nearX: tl.x(stop) + 0.2))
    }

    func testReanchorOnlyOutsideTheWindow() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let anchor = dayLocal(Date(timeIntervalSince1970: 1_790_000_000), tz)
        let w = Timeline.window(anchor: anchor)
        XCTAssertNil(Timeline.reanchor(settledAt: w.start.addingTimeInterval(3_600), anchor: anchor, tz: tz))
        XCTAssertNil(Timeline.reanchor(settledAt: w.end, anchor: anchor, tz: tz))
        let beyond = w.end.addingTimeInterval(3_600)
        XCTAssertEqual(Timeline.reanchor(settledAt: beyond, anchor: anchor, tz: tz), dayLocal(beyond, tz))
        let before = w.start.addingTimeInterval(-3_600)
        XCTAssertEqual(Timeline.reanchor(settledAt: before, anchor: anchor, tz: tz), dayLocal(before, tz))
    }
}
