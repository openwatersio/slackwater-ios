// Slackwater — GPL v3. The alert sheet's repeat menu (docs/alerts.md §7.2).
import XCTest
import SlackwaterKit
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

    private struct WindowCurrent: CurrentPredicting {
        let points: [CurrentPoint]
        func speeds(from: Date, to: Date, step: TimeInterval) -> [CurrentPoint] { points }
        func events(from: Date, to: Date) -> [CurrentEvent] { [] }
    }

    func testOpeningAlertCannotSaveAfterItsWindowOpened() {
        let points = [1.0, 0.1, 0.1, 1.0].enumerated().map {
            CurrentPoint(time: moment.addingTimeInterval(Double($0.offset - 1) * 3600), speed: $0.element)
        }
        let station = WidgetStation.current(WindowCurrent(points: points), tz: TimeZone(secondsFromGMT: 0)!, name: "Test")
        let once = AlertRule(stationID: "current:test", trigger: .slackWindowOpens,
                             once: moment.addingTimeInterval(1800))
        XCTAssertEqual(alertSheetOpeningAvailability(once, station: station, position: (0, 0),
                                                     now: moment, threshold: 0.5), .alreadyOpen)
        let before = moment.addingTimeInterval(-3600)
        XCTAssertEqual(alertSheetOpeningAvailability(once, station: station, position: (0, 0),
                                                     now: before, threshold: 0.5), .available(alertMinute(moment.addingTimeInterval(-1600))))
    }

    func testOpeningAlertCanWaitForMissingStationData() {
        XCTAssertTrue(alertSheetOpeningCanSave(.waitingForStation, now: moment))
        XCTAssertFalse(alertSheetOpeningCanSave(.checking, now: moment))
        XCTAssertFalse(alertSheetOpeningCanSave(.unavailable, now: moment))
        XCTAssertFalse(alertSheetOpeningCanSave(.alreadyOpen, now: moment))
        XCTAssertTrue(alertSheetOpeningCanSave(.available(moment.addingTimeInterval(60)), now: moment))
        XCTAssertFalse(alertSheetOpeningCanSave(.available(moment.addingTimeInterval(-60)), now: moment))
    }

    func testReminderUsesTheResolvedWindowOpening() {
        let press = moment.addingTimeInterval(3600)
        let opening = moment.addingTimeInterval(600)
        let rule = AlertRule(stationID: "a", trigger: .slackWindowOpens, once: press, lead: 1800)
        let resolved = alertSheetReminderRule(rule, opening: .available(opening))
        XCTAssertEqual(resolved.once, opening)
        XCTAssertTrue(alertSheetStartsNow(resolved, now: moment))
        XCTAssertFalse(alertSheetStartsNow(rule, now: moment))
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
