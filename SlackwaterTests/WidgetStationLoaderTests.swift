// Slackwater — GPL v3. WidgetStationLoader: id → engine-ready station for the
// widget process — bundled NOAA directly, CHS via the shared fitted-model
// store, nil when unfitted.
import XCTest
@testable import Slackwater
import TideEngine

final class WidgetStationLoaderTests: XCTestCase {
    private var storageRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in storageRoots where FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    private func makeStorage(_ change: (URL) throws -> Void = { _ in }) throws -> CatalogStorage {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        storageRoots.append(root)
        let storage = CatalogStorage(root: root, bundleDirectory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
        let batch = UUID()
        let directory = try storage.prepareStaging(for: batch)
        for resource in CatalogSnapshot.resources {
            try FileManager.default.copyItem(
                at: XCTUnwrap(Bundle.main.url(forResource: resource, withExtension: "json")),
                to: directory.appendingPathComponent(resource + ".json"))
        }
        try change(directory)
        _ = try storage.commit(batch: batch, etags: [:], active: nil)
        return storage
    }

    private func edit(_ resource: String, in directory: URL,
                      change: (inout [[String: Any]]) -> Void) throws {
        let url = directory.appendingPathComponent(resource + ".json")
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        change(&rows)
        if ["stations", "currents"].contains(resource) {
            let records = try rows.map { row -> String in
                var rest = row
                let id = rest.removeValue(forKey: "id")!
                let idJSON = try JSONSerialization.data(withJSONObject: id,
                                                        options: [.fragmentsAllowed, .withoutEscapingSlashes])
                let fieldsJSON = try JSONSerialization.data(withJSONObject: rest)
                return "{\"id\":" + String(decoding: idJSON, as: UTF8.self) + ","
                    + String(decoding: fieldsJSON.dropFirst(), as: UTF8.self)
            }
            try Data(("[" + records.joined(separator: ",") + "]").utf8).write(to: url)
        } else {
            try JSONSerialization.data(withJSONObject: rows).write(to: url)
        }
    }

    private func editStation(_ id: String, in directory: URL,
                             change: (inout [String: Any]) -> Void) throws {
        try edit("stations", in: directory) { rows in
            change(&rows[rows.firstIndex { $0["id"] as? String == id }!])
        }
    }

    private func removeStation(_ id: String, from directory: URL) throws {
        try edit("stations", in: directory) { rows in
            rows.remove(at: rows.firstIndex { $0["id"] as? String == id }!)
        }
    }

    private func appendTombstone(_ id: String, to directory: URL) throws {
        try edit("chs-tombstones", in: directory) {
            $0.append(["id": id, "name": "Removed station", "region": "Removed", "latitude": 0, "longitude": 0])
        }
    }

    private func scaleCurrentConstituents(_ id: String, by factor: Double, in directory: URL) throws {
        try edit("currents", in: directory) { rows in
            let index = rows.firstIndex { $0["id"] as? String == id }!
            var constituents = rows[index]["constituents"] as! [[String: Any]]
            for index in constituents.indices {
                constituents[index]["amplitude"] = (constituents[index]["amplitude"] as! NSNumber).doubleValue * factor
            }
            rows[index]["constituents"] = constituents
        }
    }

    func testWidgetReadsCorrectedActiveStation() throws {
        let storage = try makeStorage { directory in
            try editStation(TideStationRecord.fridayHarborID, in: directory) { $0["name"] = "Remote Friday Harbor" }
        }
        let record = try XCTUnwrap(WidgetStationLoader.loadRecord(
            id: TideStationRecord.fridayHarborID,
            locator: CatalogFileLocator(storage: storage)))
        guard case .tide(let tide, _) = record else { return XCTFail("Expected tide") }
        XCTAssertEqual(tide.name, "Remote Friday Harbor")
    }

    func testWidgetDoesNotFallBackWhenStationWasRemoved() throws {
        let bundled = try CatalogSnapshot(directory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
        let referenced = Set(bundled.tides.compactMap(\.reference))
            .union(bundled.currents.compactMap(\.tideReference))
        let removed = try XCTUnwrap(bundled.tides.first { !referenced.contains($0.id) })
        let storage = try makeStorage { directory in
            try removeStation(removed.id, from: directory)
            try appendTombstone(removed.id, to: directory)
        }
        XCTAssertNil(WidgetStationLoader.loadRecord(
            id: removed.id,
            locator: CatalogFileLocator(storage: storage)))
    }

    func testSubordinateCurrentAndReferenceUseSameGeneration() throws {
        let subordinate = try XCTUnwrap(CurrentStationRecord.all.first(where: \.isSubordinate))
        let storage = try makeStorage { directory in
            try scaleCurrentConstituents(subordinate.reference!, by: 2, in: directory)
        }
        let record = try XCTUnwrap(WidgetStationLoader.loadRecord(
            id: "current:" + subordinate.id,
            locator: CatalogFileLocator(storage: storage)))
        guard case .current(let current, let station) = record else { return XCTFail("Expected current") }
        let directory = try XCTUnwrap(storage.activeDirectory())
        let activeReference: CurrentStationRecord? = try catalogRecord(
            "currents", id: subordinate.reference!, directory: directory)
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let end = start + 6 * 3600
        let actual = station.speeds(from: start, to: end, step: 60).map(\.speed)
        let expected = current.engineStation(referenceRecord: activeReference)
            .speeds(from: start, to: end, step: 60).map(\.speed)
        let bundled = try XCTUnwrap(CurrentStationRecord.byId[subordinate.reference!])
        let stale = current.engineStation(referenceRecord: bundled)
            .speeds(from: start, to: end, step: 60).map(\.speed)
        XCTAssertEqual(actual.count, expected.count)
        XCTAssertTrue(zip(actual, expected).allSatisfy { abs($0 - $1) < 0.000_001 })
        XCTAssertTrue(zip(actual, stale).contains { abs($0 - $1) > 0.000_001 })
    }

    func testWidgetReadsEverySmallGeneratedCatalogThroughActiveDirectory() throws {
        let storage = try makeStorage()
        let directory = try XCTUnwrap(storage.activeDirectory())
        for id in [ChsStationInfo.all[0].id, ChsGateInfo.all[0].id, ChsCurrentGateInfo.all[0].id] {
            XCTAssertNotNil(try StationItem.widgetItem(id: id, directory: directory))
        }
        let tombstones: [StationTombstone] = try readCatalog("chs-tombstones", directory: directory)
        XCTAssertFalse(tombstones.isEmpty)
    }

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
