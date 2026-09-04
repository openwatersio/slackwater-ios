// Slackwater — GPL v3. WidgetStationLoader: id → engine-ready station for the
// widget process — bundled NOAA directly, CHS via the shared fitted-model
// store, nil when unfitted.
import XCTest
@testable import Slackwater
import TideEngine

final class WidgetStationLoaderTests: XCTestCase {
    func testTargetedBundledLookupFindsOneStation() {
        let record: TideStationRecord? = bundled(
            "stations", id: TideStationRecord.fridayHarborID)

        XCTAssertEqual(record?.id, TideStationRecord.fridayHarborID)
    }

    func testBundledTideStationLoads() {
        let st = WidgetStationLoader.load(id: TideStationRecord.fridayHarborID)
        guard case .tide(let s, let tz, let name)? = st else {
            return XCTFail("expected .tide, got \(String(describing: st))")
        }
        XCTAssertFalse(s.extremes(from: .now, to: .now.addingTimeInterval(86_400)).isEmpty)
        XCTAssertEqual(tz.identifier, "America/Los_Angeles")
        XCTAssert(name.contains("Friday Harbor"))
    }

    func testBundledCurrentStationLoads() {
        // Any bundled NOAA current station; take the first from the catalog.
        let record = CurrentStationRecord.all.first!
        guard case .current(let s, _, _)? =
                WidgetStationLoader.load(id: "current:" + record.id) else {
            return XCTFail("expected .current")
        }
        XCTAssertFalse(s.events(from: .now, to: .now.addingTimeInterval(86_400)).isEmpty)
    }

    func testUnknownIdIsNil() {
        XCTAssertNil(WidgetStationLoader.load(id: "nope:missing"))
    }

    func testDefaultUsesCurrentLocation() {
        XCTAssertEqual(WidgetStationLoader.defaultStationID(), AppGroup.currentLocationStationID)
    }

    func testCurrentLocationResolvesCachedStation() {
        let d = UserDefaults(suiteName: #function)!
        defer { d.removePersistentDomain(forName: #function) }
        d.set(TideStationRecord.fridayHarborID, forKey: AppGroup.currentLocationStationKey)

        XCTAssertEqual(WidgetStationLoader.resolvedStationID(
            AppGroup.currentLocationStationID, defaults: d),
            TideStationRecord.fridayHarborID)
    }

    func testCurrentLocationFallsBackWhenCacheIsInvalid() {
        let d = UserDefaults(suiteName: #function)!
        defer { d.removePersistentDomain(forName: #function) }
        let favorite = TideStationRecord.fridayHarborID
        d.set("missing", forKey: AppGroup.currentLocationStationKey)
        d.set([favorite], forKey: AppGroup.favoritesKey)

        XCTAssertEqual(WidgetStationLoader.resolvedStationID(
            AppGroup.currentLocationStationID, defaults: d), favorite)
    }

    func testConcreteStationDoesNotResolveAgain() {
        let d = UserDefaults(suiteName: #function)!
        defer { d.removePersistentDomain(forName: #function) }
        d.set("missing", forKey: AppGroup.currentLocationStationKey)

        XCTAssertEqual(WidgetStationLoader.resolvedStationID(
            TideStationRecord.fridayHarborID, defaults: d),
            TideStationRecord.fridayHarborID)
    }

    func testFallbackFollowsFavorites() {
        let d = AppGroup.defaults
        let saved = d.stringArray(forKey: AppGroup.favoritesKey)
        defer { d.set(saved, forKey: AppGroup.favoritesKey) }
        d.set([TideStationRecord.fridayHarborID], forKey: AppGroup.favoritesKey)
        XCTAssertEqual(WidgetStationLoader.fallbackStationID(defaults: d),
                       TideStationRecord.fridayHarborID)
    }
}
