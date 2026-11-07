// Slackwater — GPL v3. What the tide lead says at an instant, pinned as plain values (#901).
//
// `TideLead.reading` is a plain value, so this target can read what the lead
// renders without drawing it (RenderProbes.swift). The literals below were
// captured from the rule the lead had when it lived in `TideDetailView`.
import XCTest
@testable import Slackwater
import SlackwaterKit

@MainActor final class TideLeadTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)
    private let utc = TimeZone(identifier: "UTC")!

    private func tide() throws -> TimelineData {
        let r = try XCTUnwrap(TideStationRecord.record(id: TideStationRecord.fridayHarborID))
        return TimelineData.build(tide: r, current: nil, now: at, anchor: at)
    }

    /// The test feeds the interpolated height; the view feeds the exact one. Both are inputs, the rule under test is the state.
    private func lead(_ t: Date, in tl: TimelineData, previewRate: Double? = nil) -> TideLead {
        TideLead(timeline: tl, scrubTime: t,
                 height: tl.heightAt(t), rate: tl.rateAt(t), previewRate: previewRate,
                 imperial: true, tz: utc)
    }

    /// Hourly samples over `at(-3600)...at(18_000)` at a steady `rate` in metres per hour, with no turn anywhere.
    private func steady(rate: Double) -> TimelineData {
        let hours = Array(-1...5)
        return TimelineData(
            tz: utc, anchor: at, today: at,
            start: at.addingTimeInterval(-3600), end: at.addingTimeInterval(18_000),
            days: [],
            tidePoints: hours.map { TidePoint(time: at.addingTimeInterval(Double($0) * 3600), height: 1 + rate * Double($0)) },
            tideRates: hours.map { TideRatePoint(time: at.addingTimeInterval(Double($0) * 3600), rate: rate) },
            tideExtremes: [],
            currentPoints: [], currentEvents: [], snapTimes: [], slackWindows: [])
    }

    func testMidRiseReadsRising() throws {
        let tl = try tide()
        let pair = try XCTUnwrap(zip(tl.tideExtremes, tl.tideExtremes.dropFirst())
            .first { $0.0.kind == .low && $0.0.time > at })
        let mid = pair.0.time.addingTimeInterval(pair.1.time.timeIntervalSince(pair.0.time) / 2)
        let r = lead(mid, in: tl).reading
        XCTAssertEqual(r.state, "Rising")
        XCTAssertEqual(r.word, "Rising")
        XCTAssertEqual(r.glyph, "arrow.up.right")
        XCTAssertTrue(r.rising)
        XCTAssertFalse(r.atTurn)
        XCTAssertEqual(r.value, "4.0")
        XCTAssertEqual(r.spoken, "Rising 4.0 feet")
        XCTAssertEqual(r.spoken, spokenReading("Rising", r.value, unit: "ft"))
    }

    func testMidFallReadsFalling() throws {
        let tl = try tide()
        let pair = try XCTUnwrap(zip(tl.tideExtremes, tl.tideExtremes.dropFirst())
            .first { $0.0.kind == .high && $0.0.time > at })
        let mid = pair.0.time.addingTimeInterval(pair.1.time.timeIntervalSince(pair.0.time) / 2)
        let r = lead(mid, in: tl).reading
        XCTAssertEqual(r.state, "Falling")
        XCTAssertEqual(r.word, "Falling")
        XCTAssertEqual(r.glyph, "arrow.down.right")
        XCTAssertFalse(r.rising)
        XCTAssertFalse(r.atTurn)
        XCTAssertEqual(r.value, "6.2")
        XCTAssertEqual(r.spoken, "Falling 6.2 feet")
    }

    func testAtAHighReadsHigh() throws {
        let tl = try tide()
        let high = try XCTUnwrap(tl.tideExtremes.first { $0.kind == .high && $0.time > at })
        let r = lead(high.time, in: tl).reading
        XCTAssertEqual(r.state, "High")
        XCTAssertEqual(r.word, "High")
        XCTAssertEqual(r.glyph, "arrow.up.to.line")
        XCTAssertTrue(r.rising)
        XCTAssertTrue(r.atTurn)
        XCTAssertEqual(r.value, "7.1")
        XCTAssertEqual(r.spoken, "High 7.1 feet")
    }

    func testAtALowReadsLow() throws {
        let tl = try tide()
        let low = try XCTUnwrap(tl.tideExtremes.first { $0.kind == .low && $0.time > at })
        let r = lead(low.time, in: tl).reading
        XCTAssertEqual(r.state, "Low")
        XCTAssertEqual(r.word, "Low")
        XCTAssertEqual(r.glyph, "arrow.down.to.line")
        XCTAssertFalse(r.rising)
        XCTAssertTrue(r.atTurn)
        XCTAssertEqual(r.value, "0.6")
        XCTAssertEqual(r.spoken, "Low 0.6 feet")
    }

    /// Snap targets land exactly on the extreme; the 1 s window forgives the rest.
    func testHalfASecondFromATurnStillReadsTheTurn() throws {
        let tl = try tide()
        let high = try XCTUnwrap(tl.tideExtremes.first { $0.kind == .high && $0.time > at })
        let r = lead(high.time.addingTimeInterval(-0.5), in: tl).reading
        XCTAssertEqual(r.state, "High")
        XCTAssertTrue(r.atTurn)
    }

    func testFastWaterNamesTheRate() {
        let tl = steady(rate: 0.8)
        let t = at.addingTimeInterval(3600)
        let r = lead(t, in: tl).reading
        XCTAssertEqual(r.state, tideRateReading(rate: 0.8, imperial: true))
        XCTAssertEqual(r.state, "Rising 2.6 ft/hr")
        XCTAssertEqual(r.word, "Rising")
        XCTAssertEqual(r.glyph, "arrow.up.right")
        XCTAssertTrue(r.rising)
        XCTAssertFalse(r.atTurn)
        XCTAssertEqual(r.value, "5.9")
        XCTAssertEqual(r.spoken, spokenTideRate(after: spokenReading("Rising", r.value, unit: "ft"), rate: 0.8, imperial: true))
        XCTAssertEqual(r.spoken, "Rising 5.9 feet, 2.6 feet per hour")
    }

    /// The old rule, on purpose: with no turn ahead the lead falls back to rising, even where the water is falling. Task 2 flips it.
    func testNoLaterTurnReadsRisingByDefault() {
        let tl = steady(rate: -0.2)
        let r = lead(at.addingTimeInterval(3600), in: tl).reading
        XCTAssertEqual(r.state, "Rising")
        XCTAssertEqual(r.glyph, "arrow.up.right")
        XCTAssertTrue(r.rising)
    }

    func testAPreviewReadsItsOwnSlope() {
        let tl = steady(rate: -0.2)
        let r = lead(at.addingTimeInterval(3600), in: tl, previewRate: -0.3).reading
        XCTAssertEqual(r.state, "Falling")
        XCTAssertEqual(r.glyph, "arrow.down.right")
        XCTAssertFalse(r.rising)
    }
}
