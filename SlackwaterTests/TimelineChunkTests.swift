// Slackwater — GPL v3. Tests for the infinite strip's data layer
// (TimelineChunks.swift): chunked builds must reproduce the monolithic
// builders over the same span — including across DST seams — the merge must
// keep day chrome contiguous and correctly re-keyed, and the scale governor
// must hold inside its deadband and move outside it.
import XCTest
@testable import Slackwater
import TideEngine

final class TimelineChunkTests: XCTestCase {
    let friday = TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!
    let deception = CurrentStationRecord.all.first { $0.name.hasPrefix("Deception Pass") }!

    private func vancouverMidnight(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Vancouver")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func chunkStart(_ i: Int, origin: Date, tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(byAdding: .day, value: i * TimelineWindowStore.chunkDays, to: origin)!
    }

    private func merged(_ source: TimelineSource, origin: Date, indices: ClosedRange<Int>,
                        anchor: Date, today: Date) -> TimelineData {
        let chunks = indices.map { i in
            TimelineChunk.build(source, index: i,
                                start: chunkStart(i, origin: origin, tz: source.tz),
                                end: chunkStart(i + 1, origin: origin, tz: source.tz))
        }
        return TimelineData.merged(chunks, source: source, anchor: anchor, today: today)
    }

    // MARK: - Golden equivalence with the monolithic builders

    /// The chunked path is a second implementation of the same prediction
    /// window; over the overlap of their spans the two must agree — samples
    /// exactly (the engine grid is epoch-aligned, so both sample the same
    /// instants), events to bisection tolerance.
    func testMergedTideChunksMatchMonolithicBuild() {
        let anchor = vancouverMidnight(2026, 8, 11)
        let now = anchor.addingTimeInterval(15 * 3600)
        let mono = TimelineData.build(tide: friday, current: nil, now: now, anchor: anchor)
        // Chunks -1...1 span anchor-7d ... anchor+14d ⊇ the 228h window.
        let m = merged(.tide(friday), origin: anchor, indices: -1...1, anchor: anchor, today: anchor)
        XCTAssertLessThanOrEqual(m.start, mono.start)
        XCTAssertGreaterThanOrEqual(m.end, mono.end)

        let monoPoints = mono.tidePoints
        let overlap = m.tidePoints.filter { $0.time >= mono.start && $0.time <= monoPoints.last!.time }
        XCTAssertEqual(overlap.count, monoPoints.count, "same epoch-aligned grid over the same span")
        for (a, b) in zip(overlap, monoPoints) {
            XCTAssertEqual(a.time, b.time)
            XCTAssertEqual(a.height, b.height, accuracy: 2e-3,
                           "same instant, same constituents; the astro linearisation is re-seeded per scan and drifts ~1e-3 — under a fiftieth of a point at chart scale")
        }

        // Extremes over the monolithic window's interior (its ±6h event pad
        // reaches past the chunk set's own edges, so compare inside).
        let monoEx = mono.tideExtremes.filter { $0.time >= mono.start && $0.time <= mono.end }
        let mergedEx = m.tideExtremes.filter { $0.time >= mono.start && $0.time <= mono.end }
        XCTAssertEqual(mergedEx.count, monoEx.count)
        for (a, b) in zip(mergedEx, monoEx) {
            XCTAssertEqual(a.kind, b.kind)
            XCTAssertEqual(a.time.timeIntervalSince(b.time), 0, accuracy: 2,
                           "bisection roots from differently-seeded scans agree to ~1s")
            XCTAssertEqual(a.height, b.height, accuracy: 5e-3)
        }
    }

