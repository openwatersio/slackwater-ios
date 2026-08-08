// Slackwater — GPL v3. Tests for the continuous pan-under-centerline timeline
// (TimelineStrip.swift): fixed window and x↔time mapping, the now-readout
// equivalence with the old model's committed readout, night continuity across
// midnight, and the multi-day schedule window.
import XCTest
@testable import Slackwater
import TideEngine

final class TimelineTests: XCTestCase {
    let friday = TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!

    func testWindowAndMapping() {
        let now = Date()
        let d = TimelineData.build(tide: friday, current: nil, now: now)
        // -48h … +132h around today's local midnight (prototype TMIN/TMAX).
        XCTAssertEqual(d.end.timeIntervalSince(d.start), 180 * 3600, accuracy: 3601)
        XCTAssertEqual(d.totalWidth, 180 * Timeline.pph, accuracy: 13)
        XCTAssert(d.start <= now && now <= d.end)
        // x ↔ time round trip under the centerline.
        XCTAssertEqual(d.time(atX: d.x(now)).timeIntervalSince(now), 0, accuracy: 1)
        // Snap stops exist across the whole window (turns + sun events).
        XCTAssert(d.snapTimes.count > 20, "expected a full week of stops, got \(d.snapTimes.count)")
        XCTAssert(d.snapTimes.first! < d.today, "stops must reach back before today")
    }

    /// The centerline readout at "now" must equal the old model's now-readout:
    /// both are the same engine step-1 heights call. The strip's riding dot
    /// (10-min interpolation) must agree within rendering tolerance.
    func testNowReadoutEquivalence() {
        let now = Date()
        let engine = friday.engineStation
            .heights(from: now, to: now.addingTimeInterval(1), step: 1).first!.height
        let d = TimelineData.build(tide: friday, current: nil, now: now)
        XCTAssertEqual(d.heightAt(now), engine, accuracy: 0.02)
        print("NOW-READOUT Friday Harbor @ \(now): engine=\(engine) m, strip=\(d.heightAt(now)) m")
    }

    /// Days bleed into each other: every night band runs sunset → next
    /// sunrise, straddling the midnight between them.
    func testNightContinuityAcrossMidnight() {
        let d = TimelineData.build(tide: friday, current: nil, now: Date())
        var checked = 0
        for (a, b) in zip(d.days, d.days.dropFirst()) {
            guard let set = a.sunset, let rise = b.sunrise else { continue }
            XCTAssert(set < b.start && b.start < rise,
                      "night must straddle midnight: \(set) … \(rise)")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 7)
    }

