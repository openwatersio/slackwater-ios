// Slackwater — GPL v3. The alert row: what it offers for the moment under the centerline, and what a tap does (notifications spec §7.1).
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

    func testCalendarCreatesARuleWithAThirtyMinuteLead() {
        let change = alertRowToggle([], stationID: "noaa/9449880", offer: .tideExtreme(high: false), delivery: .calendar)
        guard case .upsert(let rule) = change else { return XCTFail("expected a new rule") }
        XCTAssertEqual(rule.stationID, "noaa/9449880")
        XCTAssertEqual(rule.trigger, .tideExtreme(high: false))
        XCTAssertEqual(rule.lead, 1_800)
        XCTAssertTrue(rule.calendar)
        XCTAssertEqual(rule.alert, .none)
    }

    func testLiveJoinsTheSameRuleAndARuleWithNothingLeftIsRemoved() {
        let calendarOnly = AlertRule(stationID: "s", trigger: .slackWindowOpens, lead: 1_800)

        guard case .upsert(let both) = alertRowToggle([calendarOnly], stationID: "s", offer: .slackWindowOpens, delivery: .live)
        else { return XCTFail("expected an update") }
        XCTAssertEqual(both.id, calendarOnly.id)
        XCTAssertTrue(both.calendar)
        XCTAssertEqual(both.alert, .notification)

        guard case .upsert(let liveOnly) = alertRowToggle([both], stationID: "s", offer: .slackWindowOpens, delivery: .calendar)
        else { return XCTFail("expected an update") }
        XCTAssertFalse(liveOnly.calendar)
        XCTAssertEqual(liveOnly.alert, .notification)

        XCTAssertEqual(alertRowToggle([liveOnly], stationID: "s", offer: .slackWindowOpens, delivery: .live),
                       .remove(calendarOnly.id))
    }

    func testADifferentOfferIsADifferentRule() {
        let existing = AlertRule(stationID: "s", trigger: .tideCrossing(heightM: 1.4, rising: true))
        let change = alertRowToggle([existing], stationID: "s", offer: .tideCrossing(heightM: 1.2, rising: true), delivery: .calendar)
        guard case .upsert(let rule) = change else { return XCTFail("expected a new rule") }
        XCTAssertNotEqual(rule.id, existing.id)
    }

    func testTheRowReadsEnabledDeliveriesAndATapWakesAnOffRule() {
        var rule = AlertRule(stationID: "s", trigger: .slack, alert: .notification)
        XCTAssertTrue(alertRowState([rule], stationID: "s", offer: .slack, premium: true).calendar)
        XCTAssertTrue(alertRowState([rule], stationID: "s", offer: .slack, premium: true).live)
        let lapsed = alertRowState([rule], stationID: "s", offer: .slack, premium: false)
        XCTAssertTrue(lapsed.calendar)
        XCTAssertFalse(lapsed.live)
        XCTAssertFalse(alertRowState([rule], stationID: "s", offer: .eclipse, premium: true).calendar)

        rule.enabled = false
        let off = alertRowState([rule], stationID: "s", offer: .slack, premium: true)
        XCTAssertFalse(off.calendar)
        XCTAssertFalse(off.live)

        guard case .upsert(let woken) = alertRowToggle([rule], stationID: "s", offer: .slack, delivery: .calendar)
        else { return XCTFail("expected an update") }
        XCTAssertTrue(woken.enabled)
        XCTAssertTrue(woken.calendar)
        XCTAssertEqual(woken.alert, .none)
    }
}
