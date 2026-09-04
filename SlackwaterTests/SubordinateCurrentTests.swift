import XCTest
import TideEngine
@testable import Slackwater

/// Subordinate current stations (#268): a bundled record with `reference` and
/// NOAA's six offsets and no constituents predicts its reference's events,
/// shifted and scaled — with a curve to draw, never a flat line.
final class SubordinateCurrentTests: XCTestCase {
    private var bonita: CurrentStationRecord {
        CurrentStationRecord.all.first { $0.id == "noaa/PCT0236" }!
    }
    private var goldenGate: CurrentStationRecord {
        CurrentStationRecord.all.first { $0.id == "noaa/SFB1201" }!
    }
    private let day = Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-14

    func testBundledSubordinateDecodesItsOffsets() {
        XCTAssertEqual(bonita.reference, "noaa/SFB1201")
        XCTAssertEqual(bonita.floodTimeOffset, -3840)
        XCTAssertEqual(bonita.ebbSpeedRatio, 0.5)
        XCTAssertTrue(bonita.constituents.isEmpty)
        XCTAssertTrue(bonita.isSubordinate)
        XCTAssertFalse(goldenGate.isSubordinate)
    }

    func testSubordinateEventsAreTheReferencesShiftedAndScaled() {
        let end = day.addingTimeInterval(86_400)
        let ref = goldenGate.engineStation.events(from: day, to: end).filter { $0.kind == .maxFlood }
        let sub = bonita.engineStation.events(from: day, to: end).filter { $0.kind == .maxFlood }
        XCTAssertFalse(ref.isEmpty)
        for s in sub {
            let r = ref.min { abs($0.time.timeIntervalSince(s.time) + 3840) < abs($1.time.timeIntervalSince(s.time) + 3840) }!
            XCTAssertEqual(s.time.timeIntervalSince(r.time), -3840, accuracy: 1)
            XCTAssertEqual(s.speed, r.speed * 0.3, accuracy: 0.001)
        }
    }

    func testSubordinateCurveIsNotFlat() {
        let speeds = bonita.engineStation.speeds(from: day, to: day.addingTimeInterval(86_400), step: 600).map(\.speed)
        XCTAssertGreaterThan(speeds.max()! - speeds.min()!, 0.5)
        XCTAssertNotEqual(bonita.cardState(at: day).signed, 0)
        XCTAssertNotEqual(currentPinColour(bonita, at: day), "unknown")
    }

    /// The pin's per-reference shortcut must agree with the engine's own
    /// per-station search at every hour of a day.
    func testPinColourMatchesExactSearchForASubordinate() {
        for hour in 0..<24 {
            let t = day.addingTimeInterval(Double(hour) * 3600)
            let exact = bonita.engineStation.speeds(from: t, to: t.addingTimeInterval(1), step: 1).first!.speed
            let exactColour = abs(exact) <= slackThresholdKn
                ? mapHex(SN.goHex, darkenedBy: PIN_STATE_DARKEN) : pinRampHex(forSpeedKn: abs(exact))
            XCTAssertEqual(currentPinColour(bonita, at: t), exactColour, "hour \(hour)")
        }
    }
}
