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

    func testADisabledRuleSaysOff() {
        var rule = AlertRule(stationID: "a", trigger: .slack)
        rule.enabled = false
        XCTAssertEqual(alertStatusText(rule, AlertStatusSnapshot(), premium: true), "Off")
    }

    func testAnUnresolvedRuleIsWaitingForStationData() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let status = AlertStatusSnapshot(unresolved: [rule.id])
        XCTAssertEqual(alertStatusText(rule, status, premium: true), "Waiting for station data")
    }

    func testAResolvedRuleWithNothingScheduledSaysSo() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let status = AlertStatusSnapshot(notificationsAuthorized: true)
        XCTAssertEqual(alertStatusText(rule, status, premium: true), "Nothing coming up")
    }

    func testAScheduledRuleFormatsWithTheGivenTimeZoneAndLocale() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let through = Date(timeIntervalSince1970: 1_787_529_600)   // 2026-08-24 00:00 UTC
        let status = AlertStatusSnapshot(scheduledThrough: [rule.id: through], notificationsAuthorized: true)
        XCTAssertEqual(alertStatusText(rule, status, premium: true,
                                       tz: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_GB")),
                       "Scheduled through 24 Aug")
    }

    func testATideAndACurrentStationWithOneNameStaySeparate() {
        let tide = AlertRule(stationID: "noaa/9449880", trigger: .tideExtreme(high: false))
        let current = AlertRule(stationID: "current:noaa/PUG1515", trigger: .slackWindowOpens)

        let groups = alertStationGroups([tide, current]) { _ in "Friday Harbor" }

        XCTAssertEqual(groups.map(\.stationID), ["current:noaa/PUG1515", "noaa/9449880"])
        XCTAssertEqual(groups.map(\.rules), [[current], [tide]])
    }
}
