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
        edited.daylightOnly = false
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
        // A rule from a newer build, with a trigger case this build has no case for.
        let future: [String: Any] = [
            "id": UUID().uuidString, "stationID": "current:noaa/PUG1701",
            "trigger": ["moonPhase": [String: Any]()], "lead": 0, "daylightOnly": false, "enabled": true,
        ]
        let knownJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(known))
        defaults.set(try JSONSerialization.data(withJSONObject: [knownJSON, future]), forKey: AppGroup.alertRulesKey)

        let store = AlertRuleStore(defaults: defaults)
        XCTAssertEqual(store.rules, [known])
        store.upsert(AlertRule(stationID: "noaa/9449880", trigger: .eclipse))

        let data = try XCTUnwrap(defaults.data(forKey: AppGroup.alertRulesKey))
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(stored.count, 3)
        XCTAssertTrue(stored.contains { ($0["trigger"] as? [String: Any])?["moonPhase"] != nil })
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

    func testDefaultsFireAtTheEventAndRepeat() {
        let rule = AlertRule(stationID: "noaa/9449880", trigger: .tideExtreme(high: false))
        XCTAssertEqual(rule.lead, 0)
        XCTAssertFalse(rule.daylightOnly)
        XCTAssertNil(rule.once)
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

    func testARuleWrittenByTheRowEraBuildStillDecodes() {
        // calendar/alert are gone from the type; a stored rule that still carries them
        // must read back as the notification rule it always was.
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let stored: [[String: Any]] = [[
            "id": UUID().uuidString, "stationID": TideStationRecord.fridayHarborID,
            "trigger": ["tideExtreme": ["high": false]],
            "lead": 1_800, "daylightOnly": false,
            "calendar": true, "alert": "notification", "enabled": true,
        ]]
        defaults.set(try! JSONSerialization.data(withJSONObject: stored), forKey: AppGroup.alertRulesKey)

        let store = AlertRuleStore(defaults: defaults)

        XCTAssertEqual(store.rules.count, 1, "an old rule must not land in `unreadable`")
        XCTAssertEqual(store.rules.first?.stationID, TideStationRecord.fridayHarborID)
        XCTAssertEqual(store.rules.first?.lead, 1_800)
        XCTAssertNil(store.rules.first?.once, "a rule from before `once` existed repeats")
    }

    func testOnceSurvivesARoundTrip() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let moment = Date(timeIntervalSince1970: 1_700_000_040)
        AlertRuleStore(defaults: defaults)
            .upsert(AlertRule(stationID: "a", trigger: .slack, once: moment))

        XCTAssertEqual(AlertRuleStore(defaults: defaults).rules.first?.once, moment)
    }

    func testARuleWithoutOnceEncodesWithoutTheKey() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        AlertRuleStore(defaults: defaults).upsert(AlertRule(stationID: "a", trigger: .slack))

        let raw = try! JSONSerialization.jsonObject(
            with: defaults.data(forKey: AppGroup.alertRulesKey)!) as! [[String: Any]]

        XCTAssertNil(raw.first?["once"])
    }
}
