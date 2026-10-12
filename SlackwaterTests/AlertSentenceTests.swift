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
        for s in ["wind over 20 knots", "next slack at Race Passage", "max flood tomorrow",
                  "when is the current slack", "weather tomorrow", "big waves"] {
            XCTAssertTrue(alertSentenceOutOfScope(s, kind: .tide), s)
        }
        // In scope, every one: daylight words the guide itself teaches, a place name the station
        // never parses, and plain tide asks. These reach the model and are read back before Save.
        for s in ["tell me when the next low tide is", "every high tide", "when does it drop below 2 feet",
                  "lowest low in daylight", "is there a lunar eclipse coming",
                  "every low tide between sunrise and sunset", "low tide before sunset",
                  "low tide at Race Passage", "when the window opens", "sunset tonight"] {
            XCTAssertFalse(alertSentenceOutOfScope(s, kind: .tide), s)
        }
        XCTAssertTrue(alertSentenceOutOfScope("next low tide", kind: .current))
        XCTAssertTrue(alertSentenceOutOfScope("when it passes 3 feet", kind: .current))
        XCTAssertFalse(alertSentenceOutOfScope("next slack window", kind: .current))
        XCTAssertFalse(alertSentenceOutOfScope("high water slack", kind: .current), "a boater's name for a slack")
        XCTAssertFalse(alertSentenceOutOfScope("the slack before the flood", kind: .current))
        XCTAssertTrue(alertSentenceOutOfScope("max ebb", kind: .derived))
        XCTAssertFalse(alertSentenceOutOfScope("the next slack", kind: .derived))
        XCTAssertFalse(alertSentenceOutOfScope("the slack before the flood", kind: .derived))
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
        XCTAssertEqual(alertSentenceDraft(TideSentenceDraft(trigger: .lowerLow, repeats: false, daylightOnly: true, leadMinutes: nil, day: nil), imperial: true).trigger,
                       .tideExtreme(high: false, ofDay: true))
        XCTAssertEqual(alertSentenceDraft(TideSentenceDraft(trigger: .higherHigh, repeats: true, daylightOnly: false, leadMinutes: nil, day: nil), imperial: true).trigger,
                       .tideExtreme(high: true, ofDay: true))
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

    func testADayAheadFromTheModelIsClampedToTheHorizon() {
        // Model output is a trust boundary: a huge day count must neither crash nor search past
        // the 14-day horizon the copy names.
        let far = alertSentenceWindow(day: .daysAhead(Int.max), now: now, tz: utc)
        XCTAssertLessThanOrEqual(far.to.timeIntervalSince(now), AlertHorizon.notifications + 86_400)
        XCTAssertGreaterThan(far.from, now)
        XCTAssertEqual(alertSentenceWindow(day: .daysAhead(30), now: now, tz: utc).from,
                       alertSentenceWindow(day: .daysAhead(14), now: now, tz: utc).from)
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
                                            nextOccurrence: { _, _, _, _ in nil }), .nothingAhead(namedDay: true))
        XCTAssertEqual(alertSentenceOutcome(draft(.tideExtreme(high: true)), stationID: "a", now: now, tz: utc,
                                            nextOccurrence: { _, _, _, _ in nil }), .nothingAhead(namedDay: false))
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
        XCTAssertEqual(lead(45), 3_600, "a tie breaks toward more warning")
    }

    // MARK: the model, where it runs

    /// A model that is "available" but throws is not a wrong draft: skip, and say what it threw.
    private func parseOrSkip(_ sentence: String, kind: StationCalendarKind, imperial: Bool) async throws -> AlertSentenceDraft {
        do {
            return try await alertSentenceParseThrowing(sentence, kind: kind, imperial: imperial)
        } catch {
            throw XCTSkip("the model reads available here but cannot answer: \(error)")
        }
    }

    /// Runs on a Mac with Apple Intelligence on (the simulator borrows the host model); skips
    /// where there is no model, and where `availability` says there is one but it cannot answer
    /// (GitHub's macOS runners). Trigger and repeats only — the rest is checked by hand from the
    /// fixture.
    func testTheModelParsesTheCommonPhrasings() async throws {
        try XCTSkipUnless(alertSentenceAvailable, "no on-device model here")
        let cases: [(String, StationCalendarKind, AlertTrigger, Bool)] = [
            ("tell me when the next low tide is", .tide, .tideExtreme(high: false), false),
            ("every high tide", .tide, .tideExtreme(high: true), true),
            ("let me know whenever it rises past 8 ft", .tide, .tideCrossing(heightM: displayedHeightM(8 / toFeet(1), imperial: true), rising: true), true),
            ("is there a lunar eclipse coming", .tide, .eclipse, false),
            ("lowest low in daylight", .tide, .tideExtreme(high: false, ofDay: true), false),
            ("every lower low tide", .tide, .tideExtreme(high: false, ofDay: true), true),
            ("the higher high tomorrow", .tide, .tideExtreme(high: true, ofDay: true), false),
            ("next slack window", .current, .slackWindowOpens, false),
            ("every max ebb", .current, .currentPeak(flood: false), true),
            ("the next slack", .derived, .slack, false),
        ]
        for (sentence, kind, trigger, repeats) in cases {
            let draft = try await parseOrSkip(sentence, kind: kind, imperial: true)
            XCTAssertEqual(draft.trigger, trigger, sentence)
            XCTAssertEqual(draft.repeats, repeats, sentence)
        }
    }

    func testDaylightAndLeadAndDayComeThrough() async throws {
        try XCTSkipUnless(alertSentenceAvailable, "no on-device model here")
        let d = try await parseOrSkip("ping me 30 minutes before every low tide in daylight", kind: .tide, imperial: true)
        // The lead is the one field the model drops now and then; the fixture's bar lets it need a tap.
        XCTAssertTrue(d.daylightOnly); XCTAssertTrue(d.repeats)
        let t = try await parseOrSkip("remind me an hour before tomorrow's low", kind: .tide, imperial: false)
        XCTAssertEqual(t.day, .tomorrow); XCTAssertEqual(t.trigger, .tideExtreme(high: false))
        let w = try await parseOrSkip("when is high water tomorrow", kind: .tide, imperial: false)
        XCTAssertEqual(w.trigger, .tideExtreme(high: true), "high water is the plain high, not the higher high")
    }

    // MARK: the instructions

    func testInstructionsNameTheKindsTriggersAndTheUnits() {
        let tide = alertSentenceInstructions(kind: .tide, imperial: true)
        XCTAssertTrue(tide.contains("feet")); XCTAssertTrue(tide.contains("low tide")); XCTAssertTrue(tide.contains("lower low")); XCTAssertFalse(tide.contains("slack"))
        let cur = alertSentenceInstructions(kind: .current, imperial: false)
        XCTAssertTrue(cur.contains("slack")); XCTAssertFalse(cur.contains("metres") || cur.contains("feet"), "a current station has no heights")
        for kind in [StationCalendarKind.tide, .current, .derived] {
            XCTAssertLessThan(alertSentenceInstructions(kind: kind, imperial: true).count, 1_200,
                              "the on-device window is 4K tokens shared with the schema and the reply")
        }
    }
}
