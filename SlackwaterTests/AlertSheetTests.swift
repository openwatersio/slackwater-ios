// Slackwater — GPL v3. The alert sheet's repeat menu (docs/alerts.md §7.2).
import XCTest
@testable import Slackwater

final class AlertSheetTests: XCTestCase {
    private let moment = Date(timeIntervalSince1970: 1_700_000_040)

    func testAMomentOffersBothChoicesAndNoMomentOffersOnlyEvery() {
        XCTAssertEqual(alertRepeatChoices(boundMoment: moment), [false, true])
        // Review Focus 4: a repeating rule from the Alerts screen has nothing to bind back to.
        XCTAssertEqual(alertRepeatChoices(boundMoment: nil), [true])
    }

    func testChoosingEveryClearsTheMomentAndDoesNotRepeatRestoresIt() {
        let once = AlertRule(stationID: "a", trigger: .slack, once: moment, lead: 900, sun: .daylight)

        let every = alertRuleRepeating(once, true, boundMoment: moment)
        XCTAssertNil(every.once)
        XCTAssertEqual(every.id, once.id)
        XCTAssertEqual(every.lead, 900)
        XCTAssertEqual(every.sun, .daylight)

        XCTAssertEqual(alertRuleRepeating(every, false, boundMoment: moment).once, moment)
    }

    func testDoesNotRepeatWithNoMomentLeavesTheRuleRepeating() {
        let every = AlertRule(stationID: "a", trigger: .slack)
        XCTAssertNil(alertRuleRepeating(every, false, boundMoment: nil).once)
    }

    // MARK: what a sentence does to the draft

    func testASentenceReplacesTheBoundMoment() {
        // Review Focus 3: the pressed minute goes; the sentence's occurrence is the new binding.
        let pressed = AlertRule(stationID: "a", trigger: .tideExtreme(high: false), once: moment, lead: 1_800)
        let event = moment.addingTimeInterval(7 * 3_600)
        let fromSentence = AlertRule(stationID: "a", trigger: .tideExtreme(high: true), once: event, lead: 900, sun: .goldenHour)

        let r = alertSheetApply(.rule(fromSentence, boundMoment: event), to: pressed, boundMoment: moment)

        XCTAssertEqual(r.rule.trigger, .tideExtreme(high: true))
        XCTAssertEqual(r.rule.once, event)
        XCTAssertEqual(r.boundMoment, event)
        XCTAssertEqual(r.rule.lead, 900)
        XCTAssertEqual(r.rule.sun, .goldenHour)
        XCTAssertEqual(r.rule.id, pressed.id, "the sheet edits one rule; a sentence does not mint a second id")
        XCTAssertNil(r.note)
    }

    func testNothingAheadAndNotOfferedKeepTheDraftAndSayWhy() {
        let draft = AlertRule(stationID: "a", trigger: .slack, once: moment)
        let a = alertSheetApply(.nothingAhead(namedDay: false), to: draft, boundMoment: moment)
        XCTAssertEqual(a.rule, draft); XCTAssertEqual(a.boundMoment, moment); XCTAssertEqual(a.note, .nothingAhead)
        XCTAssertEqual(alertSheetApply(.nothingAhead(namedDay: true), to: draft, boundMoment: moment).note, .nothingThatDay)
        let b = alertSheetApply(.notOffered, to: draft, boundMoment: moment)
        XCTAssertEqual(b.rule, draft); XCTAssertEqual(b.note, .notOffered)
        // Review Focus 4: a throw mid-parse leaves the sheet usable.
        let c = alertSheetApply(.failed, to: draft, boundMoment: moment)
        XCTAssertEqual(c.rule, draft); XCTAssertEqual(c.note, .failed)
    }

    func testSaveIsOfferedOnlyForAMomentStillAhead() {
        // A pressed moment can lie in the strip's 48-hour look-back; saving it would make a rule
        // the next reschedule deletes.
        let past = AlertRule(stationID: "a", trigger: .slack, once: moment.addingTimeInterval(-60))
        let ahead = AlertRule(stationID: "a", trigger: .slack, once: moment.addingTimeInterval(60))
        let every = AlertRule(stationID: "a", trigger: .slack)
        XCTAssertFalse(alertSheetCanSave(past, now: moment))
        XCTAssertTrue(alertSheetCanSave(ahead, now: moment))
        XCTAssertTrue(alertSheetCanSave(every, now: moment))
        // A moment 15 minutes off with a 30-minute lead saves, and the sheet says the countdown
        // starts now rather than letting the reminder silently fall behind.
        let inside = AlertRule(stationID: "a", trigger: .slack, once: moment.addingTimeInterval(900), lead: 1_800)
        XCTAssertTrue(alertSheetCanSave(inside, now: moment))
        XCTAssertTrue(alertSheetStartsNow(inside, now: moment))
        XCTAssertFalse(alertSheetStartsNow(ahead, now: moment))
        XCTAssertFalse(alertSheetStartsNow(every, now: moment))
        XCTAssertFalse(alertSheetStartsNow(past, now: moment), "a past moment is the other note")
        let longLead = AlertRule(stationID: "a", trigger: .slack, once: moment.addingTimeInterval(900), lead: 3_600)
        XCTAssertFalse(alertSheetStartsNow(longLead, now: moment), "an hour's lead gets no countdown")
        XCTAssertTrue(alertSheetReminderPassed(longLead, now: moment))
    }
}
