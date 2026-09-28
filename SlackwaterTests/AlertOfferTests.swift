// Slackwater — GPL v3. What the strip offers for the moment on the centerline (notifications spec §7.1).
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
}
