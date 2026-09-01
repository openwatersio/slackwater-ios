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

    // MARK: - The card graph's runs (cardWindows)

    /// A curve that stays under the threshold across two slacks: the two
    /// windows overlap and must merge into one run (current-charts spec §4.3).
    func testCardWindowsMergeOverlappingRuns() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // Gentle wave: ±0.3 kn, crossing zero at 1200 and 3600.
        let speeds: [Double] = [0.3, 0.1, -0.1, -0.3, -0.1, 0.1, 0.3]
        let pts = speeds.enumerated().map {
            CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 600), speed: $0.element)
        }
        let wins = cardWindows(points: pts,
                               slacks: [t0.addingTimeInterval(1200), t0.addingTimeInterval(3600)],
                               threshold: 0.5)
        XCTAssertEqual(wins.count, 1, "sub-threshold runs across two slacks must merge")
    }

    /// Distinct windows stay distinct, with interpolated ±threshold edges.
    func testCardWindowsKeepSeparateRunsApart() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // Two V-shaped crossings separated by fast water.
        let speeds: [Double] = [-1, 0, 1, 2, 1, 0, -1]
        let pts = speeds.enumerated().map {
            CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 600), speed: $0.element)
        }
        let wins = cardWindows(points: pts,
                               slacks: [t0.addingTimeInterval(600), t0.addingTimeInterval(3000)],
                               threshold: 0.5)
        XCTAssertEqual(wins.count, 2)
        // Threshold 0.5 crosses halfway down each unit leg: ±300 s of each slack.
        XCTAssertEqual(wins[0].start.timeIntervalSince(t0), 300, accuracy: 1)
        XCTAssertEqual(wins[0].end.timeIntervalSince(t0), 900, accuracy: 1)
    }
}
