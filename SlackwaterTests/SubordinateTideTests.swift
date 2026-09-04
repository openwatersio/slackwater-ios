import XCTest
import TideEngine
@testable import Slackwater

/// Subordinate tide stations (#229): a bundled record with `reference` and
/// `offsets` and no constituents predicts its reference's water, shifted and
/// scaled — never a flat line, never the reference's own curve.
final class SubordinateTideTests: XCTestCase {
    private var nurse: TideStationRecord {
        TideStationRecord.all.first { $0.id == "noaa/TEC4635" }!
    }
    private var settlementPoint: TideStationRecord {
        TideStationRecord.all.first { $0.id == "noaa/9710441" }!
    }
    private let day = Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-14

    func testBundledSubordinateDecodesItsOffsets() {
        XCTAssertEqual(nurse.reference, "noaa/9710441")
        XCTAssertEqual(nurse.offsets?.time.low, 10)
        XCTAssertEqual(nurse.offsets?.height.high, 0.79)
        XCTAssertTrue(nurse.constituents.isEmpty)
        XCTAssertTrue(nurse.isSubordinate)
        XCTAssertFalse(settlementPoint.isSubordinate)
    }

    func testSubordinatePredictsScaledReferenceExtremes() {
        let end = day.addingTimeInterval(86_400)
        let ref = settlementPoint.engineStation.extremes(from: day, to: end)
        let sub = nurse.engineStation.extremes(from: day, to: end)
        XCTAssertEqual(ref.count, sub.count)
        for (r, s) in zip(ref, sub) {
            XCTAssertEqual(r.kind, s.kind)
            let ratio = r.kind == .high ? 0.79 : 1.11
            XCTAssertEqual(s.height, r.height * ratio, accuracy: 0.001)
            let shift = r.kind == .high ? 0.0 : 600.0
            XCTAssertEqual(s.time.timeIntervalSince(r.time), shift, accuracy: 1)
        }
    }

    func testSubordinateCurveIsNotFlat() {
        let heights = nurse.engineStation.heights(from: day, to: day.addingTimeInterval(86_400), step: 600)
        let range = heights.map(\.height).max()! - heights.map(\.height).min()!
        XCTAssertGreaterThan(range, 0.3)
        XCTAssertNotEqual(nurse.cardState(at: day).height, 0)
    }

    /// The pin's shortcut must agree with the engine's own exact search at
    /// every hour of a day, including the hours near a turn.
    func testPinDirectionMatchesExactSearchForASubordinate() {
        for hour in 0..<24 {
            let t = day.addingTimeInterval(Double(hour) * 3600)
            XCTAssertEqual(tidePinRisingHybrid(nurse, at: t),
                           tidePinRising(nurse, at: t, window: PIN_TIDE_FALLBACK_WINDOW),
                           "hour \(hour)")
        }
    }
}
