// Slackwater — GPL v3. Direct tests for slackWindow (SlackWindow.swift):
// interpolated sub-threshold span, clamping, and the no-window cases.
import SwiftUI
import XCTest
@testable import Slackwater
import SlackwaterKit

final class SlackWindowTests: XCTestCase {
    @MainActor
    func testExampleKeepsZeroMarkWithComfortOnAndOff() throws {
        for threshold in [0.0, 0.5] {
            let image = try XCTUnwrap(ImageRenderer(content:
                SlackWindowPreview(threshold: threshold)
                    .frame(width: 360, height: 140)
                    .background(.black)
                    .preferredColorScheme(.dark)).uiImage)
            let cg = try XCTUnwrap(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            let green = stride(from: 0, to: pixels.count, by: 4).filter {
                Int(pixels[$0 + 1]) > Int(pixels[$0]) + 20
                    && Int(pixels[$0]) > Int(pixels[$0 + 2]) + 20
            }
            XCTAssertFalse(green.isEmpty, "the zero mark disappeared with comfort current \(threshold)")
            let attachment = XCTAttachment(image: image)
            attachment.name = "comfort-\(threshold)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testSlackIsOnlyTheZeroInstantRegardlessOfComfortCurrent() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let slack = t0.addingTimeInterval(600)
        let points = [CurrentPoint(time: t0, speed: -1),
                      CurrentPoint(time: slack, speed: 0),
                      CurrentPoint(time: t0.addingTimeInterval(1200), speed: 1)]
        for threshold in [0.0, 0.1, 0.5, 2] {
            let measured = measureSlacks(points, slacks: [slack], threshold: threshold)
            let cores = mergeWindows(measured.cores.map { (start: $0.start, end: $0.end) })
            XCTAssertTrue(cores.isEmpty, "zero has no duration at comfort current \(threshold)")
            XCTAssertTrue(readsSlack(at: slack, runs: cores, slacks: [slack]))
            XCTAssertFalse(readsSlack(at: slack.addingTimeInterval(30), runs: cores, slacks: [slack]))
            XCTAssertEqual(measured.windows.isEmpty, threshold == 0)
            XCTAssertEqual(slackCoreThresholdKn(threshold), 0)
        }
    }

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

    /// One sample inside the band and one outside it across the reversal: the
    /// edge is where the signed line meets −0.15, not a mirrored speed (#826 review).
    func testAnEdgeAcrossTheReversalCrossesOnTheOutsideSamplesSide() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = [CurrentPoint(time: t0, speed: -1),
                   CurrentPoint(time: t0.addingTimeInterval(600), speed: 0.1),
                   CurrentPoint(time: t0.addingTimeInterval(1200), speed: 1)]
        let w = slackWindow(pts, around: t0.addingTimeInterval(545.45), threshold: 0.15)!
        XCTAssertEqual(w.start.timeIntervalSince(t0), 463.64, accuracy: 0.1)
        XCTAssertEqual(w.end.timeIntervalSince(t0), 633.33, accuracy: 0.1)
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

    /// The card prints one time per mark: a drawn window at its opening, and a slack
    /// mark outside every drawn window at its own time — a core dot at its centre,
    /// judged at the card's own scale rather than the strip's, and a slack no core holds at its instant.
    func testTheCardPrintsEachRunWhereItDrawsTheRun() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let s = { (m: Double) in t0.addingTimeInterval(m * 60) }
        let cardPPH: CGFloat = 350 / CGFloat(StationCardGraph.window / 3600)
        let stroke = WindowRun(start: s(50), end: s(340))
        let dot = WindowRun(start: s(500), end: s(520))
        let core = WindowRun(start: s(505), end: s(515))
        XCTAssertFalse(dot.isDot, "a run the strip strokes")
        XCTAssertTrue(dot.drawsAsDot(pointsPerHour: cardPPH), "the card draws the same run as a dot")
        XCTAssertEqual(StationCardGraph.axisMoments([dot, stroke], cores: [core], slacks: [s(200), s(510), s(900)],
                                                    pointsPerHour: cardPPH),
                       [s(50), s(510), s(900)],
                       "a slack inside a drawn window is the window's; a window too short to draw gives way to its core's dot")

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

        // A window too short to draw has no stops; its core's dot is the one stop.
        let snaps = TimelineData.currentSnapTimes(
            events: [CurrentEvent(time: s(600), speed: 0, kind: .slack),
                     CurrentEvent(time: s(5000), speed: 2, kind: .maxFlood),
                     CurrentEvent(time: s(11_000), speed: 0, kind: .slack)],
            windows: [(slack: s(600), start: s(200), end: s(800)),
                      (slack: s(11_000), start: s(10_000), end: s(12_000))],
            cores: [(slack: s(600), start: s(550), end: s(650)),
                    (slack: s(11_000), start: s(10_400), end: s(11_600))])
        XCTAssertEqual(snaps.sorted(), [s(600), s(5000), s(10_000), s(10_400), s(11_000), s(11_600), s(12_000)])
    }

    /// A slack no core holds is one mark like a short core's dot: one magnet stop and one event time, at its instant.
    /// Inside a drawn window the window's opening is the time printed.
    func testASlackWithoutAWindowIsOneStopAndOneTime() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let h = { (hours: Double) in t0.addingTimeInterval(hours * 3600) }
        let events = [CurrentEvent(time: h(3), speed: 0, kind: .slack), CurrentEvent(time: h(8), speed: 0, kind: .slack)]
        let windows = [(slack: h(8), start: h(7), end: h(9))]
        let cores = [(slack: h(8), start: h(7.9), end: h(8.1))]
        let data = TimelineData(tz: .gmt, anchor: t0, today: t0, start: t0, end: h(12), days: [],
                                tidePoints: [], tideRates: [], tideExtremes: [],
                                currentPoints: [CurrentPoint(time: t0, speed: 1), CurrentPoint(time: h(12), speed: 1)],
                                currentEvents: events, snapTimes: [], slackWindows: windows, slackCores: cores)
        XCTAssertEqual(data.bareSlackTimes, [h(3)])
        XCTAssertEqual(data.slackAxisTimes, [h(3), h(7)])
        XCTAssertTrue(TimelineData.currentSnapTimes(events: events, windows: windows, cores: cores).contains(h(3)))
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

    func testASlackAtTheLastSampleKeepsItsOwnDotAndMagnetTarget() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let slack = t0.addingTimeInterval(600)
        let points = [CurrentPoint(time: t0, speed: 1), CurrentPoint(time: slack, speed: 0)]
        let window = try XCTUnwrap(slackWindow(points, around: slack, threshold: 0.5))
        let coreWindow = try XCTUnwrap(slackWindow(points, around: slack, threshold: 0.15))
        let run = WindowRun(start: window.start, end: window.end)
        let core = WindowRun(start: coreWindow.start, end: coreWindow.end)
        XCTAssertEqual(run.end, slack)
        XCTAssertEqual(core.end, slack)
        XCTAssertTrue(run.isDot)
        XCTAssertEqual(bareSlacks([core.start, core.centre, slack], runs: [core]), [slack])
        XCTAssertTrue(readsSlack(at: slack, runs: [core], slacks: [slack]))
        XCTAssertFalse(readsSlack(at: slack.addingTimeInterval(1), runs: [core], slacks: [slack]))
        XCTAssertEqual(StationCardGraph.axisMoments([run], cores: [core], slacks: [slack], pointsPerHour: 14),
                       [core.centre, slack])
        XCTAssertEqual(TimelineData.currentSnapTimes(
            events: [CurrentEvent(time: slack, speed: 0, kind: .slack)],
            windows: [(slack: slack, start: window.start, end: window.end)],
            cores: [(slack: slack, start: coreWindow.start, end: coreWindow.end)]).sorted(),
                       [core.centre, slack])
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

    /// The engine's slack can land past the line's ±threshold span; the window still holds it,
    /// with a bare dot when the widened closing edge is the slack itself.
    func testAWindowHoldsTheSlackTheEngineFound() throws {
        let noon = Date(timeIntervalSince1970: 1_700_000_000)
        let m = { (minutes: Double) in noon.addingTimeInterval(minutes * 60) }
        let reversal = [CurrentPoint(time: m(0), speed: 1), CurrentPoint(time: m(10), speed: -3)]
        let slack = m(6)
        let w = try XCTUnwrap(slackWindow(reversal, around: slack, threshold: 0.5))
        XCTAssertLessThanOrEqual(w.start, slack)
        XCTAssertGreaterThanOrEqual(w.end, slack)
        let runs = mergeWindows([w])
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(bareSlacks([slack], runs: runs), [slack], "the closing is excluded from the run's coverage")
        let openings = slackWindowOpenings(FixedCurrent(points: reversal, slacks: [slack]),
                                           from: m(-60), to: m(60), threshold: 0.5)
        XCTAssertEqual(openings.count, 1)
        XCTAssertNotNil(openings.first?.end, "one window opening, not a windowless slack beside it")

        // One sample inside the band: the threshold crossing toward the fast side can miss the slack too.
        let edge = [CurrentPoint(time: m(-10), speed: 2), CurrentPoint(time: m(0), speed: 0.4),
                    CurrentPoint(time: m(10), speed: -3)]
        let e = try XCTUnwrap(slackWindow(edge, around: m(2), threshold: 0.5))
        XCTAssertTrue(WindowRun(start: e.start, end: e.end).contains(m(2)))
    }
}

/// A current whose samples and slacks are given, whatever range is asked for.
private struct FixedCurrent: CurrentPredicting {
    let points: [CurrentPoint]
    let slacks: [Date]
    func speeds(from: Date, to: Date, step: TimeInterval) -> [CurrentPoint] { points }
    func events(from: Date, to: Date) -> [CurrentEvent] {
        slacks.map { CurrentEvent(time: $0, speed: 0, kind: .slack) }
    }
}
