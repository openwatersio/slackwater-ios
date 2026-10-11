// Slackwater — GPL v3. A sentence becomes a rule: the pure half (docs/alerts.md §7.3).
import XCTest
@testable import Slackwater

final class AlertSentenceTests: XCTestCase {
    // 2023-11-14 22:14 UTC; 14:14 in Vancouver.
    private let now = Date(timeIntervalSince1970: 1_700_000_040)
    private let pacific = TimeZone(identifier: "America/Vancouver")!
    private let utc = TimeZone(identifier: "UTC")!

    private func draft(_ trigger: AlertTrigger, repeats: Bool = false, daylight: Bool = false,
                       lead: Int? = nil, day: AlertRelativeDay? = nil) -> AlertSentenceDraft {
        AlertSentenceDraft(trigger: trigger, repeats: repeats, daylightOnly: daylight, leadMinutes: lead, day: day)
    }

    // MARK: the word list

    func testTheWordListCatchesTheObviousOutOfScopeAsks() {
        // Review Focus 1: the model maps these to a tide trigger; the words catch them first.
        for s in ["wind over 20 knots", "next slack at Race Passage", "max flood tomorrow", "sunset tonight",
                  "when is the current slack", "weather tomorrow"] {
            XCTAssertTrue(alertSentenceOutOfScope(s, kind: .tide), s)
        }
        for s in ["tell me when the next low tide is", "every high tide", "when does it drop below 2 feet",
                  "lowest low in daylight", "is there a lunar eclipse coming"] {
            XCTAssertFalse(alertSentenceOutOfScope(s, kind: .tide), s)
        }
        XCTAssertTrue(alertSentenceOutOfScope("next low tide", kind: .current))
        XCTAssertFalse(alertSentenceOutOfScope("next slack window", kind: .current))
        XCTAssertTrue(alertSentenceOutOfScope("max ebb", kind: .derived))
        XCTAssertFalse(alertSentenceOutOfScope("the next slack", kind: .derived))
    }

    // MARK: draft → trigger

    func testATideDraftMapsToTheEngineTrigger() {
        let rises = TideSentenceDraft(trigger: .risesPast(height: 8), repeats: true, daylightOnly: false, leadMinutes: nil, day: nil)
        XCTAssertEqual(alertSentenceDraft(rises, imperial: true).trigger,
                       .tideCrossing(heightM: displayedHeightM(8 / toFeet(1), imperial: true), rising: true))
        let falls = TideSentenceDraft(trigger: .fallsPast(height: 1.5), repeats: false, daylightOnly: true, leadMinutes: 60, day: .tomorrow)
        let d = alertSentenceDraft(falls, imperial: false)
        XCTAssertEqual(d.trigger, .tideCrossing(heightM: 1.5, rising: false))
        XCTAssertTrue(d.daylightOnly)
        XCTAssertEqual(d.leadMinutes, 60)
        XCTAssertEqual(d.day, .tomorrow)
        XCTAssertEqual(alertSentenceDraft(TideSentenceDraft(trigger: .lowTide, repeats: false, daylightOnly: false, leadMinutes: nil, day: nil), imperial: true).trigger,
                       .tideExtreme(high: false))
        XCTAssertEqual(alertSentenceDraft(TideSentenceDraft(trigger: .lunarEclipse, repeats: false, daylightOnly: false, leadMinutes: nil, day: nil), imperial: true).trigger, .eclipse)
    }

    func testCurrentAndDerivedDraftsMapToTheEngineTrigger() {
        XCTAssertEqual(alertSentenceDraft(CurrentSentenceDraft(trigger: .slackWindow, repeats: false, daylightOnly: false, leadMinutes: nil, day: nil), imperial: true).trigger, .slackWindowOpens)
        XCTAssertEqual(alertSentenceDraft(CurrentSentenceDraft(trigger: .maxEbb, repeats: false, daylightOnly: false, leadMinutes: nil, day: nil), imperial: true).trigger, .currentPeak(flood: false))
        XCTAssertEqual(alertSentenceDraft(DerivedSentenceDraft(trigger: .slack, repeats: false, daylightOnly: false, leadMinutes: nil, day: nil), imperial: true).trigger, .slack)
    }

    // MARK: the day window

    func testNoDayMeansFromNowAcrossTheNotificationHorizon() {
        let w = alertSentenceWindow(day: nil, now: now, tz: pacific)
        XCTAssertEqual(w.from, now)
        XCTAssertEqual(w.to, now.addingTimeInterval(AlertHorizon.notifications))
    }

