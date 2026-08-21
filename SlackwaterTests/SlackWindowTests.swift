// Slackwater — GPL v3. Direct tests for slackWindow (SlackWindow.swift):
// interpolated sub-threshold span, clamping, and the no-window cases.
import XCTest
@testable import Slackwater
import TideEngine

final class SlackWindowTests: XCTestCase {
    /// Symmetric V through zero: -1 kn at t0, 0 at t0+600, +1 at t0+1200.
    /// Threshold 0.5 crosses halfway down each leg.
    func testInterpolatedWindow() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = [CurrentPoint(time: t0, speed: -1),
                   CurrentPoint(time: t0.addingTimeInterval(600), speed: 0),
                   CurrentPoint(time: t0.addingTimeInterval(1200), speed: 1)]
        let w = slackWindow(pts, around: t0.addingTimeInterval(600), threshold: 0.5)!
        XCTAssertEqual(w.start.timeIntervalSince(t0), 300, accuracy: 1)
        XCTAssertEqual(w.end.timeIntervalSince(t0), 900, accuracy: 1)
    }

    func testSlackOutsideSeriesHasNoWindow() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = [CurrentPoint(time: t0, speed: -1),
                   CurrentPoint(time: t0.addingTimeInterval(600), speed: 1)]
        XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(7200), threshold: 0.5))
    }

    func testNeverSubThresholdHasNoWindow() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0..<5).map { CurrentPoint(time: t0.addingTimeInterval(Double($0) * 600),
                                             speed: 2.0) }
        XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(1200), threshold: 0.5))
    }
}
