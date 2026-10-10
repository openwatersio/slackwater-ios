// Slackwater — GPL v3. The line under the strip: which rule it reads, and what it says (docs/alerts.md §7.1).
import XCTest
@testable import Slackwater

final class AlertLineTests: XCTestCase {
    private let moment = Date(timeIntervalSince1970: 1_700_000_040)
    private let utc = TimeZone(identifier: "UTC")!
    private let en = Locale(identifier: "en_US")

    // MARK: which rule the line reads

    func testNoRuleReadsRestOrPressed() {
        XCTAssertEqual(alertLineState([], stationID: "a", offer: .slack, at: moment, pressed: false, now: moment), .rest)
        XCTAssertEqual(alertLineState([], stationID: "a", offer: .slack, at: moment, pressed: true, now: moment), .pressed(moment))
    }

    func testAOnceRuleOnThisMinuteReadsSet() {
        let rule = AlertRule(stationID: "a", trigger: .slack, once: alertMinute(moment))
        XCTAssertEqual(alertLineState([rule], stationID: "a", offer: .slack,
                                      at: moment.addingTimeInterval(31), pressed: true, now: moment), .set(rule))
    }

    func testARepeatingRuleOnThisTriggerReadsSet() {
        let rule = AlertRule(stationID: "a", trigger: .slack)
        XCTAssertEqual(alertLineState([rule], stationID: "a", offer: .slack, at: moment, pressed: false, now: moment), .set(rule))
    }

    func testTheOnceRuleWinsOverItsRepeatingTwin() {
        // Review Focus 3: the one that expires is the one to find again.
        let once = AlertRule(stationID: "a", trigger: .slack, once: alertMinute(moment))
        let every = AlertRule(stationID: "a", trigger: .slack)
        XCTAssertEqual(alertLineRule([every, once], stationID: "a", offer: .slack, at: moment, pressed: true, now: moment)?.id, once.id)
    }

    func testASwitchedOffRuleStillReadsSet() {
        // Review Focus 2: found and switched back on, not duplicated.
        var off = AlertRule(stationID: "a", trigger: .slack)
        off.enabled = false
        XCTAssertEqual(alertLineState([off], stationID: "a", offer: .slack, at: moment, pressed: false, now: moment), .set(off))
    }

    func testARuleOnAnotherStationOrTriggerOrMinuteIsNotThisLine() {
        let elsewhere = AlertRule(stationID: "b", trigger: .slack, once: alertMinute(moment))
        let other = AlertRule(stationID: "a", trigger: .tideExtreme(high: true), once: alertMinute(moment))
        let later = AlertRule(stationID: "a", trigger: .slack, once: alertMinute(moment.addingTimeInterval(600)))
        XCTAssertNil(alertLineRule([elsewhere, other, later], stationID: "a", offer: .slack, at: moment, pressed: true, now: moment))
    }

    func testAtRestTheSoonestUpcomingOnceRuleReadsSet() {
        // A Rest-tap rule is bound to the offer's next occurrence, not the centerline's minute,
        // so at rest the line must find it; pressed on some other minute, it must not.
        let later = AlertRule(stationID: "a", trigger: .slack, once: alertMinute(moment.addingTimeInterval(4 * 3_600)))
        let sooner = AlertRule(stationID: "a", trigger: .slack, once: alertMinute(moment.addingTimeInterval(3_600)))
        var past = AlertRule(stationID: "a", trigger: .slack, once: alertMinute(moment.addingTimeInterval(-3_600)))
        past.enabled = true
        XCTAssertEqual(alertLineRule([later, past, sooner], stationID: "a", offer: .slack,
                                     at: moment, pressed: false, now: moment)?.id, sooner.id)
        XCTAssertNil(alertLineRule([later, sooner], stationID: "a", offer: .slack,
                                   at: moment, pressed: true, now: moment))
        // The pressed minute still wins when it is one of them.
        XCTAssertEqual(alertLineRule([later, sooner], stationID: "a", offer: .slack,
                                     at: sooner.once!, pressed: true, now: moment)?.id, sooner.id)
    }

