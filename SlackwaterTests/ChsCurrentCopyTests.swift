// Slackwater — GPL v3. Measured limits stay separate from download progress.
import XCTest
@testable import Slackwater

final class ChsCurrentCopyTests: XCTestCase {
    private func gate(clause: String = "peak_speed", value: Double? = 0.8,
                      nearBar: Bool = false) -> ChsCurrentGateInfo {
        var gate = ChsCurrentGateInfo(
            id: "test", name: "Test Pass", region: "Test", aliases: [],
            latitude: 50, longitude: -125, timezone: "America/Vancouver",
            tideReference: nil, fitDays: 210, provisionalSlackMinutes: 40)
        gate.onlineMiss = ChsCurrentOnlineMiss(clause: clause, value: value, nearBar: nearBar)
        return gate
    }

    func testBoundNamesCHSAndUsesTheGateValue() {
        XCTAssertEqual(gate().boundHeadline(minutes: 35),
                       "Slack at Test Pass can differ from CHS's prediction by up to 35 min.")
        XCTAssertEqual(gate().provisionalHeadline,
                       "Slack at Test Pass can differ from CHS's prediction by up to 40 min.")
    }

    func testPeakSpeedUsesSelectedUnit() {
        let text = gate().onlineExplanation(speedUnit: "kmh")
        XCTAssertTrue(text.contains("1.5 km/h"), text)
        XCTAssertFalse(text.contains("kn"), text)
        XCTAssertTrue(gate().onlineExplanation(speedUnit: "ms").contains("0.4 m/s"))
    }

    func testNearBarDoesNotPresentAPassingValueAsAFailure() {
        let text = gate(value: 0.45, nearBar: true).onlineExplanation(speedUnit: "kn")
        XCTAssertTrue(text.contains("close to the validation bar"), text)
        XCTAssertFalse(text.contains("0.5"), text)
    }

    func testMissingQuarterDoesNotInventANumber() {
        let text = gate(clause: "slack_median", value: nil).onlineExplanation(speedUnit: "kn")
        XCTAssertTrue(text.contains("not enough CHS events"), text)
    }

    func testContextAndEachMissAreWholeSentences() {
        for clause in ["reversed_axis", "invented_slack", "missed_slack", "slack_worst",
                       "slack_median", "extremum_timing", "peak_speed"] {
            var g = gate(clause: clause, value: 2)
            g.missContext = "rapids"
            let text = g.onlineExplanation(speedUnit: "kn")
            XCTAssertTrue(text.hasPrefix("This place has tidal rapids. "), text)
            XCTAssertTrue(text.hasSuffix("."), text)
        }
    }
}
