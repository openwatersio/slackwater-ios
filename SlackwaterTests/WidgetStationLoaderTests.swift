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

    private func appendStation(copying id: String, as newID: String, name: String, in directory: URL) throws {
        try edit("stations", in: directory) { rows in
            var station = rows[rows.firstIndex { $0["id"] as? String == id }!]
            station["id"] = newID
            station["name"] = name
            rows.append(station)
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
        let removed = try XCTUnwrap(bundled.tides.first {
            $0.id != TideStationRecord.fridayHarborID && !referenced.contains($0.id)
        })
        let storage = try makeStorage { directory in
            try removeStation(removed.id, from: directory)
            try appendTombstone(removed.id, to: directory)
        }
        XCTAssertNil(WidgetStationLoader.loadRecord(
            id: removed.id,
            locator: CatalogFileLocator(storage: storage)))
    }

    func testCorruptActiveNOAAFileFallsBackToBundle() throws {
        let storage = try makeStorage()
        let directory = try XCTUnwrap(storage.activeDirectory())
        try Data("broken".utf8).write(to: directory.appendingPathComponent("stations.json"))
        let record = try XCTUnwrap(WidgetStationLoader.loadRecord(
            id: TideStationRecord.fridayHarborID,
            locator: CatalogFileLocator(storage: storage)))
        guard case .tide(let tide, _) = record else { return XCTFail("Expected tide") }
        XCTAssertEqual(tide.name, TideStationRecord.byId[TideStationRecord.fridayHarborID]?.name)
    }

    func testTruncatedNestedActiveNOAAFileFallsBackToBundle() throws {
        let storage = try makeStorage()
        let directory = try XCTUnwrap(storage.activeDirectory())
        try Data("[{\"id\":\"first\",\"aliases\":[]".utf8)
            .write(to: directory.appendingPathComponent("stations.json"))
        let record = try XCTUnwrap(WidgetStationLoader.loadRecord(
            id: TideStationRecord.fridayHarborID,
            locator: CatalogFileLocator(storage: storage)))
        guard case .tide(let tide, _) = record else { return XCTFail("Expected tide") }
        XCTAssertEqual(tide.name, TideStationRecord.byId[TideStationRecord.fridayHarborID]?.name)
    }

    func testCompactScannerRejectsInvalidOuterGrammar() {
        struct IDOnlyRecord: Decodable { let id: String }
        let missing = "missing"
        for bytes in [
            "[{\"id\":\"first\"}][]",
            "[{\"id\":\"first\"},garbage]",
            "[{\"id\":\"first\"}{\"id\":\"second\"}]",
            "[{\"id\":\"first\"}[]]",
            "[{\"id\":\"first\"},[]{\"id\":\"second\"}]",
            "[{\"id\":\"first\"},[garbage]{\"id\":\"second\"}]"
        ] {
            XCTAssertThrowsError(try decodeCatalogRecord(Data(bytes.utf8), id: missing) as TideStationRecord?)
        }
        XCTAssertThrowsError(try decodeCatalogRecord(Data("{\"id\":\"first\"}]".utf8), id: "first") as IDOnlyRecord?)
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
        let staleStation = current.engineStation(referenceRecord: bundled)
        let stale = staleStation
            .speeds(from: start, to: end, step: 60).map(\.speed)
        XCTAssertEqual(actual.count, expected.count)
        XCTAssertTrue(zip(actual, expected).allSatisfy { abs($0 - $1) < 0.000_001 })
        XCTAssertTrue(zip(actual, stale).contains { abs($0 - $1) > 0.000_001 })

        let paired = zip(
            station.speeds(from: start, to: end, step: 60),
            staleStation.speeds(from: start, to: end, step: 60))
        let pair = try XCTUnwrap(paired.max { abs($0.0.speed - $0.1.speed) < abs($1.0.speed - $1.1.speed) })
        let now = pair.0.time
        let card = WidgetCard.build(record, now: now)
        let expectedReading = station.speeds(from: now, to: now.addingTimeInterval(1), step: 1)[0].speed
        let staleReading = staleStation.speeds(from: now, to: now.addingTimeInterval(1), step: 1)[0].speed
        guard case .current(let signed, _, _, _, _) = card.reading else {
            return XCTFail("Expected current reading")
        }
        XCTAssertEqual(signed, expectedReading, accuracy: 0.000_001)
        XCTAssertGreaterThan(abs(signed - staleReading), 0.000_001)

        let graph = try XCTUnwrap(card.graph)
        let graphStart = now.addingTimeInterval(-StationCardGraph.backWindow)
        let graphEnd = now.addingTimeInterval(StationCardGraph.forwardWindow)
        let activeGraph = station.speeds(from: graphStart, to: graphEnd, step: StationCardGraph.sampleStep).map(\.speed)
        let staleGraph = staleStation.speeds(from: graphStart, to: graphEnd, step: StationCardGraph.sampleStep).map(\.speed)
        XCTAssertEqual(graph.points.count, activeGraph.count)
        XCTAssertTrue(zip(graph.points, activeGraph).allSatisfy { abs($0.value - $1) < 0.000_001 })
        XCTAssertTrue(zip(graph.points, staleGraph).contains { abs($0.value - $1) > 0.000_001 })
    }

    func testWidgetResolvesASubordinateOfANonPrimaryBin() throws {
        let friar = try XCTUnwrap(CurrentStationRecord.all.first { $0.id == "noaa/ACT0091" })
        let record = try XCTUnwrap(WidgetStationLoader.loadRecord(id: "current:" + friar.id))
        guard case .current(_, let station) = record else { return XCTFail("Expected current") }
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let speeds = station.speeds(from: now, to: now.addingTimeInterval(86_400), step: 600).map(\.speed)
        XCTAssertGreaterThan(speeds.max()! - speeds.min()!, 0.5, "the widget fell back to a flat harmonic with no constituents")
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

    func testWidgetIdentityCallersUseActiveCatalog() async throws {
        let bundled = try CatalogSnapshot(directory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
        let referenced = Set(bundled.tides.compactMap(\.reference))
            .union(bundled.currents.compactMap(\.tideReference))
        let removed = try XCTUnwrap(bundled.tides.first {
            $0.id != TideStationRecord.fridayHarborID && !referenced.contains($0.id)
        })
        let addedID = "999999999"
        let storage = try makeStorage { directory in
            try appendStation(copying: removed.id, as: addedID, name: "Remote only", in: directory)
            try removeStation(removed.id, from: directory)
            try appendTombstone(removed.id, to: directory)
        }
        let locator = CatalogFileLocator(storage: storage)
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set([addedID, removed.id], forKey: AppGroup.favoritesKey)

        let query = StationQuery(locator: locator, defaults: defaults)
        let sections = query.sectionedChoices()
        // The location-following entries lead the picker as their own section.
        XCTAssertEqual(sections.first?.title, "Nearest Station")
        XCTAssertEqual(sections.first?.items.map(\.id),
                       [AppGroup.currentLocationStationID,
                        AppGroup.nearestTideStationID,
                        AppGroup.nearestCurrentStationID])
        let suggestions = sections.flatMap(\.items)
        XCTAssertEqual(suggestions.first { $0.id == addedID }?.name, "Remote only")
        XCTAssertNil(suggestions.first { $0.id == removed.id })
        let resolved = try await query.entities(for: [addedID, removed.id])
        XCTAssertEqual(resolved.map(\.id), [addedID])

        defaults.set(addedID, forKey: AppGroup.currentLocationStationKey)
        XCTAssertEqual(WidgetStationLoader.resolvedStationID(
            AppGroup.currentLocationStationID, defaults: defaults, locator: locator), addedID)
        defaults.set(removed.id, forKey: AppGroup.currentLocationStationKey)
        XCTAssertEqual(WidgetStationLoader.resolvedStationID(
            AppGroup.currentLocationStationID, defaults: defaults, locator: locator),
                       addedID)
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

    func testWidgetRendersSavedOnlineCurrentGates() throws {
        let now = Date()
        let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        let start = dayLocal(now, tz).addingTimeInterval(-2 * 86_400)
        let times = stride(from: start.timeIntervalSince1970,
                           through: start.timeIntervalSince1970 + 12 * 86_400,
                           by: 900).map { $0 }
        let speeds = times.map { sin(($0 - start.timeIntervalSince1970) * .pi / (6 * 3_600)) }
        for id in ["chs-tillicum-bridge", "chs-nakwakto-rapids"] {
            let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.id == id })
            let url = ChsModelStore.onlineUrl(id)
            let previous = try? Data(contentsOf: url)
            defer {
                if let previous { try? previous.write(to: url) }
                else { try? FileManager.default.removeItem(at: url) }
            }
            try ChsModelStore.saveOnline(ChsOnlineWindow(
                stationID: id, iwlsName: gate.name, timezone: gate.timezone,
                fetchedAt: now, start: start,
                end: start.addingTimeInterval(12 * 86_400),
                floodDirection: 290, ebbDirection: 110,
                times: times, speeds: speeds))

            let record = try XCTUnwrap(WidgetStationLoader.loadRecord(id: id, at: now), "\(id) stayed blank")
            let card = WidgetCard.build(record, now: now)
            XCTAssertEqual(card.name, gate.name)
            XCTAssertGreaterThan(card.graph?.points.count ?? 0, 10)
            let graphValues = try XCTUnwrap(card.graph?.points.map(\.value))
            XCTAssertGreaterThan((graphValues.max() ?? 0) - (graphValues.min() ?? 0), 1)
            let snapshot = WidgetSnapshot.build(WidgetStationLoader.station(from: record), now: now)
            XCTAssertEqual(snapshot.curveKind, .current)
            XCTAssertGreaterThan(snapshot.sparkline.count, 10)
            XCTAssertNotNil(snapshot.next)
            XCTAssertNil(WidgetStationLoader.loadRecord(
                id: id, at: start.addingTimeInterval(11 * 86_400)),
                "a widget must not show a curve after its downloaded window runs out")
        }
    }

    func testUnknownIdIsNil() {
        XCTAssertNil(WidgetStationLoader.load(id: "nope:missing"))
    }

    func testDefaultUsesCurrentLocation() {
        XCTAssertEqual(WidgetStationLoader.defaultStationID(), AppGroup.currentLocationStationID)
    }

    /// The series-narrowed sentinels resolve through their own cached ids —
    /// a Nearest Current widget must never land on the tide gauge the
    /// any-series cache points at.
    func testNearestSeriesSentinelsResolveTheirOwnCache() {
        let d = UserDefaults(suiteName: #function)!
        defer { d.removePersistentDomain(forName: #function) }
        let currentID = "current:" + CurrentStationRecord.all.first!.id
        d.set(TideStationRecord.fridayHarborID, forKey: AppGroup.currentLocationStationKey)
        d.set(TideStationRecord.fridayHarborID, forKey: AppGroup.nearestTideStationKey)
        d.set(currentID, forKey: AppGroup.nearestCurrentStationKey)

        XCTAssertEqual(WidgetStationLoader.resolvedStationID(
            AppGroup.nearestTideStationID, defaults: d), TideStationRecord.fridayHarborID)
        XCTAssertEqual(WidgetStationLoader.resolvedStationID(
            AppGroup.nearestCurrentStationID, defaults: d), currentID)
    }

    /// A sentinel with no cached fix falls back the same way Current
    /// Location always has: first favorite, else most recent, else Friday
    /// Harbor.
    func testNearestSeriesSentinelsFallBackWithoutACache() {
        let d = UserDefaults(suiteName: #function)!
        defer { d.removePersistentDomain(forName: #function) }
        let favorite = TideStationRecord.fridayHarborID
        d.set([favorite], forKey: AppGroup.favoritesKey)

        XCTAssertEqual(WidgetStationLoader.resolvedStationID(
            AppGroup.nearestTideStationID, defaults: d), favorite)
        XCTAssertEqual(WidgetStationLoader.resolvedStationID(
            AppGroup.nearestCurrentStationID, defaults: d), favorite)
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
