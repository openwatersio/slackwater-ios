// Slackwater — GPL v3. resolveAlerts: rules → occurrences and places, with unknown stations reported rather than dropped.
import XCTest
@testable import Slackwater

final class AlertResolveTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_755_800_000)

    func testResolveNamesPlacesAndReportsUnknownStations() {
        let good = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .tideExtreme(high: true))
        let unknown = AlertRule(stationID: "noaa/does-not-exist", trigger: .tideExtreme(high: true))
        var off = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .tideExtreme(high: false))
        off.enabled = false

        let resolved = resolveAlerts([good, unknown, off], now: now, threshold: 0.5)

        XCTAssertEqual(resolved.unresolved, [unknown.id])
        XCTAssertEqual(resolved.places[TideStationRecord.fridayHarborID]?.name, "Friday Harbor")
        XCTAssertFalse(resolved.occurrences.isEmpty)
        XCTAssertTrue(resolved.occurrences.allSatisfy { $0.ruleID == good.id })
        XCTAssertTrue(resolved.occurrences.allSatisfy { $0.event.timeIntervalSince(self.now) <= AlertHorizon.calendar })
    }
}
