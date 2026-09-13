// Slackwater — GPL v3. deliveryPlan: horizons, the 64 ceiling, and the free/Premium line.
import XCTest
@testable import Slackwater

final class DeliveryPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func occurrence(_ rule: AlertRule, eventIn seconds: TimeInterval) -> AlertOccurrence {
        let event = now.addingTimeInterval(seconds)
        return AlertOccurrence(ruleID: rule.id, event: event, fire: event.addingTimeInterval(-rule.lead))
    }

    func testTheCalendarKeepsAnEventWhoseReminderHasPassed() {
        let rule = AlertRule(stationID: "a", trigger: .slack, lead: 3_600, alert: .notification)
        let o = occurrence(rule, eventIn: 1_800)   // fired 30 min ago, happens in 30 min

        let plan = deliveryPlan(rules: [rule], occurrences: [o], now: now, premium: true)

        XCTAssertEqual(plan.calendar, [o])
        XCTAssertEqual(plan.notifications, [])
    }

    func testNotificationsAreTheSoonestSixtyFourInsideFourteenDays() {
        let rule = AlertRule(stationID: "a", trigger: .slack, alert: .notification)
        let hourly = (1...(24 * 100)).map { occurrence(rule, eventIn: Double($0) * 3_600) }

        let plan = deliveryPlan(rules: [rule], occurrences: hourly.reversed(), now: now, premium: true)

        XCTAssertEqual(plan.notifications, Array(hourly.prefix(64)))
        XCTAssertEqual(plan.calendar.count, 24 * 90)
    }

    func testASparseRuleStopsAtFourteenDays() {
        let rule = AlertRule(stationID: "a", trigger: .slack, calendar: false, alert: .notification)
        let daily = (1...30).map { occurrence(rule, eventIn: Double($0) * 86_400) }

        let plan = deliveryPlan(rules: [rule], occurrences: daily, now: now, premium: true)

        XCTAssertEqual(plan.notifications, Array(daily.prefix(14)))
        XCTAssertEqual(plan.calendar, [])
    }

    func testWithoutPremiumOnlyTheCalendarIsPlanned() {
        let rule = AlertRule(stationID: "a", trigger: .slack, alert: .notification)
        let o = occurrence(rule, eventIn: 3_600)

        let plan = deliveryPlan(rules: [rule], occurrences: [o], now: now, premium: false)

        XCTAssertEqual(plan, DeliveryPlan(calendar: [o], notifications: []))
    }

    func testDisabledAndUnknownRulesPlanNothing() {
        var off = AlertRule(stationID: "a", trigger: .slack, alert: .notification)
        off.enabled = false
        let orphan = AlertRule(stationID: "b", trigger: .slack, alert: .notification)

        let plan = deliveryPlan(rules: [off],
                                occurrences: [occurrence(off, eventIn: 60), occurrence(orphan, eventIn: 60)],
                                now: now, premium: true)

        XCTAssertEqual(plan, DeliveryPlan())
    }

    func testADuplicatedRuleIdPlansOnceAndDoesNotCrash() {
        let rule = AlertRule(stationID: "a", trigger: .slack, alert: .notification)
        let o = occurrence(rule, eventIn: 3_600)

        let plan = deliveryPlan(rules: [rule, rule], occurrences: [o], now: now, premium: true)

        XCTAssertEqual(plan, DeliveryPlan(calendar: [o], notifications: [o]))
    }

    func testScheduledThroughIsEachRulesLastDelivery() {
        let tide = AlertRule(stationID: "a", trigger: .tideExtreme(high: false), lead: 600, alert: .notification)
        let pass = AlertRule(stationID: "b", trigger: .slackWindowOpens, calendar: false, alert: .notification)
        let plan = DeliveryPlan(calendar: [occurrence(tide, eventIn: 86_400), occurrence(tide, eventIn: 40 * 86_400)],
                                notifications: [occurrence(tide, eventIn: 86_400), occurrence(pass, eventIn: 7_200)])

        let through = scheduledThrough(plan)

        XCTAssertEqual(through[tide.id], now.addingTimeInterval(40 * 86_400))
        XCTAssertEqual(through[pass.id], now.addingTimeInterval(7_200))
    }
}
