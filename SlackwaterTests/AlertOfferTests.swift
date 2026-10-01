// Slackwater — GPL v3. What the strip offers for the moment on the centerline (docs/alerts.md §7.1).
import XCTest
@testable import Slackwater
import Almanac

final class AlertOfferTests: XCTestCase {
    func testTideOfferReadsTheCenterline() {
        XCTAssertEqual(tideAlertOffer(scrubbedAway: true, turnIsHigh: true, onEclipseContact: false, heightM: 2.1, rising: false, imperial: false),
                       .tideExtreme(high: true))
        XCTAssertEqual(tideAlertOffer(scrubbedAway: true, turnIsHigh: nil, onEclipseContact: true, heightM: 1.4, rising: true, imperial: false),
                       .eclipse)
        XCTAssertEqual(tideAlertOffer(scrubbedAway: true, turnIsHigh: nil, onEclipseContact: false, heightM: 1.4, rising: true, imperial: false),
                       .tideCrossing(heightM: 1.4, rising: true))
        XCTAssertEqual(tideAlertOffer(scrubbedAway: false, turnIsHigh: nil, onEclipseContact: false, heightM: 1.4, rising: true, imperial: false),
                       .tideExtreme(high: false))
    }

    func testNearbyScrubHeightsShareOneCrossingRule() {
        func offer(_ m: Double, imperial: Bool) -> AlertTrigger {
            tideAlertOffer(scrubbedAway: true, turnIsHigh: nil, onEclipseContact: false,
                           heightM: m, rising: true, imperial: imperial)
        }
        XCTAssertEqual(offer(1.4012, imperial: false), offer(1.3996, imperial: false))
        XCTAssertEqual(offer(1.4012, imperial: false), .tideCrossing(heightM: 1.4, rising: true))
        XCTAssertEqual(offer(1.0, imperial: true), offer(1.004, imperial: true))       // both read 3.3 ft
        XCTAssertNotEqual(offer(1.0, imperial: true), offer(1.04, imperial: true))     // 3.3 ft vs 3.4 ft
    }

    func testCurrentAndDerivedOffers() {
        XCTAssertEqual(currentAlertOffer(maxIsFlood: false, onEclipseContact: false), .currentPeak(flood: false))
        XCTAssertEqual(currentAlertOffer(maxIsFlood: nil, onEclipseContact: true), .eclipse)
        XCTAssertEqual(currentAlertOffer(maxIsFlood: nil, onEclipseContact: false), .slackWindowOpens)
        XCTAssertEqual(derivedAlertOffer(onEclipseContact: false), .slack)
        XCTAssertEqual(derivedAlertOffer(onEclipseContact: true), .eclipse)
    }

    func testAnEclipseContactMatchesWithinASecond() throws {
        let iso = ISO8601DateFormatter()
        let observer = try Observer(latitudeDeg: 48.545, longitudeDeg: -123.013)
        let eclipses = visibleEclipses(from: try XCTUnwrap(iso.date(from: "2026-03-01T00:00:00Z")),
                                       to: try XCTUnwrap(iso.date(from: "2026-03-05T00:00:00Z")),
                                       observer: observer)
        let contact = try XCTUnwrap(eclipses.first?.contacts.first)
        XCTAssertTrue(isOnEclipseContact(contact.addingTimeInterval(0.5), eclipses))
        XCTAssertFalse(isOnEclipseContact(contact.addingTimeInterval(5), eclipses))
        XCTAssertFalse(isOnEclipseContact(contact, []))
    }

    // MARK: the popup's two rows

    private let moment = Date(timeIntervalSince1970: 1_700_000_040)

    func testTheFirstTapMakesARuleForThatMomentAlone() {
        let change = alertPopupToggle([], stationID: "a", offer: .slack, at: moment, row: .once)

        guard case .upsert(let rule) = change else { return XCTFail("expected a new rule") }
        XCTAssertEqual(rule.once, moment)
        XCTAssertEqual(rule.lead, alertPopupLead)
        XCTAssertEqual(rule.trigger, .slack)
        XCTAssertTrue(rule.enabled)
    }

    func testTheEveryRowMakesARuleWithNoMoment() {
        let change = alertPopupToggle([], stationID: "a", offer: .slack, at: moment, row: .every)

        guard case .upsert(let rule) = change else { return XCTFail("expected a new rule") }
        XCTAssertNil(rule.once)
    }

    func testTappingARowThatIsOnRemovesItsRule() {
        let rule = AlertRule(stationID: "a", trigger: .slack, once: moment)

        XCTAssertEqual(alertPopupToggle([rule], stationID: "a", offer: .slack, at: moment, row: .once),
                       .remove(rule.id))
    }

    func testTheTwoRowsAreIndependent() {
        let once = AlertRule(stationID: "a", trigger: .slack, once: moment)

        // The every row doesn't see the once rule as its own.
        guard case .upsert(let made) = alertPopupToggle([once], stationID: "a", offer: .slack,
                                                        at: moment, row: .every)
        else { return XCTFail("expected a new rule") }
        XCTAssertNil(made.once)
        XCTAssertNotEqual(made.id, once.id)
    }

