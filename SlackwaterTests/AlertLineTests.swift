// Slackwater — GPL v3. The line under the strip: which rule it reads, and what it says (docs/alerts.md §7.1).
import XCTest
@testable import Slackwater
import SlackwaterKit

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
        XCTAssertNil(rule.sun)
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

    func testAlertMomentsCoverEachOccurrenceOfTheStationsRules() throws {
        let id = TideStationRecord.fridayHarborID
        let every = AlertRule(stationID: id, trigger: .tideExtreme(high: false), lead: 1_800)
        let other = AlertRule(stationID: "current:noaa/PUG1701", trigger: .slackWindowOpens)
        let from = Date(timeIntervalSince1970: 1_755_800_000), to = from.addingTimeInterval(10 * 86_400)

        let moments = alertMoments(stationID: id, rules: [every, other], from: from, to: to, threshold: 0.5)

        XCTAssertFalse(moments.isEmpty)
        XCTAssertTrue(moments.allSatisfy { $0.ruleID == every.id }, "another station's rule draws nothing here")
        XCTAssertTrue(moments.allSatisfy { from...to ~= $0.event })
        // One marker per occurrence, in order, none on the same minute.
        for (a, b) in zip(moments, moments.dropFirst()) { XCTAssertLessThan(a.event, b.event) }
    }

    func testAOnceRuleBoundJustBeforeTheWindowKeepsItsOwnMoment() throws {
        // `alertOccurrences` filters to the query before a once rule picks the occurrence nearest
        // its minute, within six hours. A press on a current strip parks on the slack while the
        // occurrence is the window's opening, so a window that opened just before the loaded
        // window, with the next opening under six hours from the press, would hand the marker
        // to that next opening if the query were cut at the edge. The request's padding keeps
        // the one meant in reach; the strip clips it.
        let id = "current:noaa/PUG1701"
        let every = AlertRule(stationID: id, trigger: .slackWindowOpens, lead: 900)
        let from = Date(timeIntervalSince1970: 1_755_800_000)
        let openings = alertMoments(stationID: id, rules: [every], from: from, to: from.addingTimeInterval(5 * 86_400), threshold: 0.5).map(\.event)
        let press = 20 * 60.0
        guard let i = openings.indices.dropLast().first(where: { openings[$0 + 1].timeIntervalSince(openings[$0]) - press < 6 * 3_600 }) else {
            throw XCTSkip("no two openings under 6 h 20 m apart in five days")
        }
        let opening = openings[i]
        let once = AlertRule(stationID: id, trigger: .slackWindowOpens, once: opening.addingTimeInterval(press), lead: 900)
        let request = AlertMomentRequest(stationID: id, rules: [once], start: opening.addingTimeInterval(press / 2),
                                         end: opening.addingTimeInterval(2 * 86_400), threshold: 0.5)

        let moments = alertMoments(stationID: id, rules: [once], from: request.from, to: request.to, threshold: 0.5)

        XCTAssertEqual(moments.map(\.event), [opening], "the window the press was in, not the next one")

        // The same with the press itself outside the loaded window: the rule still resolves
        // around its own minute, so the next opening inside the window is not taken for it.
        let later = AlertMomentRequest(stationID: id, rules: [once], start: opening.addingTimeInterval(7 * 3_600),
                                       end: opening.addingTimeInterval(2 * 86_400), threshold: 0.5)
        let fromLater = alertMoments(stationID: id, rules: [once], from: later.from, to: later.to, threshold: 0.5)
        XCTAssertEqual(fromLater.map(\.event), [opening], "its own opening, for the strip to clip")
    }

    func testTwoRulesOnOneMomentGiveOneMarker() throws {
        let id = TideStationRecord.fridayHarborID
        let hour = AlertRule(stationID: id, trigger: .tideExtreme(high: false), lead: 3_600)
        let quarter = AlertRule(stationID: id, trigger: .tideExtreme(high: false), lead: 900)
        let from = Date(timeIntervalSince1970: 1_755_800_000), to = from.addingTimeInterval(3 * 86_400)

        let moments = alertMoments(stationID: id, rules: [hour, quarter], from: from, to: to, threshold: 0.5)

        XCTAssertFalse(moments.isEmpty)
        for (a, b) in zip(moments, moments.dropFirst()) { XCTAssertLessThan(a.event, b.event, "one marker per minute") }
    }

    func testAlertMomentsMarkASlackWindowsOpening() throws {
        let id = "current:noaa/PUG1701"
        let rule = AlertRule(stationID: id, trigger: .slackWindowOpens, lead: 900)
        let from = Date(timeIntervalSince1970: 1_755_800_000), to = from.addingTimeInterval(3 * 86_400)
        let moments = alertMoments(stationID: id, rules: [rule], from: from, to: to, threshold: 0.5)
        XCTAssertFalse(moments.isEmpty)
        // The marker is the window's opening, where the alert fires for: one per window, in order.
        for (a, b) in zip(moments, moments.dropFirst()) { XCTAssertLessThan(a.event, b.event) }
    }

    private func flatTimeline(hours: Int) -> TimelineData {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        let start = Date(timeIntervalSince1970: 1_755_800_000), end = start.addingTimeInterval(Double(hours) * 3_600)
        let times = stride(from: 0.0, through: end.timeIntervalSince(start), by: 600).map { start.addingTimeInterval($0) }
        return TimelineData(tz: tz, anchor: start, today: start, start: start, end: end, days: [],
                            tidePoints: times.map { TidePoint(time: $0, height: 1) },
                            tideRates: times.map { TideRatePoint(time: $0, rate: 0) },
                            tideExtremes: [], currentPoints: [], currentEvents: [], snapTimes: [], slackWindows: [])
    }

    func testAlertMarkerXsKeepOnlyTheMomentsInsideTheTileAndTheWindow() throws {
        let data = flatTimeline(hours: 48)
        let tileEnd = data.start.addingTimeInterval(8 * 3_600)
        let inside = data.start.addingTimeInterval(5 * 3_600)
        // A minute before the window is well inside a bell's width of its edge, and still not drawn.
        let before = AlertMoment(ruleID: UUID(), event: data.start.addingTimeInterval(-60))
        let drawn = AlertMoment(ruleID: UUID(), event: inside)
        let nextTile = AlertMoment(ruleID: UUID(), event: tileEnd.addingTimeInterval(3_600))
        let past = AlertMoment(ruleID: UUID(), event: data.end.addingTimeInterval(3_600))

        let xs = alertMarkerXs([before, drawn, nextTile, past], in: data, between: data.start, and: tileEnd)

        XCTAssertEqual(xs.count, 1, "a moment outside the tile or the window draws nothing here")
        XCTAssertEqual(xs[0], data.x(inside), accuracy: 0.01)
    }

    func testAlertMarkerXsKeepAMomentWhoseBellCrossesTheTileSeam() throws {
        // Each tile clips to its own edge, so a bell astride a seam is drawn by both tiles,
        // each its own half; a moment a bell's width past the seam is the next tile's alone.
        let data = flatTimeline(hours: 48)
        let tileEnd = data.start.addingTimeInterval(8 * 3_600)
        let astride = AlertMoment(ruleID: UUID(), event: data.time(atX: data.x(tileEnd) + 3))
        let clear = AlertMoment(ruleID: UUID(), event: data.time(atX: data.x(tileEnd) + 20))

        let xs = alertMarkerXs([astride, clear], in: data, between: data.start, and: tileEnd)

        XCTAssertEqual(xs.count, 1)
        XCTAssertEqual(xs[0], data.x(astride.event), accuracy: 0.01)
    }

    func testTheBellSitsBetweenThePillRowAndThePlot() {
        let geo = TimelineGeo(data: flatTimeline(hours: 48))
        let bellHalf: CGFloat = 4.5
        XCTAssertGreaterThanOrEqual(geo.alertBellY - bellHalf, geo.chromeY + 30, "the bell clears the pill row")
        XCTAssertLessThanOrEqual(geo.alertBellY + bellHalf, geo.alertLineTop, "the line starts under the bell")
        XCTAssertLessThan(geo.alertLineTop, geo.bodyTop, "the line reaches the plot from above it")
    }

    func testAMomentRequestChangesOnlyWithTheRulesOrTheWindow() {
        // The strip's window republishes on every chunk arrival and right-edge append; the
        // moments are re-resolved only when the rules or the window's edges change.
        let rule = AlertRule(stationID: "a", trigger: .slack)
        let start = Date(timeIntervalSince1970: 1_755_800_000), end = start.addingTimeInterval(7 * 86_400)
        let a = AlertMomentRequest(stationID: "a", rules: [rule], start: start, end: end, threshold: 0.5)
        XCTAssertEqual(a, AlertMomentRequest(stationID: "a", rules: [rule], start: start, end: end, threshold: 0.5))
        XCTAssertNotEqual(a, AlertMomentRequest(stationID: "a", rules: [rule], start: start, end: end.addingTimeInterval(86_400), threshold: 0.5))
        var edited = rule; edited.lead = 900
        XCTAssertNotEqual(a, AlertMomentRequest(stationID: "a", rules: [edited], start: start, end: end, threshold: 0.5))
        // A slack window opens where the current drops under the person's speed, so the speed moves the moments.
        XCTAssertNotEqual(a, AlertMomentRequest(stationID: "a", rules: [rule], start: start, end: end, threshold: 1.0))
        // The query is the window itself: a repeating rule's occurrences stand alone, and a once
        // rule is resolved around its own minute whatever the query (alertMarkerXs clips).
        XCTAssertEqual(a.from, start)
        XCTAssertEqual(a.to, end)
    }
}
