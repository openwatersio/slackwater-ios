// Slackwater — GPL v3. The Alerts screen says why a rule is quiet, never just that it is.
import XCTest
@testable import Slackwater

final class AlertStatusTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let gb = Locale(identifier: "en_GB")
    private let through = Date(timeIntervalSince1970: 1_787_529_600)   // 2026-08-24 00:00 UTC

    private func text(_ rule: AlertRule, _ status: AlertStatusSnapshot, premium: Bool = true) -> String {
        alertStatusText(rule, status, premium: premium, tz: utc, locale: gb)
    }

    func testStatusSaysWhyARuleIsQuiet() {
        let rule = AlertRule(stationID: "x", trigger: .slack, alert: .notification)
        var status = AlertStatusSnapshot(scheduledThrough: [rule.id: through], unresolved: [],
                                         notificationsAuthorized: true, calendarAuthorized: true)

        XCTAssertEqual(text(rule, status), "Scheduled through 24 Aug")
        XCTAssertEqual(text(rule, status, premium: false), "Calendar only — notifications are Premium")

        status.notificationsAuthorized = false
        XCTAssertEqual(text(rule, status), "Notifications are off in Settings")

        status.unresolved = [rule.id]
        XCTAssertEqual(text(rule, status), "Waiting for station data")

        var off = rule
        off.enabled = false
        XCTAssertEqual(text(off, status), "Off")
    }

    func testCalendarOnlyRules() {
        let rule = AlertRule(stationID: "x", trigger: .eclipse)
        var status = AlertStatusSnapshot(calendarAuthorized: false)
        XCTAssertEqual(text(rule, status), "Calendar access is off in Settings")

        status.calendarAuthorized = true
        XCTAssertEqual(text(rule, status), "Nothing coming up")

        let notifyOnly = AlertRule(stationID: "x", trigger: .slack, calendar: false, alert: .notification)
        XCTAssertEqual(text(notifyOnly, status, premium: false), "Notifications are Premium")
    }
}