    /// The schedule window (today 00:00 → +54h, prototype tableEl TOP) spans
    /// at least two local days of tide turns — the rolling multi-day list.
    func testScheduleWindowSpansMultipleDays() {
        let d = TimelineData.build(tide: friday, current: nil, now: Date())
        let t1 = d.today.addingTimeInterval(Timeline.scheduleHours * 3600)
        let turns = d.tideExtremes.filter { $0.time >= d.today && $0.time <= t1 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = d.tz
        let days = Set(turns.map { cal.startOfDay(for: $0.time) })
        XCTAssertGreaterThanOrEqual(days.count, 2)
    }

    /// Two single-track geometries, no combined case (split-scrubbers spec §1/§2).
    func testSingleTrackGeometries() {
        let tideData = TimelineData.build(tide: friday, current: nil, now: Date())
        let tide = TimelineGeo(data: tideData)
        XCTAssert(tide.hasTide && !tide.hasCurrent)
        XCTAssertEqual(tide.height, 274, "the two-row gutter adds 48 below the track (Amendment A)")
        XCTAssertEqual(tide.gutterY, 250, "row 0 baseline")
        XCTAssert(tide.gutterY > tide.bodyBottom && tide.gutterY < tide.height,
                  "gutter row 0 text sits below the track and inside the canvas")
        XCTAssertEqual(tide.gutterY(row: 1), 262, "row 1 is 12pt lower")
        XCTAssert(tide.gutterY(row: 1) < tide.height, "gutter row 1 still fits inside canvas")

        // Current-only: construct TimelineData directly — the geometry keys only
        // on which point arrays are non-empty.
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let cur = TimelineGeo(data: TimelineData(
            tz: .current, today: t0, start: t0, end: t0.addingTimeInterval(3600),
            days: [], tidePoints: [], tideExtremes: [],
            currentPoints: [CurrentPoint(time: t0, speed: 1)], currentEvents: [],
            snapTimes: []))
        XCTAssert(!cur.hasTide && cur.hasCurrent)
        XCTAssertEqual(cur.height, 368, "the two-row gutter adds 48 below the track (Amendment A)")
        XCTAssertEqual(cur.gutterY, 344, "row 0 baseline")
        XCTAssertEqual(cur.curBottom, 320)
        XCTAssertEqual(cur.bodyBottom, 320)
        XCTAssert(cur.gutterY > cur.bodyBottom && cur.gutterY < cur.height,
                  "gutter row 0 text sits below the track and inside the canvas")
        XCTAssertEqual(cur.gutterY(row: 1), 356, "row 1 is 12pt lower")
        XCTAssert(cur.gutterY(row: 1) < cur.height, "gutter row 1 still fits inside canvas")
        // The 24pt clearance is set by the max-ebb speed label, not by the
        // gutter text: that label draws at `curY + 14` and curY clamps to
        // `zeroY + curHalf`, so it reaches ~331 (gutter spec §1).
        XCTAssertGreaterThan(cur.gutterY, cur.curY(-999) + 14,
                             "the gutter must clear a clamped max-ebb speed label")

        // Both arrays non-empty: pins that no case (true, true) exists to claim
        // it — resurrecting the deleted combined arm ahead of `case (true, _)`
        // would go uncaught otherwise. TidePoint has no public init outside
        // TideEngine, so the tide side is real data borrowed from the tide-only
        // build above; only the current side is synthesized.
        let both = TimelineGeo(data: TimelineData(
            tz: tideData.tz, today: tideData.today, start: tideData.start, end: tideData.end,
            days: tideData.days, tidePoints: tideData.tidePoints, tideExtremes: tideData.tideExtremes,
            currentPoints: [CurrentPoint(time: tideData.start, speed: 1)], currentEvents: [],
            snapTimes: tideData.snapTimes))
        XCTAssert(both.hasTide && both.hasCurrent)
        XCTAssertEqual(both.height, 274, "combined input resolves tide-first — no combined case exists (spec §1/§2)")
        XCTAssertEqual(both.curTop, 0)
    }

    /// v falls linearly 2 kn → -2 kn over 2 h (slack at +60 min); |v| < 0.5
    /// between +45 and +75 min. Samples every 10 min like the drawn series.
    func testSlackWindowInterpolatesCrossings() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0...12).map { i in
            CurrentPoint(time: t0.addingTimeInterval(Double(i) * 600),
                         speed: 2.0 - Double(i) / 3.0)
        }
        let w = try XCTUnwrap(slackWindow(pts, around: t0.addingTimeInterval(3600),
                                          threshold: Timeline.slackThresholdKn))
        XCTAssertEqual(w.start.timeIntervalSince(t0), 2700, accuracy: 1)
        XCTAssertEqual(w.end.timeIntervalSince(t0), 4500, accuracy: 1)
    }

    /// A series that never leaves the window clamps to its edges.
    func testSlackWindowClampsToSeriesEdges() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0...6).map { CurrentPoint(time: t0.addingTimeInterval(Double($0) * 600), speed: 0.1) }
        let w = try XCTUnwrap(slackWindow(pts, around: t0.addingTimeInterval(1800), threshold: 0.5))
        XCTAssertEqual(w.start, pts.first!.time)
        XCTAssertEqual(w.end, pts.last!.time)
    }

    /// No sub-threshold sample brackets the slack (a violent gate where the
    /// 10-min sampling steps over the window) — no window, not a wrong one.
    func testSlackWindowNilWhenSamplingStepsOver() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0...4).map { i in
            CurrentPoint(time: t0.addingTimeInterval(Double(i) * 600),
                         speed: i < 2 ? 4.0 : -4.0)
        }
        XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(900), threshold: 0.5))
    }

    /// Greedy row assignment for gutter labels: each label takes the lowest row
    /// whose previous label has cleared it (Amendment A).
    func testGutterRowsGreedyAssignment() {
        // Well-separated labels all land in row 0.
        XCTAssertEqual(gutterRows(centers: [10, 100, 200], widths: [20, 20, 20]),
                       [0, 0, 0])

        // Two labels that overlap: second goes to row 1.
        XCTAssertEqual(gutterRows(centers: [10, 30], widths: [40, 40]),
                       [0, 1])

        // Three tightly packed labels: rows 0, 1, then 0 again (first row has cleared).
        XCTAssertEqual(gutterRows(centers: [10, 30, 60], widths: [20, 20, 20]),
                       [0, 1, 0])

        // Fallback branch: four densely packed labels where neither row clears by label 3.
        // Centers [0, 30, 60, 90] with widths [60, 60, 60, 60]:
        // - Label 0: [-30, 30] → row 0
        // - Label 1: [0, 60] → row 0 blocked (30 >= 0), row 1 clear → row 1
        // - Label 2: [30, 90] → both blocked (row 0 at 30, row 1 at 60), pick row 0 (ends earliest)
        // - Label 3: [60, 120] → both blocked, pick row 1 (ends earliest after row 0 updated to 90)
        XCTAssertEqual(gutterRows(centers: [0, 30, 60, 90], widths: [60, 60, 60, 60]),
                       [0, 1, 0, 1],
                       "fallback branch: when both rows blocked, picks row with earliest end")

        // Count matching: always returns same number of rows as there are labels.
        let centers: [CGFloat] = [10, 50, 100, 150, 200]
        let widths: [CGFloat] = [30, 30, 30, 30, 30]
        let rows = gutterRows(centers: centers, widths: widths)
        XCTAssertEqual(rows.count, centers.count)
        XCTAssert(rows.allSatisfy { $0 < 2 }, "all rows should be in valid range [0, 1]")
    }
}
