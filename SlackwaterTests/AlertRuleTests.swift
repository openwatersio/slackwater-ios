// Slackwater — GPL v3. Alert rules: coding, the store, and the place-first names.
import XCTest
@testable import Slackwater

@MainActor final class AlertRuleTests: XCTestCase {
    func testRulesRoundTripThroughTheStore() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        var changes = 0
        let store = AlertRuleStore(defaults: defaults)
        store.onChange = { changes += 1 }

        let rule = AlertRule(stationID: "current:noaa/PUG1701",
                             trigger: .tideCrossing(heightM: 1.4, rising: true),
                             lead: 1_800, daylightOnly: true)
        store.upsert(rule)
        var edited = rule
        edited.calendar = false
        store.upsert(edited)

        XCTAssertEqual(AlertRuleStore(defaults: defaults).rules, [edited])
        store.remove(rule.id)
        XCTAssertEqual(AlertRuleStore(defaults: defaults).rules, [])
        XCTAssertEqual(changes, 3)
    }

    func testARuleThisBuildCannotReadSurvivesAnEdit() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let known = AlertRule(stationID: "noaa/9449880", trigger: .tideExtreme(high: false))
        // A rule from a newer build, with an alert level this build has no case for.
        let future: [String: Any] = [
            "id": UUID().uuidString, "stationID": "current:noaa/PUG1701",
            "trigger": ["slackWindowOpens": [String: Any]()], "lead": 0, "daylightOnly": false,
            "calendar": true, "alert": "alarm", "enabled": true,
        ]
        let knownJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(known))
        defaults.set(try JSONSerialization.data(withJSONObject: [knownJSON, future]), forKey: AppGroup.alertRulesKey)

        let store = AlertRuleStore(defaults: defaults)
        XCTAssertEqual(store.rules, [known])
        store.upsert(AlertRule(stationID: "noaa/9449880", trigger: .eclipse))

        let data = try XCTUnwrap(defaults.data(forKey: AppGroup.alertRulesKey))
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(stored.count, 3)
        XCTAssertTrue(stored.contains { $0["alert"] as? String == "alarm" })
    }

    func testARuleThatCannotBeEncodedDoesNotWipeTheStore() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = AlertRuleStore(defaults: defaults)
        let good = AlertRule(stationID: "noaa/9449880", trigger: .eclipse)
        store.upsert(good)
        store.upsert(AlertRule(stationID: "noaa/9449880", trigger: .tideCrossing(heightM: .nan, rising: true)))

        XCTAssertEqual(AlertRuleStore(defaults: defaults).rules, [good])
    }

    func testEveryTriggerSurvivesCoding() throws {
        let triggers: [AlertTrigger] = [
            .slackWindowOpens, .slack, .currentPeak(flood: true), .tideExtreme(high: false),
            .tideCrossing(heightM: 0.25, rising: false), .eclipse,
        ]
        let decoded = try JSONDecoder().decode([AlertTrigger].self,
                                               from: JSONEncoder().encode(triggers))
        XCTAssertEqual(decoded, triggers)
    }

    func testDefaultsAreCalendarOnAndNotificationsOff() {
        let rule = AlertRule(stationID: "noaa/9449880", trigger: .tideExtreme(high: false))
        XCTAssertEqual(rule.lead, 0)
        XCTAssertFalse(rule.daylightOnly)
        XCTAssertTrue(rule.calendar)
        XCTAssertEqual(rule.alert, .none)
        XCTAssertTrue(rule.enabled)
    }

    func testSummaryPutsThePlaceFirst() {
        XCTAssertEqual(alertRuleSummary(.slackWindowOpens, stationName: "Race Passage", imperial: true),
                       "Race Passage - Slack window")
        XCTAssertEqual(alertRuleSummary(.slack, stationName: "Dodd Narrows", imperial: true),
                       "Dodd Narrows - Slack")
        XCTAssertEqual(alertRuleSummary(.currentPeak(flood: false), stationName: "Race Passage", imperial: true),
                       "Race Passage - Max ebb")
        XCTAssertEqual(alertRuleSummary(.tideExtreme(high: true), stationName: "Friday Harbor", imperial: true),
                       "Friday Harbor - High tide")
        XCTAssertEqual(alertRuleSummary(.tideCrossing(heightM: 1, rising: true), stationName: "Friday Harbor", imperial: false),
                       "Friday Harbor - Rising past 1.00 m")
        XCTAssertEqual(alertRuleSummary(.tideCrossing(heightM: 1, rising: false), stationName: "Friday Harbor", imperial: true),
                       "Friday Harbor - Falling past 3.3 ft")
        XCTAssertEqual(alertRuleSummary(.eclipse, stationName: "Friday Harbor", imperial: true),
                       "Friday Harbor - Lunar eclipse")
    }

    func testAHairlineSlackIsJustSlack() {
        XCTAssertEqual(alertEventName(.slackWindowOpens, noWindow: true, imperial: true), "Slack")
    }
}