    func testARelativeDayResolvesInTheStationsZoneAcrossDST() {
        // Review Focus 2. 2023-11-05 is Vancouver's fall-back day: 25 hours long.
        let saturday = Date(timeIntervalSince1970: 1_699_120_800)   // 2023-11-04 18:00 UTC = 11:00 PDT
        let w = alertSentenceWindow(day: .tomorrow, now: saturday, tz: pacific)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = pacific
        XCTAssertEqual(cal.component(.day, from: w.from), 5)
        XCTAssertEqual(cal.component(.hour, from: w.from), 0)
        XCTAssertEqual(w.to.timeIntervalSince(w.from), 25 * 3_600, "a DST day is not 86 400 seconds")
        // Today starts now, not at midnight: a low already past this morning is not "today's".
        XCTAssertEqual(alertSentenceWindow(day: .today, now: saturday, tz: pacific).from, saturday)
        XCTAssertEqual(cal.component(.day, from: alertSentenceWindow(day: .daysAhead(3), now: saturday, tz: pacific).from), 7)
    }

    // MARK: the outcome

    func testASingularSentenceBindsToTheFirstOccurrence() {
        let event = now.addingTimeInterval(5 * 3_600 + 20)
        let out = alertSentenceOutcome(draft(.tideExtreme(high: false), lead: 15), stationID: "a", now: now, tz: utc,
                                       nextOccurrence: { trigger, daylight, from, to in
                                           XCTAssertEqual(trigger, .tideExtreme(high: false)); XCTAssertFalse(daylight)
                                           XCTAssertEqual(from, self.now); return event })
        guard case .rule(let rule, let bound) = out else { return XCTFail("\(out)") }
        XCTAssertEqual(rule.once, alertMinute(event))
        XCTAssertEqual(bound, alertMinute(event))
        XCTAssertEqual(rule.lead, 900)
        XCTAssertEqual(rule.stationID, "a")
        XCTAssertTrue(rule.enabled)
    }

    func testARepeatingSentenceStillBindsAMomentForTheMenu() {
        let event = now.addingTimeInterval(3_600)
        let out = alertSentenceOutcome(draft(.slackWindowOpens, repeats: true, daylight: true), stationID: "a", now: now, tz: utc,
                                       nextOccurrence: { _, daylight, _, _ in XCTAssertTrue(daylight); return event })
        guard case .rule(let rule, let bound) = out else { return XCTFail("\(out)") }
        XCTAssertNil(rule.once)
        XCTAssertEqual(bound, alertMinute(event))
        XCTAssertTrue(rule.daylightOnly)
        XCTAssertEqual(rule.lead, alertNewRuleLead, "no lead in the sentence keeps the sheet's half hour")
    }

    func testANamedDayWithNoOccurrenceIsNothingAhead() {
        // Review Focus 2.
        XCTAssertEqual(alertSentenceOutcome(draft(.tideExtreme(high: true), day: .tomorrow), stationID: "a", now: now, tz: utc,
                                            nextOccurrence: { _, _, _, _ in nil }), .nothingAhead)
    }

    func testARepeatingSentenceWithNothingAheadStillMakesARule() {
        // "Every slack window" at a gate that is shut all fortnight: the rule is right, the menu has no moment.
        let out = alertSentenceOutcome(draft(.slackWindowOpens, repeats: true), stationID: "a", now: now, tz: utc,
                                       nextOccurrence: { _, _, _, _ in nil })
        guard case .rule(let rule, let bound) = out else { return XCTFail("\(out)") }
        XCTAssertNil(rule.once); XCTAssertNil(bound)
    }

    func testTheLeadIsClampedToTheSheetsChoices() {
        func lead(_ minutes: Int) -> TimeInterval? {
            guard case .rule(let rule, _) = alertSentenceOutcome(draft(.slack, repeats: true, lead: minutes), stationID: "a",
                                                                  now: now, tz: utc, nextOccurrence: { _, _, _, _ in nil })
            else { return nil }
            return rule.lead
        }
        XCTAssertEqual(lead(50), 3_600, "50 min rounds to the nearest offered lead")
        XCTAssertEqual(lead(10), 900)
        XCTAssertEqual(lead(0), 0)
        XCTAssertEqual(lead(2_000), 86_400)
        XCTAssertTrue(alertLeads.contains(lead(45)!), "a tie lands on one of the offered leads either way")
    }

    // MARK: the instructions

    func testInstructionsNameTheKindsTriggersAndTheUnits() {
        let tide = alertSentenceInstructions(kind: .tide, imperial: true)
        XCTAssertTrue(tide.contains("feet")); XCTAssertTrue(tide.contains("low tide")); XCTAssertFalse(tide.contains("slack"))
        let cur = alertSentenceInstructions(kind: .current, imperial: false)
        XCTAssertTrue(cur.contains("slack")); XCTAssertFalse(cur.contains("metres") || cur.contains("feet"), "a current station has no heights")
        XCTAssertLessThan(alertSentenceInstructions(kind: .derived, imperial: false).count, 1_200, "the on-device window is 4K tokens shared with the schema and the reply")
    }
}
