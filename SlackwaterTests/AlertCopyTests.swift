// Slackwater — GPL v3. What an alert says: the place, then the event, then the time in the station's zone.
import XCTest
@testable import Slackwater

final class AlertCopyTests: XCTestCase {
    private let place = AlertPlace(name: "Race Passage", tz: TimeZone(identifier: "UTC")!)
    private let gb = Locale(identifier: "en_GB")
    private let event = Date(timeIntervalSince1970: 1_786_372_320)   // 2026-08-10 14:32 UTC

    private func copy(_ trigger: AlertTrigger, lead: TimeInterval = 0, end: Date? = nil, noWindow: Bool = false,
                      heightM: Double? = nil, imperial: Bool = true, includeLead: Bool = true) -> AlertCopy {
        let rule = AlertRule(stationID: "x", trigger: trigger, lead: lead)
        let o = AlertOccurrence(ruleID: rule.id, event: event, fire: event.addingTimeInterval(-lead),
                                end: end, noWindow: noWindow, heightM: heightM)
        return alertCopy(rule, o, place: place, imperial: imperial, threshold: 0.5,
                         includeLead: includeLead, locale: gb)
    }

    func testAWindowNamesItsSpanAndThreshold() {
        XCTAssertEqual(copy(.slackWindowOpens, lead: 1_800, end: event.addingTimeInterval(38 * 60)),
                       AlertCopy(title: "Race Passage - Slack window",
                                 body: "14:32–15:10, under 0.5 kn · in 30 min"))
    }

    func testAHairlineSlackSaysThereIsNoWindow() {
        XCTAssertEqual(copy(.slackWindowOpens, noWindow: true),
                       AlertCopy(title: "Race Passage - Slack", body: "14:32, no window under 0.5 kn"))
    }

    func testTheCalendarLeavesTheLeadOut() {
        XCTAssertEqual(copy(.currentPeak(flood: true), lead: 3_600, includeLead: false),
                       AlertCopy(title: "Race Passage - Max flood", body: "14:32"))
    }

    func testTideCopyCarriesTheHeightInTheUsersUnits() {
        XCTAssertEqual(copy(.tideExtreme(high: false), heightM: 0.4, imperial: false),
                       AlertCopy(title: "Race Passage - Low tide", body: "14:32 · 0.40 m"))
        XCTAssertEqual(copy(.tideCrossing(heightM: 1, rising: true), lead: 86_400, heightM: 1),
                       AlertCopy(title: "Race Passage - Rising past 3.3 ft", body: "14:32 · in 1 day"))
    }

    func testSlackAndEclipse() {
        XCTAssertEqual(copy(.slack), AlertCopy(title: "Race Passage - Slack", body: "14:32"))
        XCTAssertEqual(copy(.eclipse), AlertCopy(title: "Race Passage - Lunar eclipse", body: "14:32"))
    }

    func testLeadLabels() {
        XCTAssertEqual(alertLeads.map(alertLeadLabel),
                       ["At the time", "15 min before", "30 min before", "1 hr before", "3 hr before", "1 day before"])
    }

    private func shape(_ title: String, start: TimeInterval, end: TimeInterval? = nil,
                       alarm: TimeInterval? = nil) -> CalendarEventShape {
        CalendarEventShape(title: title, start: event.addingTimeInterval(start),
                           end: event.addingTimeInterval(end ?? start), alarmOffset: alarm)
    }

    func testAnEventWithinAMinuteOfThePlanIsTheSameEvent() {
        let changes = calendarChanges(existing: [shape("Friday Harbor - High tide", start: 60)],
                                      wanted: [shape("Friday Harbor - High tide", start: 0)],
                                      now: event.addingTimeInterval(-3_600))
        XCTAssertEqual(changes.remove, [])
        XCTAssertEqual(changes.add, [])
    }

    func testAMovedWindowOrAChangedAlarmIsANewEvent() {
        let existing = [shape("Race Passage - Slack window", start: 0, end: 600),
                        shape("Friday Harbor - Low tide", start: 7_200)]
        let wanted = [shape("Race Passage - Slack window", start: 0, end: 1_800),   // a threshold change moved the close
                      shape("Friday Harbor - Low tide", start: 7_200, alarm: -1_800)] // Premium added the alarm

        let changes = calendarChanges(existing: existing, wanted: wanted, now: event.addingTimeInterval(-3_600))

        XCTAssertEqual(changes.remove, [0, 1])
        XCTAssertEqual(changes.add, [0, 1])
    }

    func testAnEventAlreadyUnderWayIsNeverRemoved() {
        let existing = [shape("Race Passage - Slack window", start: -600, end: 600),  // open right now
                        shape("Friday Harbor - Low tide", start: 3_600)]

        let changes = calendarChanges(existing: existing, wanted: [], now: event)

        XCTAssertEqual(changes.remove, [1])
        XCTAssertEqual(changes.add, [])
    }

    func testEachEventMatchesOnceAndARepeatedPlanIsAddedOnce() {
        let now = event.addingTimeInterval(-3_600)
        // Two planned slacks a minute apart can't both claim one existing event.
        let claimed = calendarChanges(existing: [shape("Race Passage - Slack", start: 0)],
                                      wanted: [shape("Race Passage - Slack", start: 0), shape("Race Passage - Slack", start: 60)],
                                      now: now)
        XCTAssertEqual(claimed.remove, [])
        XCTAssertEqual(claimed.add, [1])
        // Two rules planning the identical event write it once.
        let repeated = calendarChanges(existing: [],
                                       wanted: [shape("Friday Harbor - Low tide", start: 0), shape("Friday Harbor - Low tide", start: 0)],
                                       now: now)
        XCTAssertEqual(repeated.add, [0])
    }
}
