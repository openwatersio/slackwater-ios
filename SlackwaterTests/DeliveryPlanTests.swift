// Slackwater — GPL v3. deliveryPlan: horizons, the 64 ceiling, and the free/Premium line.
import XCTest
@testable import Slackwater

final class DeliveryPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func occurrence(_ rule: AlertRule, eventIn seconds: TimeInterval) -> AlertOccurrence {
        let event = now.addingTimeInterval(seconds)
        return AlertOccurrence(ruleID: rule.id, event: event, fire: event.addingTimeInterval(-rule.lead))
    }

    func testNotificationsAreTheSoonestSixtyFourInsideFourteenDays() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let hourly = (1...(24 * 100)).map { occurrence(rule, eventIn: Double($0) * 3_600) }

        let plan = deliveryPlan(rules: [rule], occurrences: hourly.reversed(),
                               calendarOccurrences: [], now: now, premium: true)

        XCTAssertEqual(plan.notifications, Array(hourly.prefix(64)))
    }

    func testASparseRuleStopsAtFourteenDays() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let daily = (1...30).map { occurrence(rule, eventIn: Double($0) * 86_400) }

        let plan = deliveryPlan(rules: [rule], occurrences: daily,
                               calendarOccurrences: [], now: now, premium: true)

        XCTAssertEqual(plan.notifications, Array(daily.prefix(14)))
    }

    func testAFiredNotificationIsDroppedAndItsEventIsNot() {
        let rule = AlertRule(stationID: "a", trigger: .slack, lead: 3_600)
        let o = occurrence(rule, eventIn: 1_800)   // fired 30 min ago, happens in 30 min

        let plan = deliveryPlan(rules: [rule], occurrences: [o],
                               calendarOccurrences: [o], now: now, premium: true)

        XCTAssertEqual(plan.notifications, [])
        XCTAssertEqual(plan.calendar, [o])
    }

    func testWithoutPremiumTheCalendarIsPlannedAndNothingElseIs() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let o = occurrence(rule, eventIn: 3_600)

        let plan = deliveryPlan(rules: [rule], occurrences: [o],
                               calendarOccurrences: [o], now: now, premium: false)

        XCTAssertEqual(plan, DeliveryPlan(calendar: [o], notifications: []))
    }

    func testDisabledAndUnknownRulesPlanNothing() {
        var off = AlertRule(stationID: "a", trigger: .slack)
        off.enabled = false
        let orphan = AlertRule(stationID: "b", trigger: .slack)

        let plan = deliveryPlan(rules: [off],
                                occurrences: [occurrence(off, eventIn: 60), occurrence(orphan, eventIn: 60)],
                                calendarOccurrences: [], now: now, premium: true)

        XCTAssertEqual(plan, DeliveryPlan())
    }

    func testADuplicatedRuleIdPlansOnceAndDoesNotCrash() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let o = occurrence(rule, eventIn: 3_600)

        let plan = deliveryPlan(rules: [rule, rule], occurrences: [o],
                               calendarOccurrences: [], now: now, premium: true)

        XCTAssertEqual(plan, DeliveryPlan(calendar: [], notifications: [o]))
    }

    func testTwoRulesOnTheSameMomentDeliverOneNotification() {
        // A `once` rule on one moment beside an "Every low tide" rule: at the moment itself the two
        // carry the same title and the same body.
        let station = "a"
        let trigger = AlertTrigger.tideExtreme(high: false)
        let every = AlertRule(stationID: station, trigger: trigger, lead: 1_800)
        let event = now.addingTimeInterval(7_200)
        let once = AlertRule(stationID: station, trigger: trigger, once: event, lead: 1_800)
        let fire = event.addingTimeInterval(-1_800)

        let plan = deliveryPlan(rules: [every, once],
                                occurrences: [AlertOccurrence(ruleID: every.id, event: event, fire: fire),
                                              AlertOccurrence(ruleID: once.id, event: event, fire: fire)],
                                calendarOccurrences: [], now: now, premium: true)

        XCTAssertEqual(plan.notifications.count, 1)
        XCTAssertEqual(plan.notifications.first?.event, event)
        // The `once` rule is the one kept: it has no other occurrence to show on the Alerts
        // screen, while the repeating rule names its next low tide either way.
        XCTAssertEqual(plan.notifications.first?.ruleID, once.id)
        XCTAssertNotNil(scheduledThrough(plan)[once.id])
    }

    func testTheSameMomentAtTwoLeadsStaysTwoReminders() {
        // Half an hour before and a day before are genuinely two different reminders.
        let station = "a"
        let trigger = AlertTrigger.tideExtreme(high: false)
        let soon = AlertRule(stationID: station, trigger: trigger, lead: 1_800)
        let day = AlertRule(stationID: station, trigger: trigger, lead: 86_400)
        let event = now.addingTimeInterval(2 * 86_400)

        let plan = deliveryPlan(rules: [soon, day],
                                occurrences: [occurrence(soon, eventIn: 2 * 86_400),
                                              occurrence(day, eventIn: 2 * 86_400)],
                                calendarOccurrences: [], now: now, premium: true)

        XCTAssertEqual(plan.notifications.count, 2)
        XCTAssertEqual(Set(plan.notifications.map(\.fire)),
                       [event.addingTimeInterval(-1_800), event.addingTimeInterval(-86_400)])
    }

    func testTwoStationsOnTheSameMomentBothDeliver() {
        let here = AlertRule(stationID: "a", trigger: .slack)
        let there = AlertRule(stationID: "b", trigger: .slack)

        let plan = deliveryPlan(rules: [here, there],
                                occurrences: [occurrence(here, eventIn: 3_600),
                                              occurrence(there, eventIn: 3_600)],
                                calendarOccurrences: [], now: now, premium: true)

        XCTAssertEqual(plan.notifications.count, 2)
    }

    func testCalendarOccurrencesStopAtNinetyDaysAndSortByEvent() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let late = occurrence(rule, eventIn: 91 * 86_400)
        let soon = occurrence(rule, eventIn: 86_400)
        let sooner = occurrence(rule, eventIn: 3_600)

        let plan = deliveryPlan(rules: [], occurrences: [],
                               calendarOccurrences: [late, soon, sooner], now: now, premium: false)

        XCTAssertEqual(plan.calendar, [sooner, soon])
    }

    func testScheduledThroughIsEachRulesLastNotification() {
        let tide = AlertRule(stationID: "a", trigger: .tideExtreme(high: false), lead: 600)
        let pass = AlertRule(stationID: "b", trigger: .slackWindowOpens)
        let plan = DeliveryPlan(calendar: [],
                                notifications: [occurrence(tide, eventIn: 40 * 86_400),
                                                occurrence(tide, eventIn: 86_400),
                                                occurrence(pass, eventIn: 7_200)])

        let through = scheduledThrough(plan)

        XCTAssertEqual(through[tide.id], now.addingTimeInterval(40 * 86_400 - 600))
        XCTAssertEqual(through[pass.id], now.addingTimeInterval(7_200))
    }
}
