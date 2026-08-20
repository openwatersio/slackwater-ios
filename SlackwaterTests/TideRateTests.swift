// Slackwater — GPL v3. Rate of rise (#95 part 1): dh/dt for the detail
// readout. Analytic in spirit — a centered difference of exact engine
// evaluations, not neighbouring 600 s strip samples (TideStation.swift:48
// records why sample differencing near a turn picks up numerical noise).
import XCTest
import TideEngine
@testable import Slackwater

final class TideRateTests: XCTestCase {
    // Pure M2, 1 m amplitude: dh/dt = A·f·ω·sin(...), so it vanishes at the
    // turns and peaks near A·ω = 2π/12.4206 h ≈ 0.506 m/hr halfway between
    // them (node factor f keeps the true value within a few percent).
    private let m2 = Station(constituents: [HarmonicConstituent(name: "M2", amplitude: 1.0, phase: 0)])
    private let start = Date(timeIntervalSince1970: 1_770_000_000)

    private func firstRise() -> (low: TideExtreme, high: TideExtreme) {
        let ex = m2.extremes(from: start, to: start.addingTimeInterval(24 * 3600))
        let lowIdx = ex.firstIndex { $0.kind == .low }!
        return (ex[lowIdx], ex[lowIdx + 1])
    }

    func testRateVanishesAtTheTurns() {
        let (low, high) = firstRise()
        XCTAssertEqual(m2.rateOfChange(at: low.time), 0, accuracy: 0.05)
        XCTAssertEqual(m2.rateOfChange(at: high.time), 0, accuracy: 0.05)
    }

    func testRatePeaksMidTideInMetresPerHour() {
        let (low, high) = firstRise()
        let mid = low.time.addingTimeInterval(high.time.timeIntervalSince(low.time) / 2)
        let rate = m2.rateOfChange(at: mid)
        // Magnitude in m/hr — a per-second slip would read 0.00014 here.
        XCTAssertEqual(rate, 0.506, accuracy: 0.05)
    }

    func testRateIsNegativeWhileFalling() {
        let (low, high) = firstRise()
        // Same distance past the high as the rise's midpoint was before it.
        let fallingMid = high.time.addingTimeInterval(high.time.timeIntervalSince(low.time) / 2)
        XCTAssertLessThan(m2.rateOfChange(at: fallingMid), -0.4)
    }
}
