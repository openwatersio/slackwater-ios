// Slackwater — GPL v3. Station provenance shown on current details (#170).
import XCTest
@testable import Slackwater

final class CurrentStationDetailsTests: XCTestCase {
    func testMeanFlowNamesTheDirectionItLeans() {
        XCTAssertEqual(record(meanFlow: 0.31).detailsMeanFlow(unit: "kn"), "0.3 kn toward flood")
        XCTAssertEqual(record(meanFlow: -0.31).detailsMeanFlow(unit: "kn"), "0.3 kn toward ebb")
    }

    /// Under the formatter's own 0.05 kn floor the speed prints as 0.0 and the
    /// sign is noise — a confident "0.0 kn toward ebb" would be a lie.
    func testNegligibleMeanFlowReadsAsNone() {
        XCTAssertEqual(record(meanFlow: -0.02).detailsMeanFlow(unit: "kn"), "None measured")
    }

    func testHarmonicStationHasNoOffsetTable() {
        let harmonic = record(meanFlow: 0)
        XCTAssertNil(harmonic.detailsOffsets)
        XCTAssertEqual(harmonic.detailsPrediction, "2 harmonic constituents, computed on this device")
    }

    func testSubordinateShowsNoaaTableAsPublished() throws {
        var sub = record(meanFlow: 0)
        sub.reference = "noaa/ref"
        sub.slackBeforeFloodOffset = 720      // +12 min
        sub.floodTimeOffset = -1_800          // −30 min
        sub.slackBeforeEbbOffset = 0
        sub.ebbTimeOffset = 3_600             // +60 min
        sub.floodSpeedRatio = 0.85
        sub.ebbSpeedRatio = 1.2

        let offsets = try XCTUnwrap(sub.detailsOffsets)
        XCTAssertEqual(offsets.times,
                       "slack before flood +12 min · max flood -30 min · slack before ebb 0 min · max ebb +60 min")
        XCTAssertEqual(offsets.ratios, "flood ×0.85 · ebb ×1.20")
        XCTAssertTrue(sub.detailsPrediction.contains("NOAA offsets"))
    }

    private func record(meanFlow: Double) -> CurrentStationRecord {
        CurrentStationRecord(
            id: "noaa/TEST", name: "Test", region: "Test", aliases: [],
            latitude: 0, longitude: 0, timezone: "UTC",
            floodDirection: 90, ebbDirection: 270, meanFlow: meanFlow, tideReference: nil,
            constituents: [.init(name: "M2", amplitude: 1, phase: 0),
                            .init(name: "S2", amplitude: 0.2, phase: 30)])
    }
}
