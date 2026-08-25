// Slackwater — GPL v3. Voice shortcuts query the selected local tide station.
import XCTest
@testable import Slackwater

final class TideShortcutTests: XCTestCase {
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

    func testDefaultQuerySkipsASelectedCurrentStation() throws {
        let savedFavorites = AppGroup.defaults.stringArray(forKey: AppGroup.favoritesKey)
        let savedRecents = AppGroup.defaults.stringArray(forKey: AppGroup.recentsKey)
        defer {
            AppGroup.defaults.set(savedFavorites, forKey: AppGroup.favoritesKey)
            AppGroup.defaults.set(savedRecents, forKey: AppGroup.recentsKey)
        }
        AppGroup.defaults.set(["current:" + CurrentStationRecord.all.first!.id],
                              forKey: AppGroup.favoritesKey)
        AppGroup.defaults.set([TideStationRecord.fridayHarborID],
                              forKey: AppGroup.recentsKey)

        let result = try XCTUnwrap(TideShortcutQuery.next(.low,
            after: Date(timeIntervalSince1970: 1_755_800_000)))

        XCTAssertEqual(result.stationName, "Friday Harbor")
    }

    func testDefaultQueryFallsBackToFridayHarbor() throws {
        let savedFavorites = AppGroup.defaults.stringArray(forKey: AppGroup.favoritesKey)
        let savedRecents = AppGroup.defaults.stringArray(forKey: AppGroup.recentsKey)
        defer {
            AppGroup.defaults.set(savedFavorites, forKey: AppGroup.favoritesKey)
            AppGroup.defaults.set(savedRecents, forKey: AppGroup.recentsKey)
        }
        AppGroup.defaults.removeObject(forKey: AppGroup.favoritesKey)
        AppGroup.defaults.removeObject(forKey: AppGroup.recentsKey)

        let result = try XCTUnwrap(TideShortcutQuery.next(.high,
            after: Date(timeIntervalSince1970: 1_755_800_000)))

        XCTAssertEqual(result.stationName, "Friday Harbor")
    }
}
