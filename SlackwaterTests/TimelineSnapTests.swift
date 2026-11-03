// Slackwater — GPL v3. One snap rule for both scrub hosts (#522).
import XCTest
@testable import Slackwater
import SlackwaterKit

final class TimelineSnapTests: XCTestCase {
    private func friday() throws -> TimelineData {
        let record = try XCTUnwrap(TideStationRecord.record(id: TideStationRecord.fridayHarborID))
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        return TimelineData.build(tide: record, current: nil, now: at, anchor: at)
    }

    func testMagnetTargetPullsTheNearestStopInReach() throws {
        let tl = try friday()
        let stop = try XCTUnwrap(tl.snapTimes.dropFirst(3).first)
        XCTAssertEqual(tl.magnetTarget(nearX: tl.x(stop) + 3), stop)
    }

    /// A press picks an alert's moment, so 40 minutes before a stop is not the stop.
    func testMagnetTargetLeavesAMomentBetweenStops() throws {
        let tl = try friday()
        let pairs = zip(tl.snapTimes, tl.snapTimes.dropFirst())
        let gap = try XCTUnwrap(pairs.max { $0.1.timeIntervalSince($0.0) < $1.1.timeIntervalSince($1.0) })
        XCTAssertNil(tl.magnetTarget(nearX: tl.x(gap.1.addingTimeInterval(-40 * 60))))
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

    /// A rest a hair off a stop still takes it, so the reading is the stop's own instant.
    func testMagnetTargetHoldsAStopItAlreadySitsOn() throws {
        let tl = try friday()
        let stop = try XCTUnwrap(tl.snapTimes.dropFirst(3).first)
        XCTAssertEqual(tl.magnetTarget(nearX: tl.x(stop) + 0.2), stop)
        XCTAssertEqual(tl.magnetTarget(nearX: tl.x(stop)), stop)
    }

    /// With Settings hiding the sun marks, sunrise and sunset stop being stops, and nothing else does.
    func testHiddenSunMarksAreNotStops() throws {
        let tl = try friday()
        let sun = Set(tl.days.flatMap { [$0.sunrise, $0.sunset].compactMap { $0 } })
        let shown = tl.stops(showingSun: true), hidden = tl.stops(showingSun: false)
        XCTAssertEqual(shown, tl.snapTimes)
        XCTAssertFalse(sun.isDisjoint(with: shown), "the fixture must hold sun stops")
        XCTAssertEqual(Set(hidden), Set(tl.snapTimes).subtracting(sun))
        let rise = try XCTUnwrap(shown.first { sun.contains($0) })
        XCTAssertEqual(tl.magnetTarget(nearX: tl.x(rise), showingSun: true), rise)
        XCTAssertNotEqual(tl.magnetTarget(nearX: tl.x(rise), showingSun: false), rise)
        // Built from the stops that aren't the sun's, so none of those can be in it.
        XCTAssertTrue(tl.sunOnlyStops.isSubset(of: sun))
        let others = tl.tideExtremes.map(\.time) + tideFlowArrows(tl.tideRates).map(\.time)
            + tl.eclipses.map(\.peak) + tl.solarEclipses.map(\.peak)
        XCTAssertTrue(tl.sunOnlyStops.isDisjoint(with: others))
    }

    /// Hiding the sun removes only what is sun alone: a stop on a sunrise's own second that isn't
    /// in `sunOnlyStops`, as a builder leaves a coincident turn, stays.
    func testAStopOnASunriseSurvivesTheHiddenSun() throws {
        let tl = try friday()
        let rise = try XCTUnwrap(tl.days.compactMap(\.sunrise).first { tl.contains($0) })
        let turn = TideExtreme(time: rise, height: 1, kind: .high)
        let coincident = TimelineData(tz: tl.tz, anchor: tl.anchor, today: tl.today, start: tl.start, end: tl.end,
                                      days: tl.days, tidePoints: tl.tidePoints, tideRates: tl.tideRates,
                                      tideExtremes: [turn], currentPoints: [], currentEvents: [],
                                      snapTimes: [rise], slackWindows: [], sunOnlyStops: [])
        XCTAssertEqual(coincident.stops(showingSun: false), [rise])
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

    /// The online gate's strip stops half a viewport inside its window, so the
    /// furthest a scrub can rest is that far in from either end.
    func testEdgeReanchorFiresAtTheClampedEnds() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        let anchor = dayLocal(Date(timeIntervalSince1970: 1_791_000_000), tz)
        let w = Timeline.window(anchor: anchor)
        let viewport: CGFloat = 393
        let half = Double(viewport / 2 / Timeline.pph) * 3600
        let lastReachable = w.end.addingTimeInterval(-half)
        XCTAssertEqual(Timeline.edgeReanchor(settledAt: lastReachable, anchor: anchor, viewportPts: viewport, tz: tz),
                       dayLocal(lastReachable, tz))
        let firstReachable = w.start.addingTimeInterval(half)
        XCTAssertEqual(Timeline.edgeReanchor(settledAt: firstReachable, anchor: anchor, viewportPts: viewport, tz: tz),
                       dayLocal(firstReachable, tz))
        let midweek = anchor.addingTimeInterval(3 * 86_400)
        XCTAssertNil(Timeline.edgeReanchor(settledAt: midweek, anchor: anchor, viewportPts: viewport, tz: tz))
        XCTAssertNil(Timeline.edgeReanchor(settledAt: lastReachable, anchor: anchor, viewportPts: 0, tz: tz))
        // The new window centres the resting scrub, well clear of its own ends.
        let next = try XCTUnwrap(Timeline.edgeReanchor(settledAt: lastReachable, anchor: anchor,
                                                       viewportPts: viewport, tz: tz))
        XCTAssertNil(Timeline.edgeReanchor(settledAt: lastReachable, anchor: next, viewportPts: viewport, tz: tz))
    }
}
