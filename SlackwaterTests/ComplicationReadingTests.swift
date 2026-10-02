// Slackwater — GPL v3. What the watch's inline, circular and corner
// complications draw (#524).
import XCTest
import SlackwaterKit
@testable import Slackwater

final class ComplicationReadingTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let now = Date(timeIntervalSince1970: 1_755_800_000)

    private var tide: WidgetStation {
        .tide(Station(constituents: [HarmonicConstituent(name: "M2", amplitude: 1, phase: 0)], offset: 1.5),
              tz: utc, name: "Test Tide")
    }
    private var current: WidgetStation {
        WidgetStationLoader.load(id: "current:" + CurrentStationRecord.all.first!.id)!
    }

    func testTideWordFollowsTheNextSample() throws {
        let r = try XCTUnwrap(ComplicationReading.build(tide, now: now))
        let i = try XCTUnwrap(r.samples.firstIndex { $0.hours >= 0 })
        let rising = r.samples[i + 1].value > r.samples[i].value
        XCTAssertEqual(r.word, rising ? "Rising" : "Falling")
        XCTAssertEqual(r.symbol, rising ? "arrow.up" : "arrow.down")
        XCTAssertEqual(try XCTUnwrap(r.gauge).towardEnd, rising)
    }

    func testSamplesCoverTheSpanEveryTenMinutes() throws {
        let r = try XCTUnwrap(ComplicationReading.build(tide, now: now))
        // The engine aligns samples to a ten-minute grid, so the ends land
        // within one step of the span's.
        let step = 1.0 / 6
        XCTAssert((-3 ... -3 + step).contains(try XCTUnwrap(r.samples.first).hours))
        XCTAssert((3 - step ... 3).contains(try XCTUnwrap(r.samples.last).hours))
        for (a, b) in zip(r.samples, r.samples.dropFirst()) {
            XCTAssertEqual(b.hours - a.hours, step, accuracy: 1e-6)
        }
    }

    func testTideGaugeSitsBetweenItsTurns() throws {
        let g = try XCTUnwrap(ComplicationReading.build(tide, now: now)?.gauge)
        XCTAssert((0...1).contains(g.fraction))
        XCTAssertNil(g.windowStart)
        let lo = try XCTUnwrap(Double(try XCTUnwrap(g.startText)))
        let hi = try XCTUnwrap(Double(try XCTUnwrap(g.endText)))
        XCTAssertLessThan(lo, hi)
    }

    func testValueTextCarriesNoUnit() throws {
        let saved = AppGroup.defaults.string(forKey: unitsKey)
        defer { AppGroup.defaults.set(saved, forKey: unitsKey) }
        for units in ["metric", "imperial"] {
            AppGroup.defaults.set(units, forKey: unitsKey)
            let t = try XCTUnwrap(ComplicationReading.build(tide, now: now))
            let c = try XCTUnwrap(ComplicationReading.build(current, now: now))
            for text in [t.valueText, c.valueText] {
                XCTAssertNil(text.rangeOfCharacter(from: .letters), "\(units): \(text)")
            }
        }
    }

    /// The card's windows for `current` around `at`, over the reading's
    /// range (-3 h to +26 h), built straight from the station.
    private func cardRuns(at t: Date) throws -> [WindowRun] {
        guard case .current(let s, _, _) = current else { throw XCTSkip("fixture is not a current") }
        let from = t.addingTimeInterval(-3 * 3600), to = t.addingTimeInterval(26 * 3600)
        return cardWindows(points: s.speeds(from: from, to: to, step: 600),
                           slacks: s.events(from: from, to: to).filter { $0.kind == .slack }.map(\.time))
    }

    func testCurrentSlackRunsAreTheCardWindows() throws {
        let r = try XCTUnwrap(ComplicationReading.build(current, now: now))
        XCTAssertEqual(r.kind, .current)
        let hours = { (t: Date) in t.timeIntervalSince(self.now) / 3600 }
        let expected = try cardRuns(at: now).map { hours($0.start)...hours($0.end) }
            .filter { $0.overlaps(ComplicationReading.span) }
        XCTAssertFalse(expected.isEmpty, "the fixture has a window within ±3 h")
        XCTAssertEqual(r.slackRuns, expected)
    }

    func testInsideAWindowTheDotSitsInTheWindow() throws {
        guard case .current(_, let tz, _) = current else { return XCTFail() }
        let ahead = try XCTUnwrap(try cardRuns(at: now).first { $0.start > now })
        let t = ahead.start.addingTimeInterval(ahead.end.timeIntervalSince(ahead.start) / 2)
        let r = try XCTUnwrap(ComplicationReading.build(current, now: t))
        let g = try XCTUnwrap(r.gauge)
        XCTAssertGreaterThanOrEqual(g.fraction, try XCTUnwrap(g.windowStart))
        XCTAssertLessThanOrEqual(g.fraction, 1)
        XCTAssertEqual(r.word, CurrentPhase.slack.word)
        // The label is when the window closes, never a time already past.
        let window = try XCTUnwrap(try cardRuns(at: t).first { $0.contains(t) })
        XCTAssertGreaterThan(window.end, t)
        XCTAssertEqual(g.endText, cardTime(window.end, tz))
    }

    func testWordIsSlackInsideAWindowAboveTheFixedThreshold() throws {
        // A moment the card calls slack (inside its window) whose speed is
        // still above the phase word's fixed 0.15 kn.
        guard case .current(let s, _, _) = current else { return XCTFail() }
        let runs = try cardRuns(at: now)
        let p = try XCTUnwrap(s.speeds(from: now, to: now.addingTimeInterval(48 * 3600), step: 600).first { p in
            (slackKn..<slackThresholdKn).contains(abs(p.speed)) && runs.contains { $0.contains(p.time) }
        })
        XCTAssertNotEqual(currentPhase(signed: p.speed), .slack)
        let r = try XCTUnwrap(ComplicationReading.build(current, now: p.time))
        XCTAssertEqual(r.word, CurrentPhase.slack.word)
        XCTAssertEqual(r.symbol, "arrow.left.arrow.right")
    }

    func testCurrentGaugeEndsAtTheWindow() throws {
        let g = try XCTUnwrap(ComplicationReading.build(current, now: now)?.gauge)
        let start = try XCTUnwrap(g.windowStart)
        XCTAssert((0..<1).contains(start))
        XCTAssertNotNil(g.endText)
        XCTAssertTrue(g.towardEnd)
    }

    func testCurrentWithoutAWindowHasNoGauge() throws {
        // A current that never drops under the threshold: a steady 2 kn flood.
        let steady = Station(constituents: [HarmonicConstituent(name: "M2", amplitude: 0.5, phase: 0)], offset: 2)
        let r = try XCTUnwrap(ComplicationReading.build(
            .current(SteadyCurrent(station: steady), tz: utc, name: "Steady"), now: now))
        XCTAssertNil(r.gauge)
        XCTAssertTrue(r.slackRuns.isEmpty)
        XCTAssertEqual(r.word, "Flooding")
    }

    func testDerivedGateHasNoReading() {
        let reference = Station(constituents: [HarmonicConstituent(name: "M2", amplitude: 1.5, phase: 0)], offset: 3)
        let gate = DerivedSlackStation(reference: reference, hwLagMinutes: 25, lwLagMinutes: 35)
        XCTAssertNil(ComplicationReading.build(.derived(gate, tz: utc, name: "Gate"), now: now))
    }

    func testDeterministic() {
        XCTAssertEqual(ComplicationReading.build(tide, now: now), ComplicationReading.build(tide, now: now))
    }
}

/// A current whose speed is a tide curve read as knots: always flooding when
/// the curve stays above zero.
private struct SteadyCurrent: CurrentPredicting {
    let station: Station
    func speeds(from: Date, to: Date, step: TimeInterval) -> [CurrentPoint] {
        station.heights(from: from, to: to, step: step).map { CurrentPoint(time: $0.time, speed: $0.height) }
    }
    func events(from: Date, to: Date) -> [CurrentEvent] { [] }
}
