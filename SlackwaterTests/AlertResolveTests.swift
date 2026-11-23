// Slackwater — GPL v3. resolveAlerts: rules → occurrences and places, with unknown stations reported rather than dropped.
import XCTest
@testable import Slackwater
import SlackwaterKit

private struct CurrentWithLaterSlack: CurrentPredicting {
    let slack: Date
    func speeds(from: Date, to: Date, step: TimeInterval) -> [CurrentPoint] {
        [CurrentPoint(time: from, speed: 1), CurrentPoint(time: to, speed: 1)]
    }
    func events(from: Date, to: Date) -> [CurrentEvent] {
        from <= slack && slack <= to ? [CurrentEvent(time: slack, speed: 0, kind: .slack, verifiedZero: true)] : []
    }
}

final class AlertResolveTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_755_800_000)

    func testDeliveryUsesOnlyRulesUnchangedDuringResolution() {
        let kept = AlertRule(stationID: "kept", trigger: .slack)
        let deleted = AlertRule(stationID: "deleted", trigger: .slack)
        let edited = AlertRule(stationID: "edited", trigger: .slack)
        var disabled = edited
        disabled.enabled = false
        let added = AlertRule(stationID: "added", trigger: .slack)
        XCTAssertEqual(unchangedResolvedRules([kept, deleted, edited], current: [kept, disabled, added]), [kept])
    }

    func testEditedEnabledRuleKeepsItsActiveCountdown() {
        let snapshot = AlertRule(stationID: "current:test", trigger: .slack)
        var edited = snapshot
        edited.lead = 1800
        let active = LiveActivityRecord(key: "open", ruleID: snapshot.id, pending: false,
                                        event: now.addingTimeInterval(-600), end: now.addingTimeInterval(600))
        XCTAssertTrue(unchangedResolvedRules([snapshot], current: [edited]).isEmpty)
        XCTAssertTrue(liveActivitiesToEnd([active], liveRuleIDs: activeRuleIDs([edited]), now: now).isEmpty)
        edited.enabled = false
        XCTAssertEqual(liveActivitiesToEnd([active], liveRuleIDs: activeRuleIDs([edited]), now: now), ["open"])
    }

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

    func testOffModeRotaryRuleReportsNoPredictedSlack() {
        let rule = AlertRule(stationID: "current:noaa/KOD0901", trigger: .slackWindowOpens)
        let resolved = resolveAlerts([rule], subscriptions: [], now: now, threshold: 0)
        XCTAssertTrue(resolved.occurrences.isEmpty)
        XCTAssertTrue(resolved.noSlack.contains(rule.id))
        XCTAssertFalse(resolved.unresolved.contains(rule.id))
    }

    func testOnceSavedWithWindowOffRequiresReviewWhenTurnedOn() {
        var rule = AlertRule(stationID: "current:noaa/ACT1616", trigger: .slackWindowOpens,
                             once: now.addingTimeInterval(3600))
        rule.currentWindowRule = true
        rule.currentWindowWasOff = true
        let result = resolveAlerts([rule], subscriptions: [], now: now, threshold: 0.5)
        XCTAssertTrue(result.legacyReview.contains(rule.id))
        XCTAssertTrue(result.occurrences.isEmpty)
    }

    func testPastLegacyWindowWaitsThenExpiresWithoutReview() {
        let rule = AlertRule(stationID: "current:noaa/ACT1616", trigger: .slackWindowOpens,
                             once: now.addingTimeInterval(-3600))
        let result = resolveAlerts([rule], subscriptions: [], now: now, threshold: 0.5)
        XCTAssertFalse(result.legacyReview.contains(rule.id))
        XCTAssertTrue(result.occurrences.isEmpty)
        XCTAssertTrue(expiredUnchangedRules([rule], current: [rule], now: now,
                                            occurrences: [], noSlack: result.noSlack).isEmpty)
        XCTAssertEqual(expiredUnchangedRules([rule], current: [rule], now: now.addingTimeInterval(21_600),
                                              occurrences: [], noSlack: result.noSlack), [rule.id])
    }

    func testPastLegacyWindowDoesNotRequireReview() {
        let rule = AlertRule(stationID: "current:noaa/ACT1616", trigger: .slackWindowOpens,
                             once: now.addingTimeInterval(-21_601))
        let result = resolveAlerts([rule], subscriptions: [], now: now, threshold: 0.5)
        XCTAssertFalse(result.legacyReview.contains(rule.id))
    }

    func testLegacyOnceWindowRequiresReviewEvenWhenCurrentSelectionMatches() throws {
        let id = "current:noaa/ACT1616"
        let record = try XCTUnwrap(WidgetStationLoader.loadRecord(id: id, at: now))
        let station = WidgetStationLoader.station(from: record)
        let every = AlertRule(stationID: id, trigger: .slackWindowOpens)
        let opening = try XCTUnwrap(alertOccurrences(every, station: station, position: record.alertPosition,
                                                     from: now, to: now.addingTimeInterval(86_400), threshold: 0.5).first)
        let old = AlertRule(stationID: id, trigger: .slackWindowOpens, once: opening.event)
        let resolved = resolveAlerts([old], subscriptions: [], now: now, threshold: 0.5)
        XCTAssertTrue(resolved.occurrences.isEmpty)
        XCTAssertTrue(resolved.legacyReview.contains(old.id))
    }

    func testLegacySelectedSlackIsCheckedEvenWhenLaterSlackExists() {
        let station = WidgetStation.current(CurrentWithLaterSlack(slack: now.addingTimeInterval(86_400)),
                                            tz: TimeZone(secondsFromGMT: 0)!, name: "Test")
        let rule = AlertRule(stationID: "current:test", trigger: .slackWindowOpens,
                             once: now.addingTimeInterval(3600))
        XCTAssertTrue(offModeHasNoSlack(rule, station: station, position: (0, 0), now: now,
                                        until: now.addingTimeInterval(2 * 86_400), occurrences: []))
    }

    func testLegacySelectedSlackDoesNotMoveToAnotherNearbySlack() {
        let station = WidgetStation.current(CurrentWithLaterSlack(slack: now.addingTimeInterval(4 * 3600)),
                                            tz: TimeZone(secondsFromGMT: 0)!, name: "Test")
        let rule = AlertRule(stationID: "current:test", trigger: .slackWindowOpens,
                             once: now.addingTimeInterval(3600))
        XCTAssertTrue(offModeHasNoSlack(rule, station: station, position: (0, 0), now: now,
                                        until: now.addingTimeInterval(2 * 86_400), occurrences: []))
    }

    func testLegacySelectedSlackAllowsSmallPredictionShift() {
        let selected = now.addingTimeInterval(3600)
        let station = WidgetStation.current(CurrentWithLaterSlack(slack: selected.addingTimeInterval(120)),
                                            tz: TimeZone(secondsFromGMT: 0)!, name: "Test")
        let rule = AlertRule(stationID: "current:test", trigger: .slackWindowOpens, once: selected)
        XCTAssertFalse(offModeHasNoSlack(rule, station: station, position: (0, 0), now: now,
                                         until: now.addingTimeInterval(2 * 86_400), occurrences: []))
    }

    func testTemporaryOffKeepsSavedWindowUntilItCanBeResolvedAgain() {
        var rule = AlertRule(stationID: "current:noaa/KOD0901", trigger: .slackWindowOpens,
                             once: now.addingTimeInterval(-60))
        rule.currentWindowRule = true
        let off = resolveAlerts([rule], subscriptions: [], now: now, threshold: 0)
        XCTAssertEqual(off.heldWindows, [rule.id])
        XCTAssertTrue(off.occurrences.isEmpty)
        XCTAssertTrue(expiredUnchangedRules([rule], current: [rule], now: now,
                                            occurrences: off.occurrences, heldWindows: off.heldWindows).isEmpty)
        let later = now.addingTimeInterval(7 * 3600)
        XCTAssertEqual(expiredUnchangedRules([rule], current: [rule], now: later,
                                             occurrences: [], heldWindows: off.heldWindows), [rule.id])
        XCTAssertTrue(resolveAlerts([rule], subscriptions: [], now: now, threshold: 0.5).heldWindows.isEmpty)
    }

    func testOffModeRotaryOnceRuleNeedsReviewInsteadOfExpiringSilently() {
        var rule = AlertRule(stationID: "current:noaa/KOD0901", trigger: .slackWindowOpens)
        rule.once = now.addingTimeInterval(-60)
        let resolved = resolveAlerts([rule], subscriptions: [], now: now, threshold: 0)
        XCTAssertTrue(resolved.noSlack.contains(rule.id))
        XCTAssertTrue(expiredUnchangedRules([rule], current: [rule], now: now,
                                            occurrences: resolved.occurrences,
                                            noSlack: resolved.noSlack).isEmpty)
    }

    func testMarkedRuleDoesNotResumeWhenComfortSettingChanges() {
        var rule = AlertRule(stationID: "current:noaa/KOD0901", trigger: .slackWindowOpens,
                             once: now.addingTimeInterval(3600))
        rule.slackNeedsReview = true
        let resolved = resolveAlerts([rule], subscriptions: [], now: now, threshold: 0.5)
        XCTAssertTrue(resolved.occurrences.isEmpty)
        XCTAssertTrue(expiredUnchangedRules([rule], current: [rule], now: .distantFuture, occurrences: []).isEmpty)
        XCTAssertEqual(alertStatusText(rule, AlertStatusSnapshot(), premium: true),
                       "Review or delete this alert.")
    }

    func testOffModeRotaryCalendarReportsNoPredictedSlack() {
        let stationID = "current:noaa/KOD0901"
        let resolved = resolveAlerts([], subscriptions: [stationID], now: now, threshold: 0)
        XCTAssertTrue(resolved.calendarNoSlack.contains(stationID))
        XCTAssertFalse(resolved.unresolvedStations.contains(stationID))
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
