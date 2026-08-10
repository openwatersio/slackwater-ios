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

    /// The band rows must stay in reading order and inside the canvas, for
    /// whichever track owns the box. Get one slot backwards and the glyph
    /// prints over the value with nothing to say so.
    private func assertBandsAreReadable(_ g: TimelineGeo,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssert(g.topTimeY < g.topValueY && g.topValueY < g.topGlyphY && g.topGlyphY < g.bodyTop,
                  "top band reads time → value → glyph → curve", file: file, line: line)
        XCTAssert(g.bodyBottom < g.bottomGlyphY && g.bottomGlyphY < g.bottomValueY
                    && g.bottomValueY < g.bottomTimeY,
                  "bottom band reads curve → glyph → value → time", file: file, line: line)
        XCTAssertGreaterThan(g.topTimeY, g.sunY + 8,
                             "the top band must clear the sun dots above it", file: file, line: line)
        XCTAssertLessThan(g.bottomTimeY, g.height - 8,
                          "the last row must sit inside the canvas", file: file, line: line)
    }

    /// Two single-track geometries, no combined case (split-scrubbers spec §1/§2).
    func testSingleTrackGeometries() {
        let tideData = TimelineData.build(tide: friday, current: nil, now: Date())
        let tide = TimelineGeo(data: tideData)
        XCTAssert(tide.hasTide && !tide.hasCurrent)
        XCTAssertEqual(tide.height, 328, "NEAPS bands above and below the track, no gutter")
        XCTAssertEqual(tide.tideTop, 106)
        XCTAssertEqual(tide.tideBottom, 256)
        XCTAssertEqual(tide.bodyTop, tide.tideTop)
        XCTAssertEqual(tide.bodyBottom, tide.tideBottom)
        assertBandsAreReadable(tide)

        // Current-only: construct TimelineData directly — the geometry keys only
        // on which point arrays are non-empty.
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let cur = TimelineGeo(data: TimelineData(
            tz: .current, today: t0, start: t0, end: t0.addingTimeInterval(3600),
            days: [], tidePoints: [], tideExtremes: [],
            currentPoints: [CurrentPoint(time: t0, speed: 1)], currentEvents: [],
            snapTimes: [], slackWindows: []))
        XCTAssert(!cur.hasTide && cur.hasCurrent)

        // The two tracks are the SAME box now. They diverged while the current
        // strip drew speed labels on its curve and carried FLOOD/EBB reference
        // lines; both are gone, so a current reading and a tide reading sit in
        // the same rows and the two details are the same size on screen. If a
        // future change reintroduces a per-track height, it should have to
        // argue with this assertion first.
        XCTAssertEqual(cur.height, tide.height, "one strip height, both tracks")
        XCTAssertEqual(cur.curTop, tide.tideTop)
        XCTAssertEqual(cur.curBottom, tide.tideBottom)
        XCTAssertEqual(cur.bodyTop, cur.curTop)
        XCTAssertEqual(cur.bodyBottom, cur.curBottom)
        assertBandsAreReadable(cur)
        // Slack's column spans the whole track, so a max-ebb band below and a
        // slack's end-time band below must share the one bottom row without the
        // column swallowing either.
        XCTAssertGreaterThan(cur.bottomGlyphY, cur.curY(-999),
                             "the bottom band must clear a clamped max-ebb dot")

        // Both arrays non-empty: pins that no case (true, true) exists to claim
        // it — resurrecting the deleted combined arm ahead of `case (true, _)`
        // would go uncaught otherwise. TidePoint has no public init outside
        // TideEngine, so the tide side is real data borrowed from the tide-only
        // build above; only the current side is synthesized.
        let both = TimelineGeo(data: TimelineData(
            tz: tideData.tz, today: tideData.today, start: tideData.start, end: tideData.end,
            days: tideData.days, tidePoints: tideData.tidePoints, tideExtremes: tideData.tideExtremes,
            currentPoints: [CurrentPoint(time: tideData.start, speed: 1)], currentEvents: [],
            snapTimes: tideData.snapTimes, slackWindows: []))
        XCTAssert(both.hasTide && both.hasCurrent)
        XCTAssertEqual(both.height, 328, "combined input resolves tide-first — no combined case exists (spec §1/§2)")
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

    /// The window computation is build-time data now, not a per-view recompute
    /// (gutter spec §3) — so the band on the strip and the duration in the
    /// readout are the same numbers by construction.
    func testSlackWindowsBracketTheirSlacks() throws {
        let station = try XCTUnwrap(CurrentStationRecord.all.first)
        let d = TimelineData.build(tide: nil, current: station, now: Date())
        let slacks = d.currentEvents.filter { $0.kind == .slack }
        XCTAssertGreaterThan(slacks.count, 10, "a week of slacks must exist to window")
        XCTAssertFalse(d.slackWindows.isEmpty)
        for w in d.slackWindows {
            XCTAssert(w.start <= w.slack && w.slack <= w.end,
                      "a window must bracket its own slack: \(w)")
            XCTAssert(slacks.contains { $0.time == w.slack },
                      "every window belongs to a drawn slack event")
        }
    }

    /// A derived gate's curve is a schematic ±1 SHAPE, not a velocity, so a
    /// 0.5 kn window measured off it would be fiction (gutter spec §3). Its
    /// slacks fall back to a plain dropline instead.
    func testDerivedGateHasNoSlackWindows() throws {
        let port = TideStationRecord(
            id: "chs-point-atkinson", name: "Point Atkinson", region: "West Vancouver",
            aliases: [], latitude: 49.337, longitude: -123.254,
            timezone: "America/Vancouver", chartDatum: "Chart", datumOffset: 3.0,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 0)])
        let gate = DerivedGateRecord(gate: ChsGateInfo.all.first { $0.id == "chs-malibu-rapids" }!,
                                     port: port)
        let d = TimelineData.build(gate: gate, now: Date())
        XCTAssert(d.hasCurrent, "the schematic track exists")
        XCTAssertFalse(d.currentEvents.isEmpty, "the gate has slack events")
        XCTAssert(d.slackWindows.isEmpty, "but no windows — the curve is a shape (gutter spec §3)")
    }

    /// The strip is wider than one Metal texture. A `Canvas` is a single
    /// backing layer capped at 8192px per side, and the whole chart renders
    /// EMPTY past it — silently, no error, which is why this needs a test and
    /// not a comment. Widening `pph` from 12 to 18 crossed it on a 3× phone
    /// (9720px) and blanked every tide detail; the tiles exist to keep each
    /// layer under the cap, so the assertion is on a tile, not on the strip.
    func testCanvasTilesStayUnderTheTextureCap() {
        let d = TimelineData.build(tide: friday, current: nil, now: Date())
        let cap: CGFloat = 8192
        let scale: CGFloat = 3        // the densest screen this ships to

        XCTAssertGreaterThan(d.totalWidth * scale, cap,
                             "if the whole strip fits in one texture the tiling is dead code — delete it, don't keep an untested branch")
        XCTAssertLessThan(TimelineCanvas.tileWidth * scale, cap,
                          "a tile must fit in one texture at 3×")
        XCTAssertLessThan(TimelineGeo(data: d).height * scale, cap,
                          "and so must its height")
        // Whole points at every scale factor: a fractional boundary antialiases
        // against transparent on both sides and leaves a hairline seam.
        for s in [1.0, 2.0, 3.0] as [CGFloat] {
            XCTAssertEqual((TimelineCanvas.tileWidth * s).truncatingRemainder(dividingBy: 1), 0,
                           "tile boundary must land on a pixel at \(s)×")
        }
    }

    /// The fixed left axis: round values, at most six of them, inside the
    /// plotted span. The step has to adapt — a Salish spring range and a
    /// half-metre creek can't share one interval — and the labels have to be
    /// values a chart datum is actually quoted in, not raw span edges.
    func testAxisTicksAreRoundAndBounded() {
        // ~4.4 m of range: whole metres, all inside the span.
        let m = axisTicks(lo: -0.4, hi: 4.0, imperial: false)
        XCTAssertEqual(m, [0, 1, 2, 3, 4])
        XCTAssert(m.allSatisfy { $0 >= -0.4 && $0 <= 4.0 }, "a tick outside the span points at nothing")

        // A narrow station drops to the half-metre step rather than showing one label.
        XCTAssertEqual(axisTicks(lo: 0.1, hi: 1.4, imperial: false), [0.5, 1.0])

        // A big range coarsens instead of printing a wall of numbers.
        XCTAssert(axisTicks(lo: -1, hi: 12, imperial: false).count <= 6)
        XCTAssert(axisTicks(lo: -1, hi: 12, imperial: true).count <= 6,
                  "~43 ft of range in feet still fits the column")

        // Imperial reads the span in feet: 4 m is ~13.1 ft, so the ticks must
        // be foot values, not metre ones leaking through.
        let ft = axisTicks(lo: 0, hi: 4.0, imperial: true)
        XCTAssertEqual(ft.last, 10, "ticks are display units — 10 ft, not 4")
        XCTAssertEqual(axisTickMetres(10, imperial: true), 10 / 3.28084, accuracy: 1e-9)
        XCTAssertEqual(axisTickMetres(3, imperial: false), 3, "metric ticks are already metres")

        // Degenerate spans can't loop forever or emit junk.
        XCTAssert(axisTicks(lo: 2, hi: 2, imperial: false).isEmpty)

        XCTAssertEqual(axisTickLabel(4), "4", "no trailing zeros in an axis column")
        XCTAssertEqual(axisTickLabel(0.5), "0.5")
        XCTAssertEqual(axisTickLabel(-0.0), "0", "no negative zero at chart datum")
    }

    /// Events scanned from a sampled series (online gates draw fetched points,
    /// not a harmonic engine): slacks at interpolated zero crossings, one signed
    /// maximum per run between them.
    func testSampleEventsScanCrossingsAndExtrema() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // 2 → -2 → 2 over 3 h at 15-min samples: crossings at +1h and +2h... use
        // a triangle wave: v(i) = [2,1,0.5,-0.5,-1,-2,-1,-0.5,0.5,1,2] per 15 min.
        let vs: [Double] = [2, 1, 0.5, -0.5, -1, -2, -1, -0.5, 0.5, 1, 2]
        let pts = vs.enumerated().map { CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 900), speed: $0.element) }
        let events = sampleEvents(pts)
        let slacks = events.filter { $0.kind == .slack }
        XCTAssertEqual(slacks.count, 2)
        // First crossing: between samples 2 (0.5) and 3 (-0.5) → halfway, 2250 s.
        XCTAssertEqual(slacks[0].time.timeIntervalSince(t0), 2250, accuracy: 1)
        XCTAssertEqual(slacks[1].time.timeIntervalSince(t0), 6750, accuracy: 1)
        let ebbs = events.filter { $0.kind == .maxEbb }
        XCTAssertEqual(ebbs.count, 1)
        XCTAssertEqual(ebbs[0].speed, -2, accuracy: 1e-9)
        XCTAssertEqual(ebbs[0].time.timeIntervalSince(t0), 5 * 900, accuracy: 1)
        // Leading/trailing runs also get their maxima (floods at each end).
        let floods = events.filter { $0.kind == .maxFlood }
        XCTAssertEqual(floods.count, 2)
        XCTAssertEqual(floods[0].speed, 2, accuracy: 1e-9)
        XCTAssertEqual(floods[0].time.timeIntervalSince(t0), 0, accuracy: 1)
        XCTAssertEqual(floods[1].speed, 2, accuracy: 1e-9)
        XCTAssertEqual(floods[1].time.timeIntervalSince(t0), 10 * 900, accuracy: 1)
        // Events alternate: no two slacks adjacent, no two maxima adjacent.
        for (a, b) in zip(events, events.dropFirst()) {
            XCTAssert((a.kind == .slack) != (b.kind == .slack))
        }
    }

    /// A monotone window with no crossing: one maximum, no slacks, no crash.
    func testSampleEventsMonotone() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0..<8).map { CurrentPoint(time: t0.addingTimeInterval(Double($0) * 900), speed: 1 + Double($0) * 0.1) }
        let events = sampleEvents(pts)
        XCTAssert(events.filter { $0.kind == .slack }.isEmpty)
        XCTAssertEqual(events.filter { $0.kind == .maxFlood }.count, 1)
    }

    /// An exact-zero sample IS the slack — both polarities, no interpolation.
    func testSampleEventsExactZeroSample() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func pts(_ vs: [Double]) -> [CurrentPoint] {
            vs.enumerated().map { CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 900), speed: $0.element) }
        }
        for vs in [[-2.0, -1, 0, 1], [2.0, 1, 0, -1]] {
            let events = sampleEvents(pts(vs))
            let slacks = events.filter { $0.kind == .slack }
            XCTAssertEqual(slacks.count, 1, "\(vs): the zero sample is one slack")
            XCTAssertEqual(slacks[0].time.timeIntervalSince(t0), 2 * 900, accuracy: 1)
            XCTAssertEqual(events.filter { $0.kind == .maxEbb }.count, 1, "\(vs)")
            XCTAssertEqual(events.filter { $0.kind == .maxFlood }.count, 1, "\(vs)")
        }
        // Consecutive zeros: one slack, at the first zero sample.
        let events = sampleEvents(pts([1, 0, 0, -1]))
        XCTAssertEqual(events.filter { $0.kind == .slack }.count, 1)
        XCTAssertEqual(events.filter { $0.kind == .slack }[0].time.timeIntervalSince(t0), 900, accuracy: 1)
    }

    /// The online-gate path: build directly from fetched points (no engine
    /// station involved) — current-only strip, standard 340pt geometry, and
    /// every in-window event lands as a snap stop (mirrors the DerivedGateTests
    /// snap assertion for the schematic-gate path).
    func testBuildFromOnlinePointsIsCurrentOnlyAndSnaps() {
        let now = Date()
        let tz = TimeZone(identifier: "America/Vancouver")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: now)
        let start = today.addingTimeInterval(-Timeline.backHours * 3600)
        let end = today.addingTimeInterval(Timeline.forwardHours * 3600)

        // 15-min samples spanning the whole strip window, oscillating with a
        // ~12h period so slack/max events recur across it (real semidiurnal shape).
        var pts: [CurrentPoint] = []
        var t = start
        while t <= end {
            let hours = t.timeIntervalSince(start) / 3600
            pts.append(CurrentPoint(time: t, speed: 2.0 * sin(hours / 6.0 * .pi)))
            t = t.addingTimeInterval(900)
        }

        let d = TimelineData.build(onlinePoints: pts, tz: tz, lat: 48.5, lon: -123.0, now: now)

        XCTAssert(d.hasCurrent && !d.hasTide)
        // 328: one strip height for both tracks since the NEAPS bands retired
        // the gutter (was 340 pre-gutter, 380 with the three-row gutter).
        XCTAssertEqual(TimelineGeo(data: d).height, 328)
        XCTAssertFalse(d.currentEvents.isEmpty)
        // Fetched official samples are real velocities, so the online-gate path
        // gets slack windows — the derived-gate path does not, because its curve
        // is a schematic shape (gutter spec §3).
        XCTAssertFalse(d.slackWindows.isEmpty,
                       "online gates draw fetched speeds, so their slacks carry windows")
        for w in d.slackWindows {
            XCTAssert(w.start <= w.slack && w.slack <= w.end,
                      "a window must bracket its own slack: \(w)")
        }
        XCTAssert(d.currentEvents
            .filter { $0.time >= d.start && $0.time <= d.end }
            .allSatisfy { e in d.snapTimes.contains { abs($0.timeIntervalSince(e.time)) < 1 } })
    }

    /// A window ending exactly on a slack sample must not trap (the post-loop
    /// run close sees an empty run) — and the zero still reads as the slack.
    func testSampleEventsTrailingZero() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = [1.0, -1, 0].enumerated().map {
            CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 900), speed: $0.element)
        }
        let events = sampleEvents(pts)
        let slacks = events.filter { $0.kind == .slack }
        XCTAssertEqual(slacks.count, 2)                       // the crossing + the trailing zero
        XCTAssertEqual(slacks[0].time.timeIntervalSince(t0), 450, accuracy: 1)
        XCTAssertEqual(slacks[1].time.timeIntervalSince(t0), 1800, accuracy: 1)
        XCTAssertEqual(events.filter { $0.kind == .maxFlood }.count, 1)
        XCTAssertEqual(events.filter { $0.kind == .maxEbb }.count, 1)
    }
}