    // MARK: the new rule

    func testANewRuleIsBoundToTheMinuteWithTheStandardLead() {
        let rule = alertNewRule(stationID: "a", offer: .slack, at: moment.addingTimeInterval(31))
        XCTAssertEqual(rule.once, alertMinute(moment))
        XCTAssertEqual(rule.lead, alertNewRuleLead)
        XCTAssertEqual(rule.trigger, .slack)
        XCTAssertTrue(rule.enabled)
        XCTAssertFalse(rule.daylightOnly)
    }

    // MARK: the Rest tap's draft

    func testARestDraftBindsToTheNextOccurrenceAndOutlivesTheSaveReschedule() throws {
        // A draft bound to the floored "now" is already in the past, and the reschedule a save
        // triggers drops every once rule whose minute has passed — so the Rest tap binds to the
        // next occurrence instead, and must do so on a moving clock.
        let low = AlertTrigger.tideExtreme(high: false)
        let next = try XCTUnwrap(alertNextOccurrence(stationID: TideStationRecord.fridayHarborID, offer: low,
                                                     after: moment, threshold: 0.5))
        XCTAssertGreaterThan(next, moment)
        XCTAssertLessThan(next.timeIntervalSince(moment), 14 * 3_600, "a low comes at least twice a day")

        let rule = alertNewRule(stationID: TideStationRecord.fridayHarborID, offer: low, at: next)
        XCTAssertTrue(expiredRules([rule], now: moment.addingTimeInterval(30)).isEmpty)
    }

    func testAnUnknownStationHasNoNextOccurrence() {
        XCTAssertNil(alertNextOccurrence(stationID: "nope/0", offer: .slack, after: moment, threshold: 0.5))
    }

    // MARK: what the line says

    // The moment is "weekday, time" — Tue 10:13 PM — the shape the spec's "Sat 14:32" names.
    // Prefix and time checks, not whole strings: the exact weekday/time joiner is the
    // locale's, and pinning it makes the test fail on a Foundation update.
    func testTheLabelPerState() {
        let low = AlertTrigger.tideExtreme(high: false)
        XCTAssertEqual(alertLineLabel(.rest, offer: low, tz: utc, imperial: true, locale: en), "Set an alert")
        let pressed = alertLineLabel(.pressed(moment), offer: low, tz: utc, imperial: true, locale: en)
        XCTAssertTrue(pressed.hasPrefix("Set alert for low tide · Tue"), pressed)
        XCTAssertTrue(pressed.contains("10:14"), pressed)
        let once = AlertRule(stationID: "a", trigger: low, once: alertMinute(moment))
        let set = alertLineLabel(.set(once), offer: low, tz: utc, imperial: true, locale: en)
        XCTAssertTrue(set.hasPrefix("Alert set · low tide · Tue"), set)
        XCTAssertTrue(set.contains("10:14"), set)
        let every = AlertRule(stationID: "a", trigger: low)
        XCTAssertEqual(alertLineLabel(.set(every), offer: low, tz: utc, imperial: true, locale: en),
                       "Alert set · every low tide")
    }

    func testTheLabelReadsTheStationsZone() {
        let pacific = TimeZone(identifier: "America/Vancouver")!
        let label = alertLineLabel(.pressed(moment), offer: .slack, tz: pacific, imperial: true, locale: en)
        XCTAssertTrue(label.hasPrefix("Set alert for slack · Tue"), label)
        XCTAssertTrue(label.contains("2:14"), label)
        XCTAssertFalse(label.contains("10:14"), label)
    }

    func testACrossingLabelIsAClause() {
        let label = alertLineLabel(.pressed(moment), offer: .tideCrossing(heightM: 1.0, rising: false),
                                   tz: utc, imperial: false, locale: en)
        XCTAssertTrue(label.hasPrefix("Set alert for falling past 1.00 m · Tue"), label)
    }
}