    func testWithBothRulesSetATapRemovesOnlyItsOwn() {
        let once = AlertRule(stationID: "a", trigger: .slack, once: moment)
        let every = AlertRule(stationID: "a", trigger: .slack)

        XCTAssertEqual(alertPopupToggle([once, every], stationID: "a", offer: .slack,
                                        at: moment, row: .once),
                       .remove(once.id))
        XCTAssertEqual(alertPopupToggle([once, every], stationID: "a", offer: .slack,
                                        at: moment, row: .every),
                       .remove(every.id))
    }

    func testASecondTapOnTheSameMomentDoesNotMakeASecondRule() {
        // Review Focus 5: a double tap, or a tap landing while the first write is in flight.
        let first = alertPopupToggle([], stationID: "a", offer: .slack, at: moment, row: .once)
        guard case .upsert(let rule) = first else { return XCTFail("expected a new rule") }

        XCTAssertEqual(alertPopupToggle([rule], stationID: "a", offer: .slack, at: moment, row: .once),
                       .remove(rule.id))
    }

    func testAnUnflooredMomentFindsTheRuleMadeFromItsMinute() {
        let rule = AlertRule(stationID: "a", trigger: .slack, once: alertMinute(moment))

        XCTAssertEqual(alertPopupToggle([rule], stationID: "a", offer: .slack,
                                        at: moment.addingTimeInterval(31), row: .once),
                       .remove(rule.id))
    }

    func testASwitchedOffRuleWakesInsteadOfASecondBeingMade() {
        var off = AlertRule(stationID: "a", trigger: .slack, lead: 900, daylightOnly: true)
        off.enabled = false

        guard case .upsert(let woken) = alertPopupToggle([off], stationID: "a", offer: .slack,
                                                         at: moment, row: .every)
        else { return XCTFail("expected the rule back") }
        XCTAssertEqual(woken.id, off.id)
        XCTAssertTrue(woken.enabled)
        XCTAssertEqual(woken.lead, off.lead)
        XCTAssertEqual(woken.daylightOnly, off.daylightOnly)
    }

    func testARuleOnAnotherStationOrTriggerIsNotThisRow() {
        let elsewhere = AlertRule(stationID: "b", trigger: .slack, once: moment)
        let other = AlertRule(stationID: "a", trigger: .tideExtreme(high: true), once: moment)

        guard case .upsert = alertPopupToggle([elsewhere, other], stationID: "a", offer: .slack,
                                              at: moment, row: .once)
        else { return XCTFail("expected a new rule") }
    }

    // MARK: which rows read on

    func testARowReadsOnOnlyForItsOwnRule() {
        let rules = [AlertRule(stationID: "a", trigger: .slack, once: moment)]

        let state = alertPopupState(rules, stationID: "a", offer: .slack, at: moment, premium: true)

        XCTAssertTrue(state.once)
        XCTAssertFalse(state.every)
    }

    func testWithBothRulesSetBothRowsReadOn() {
        let rules = [AlertRule(stationID: "a", trigger: .slack, once: moment),
                     AlertRule(stationID: "a", trigger: .slack)]

        let state = alertPopupState(rules, stationID: "a", offer: .slack, at: moment, premium: true)

        XCTAssertTrue(state.once)
        XCTAssertTrue(state.every)
    }

    func testARowReadsOnFromAnUnflooredMoment() {
        let rules = [AlertRule(stationID: "a", trigger: .slack, once: alertMinute(moment))]

        XCTAssertTrue(alertPopupState(rules, stationID: "a", offer: .slack,
                                      at: moment.addingTimeInterval(31), premium: true).once)
    }

    func testNothingReadsOnWithoutPremium() {
        // However the stored rule reads, notifications never fire without it.
        let rules = [AlertRule(stationID: "a", trigger: .slack, once: moment)]

        XCTAssertEqual(alertPopupState(rules, stationID: "a", offer: .slack, at: moment,
                                       premium: false).once, false)
    }

    func testASwitchedOffRuleReadsOff() {
        var off = AlertRule(stationID: "a", trigger: .slack, once: moment)
        off.enabled = false

        XCTAssertEqual(alertPopupState([off], stationID: "a", offer: .slack, at: moment,
                                       premium: true).once, false)
    }

    // MARK: the repeating row's words

    func testTheEveryLabelReadsAsASentence() {
        XCTAssertEqual(alertEveryLabel(.slackWindowOpens, imperial: true), "Every slack window")
        XCTAssertEqual(alertEveryLabel(.tideExtreme(high: false), imperial: true), "Every low tide")
        XCTAssertEqual(alertEveryLabel(.currentPeak(flood: true), imperial: true), "Every max flood")
        XCTAssertEqual(alertEveryLabel(.eclipse, imperial: true), "Every lunar eclipse")
    }

    func testACrossingsEveryLabelIsAClause() {
        // "Every rising past 3.3 ft" is not English.
        XCTAssertEqual(alertEveryLabel(.tideCrossing(heightM: 1.0, rising: false), imperial: false),
                       "Every time it falls past 1.00 m")
        XCTAssertEqual(alertEveryLabel(.tideCrossing(heightM: 1.0, rising: true), imperial: false),
                       "Every time it rises past 1.00 m")
    }
}
