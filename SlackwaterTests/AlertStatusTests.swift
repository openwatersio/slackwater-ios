// Slackwater — GPL v3. The Alerts screen says why a rule is quiet, never just that it is.
import XCTest
@testable import Slackwater

final class AlertStatusTests: XCTestCase {
    func testAPremiumlessRuleSaysSo() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        XCTAssertEqual(alertStatusText(rule, AlertStatusSnapshot(), premium: false),
                       "Notifications are Premium")
    }

    func testAPremiumRuleWithNotificationsOffSaysSo() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let status = AlertStatusSnapshot(notificationsAuthorized: false)
        XCTAssertEqual(alertStatusText(rule, status, premium: true),
                       "Notifications are off in Settings")
    }

    func testATideAndACurrentStationWithOneNameStaySeparate() {
        let tide = AlertRule(stationID: "noaa/9449880", trigger: .tideExtreme(high: false))
        let current = AlertRule(stationID: "current:noaa/PUG1515", trigger: .slackWindowOpens)

        let groups = alertStationGroups([tide, current]) { _ in "Friday Harbor" }

        XCTAssertEqual(groups.map(\.stationID), ["current:noaa/PUG1515", "noaa/9449880"])
        XCTAssertEqual(groups.map(\.rules), [[current], [tide]])
    }
}