    func testMergedCurrentChunksMatchMonolithicBuild() {
        let anchor = vancouverMidnight(2026, 8, 11)
        let now = anchor.addingTimeInterval(15 * 3600)
        let mono = TimelineData.build(tide: nil, current: deception, now: now, anchor: anchor)
        let m = merged(.current(deception, threshold: defaultSlackThresholdKn),
                       origin: anchor, indices: -1...1, anchor: anchor, today: anchor)

        let monoPoints = mono.currentPoints
        let overlap = m.currentPoints.filter { $0.time >= mono.start && $0.time <= monoPoints.last!.time }
        XCTAssertEqual(overlap.count, monoPoints.count)
        for (a, b) in zip(overlap, monoPoints) {
            XCTAssertEqual(a.time, b.time)
            XCTAssertEqual(a.speed, b.speed, accuracy: 2e-3)
        }

        let monoEv = mono.currentEvents.filter { $0.time >= mono.start && $0.time <= mono.end }
        let mergedEv = m.currentEvents.filter { $0.time >= mono.start && $0.time <= mono.end }
        XCTAssertEqual(mergedEv.count, monoEv.count)
        for (a, b) in zip(mergedEv, monoEv) {
            XCTAssertEqual(a.kind, b.kind)
            XCTAssertEqual(a.time.timeIntervalSince(b.time), 0, accuracy: 2)
        }

        // Slack windows: same slacks, same interpolated edges — the chunk
        // path measures them off padded samples, which only widens what a
        // window clipped at the monolithic edge could see.
        let monoWin = mono.slackWindows.filter { $0.slack >= mono.start && $0.slack <= mono.end }
        let mergedWin = m.slackWindows.filter { $0.slack >= mono.start && $0.slack <= mono.end }
        XCTAssertEqual(mergedWin.count, monoWin.count)
        for (a, b) in zip(mergedWin, monoWin) {
            XCTAssertEqual(a.start.timeIntervalSince(b.start), 0, accuracy: 30)
            XCTAssertEqual(a.end.timeIntervalSince(b.end), 0, accuracy: 30)
        }
    }

