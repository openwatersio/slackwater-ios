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

        let resolved = resolveAlerts([good, unknown, off], subscriptions: [], now: now, threshold: 0.5)

        XCTAssertEqual(resolved.unresolved, [unknown.id])
        XCTAssertEqual(resolved.places[TideStationRecord.fridayHarborID]?.name, "Friday Harbor")
        XCTAssertFalse(resolved.occurrences.isEmpty)
        XCTAssertTrue(resolved.occurrences.allSatisfy { $0.ruleID == good.id })
        XCTAssertTrue(resolved.occurrences.allSatisfy { $0.event.timeIntervalSince(self.now) <= AlertHorizon.calendar })
    }

    func testASubscribedStationResolvesItsOwnTriggersAndNoRules() {
        let resolved = resolveAlerts([], subscriptions: [TideStationRecord.fridayHarborID],
                                     now: now, threshold: 0.5)

        XCTAssertTrue(resolved.occurrences.isEmpty, "no rules, so no notifications")
        XCTAssertFalse(resolved.calendarOccurrences.isEmpty)
        let triggers = Set(resolved.calendarOccurrences.compactMap {
            resolved.calendarRules[$0.ruleID]?.trigger
        })
        XCTAssertTrue(triggers.contains(.tideExtreme(high: true)))
        XCTAssertTrue(triggers.contains(.tideExtreme(high: false)))
        XCTAssertFalse(triggers.contains(.currentPeak(flood: true)),
                       "a tide station publishes its extremes and nothing else")
    }

    func testEveryCalendarOccurrenceKnowsItsStation() {
        let resolved = resolveAlerts([], subscriptions: [TideStationRecord.fridayHarborID],
                                     now: now, threshold: 0.5)

        XCTAssertFalse(resolved.calendarOccurrences.isEmpty)
        for o in resolved.calendarOccurrences {
            XCTAssertEqual(resolved.calendarStations[o.ruleID], TideStationRecord.fridayHarborID)
        }
    }

    func testASubscriptionWhoseStationCannotLoadResolvesNothingAndIsNamed() {
        let resolved = resolveAlerts([], subscriptions: ["noaa/does-not-exist"],
                                     now: now, threshold: 0.5)

        XCTAssertEqual(resolved.calendarOccurrences, [])
        XCTAssertEqual(resolved.unresolvedStations, ["noaa/does-not-exist"])
    }

    func testCalendarOccurrencesCarryNoLead() {
        let resolved = resolveAlerts([], subscriptions: [TideStationRecord.fridayHarborID],
                                     now: now, threshold: 0.5)

        for o in resolved.calendarOccurrences {
            XCTAssertEqual(o.fire, o.event, "a calendar event sits at its own time")
        }
    }

    func testLosingPremiumKeepsEveryCalendarAndStopsTheNotifications() {
        // Review Focus 3: the free cap applies when a subscription is written, never when one
        // is planned — a lapsed subscriber keeps the four calendars they set up.
        let stations = [TideStationRecord.fridayHarborID]
        let rule = AlertRule(stationID: TideStationRecord.fridayHarborID,
                             trigger: .tideExtreme(high: false), lead: 1_800)
        let resolved = resolveAlerts([rule], subscriptions: stations, now: now, threshold: 0.5)

        let free = deliveryPlan(rules: [rule], occurrences: resolved.occurrences,
                                calendarOccurrences: resolved.calendarOccurrences,
                                now: now, premium: false)

        XCTAssertFalse(free.calendar.isEmpty)
        XCTAssertEqual(free.notifications, [])
    }
}
