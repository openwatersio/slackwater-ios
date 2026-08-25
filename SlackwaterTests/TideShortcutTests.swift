// Slackwater — GPL v3. Voice shortcuts query the selected local tide station.
import XCTest
@testable import Slackwater

@MainActor final class TideShortcutTests: XCTestCase {
    func testQueryReturnsTheRequestedTideKind() throws {
        let savedUnits = AppGroup.defaults.object(forKey: unitsKey)
        defer { AppGroup.defaults.set(savedUnits, forKey: unitsKey) }
        AppGroup.defaults.set("imperial", forKey: unitsKey)
        let station = try XCTUnwrap(WidgetStationLoader.load(id: TideStationRecord.fridayHarborID))
        let now = Date(timeIntervalSince1970: 1_755_800_000)

        let low = try XCTUnwrap(TideShortcutQuery.next(.low, at: station, after: now))
        let high = try XCTUnwrap(TideShortcutQuery.next(.high, at: station, after: now))

        XCTAssertEqual(low.extreme.kind, .low)
        XCTAssertEqual(high.extreme.kind, .high)
        XCTAssertGreaterThan(low.extreme.time, now)
        XCTAssertGreaterThan(high.extreme.time, now)
        XCTAssertTrue(low.spoken.contains("low tide at Friday Harbor"))
        XCTAssertNotNil(low.spoken.range(of: #"\d+\.\d+ feet\.$"#,
                                         options: .regularExpression))
        XCTAssertTrue(low.spoken.hasSuffix("feet."))

        AppGroup.defaults.set("metric", forKey: unitsKey)
        XCTAssertTrue(low.spoken.hasSuffix("metres."))

        guard case .tide(let engine, _, _) = station else { return XCTFail("expected tide station") }
        let utc = try XCTUnwrap(TideShortcutQuery.next(.low,
            at: .tide(engine, tz: TimeZone(secondsFromGMT: 0)!, name: "Test"), after: now))
        let kiritimati = try XCTUnwrap(TideShortcutQuery.next(.low,
            at: .tide(engine, tz: TimeZone(secondsFromGMT: 14 * 3_600)!, name: "Test"), after: now))
        XCTAssertNotEqual(utc.spoken, kiritimati.spoken)
    }

    func testNearestStationSeparatesTidesFromCurrents() throws {
        let tide = try XCTUnwrap(TideStationRecord.all.first {
            $0.id == TideStationRecord.fridayHarborID
        })
        let nearestTide = try XCTUnwrap(LocalStationQuery.nearest(
            .tide, to: (tide.latitude, tide.longitude)))
        guard case .tide(_, _, let tideName) = nearestTide else {
            return XCTFail("expected a tide station")
        }
        XCTAssertEqual(tideName, tide.name)

        let current = CurrentStationRecord.all.first!
        let nearestCurrent = try XCTUnwrap(LocalStationQuery.nearest(
            .current, to: (current.latitude, current.longitude)))
        guard case .current(_, _, let currentName) = nearestCurrent else {
            return XCTFail("expected a current station")
        }
        XCTAssertEqual(currentName, current.name)
    }

    func testSlackQueryReturnsTheNextMeasuredWindow() throws {
        let record = CurrentStationRecord.all.first!
        let station = WidgetStation.current(record.engineStation, tz: record.tz, name: record.name)
        let now = Date(timeIntervalSince1970: 1_755_800_000)

        let result = try XCTUnwrap(SlackWindowShortcutQuery.next(at: station, after: now))

        XCTAssertLessThan(result.start, result.slack.time)
        XCTAssertGreaterThan(result.end, result.slack.time)
        XCTAssertTrue(result.spoken.contains("slack window at \(record.name)"))
        XCTAssertTrue(result.spoken.contains("starts in"))

        let active = SlackWindowShortcutResult(
            slack: result.slack, start: result.start, end: result.end,
            stationName: result.stationName, timeZone: result.timeZone,
            queriedAt: result.start.addingTimeInterval(60))
        XCTAssertTrue(active.spoken.contains("is open now"))
    }
}