    /// The schematic gate: same slack times, same ±1 shape at every sample.
    /// Compared over the monolithic window's interior: at its very edges the
    /// monolithic ±6h slack pad can miss a bracketing slack the chunk path's
    /// wider pad sees, and the shape there is the monolithic edge artefact.
    func testMergedGateChunksMatchMonolithicBuild() {
        let port = TideStationRecord(
            id: "chs-point-atkinson", name: "Point Atkinson", region: "West Vancouver",
            aliases: [], latitude: 49.337, longitude: -123.254,
            timezone: "America/Vancouver", chartDatum: "Chart", datumOffset: 3.0,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 0)])
        let record = DerivedGateRecord(gate: ChsGateInfo.all.first { $0.id == "chs-malibu-rapids" }!,
                                       port: port)
        let anchor = vancouverMidnight(2026, 8, 11)
        let now = anchor.addingTimeInterval(15 * 3600)
        let mono = TimelineData.build(gate: record, now: now, anchor: anchor)
        let m = merged(.gate(record), origin: anchor, indices: -1...1, anchor: anchor, today: anchor)

        XCTAssert(m.speedsAreSchematic)
        let lo = mono.start.addingTimeInterval(12 * 3600)
        let hi = mono.end.addingTimeInterval(-12 * 3600)
        let monoPoints = mono.currentPoints.filter { $0.time >= lo && $0.time < hi }
        let overlap = m.currentPoints.filter { $0.time >= lo && $0.time < hi }
        XCTAssertEqual(overlap.count, monoPoints.count)
        for (a, b) in zip(overlap, monoPoints) {
            XCTAssertEqual(a.time, b.time)
            // The shape is deterministic in its slacks — but the slacks are
            // the port's bisected extremes plus a lag, and those carry the
            // same ~1s re-seed jitter, which moves the half-sine's phase by
            // ~1s in ~6h.
            XCTAssertEqual(a.speed, b.speed, accuracy: 1e-3)
        }
        let monoEv = mono.currentEvents.filter { $0.time >= lo && $0.time <= hi }
        let mergedEv = m.currentEvents.filter { $0.time >= lo && $0.time <= hi }
        XCTAssertEqual(mergedEv.count, monoEv.count)
        for (a, b) in zip(mergedEv, monoEv) {
            XCTAssertEqual(a.time.timeIntervalSince(b.time), 0, accuracy: 2)
        }
    }

    // MARK: - Seams and DST

    /// The spring-forward week: chunk boundaries stay on local midnights, the
    /// sample grid stays unbroken across the seam (a 23-hour day is still a
    /// whole number of 600s steps), and merged day chrome is contiguous
    /// calendar days with anchor-relative offsets.
    func testChunkSeamAcrossSpringForward() {
        let origin = vancouverMidnight(2026, 3, 8)   // the transition day
        let source = TimelineSource.tide(friday)
        let m = merged(source, origin: origin, indices: -1...1, anchor: origin, today: origin)

        for (a, b) in zip(m.tidePoints, m.tidePoints.dropFirst()) {
            XCTAssertEqual(b.time.timeIntervalSince(a.time), 600,
                           "one unbroken 600s grid across chunk seams and the DST hour")
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = friday.tz
        for (a, b) in zip(m.days, m.days.dropFirst()) {
            XCTAssertEqual(cal.date(byAdding: .day, value: 1, to: a.start), b.start,
                           "merged day chrome is contiguous calendar days")
            XCTAssertEqual(b.offset, a.offset + 1)
        }
        for day in m.days {
            XCTAssertEqual(cal.dateComponents([.day], from: origin, to: day.start).day, day.offset,
                           "offsets are days-from-anchor, the key the schedule groups on")
        }
    }

    /// Boundary events must appear exactly once. Every extreme in a merged
    /// three-chunk span is strictly later than the one before it — a
    /// double-counted seam event would show up as a near-zero gap.
    func testNoDuplicateEventsAtSeams() {
        let origin = vancouverMidnight(2026, 8, 11)
        let m = merged(.tide(friday), origin: origin, indices: -1...1, anchor: origin, today: origin)
        for (a, b) in zip(m.tideExtremes, m.tideExtremes.dropFirst()) {
            XCTAssertGreaterThan(b.time.timeIntervalSince(a.time), 3600,
                                 "adjacent extremes are hours apart; a seam duplicate would be seconds")
        }
    }

    // MARK: - Scale governor

    func testGovernorHoldsInsideTheDeadband() {
        let scale = TimelineScale(tideMid: 2, tideSpan: 2, maxAbsCur: 4)
        // Visible data well inside the box, but not empty enough to contract.
        let held = ScaleGovernor.update(scale, tideMin: 0.5, tideMax: 3.5, maxSpeed: 3.5)
        XCTAssertEqual(held, scale, "an ordinary pan must not rescale")
    }

    func testGovernorExpandsJustBeforeClipping() {
        let scale = TimelineScale(tideMid: 2, tideSpan: 2, maxAbsCur: 4)
        let out = ScaleGovernor.update(scale, tideMin: 0, tideMax: 4.2, maxSpeed: 5)
        XCTAssertEqual(out.tideMid, 2.1, accuracy: 1e-9)
        XCTAssertEqual(out.tideSpan, 2.1 * 1.06, accuracy: 1e-9)
        XCTAssertEqual(out.maxAbsCur, 5 * 1.05, accuracy: 1e-9)
    }

    func testGovernorContractsWhenTheBoxGoesEmpty() {
        let scale = TimelineScale(tideMid: 2, tideSpan: 4, maxAbsCur: 8)
        let out = ScaleGovernor.update(scale, tideMin: 1.5, tideMax: 2.5, maxSpeed: 1)
        XCTAssertEqual(out.tideSpan, 0.5 * 1.06, accuracy: 1e-9)
        XCTAssertEqual(out.maxAbsCur, 1.05, accuracy: 1e-9)
    }

    /// Adopting a fit must be a fixed point: the same visible data evaluated
    /// against the adopted scale holds still, or the strip would oscillate.
    func testGovernorAdoptionIsAFixedPoint() {
        let scale = TimelineScale(tideMid: 2, tideSpan: 2, maxAbsCur: 4)
        let adopted = ScaleGovernor.update(scale, tideMin: 0, tideMax: 4.2, maxSpeed: 5)
        XCTAssertNotEqual(adopted, scale)
        let again = ScaleGovernor.update(adopted, tideMin: 0, tideMax: 4.2, maxSpeed: 5)
        XCTAssertEqual(again, adopted)
    }

    /// The fitting formulas are TimelineGeo's own: a geo built with an
    /// explicit scale equal to the data-derived one draws identically.
    func testScaleFittingMatchesGeoDefaults() {
        let anchor = vancouverMidnight(2026, 8, 11)
        let data = TimelineData.build(tide: friday, current: nil,
                                      now: anchor.addingTimeInterval(15 * 3600), anchor: anchor)
        let derived = TimelineGeo(data: data)
        let explicit = TimelineGeo(data: data, scale: TimelineScale.fitting(data))
        XCTAssertEqual(derived.tideMid, explicit.tideMid)
        XCTAssertEqual(derived.tideSpan, explicit.tideSpan)
        XCTAssertEqual(derived.maxAbsCur, explicit.maxAbsCur)
    }

    // MARK: - Canvas identity

    /// The strip caches its drawn canvas, so a rebuild that changes the
    /// picture has to be distinguishable from one that does not. Shape cannot
    /// do it: the same station over the same window with a different slack
    /// threshold has an IDENTICAL span and sample count and different green
    /// bands. Keying the cache on those counts held the old drawing under a
    /// readout showing the new threshold — a safe-passage window the app no
    /// longer stood behind. This asserts the collision is real and that
    /// identity survives it.
    func testRebuildWithANewThresholdIsDistinguishableFromTheOldOne() {
        let anchor = vancouverMidnight(2026, 8, 11)
        let now = anchor.addingTimeInterval(15 * 3600)
        let loose = TimelineData.build(tide: nil, current: deception, now: now, anchor: anchor,
                                       threshold: 0.5)
        let tight = TimelineData.build(tide: nil, current: deception, now: now, anchor: anchor,
                                       threshold: 2.0)

        // The collision the shape-based key could not see.
        XCTAssertEqual(loose.start, tight.start)
        XCTAssertEqual(loose.end, tight.end)
        XCTAssertEqual(loose.currentPoints.count, tight.currentPoints.count)
        XCTAssertEqual(loose.currentPoints.map(\.speed), tight.currentPoints.map(\.speed),
                       "same samples — only the threshold read off them differs")
        XCTAssertNotEqual(loose.slackWindows.map(\.start), tight.slackWindows.map(\.start),
                          "a different threshold must actually move the green bands, or this proves nothing")

        XCTAssertNotEqual(loose.revision, tight.revision,
                          "the cache must see two different charts here")
    }

    /// A copy is the same picture and must NOT invalidate the cache, or the
    /// strip is back to redrawing on every frame — the lag this replaced.
    func testRevisionSurvivesCopyingAndIsUniquePerBuild() {
        let anchor = vancouverMidnight(2026, 8, 11)
        let now = anchor.addingTimeInterval(15 * 3600)
        let built = TimelineData.build(tide: friday, current: nil, now: now, anchor: anchor)
        let copy = built
        XCTAssertEqual(copy.revision, built.revision, "a copy draws the same picture")

        let rebuilt = TimelineData.build(tide: friday, current: nil, now: now, anchor: anchor)
        XCTAssertNotEqual(rebuilt.revision, built.revision,
                          "every build is its own timeline, even an identical one")

        let m1 = merged(.tide(friday), origin: anchor, indices: 0...0, anchor: anchor, today: anchor)
        let m2 = merged(.tide(friday), origin: anchor, indices: 0...0, anchor: anchor, today: anchor)
        XCTAssertNotEqual(m1.revision, m2.revision, "and so is every merge")
    }

    // MARK: - The store

    /// Opening builds only the chunks the first view needs, then a far focus
    /// extends the window; a left-edge change while the scroll is loud waits
    /// for the gate, an append does not.
    @MainActor func testStoreExtendsBackwardOnlyWhenQuiet() throws {
        let anchor = todayLocal(friday.tz)
        let store = TimelineWindowStore(source: .tide(friday))
        store.start(anchor: anchor, now: appNow())
        let tl0 = try XCTUnwrap(store.timeline)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = friday.tz
        // Pretend the strip is decelerating leftwards into three weeks ago.
        store.gate.isQuiet = false
        let past = cal.date(byAdding: .day, value: -21, to: anchor)!
        store.focus(past, viewportPts: 400)
        // Builds run detached; give them ample time to land while loud.
        let loudUntil = Date().addingTimeInterval(3)
        while Date() < loudUntil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(store.timeline?.start, tl0.start,
                       "a left-edge extension must wait for the scroll to rest")

        // Rest: the parked publish (or any straggling build) lands now.
        store.gate.isQuiet = true
        let deadline = Date().addingTimeInterval(20)
        while store.timeline?.contains(past) != true, Date() < deadline {
            store.focus(past, viewportPts: 400)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(store.timeline?.contains(past), true,
                       "the parked publish lands at the next quiet moment")
    }

    @MainActor func testStoreJumpLandsSynchronously() {
        let anchor = todayLocal(friday.tz)
        let store = TimelineWindowStore(source: .tide(friday))
        store.start(anchor: anchor, now: appNow())
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = friday.tz
        let far = cal.date(byAdding: .month, value: 6, to: anchor)!
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: far)!
        store.jump(to: noon, anchor: far)
        XCTAssertEqual(store.timeline?.contains(noon), true,
                       "a picked week must be scrubable the moment the picker closes")
        XCTAssertEqual(store.timeline?.anchor, far)
    }
}
