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
        let once = AlertRule(stationID: "a", trigger: .slack, once: moment, lead: 900, daylightOnly: true)

        let every = alertRuleRepeating(once, true, boundMoment: moment)
        XCTAssertNil(every.once)
        XCTAssertEqual(every.id, once.id)
        XCTAssertEqual(every.lead, 900)
        XCTAssertTrue(every.daylightOnly)

        XCTAssertEqual(alertRuleRepeating(every, false, boundMoment: moment).once, moment)
    }

    func testDoesNotRepeatWithNoMomentLeavesTheRuleRepeating() {
        let every = AlertRule(stationID: "a", trigger: .slack)
        XCTAssertNil(alertRuleRepeating(every, false, boundMoment: nil).once)
    }
}
