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
        XCTAssertEqual(r.samples.first?.hours ?? 0, -3, accuracy: 1e-9)
        XCTAssertEqual(r.samples.last?.hours ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(r.samples.count, 13 * 6 + 1)
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

    func testCurrentSlackRunsCoverEverySampleUnderTheThreshold() throws {
        let r = try XCTUnwrap(ComplicationReading.build(current, now: now))
        XCTAssertEqual(r.kind, .current)
        for s in r.samples where abs(s.value) < slackThresholdKn {
            XCTAssert(r.slackRuns.contains { $0.contains(s.hours) }, "sample at \(s.hours) h")
        }
    }

    func testInsideAWindowTheDotSitsInTheWindow() throws {
        // Walk forward until the current is under the slack threshold.
        guard case .current(let s, _, _) = current else { return XCTFail() }
        let slackAt = try XCTUnwrap(s.speeds(from: now, to: now.addingTimeInterval(86_400), step: 300)
            .first { abs($0.speed) < slackThresholdKn * 0.5 }?.time)
        let g = try XCTUnwrap(ComplicationReading.build(current, now: slackAt)?.gauge)
        XCTAssertGreaterThanOrEqual(g.fraction, try XCTUnwrap(g.windowStart))
        XCTAssertLessThanOrEqual(g.fraction, 1)
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
