// Slackwater — GPL v3. Direct tests for slackWindow (SlackWindow.swift):
// interpolated sub-threshold span, clamping, and the no-window cases.
import SwiftUI
import XCTest
@testable import Slackwater
import SlackwaterKit

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

    // MARK: - Runs and axis moments (shared by the card and the strip)

    /// Touching or overlapping windows are one run (current-charts spec §4.3);
    /// a gap keeps two runs apart.
    func testMergeWindowsJoinsTouchingAndOverlappingRuns() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let s = { (m: Double) in t0.addingTimeInterval(m * 60) }
        let runs = mergeWindows([(start: s(50), end: s(120)),
                                 (start: s(110), end: s(220)),   // overlaps
                                 (start: s(220), end: s(340)),   // touches
                                 (start: s(500), end: s(700))])  // gap
        XCTAssertEqual(runs, [WindowRun(start: s(50), end: s(340)),
                              WindowRun(start: s(500), end: s(700))])
    }

    /// The card prints one time per run under its mark: a stroke at its opening, a dot at its centre,
    /// judged at the card's own scale rather than the strip's.
    func testTheCardPrintsEachRunWhereItDrawsTheRun() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let s = { (m: Double) in t0.addingTimeInterval(m * 60) }
        let cardPPH: CGFloat = 350 / CGFloat(StationCardGraph.window / 3600)
        let stroke = WindowRun(start: s(50), end: s(340))
        let dot = WindowRun(start: s(500), end: s(520))
        XCTAssertFalse(dot.isDot, "a run the strip strokes")
        XCTAssertEqual(StationCardGraph.axisMoments([dot, stroke], pointsPerHour: cardPPH), [s(50), s(510)])

        for run in [stroke, dot] {
            var path = Path()
            path.move(to: CGPoint(x: 10, y: 40))
            path.addLine(to: CGPoint(x: 10 + CGFloat(run.end.timeIntervalSince(run.start) / 3600) * cardPPH, y: 40))
            XCTAssertEqual(CurveDrawing.isDot(path), run.drawsAsDot(pointsPerHour: cardPPH),
                           "the card draws \(run) one way and times it the other")
        }
    }

    /// A dot is one mark, so it is one magnet stop and one event time, at its centre.
    func testADotRunIsOneMomentAtItsCentre() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let s = { (sec: Double) in t0.addingTimeInterval(sec) }
        let dot = WindowRun(start: s(200), end: s(800))
        XCTAssertTrue(dot.isDot)
        XCTAssertEqual(dot.centre, s(500))
        XCTAssertEqual(dot.snapMoments, [s(500)])
        XCTAssertEqual(dot.axisMoment, s(500))

        let wide = WindowRun(start: s(10_000), end: s(12_000))
        XCTAssertFalse(wide.isDot)
        XCTAssertEqual(wide.snapMoments, [s(10_000), s(12_000)])
        XCTAssertEqual(wide.axisMoment, s(10_000))

        let snaps = TimelineData.currentSnapTimes(
            events: [CurrentEvent(time: s(600), speed: 0, kind: .slack),
                     CurrentEvent(time: s(5000), speed: 2, kind: .maxFlood),
                     CurrentEvent(time: s(11_000), speed: 0, kind: .slack)],
            windows: [(slack: s(600), start: s(200), end: s(800)),
                      (slack: s(11_000), start: s(10_000), end: s(12_000))])
        XCTAssertEqual(snaps.sorted(), [s(500), s(5000), s(10_000), s(11_000), s(12_000)])
    }

    /// Data that disagreed with the drawing would name two stops around one dot, or one stop on a stroke.
    func testTheDotTestMatchesTheDrawnRun() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        for seconds in [60.0, 990, 999, 1001, 1010, 3600] {
            let run = WindowRun(start: t0, end: t0.addingTimeInterval(seconds))
            var path = Path()
            path.move(to: CGPoint(x: 100, y: 40))
            path.addLine(to: CGPoint(x: 100 + CGFloat(seconds / 3600) * Timeline.pph, y: 40))
            XCTAssertEqual(CurveDrawing.isDot(path), run.isDot, "a \(seconds) s run")
        }
    }

    /// A fast reversal whose bracketing samples are both outside the band, at
    /// unequal speeds: the window is where the straight line between them is
    /// within ±threshold.
    func testFastReversalOutsideTheBandHasAnInterpolatedWindow() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = [CurrentPoint(time: t0, speed: 3),
                   CurrentPoint(time: t0.addingTimeInterval(600), speed: 1.5),
                   CurrentPoint(time: t0.addingTimeInterval(1200), speed: -1),
                   CurrentPoint(time: t0.addingTimeInterval(1800), speed: -3)]
        let w = try XCTUnwrap(slackWindow(pts, around: t0.addingTimeInterval(960), threshold: 0.5))
        // v = 1.5 − 2.5·f over the segment: +0.5 at f = 0.4, −0.5 at f = 0.8.
        XCTAssertEqual(w.start.timeIntervalSince(t0), 840, accuracy: 0.01)
        XCTAssertEqual(w.end.timeIntervalSince(t0), 1080, accuracy: 0.01)
    }

    /// Two samples on the same side of zero bracket no reversal, so a slack
    /// placed between them still has no window.
    func testSameSignSamplesOutsideTheBandHaveNoWindow() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = [CurrentPoint(time: t0, speed: -2),
                   CurrentPoint(time: t0.addingTimeInterval(600), speed: -1)]
        XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(300), threshold: 0.5))
    }
}
