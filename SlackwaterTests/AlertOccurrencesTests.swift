// Slackwater — GPL v3. alertOccurrences against bundled stations: each trigger reads the producer the strip draws.
import XCTest
@testable import Slackwater
import Almanac
import SlackwaterKit

@MainActor final class AlertOccurrencesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_755_800_000)   // 2025-08-21
    private var week: Date { now.addingTimeInterval(7 * 86_400) }
    private let deception = "current:noaa/PUG1701"

    private func load(_ id: String) throws -> (station: WidgetStation, position: (lat: Double, lon: Double)) {
        let record = try XCTUnwrap(WidgetStationLoader.loadRecord(id: id))
        return (WidgetStationLoader.station(from: record), record.alertPosition)
    }

    func testTideExtremesAreTheEngineLowsWithTheLeadApplied() throws {
        let (station, position) = try load(TideStationRecord.fridayHarborID)
        guard case .tide(let engine, _, _) = station else { return XCTFail("expected a tide station") }
        let rule = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .tideExtreme(high: false), lead: 1_800)

        let found = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5)

        let lows = engine.extremes(from: now, to: week).filter { $0.kind == .low && $0.time >= now && $0.time <= week }
        XCTAssertFalse(lows.isEmpty)
        XCTAssertEqual(found.map(\.event), lows.map { alertMinute($0.time) })
        XCTAssertEqual(found.map(\.heightM), lows.map { Optional($0.height) })
        XCTAssertTrue(found.allSatisfy { $0.event.timeIntervalSince($0.fire) == 1_800 && $0.ruleID == rule.id })
    }

    func testRisingCrossingsSitBetweenALowBelowAndAHighAbove() throws {
        let (station, position) = try load(TideStationRecord.fridayHarborID)
        guard case .tide(let engine, _, _) = station else { return XCTFail("expected a tide station") }
        let extremes = engine.extremes(from: now.addingTimeInterval(-86_400), to: week.addingTimeInterval(86_400))
        let level = 1.0
        let rule = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .tideCrossing(heightM: level, rising: true))

        let found = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5)

        XCTAssertFalse(found.isEmpty)
        for o in found {
            guard let before = extremes.last(where: { $0.time <= o.event }),
                  let after = extremes.first(where: { $0.time > o.event }) else { continue }
            XCTAssertEqual(before.kind, .low)
            XCTAssertEqual(after.kind, .high)
            XCTAssertLessThan(before.height, level)
            XCTAssertGreaterThan(after.height, level)
        }
    }

    func testCurrentPeaksAreTheEngineMaxima() throws {
        let (station, position) = try load(deception)
        guard case .current(let engine, _, _) = station else { return XCTFail("expected a current station") }
        let rule = AlertRule(stationID: deception, trigger: .currentPeak(flood: true))

        let found = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5)

        let floods = engine.events(from: now, to: week).filter { $0.kind == .maxFlood && $0.time >= now && $0.time <= week }
        XCTAssertFalse(floods.isEmpty)
        XCTAssertEqual(found.map(\.event), floods.map { alertMinute($0.time) })
    }

    func testTheFirstWindowOpeningAgreesWithTheSiriAnswer() throws {
        // A generous threshold so no slack in the week is a hairline and the Siri query
        // (which answers only a real window) has one to give.
        let saved = AppGroup.defaults.object(forKey: AppGroup.slackWindowSpeedKey)
        defer { AppGroup.defaults.set(saved, forKey: AppGroup.slackWindowSpeedKey) }
        AppGroup.defaults.set(2.0, forKey: AppGroup.slackWindowSpeedKey)
        let (station, position) = try load(deception)
        let rule = AlertRule(stationID: deception, trigger: .slackWindowOpens)

        let found = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 2.0)
        let siri = try XCTUnwrap(SlackWindowShortcutQuery.next(at: station, after: now))

        XCTAssertFalse(found.isEmpty)
        XCTAssertTrue(found.allSatisfy { $0.end != nil && !$0.noWindow })
        // The Siri query samples from its own slack − 6 h; ours from the range − 6 h. The two
        // 10-minute grids interpolate the same crossing a little differently.
        if siri.start >= now {
            XCTAssertEqual(try XCTUnwrap(found.first).event.timeIntervalSince1970,
                           siri.start.timeIntervalSince1970, accuracy: 120)
        }
    }

    func testAWiderThresholdOpensTheWindowEarlier() throws {
        // The threshold is the user's boat: moving it moves every window (spec §4, §6).
        let (station, position) = try load(deception)
        let rule = AlertRule(stationID: deception, trigger: .slackWindowOpens)
        let narrow = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 1.0)
        let wide = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 2.0)

        let first = try XCTUnwrap(narrow.first { !$0.noWindow })
        let same = try XCTUnwrap(wide.first { abs($0.event.timeIntervalSince(first.event)) < 3 * 3_600 })
        XCTAssertLessThan(same.event, first.event)
    }

    func testATriggerThatDoesNotFitTheStationFindsNothing() throws {
        let (station, position) = try load(TideStationRecord.fridayHarborID)
        let rule = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .slackWindowOpens)
        XCTAssertEqual(alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5), [])
    }

    func testDaylightOnlyKeepsTheLowsUnderTheSun() throws {
        let (station, position) = try load(TideStationRecord.fridayHarborID)
        var rule = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .tideExtreme(high: false))
        let all = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5)
        rule.daylightOnly = true
        let sunlit = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5)
        let spans = daylightSpans(from: now, to: week, lat: position.lat, lon: position.lon)

        XCTAssertLessThan(sunlit.count, all.count)
        XCTAssertFalse(sunlit.isEmpty)
        XCTAssertTrue(sunlit.allSatisfy { o in spans.contains { $0.contains(o.event) } })
        XCTAssertTrue(Set(sunlit.map(\.event)).isSubset(of: Set(all.map(\.event))))
    }

    func testEclipsesLandOnTheFirstBite() throws {
        // Aug 2025 → Apr 2026 holds the 2026-03-03 total eclipse, visible from the Salish Sea.
        let (station, position) = try load(TideStationRecord.fridayHarborID)
        let until = now.addingTimeInterval(240 * 86_400)
        let rule = AlertRule(stationID: TideStationRecord.fridayHarborID, trigger: .eclipse)

        let found = alertOccurrences(rule, station: station, position: position, from: now, to: until, threshold: 0.5)

        let observer = try Observer(latitudeDeg: position.lat, longitudeDeg: position.lon)
        let expected = visibleEclipses(from: now, to: until, observer: observer).map { alertMinute($0.start) }.filter { $0 >= now && $0 <= until }
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(found.map(\.event), expected)
    }

    func testNinetyDaysOfWindowsStayInsideTheLaunchBudget() throws {
        let (station, position) = try load(deception)
        let rule = AlertRule(stationID: deception, trigger: .slackWindowOpens, daylightOnly: true)
        var found: [AlertOccurrence] = []
        let took = elapsed {
            found = alertOccurrences(rule, station: station, position: position,
                                     from: now, to: now.addingTimeInterval(90 * 86_400), threshold: 0.5)
        }
        print("90 days of daylight slack windows: \(took * 1000) ms, \(found.count) occurrences")
        XCTAssertGreaterThan(found.count, 100)
        // Spec §11 spike 2 (cost). If this fails, report the printed time; do not widen the budget.
        XCTAssertLessThan(took, 1.0 * perfScale)
    }

    func testOccurrencesDoNotDriftBetweenRuns() {
        // Two reschedules in different 10-minute buckets must name each instant to within the
        // calendar's matching tolerance, or its event is removed and re-added whenever the app
        // comes forward. Instants on a minute boundary can land a minute apart; 60 s is the bound.
        let cases: [(String, AlertTrigger)] = [
            (TideStationRecord.fridayHarborID, .tideCrossing(heightM: 1.0, rising: true)),
            (TideStationRecord.fridayHarborID, .tideExtreme(high: false)),
            (TideStationRecord.fridayHarborID, .tideExtreme(high: true)),
            (deception, .slackWindowOpens),          // at 0.5 kn this includes hairline slacks
            (deception, .currentPeak(flood: true)),
            (deception, .currentPeak(flood: false)),
            ("chs-malibu-rapids", .slack),           // a derived gate, when its reference is fitted
        ]
        let later = now.addingTimeInterval(3_700)
        // Clear of `later`, so an instant flooring across it can't change either run's count.
        let cut = later.addingTimeInterval(120)
        var ran = 0
        for (id, trigger) in cases {
            // A CHS derived gate predicts only once its reference port is fitted, which not
            // every machine has done. Skipping is right; asserting would fail by geography.
            guard let record = WidgetStationLoader.loadRecord(id: id) else { continue }
            ran += 1
            let (station, position) = (WidgetStationLoader.station(from: record), record.alertPosition)
            let rule = AlertRule(stationID: id, trigger: trigger)
            let first = alertOccurrences(rule, station: station, position: position, from: now, to: week, threshold: 0.5)
                .filter { $0.event >= cut }
            let second = alertOccurrences(rule, station: station, position: position, from: later, to: week, threshold: 0.5)
                .filter { $0.event >= cut }
            XCTAssertFalse(second.isEmpty, "\(trigger) found nothing")
            XCTAssertEqual(second.count, first.count, "\(trigger) found a different set of occurrences")
            for (a, b) in zip(first, second) {
                XCTAssertLessThanOrEqual(abs(a.event.timeIntervalSince(b.event)), 60, "\(trigger) instant drifted past a minute")
                XCTAssertLessThanOrEqual(abs((a.end ?? a.event).timeIntervalSince(b.end ?? b.event)), 60,
                                         "\(trigger) window end drifted past a minute")
            }
        }
        // Only the CHS derived gate is allowed to be absent. If the bundled six stop loading,
        // this test passes on an empty loop while every foreground silently rewrites the user's
        // calendar — the one thing it exists to catch.
        XCTAssertGreaterThanOrEqual(ran, 6, "the bundled cases must all load")
    }

    func testAOnceRuleFindsOnlyItsOwnMoment() throws {
        let id = TideStationRecord.fridayHarborID
        let (station, position) = try load(id)
        let every = AlertRule(stationID: id, trigger: .tideExtreme(high: false))
        let all = alertOccurrences(every, station: station, position: position,
                                   from: now, to: week, threshold: 0.5)
        XCTAssertGreaterThan(all.count, 2, "the fixture needs several lows to pick one out of")
        let chosen = all[1].event

        var only = every
        only.once = chosen
        let found = alertOccurrences(only, station: station, position: position,
                                     from: now, to: week, threshold: 0.5)

        XCTAssertEqual(found.map(\.event), [chosen])
    }

    func testAOnceRuleGivenAnUnflooredInstantStillMatches() throws {
        let id = TideStationRecord.fridayHarborID
        let (station, position) = try load(id)
        let every = AlertRule(stationID: id, trigger: .tideExtreme(high: false))
        let chosen = alertOccurrences(every, station: station, position: position,
                                      from: now, to: week, threshold: 0.5)[1].event

        var only = every
        only.once = chosen.addingTimeInterval(47)   // a caller's un-floored Date

        XCTAssertEqual(alertOccurrences(only, station: station, position: position,
                                        from: now, to: week, threshold: 0.5).map(\.event),
                       [chosen])
    }

    func testAOnceRuleWhoseMomentIsNotAnEventFindsNothing() throws {
        let id = TideStationRecord.fridayHarborID
        let (station, position) = try load(id)
        var only = AlertRule(stationID: id, trigger: .tideExtreme(high: false))
        // 37 minutes past a 10-minute grid instant: no extreme lands on this minute.
        only.once = now.addingTimeInterval(37 * 60)

        XCTAssertEqual(alertOccurrences(only, station: station, position: position,
                                        from: now, to: week, threshold: 0.5), [])
    }

    func testExpiryTakesOnlyOnceRulesWhoseMomentHasPassed() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let repeating = AlertRule(stationID: "a", trigger: .slack)
        let past = AlertRule(stationID: "a", trigger: .slack, once: now.addingTimeInterval(-60))
        let coming = AlertRule(stationID: "a", trigger: .slack, once: now.addingTimeInterval(60))

        XCTAssertEqual(expiredRules([repeating, past, coming], now: now), [past.id])
    }
}
