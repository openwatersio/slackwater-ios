import XCTest
import SlackwaterDatabase
@testable import Slackwater

@MainActor final class CatalogSnapshotTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for resource in CatalogSnapshot.resources {
            let file = CatalogSnapshot.fileName(resource)
            try FileManager.default.copyItem(
                at: XCTUnwrap(Bundle.main.url(forResource: file, withExtension: nil)),
                to: directory.appendingPathComponent(file))
        }
    }

    override func tearDown() async throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
        try await super.tearDown()
    }

    private func edit(_ resource: String, _ change: (inout [[String: Any]]) -> Void) throws {
        let url = directory.appendingPathComponent(resource + ".json")
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        change(&rows)
        try JSONSerialization.data(withJSONObject: rows).write(to: url)
    }

    /// The JSON catalogs; tide and current stations are binary databases,
    /// edited below as decoded records instead.
    private let jsonResources = CatalogSnapshot.resources.filter { $0 != "stations" && $0 != "currents" }

    /// The bundled tide records as JSON rows, encoded once. Validation reads
    /// records, so a change to a row reaches it exactly as a bad file would.
    private static let tideRows: [[String: Any]] = {
        let data = try! JSONEncoder().encode(TideStationRecord.all)
        return try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    }()

    /// The bundled current records as rows, from the currents.json that
    /// CurrentStationDatabaseTests holds equal to the database.
    private static let currentRows: [[String: Any]] = {
        let url = repoRoot.appendingPathComponent("Slackwater/Resources/currents.json")
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
    }()

    private static func decoded<T: Decodable>(_ rows: [[String: Any]]) throws -> [T] {
        try JSONDecoder().decode([T].self, from: JSONSerialization.data(withJSONObject: rows))
    }

    private func snapshot(tides: (inout [[String: Any]]) -> Void = { _ in },
                          currents: (inout [[String: Any]]) -> Void = { _ in },
                          records: (inout [CurrentStationRecord]) -> Void = { _ in },
                          active: CatalogSnapshot? = nil) throws -> CatalogSnapshot {
        var tideRows = Self.tideRows, currentRows = Self.currentRows
        tides(&tideRows)
        currents(&currentRows)
        var currentRecords: [CurrentStationRecord] = try Self.decoded(currentRows)
        records(&currentRecords)
        return try CatalogSnapshot(tides: Self.decoded(tideRows), currents: currentRecords,
                                   directory: directory, active: active)
    }

    private func rejectedTides(file: StaticString = #filePath, line: UInt = #line,
                               _ change: (inout [[String: Any]]) -> Void) {
        rejectedRecords("stations", file: file, line: line) { try snapshot(tides: change) }
    }

    private func rejectedCurrents(active: CatalogSnapshot? = nil, file: StaticString = #filePath, line: UInt = #line,
                                  _ change: (inout [[String: Any]]) -> Void) {
        rejectedRecords("currents", file: file, line: line) { try snapshot(currents: change, active: active) }
    }

    private func rejectedRecords(_ resource: String, file: StaticString, line: UInt,
                                 _ build: () throws -> CatalogSnapshot) {
        XCTAssertThrowsError(try build(), file: file, line: line) {
            guard let error = $0 as? CatalogError else { return XCTFail("Unexpected error: \($0)", file: file, line: line) }
            XCTAssertEqual(error.resource, resource, file: file, line: line)
            XCTAssertEqual(error.stage, .validation, file: file, line: line)
        }
    }

    private func rejected(_ resource: String, stage: CatalogError.Stage = .validation,
                          active: CatalogSnapshot? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try CatalogSnapshot(directory: directory, active: active), file: file, line: line) {
            guard let error = $0 as? CatalogError else { return XCTFail("Unexpected error: \($0)", file: file, line: line) }
            XCTAssertEqual(error.resource, resource, file: file, line: line)
            XCTAssertEqual(error.stage, stage, file: file, line: line)
        }
    }

    func testShippedSnapshotAndCorrectionValidate() throws {
        let original = try CatalogSnapshot(directory: directory)
        XCTAssertEqual(original.items.count, StationItem.all.count)
        XCTAssertEqual(original.byID.count, original.items.count)
        var correctedID = ""
        try edit("chs-stations") { correctedID = $0[0]["id"] as! String; $0[0]["name"] = "Corrected name" }
        let corrected = try CatalogSnapshot(directory: directory, active: original)
        XCTAssertEqual(corrected.byID[correctedID]?.name, "Corrected name")
        XCTAssertNotEqual(original.byID[correctedID]?.name, "Corrected name")
    }

    func testMissingMalformedAndEmptyFilesAreNamedErrors() throws {
        for resource in ["stations", "currents"] {
            let url = directory.appendingPathComponent(CatalogSnapshot.fileName(resource))
            let saved = try Data(contentsOf: url)
            try FileManager.default.removeItem(at: url)
            rejected(resource, stage: .lookup)
            try Data("broken".utf8).write(to: url)
            rejected(resource, stage: .decode)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            rejected(resource, stage: .read)
            try FileManager.default.removeItem(at: url)
            try saved.write(to: url)
        }
    }

    /// A database cut short after a valid header opens unverified and traps on
    /// a later read, so validation verifies the whole file and refuses it.
    func testTruncatedDatabasesAreRefused() throws {
        for resource in ["stations", "currents"] {
            let url = directory.appendingPathComponent(CatalogSnapshot.fileName(resource))
            let saved = try Data(contentsOf: url)
            try saved.prefix(saved.count / 2).write(to: url)
            XCTAssertNoThrow(try stationDatabase(resource, directory: directory), "the header alone still opens")
            rejected(resource, stage: .decode)
            try saved.write(to: url)
        }
    }

    func testRequiredCatalogNeverConvertsFailureToEmpty() throws {
        let missing = directory.appendingPathComponent("missing", isDirectory: true)
        XCTAssertThrowsError(
            try requiredCatalog("chs-stations", directory: missing) as [ChsStationInfo]
        ) { error in
            let catalog = error as? CatalogError
            XCTAssertEqual(catalog?.resource, "chs-stations")
            XCTAssertEqual(catalog?.stage, .lookup)
        }
    }

    func testEveryCatalogMustRemainNonempty() throws {
        rejectedTides { $0 = [] }
        rejectedCurrents { $0 = [] }
        for resource in jsonResources {
            let url = directory.appendingPathComponent(resource + ".json")
            let saved = try Data(contentsOf: url)
            try Data("[]".utf8).write(to: url)
            rejected(resource)
            try saved.write(to: url)
        }
    }

    func testInvalidIdentityAndDuplicateIDs() throws {
        for (key, value) in [("id", "" as Any), ("name", "  "), ("latitude", 91), ("longitude", -181)] {
            rejectedTides { $0[0][key] = value }
        }
        rejectedTides { $0.append($0[0]) }
        rejectedTides { $0[0]["timezone"] = "not/a/timezone" }
        for (key, value) in [("id", "" as Any), ("name", "  "), ("latitude", 91), ("longitude", -181)] {
            rejectedCurrents { $0[0][key] = value }
        }
        rejectedCurrents { $0.append($0[0]) }
        rejectedCurrents { $0[0]["timezone"] = "not/a/timezone" }
        for resource in jsonResources {
            let url = directory.appendingPathComponent(resource + ".json")
            let saved = try Data(contentsOf: url)
            for (key, value) in [("id", "" as Any), ("name", "  "), ("latitude", 91), ("longitude", -181)] {
                try edit(resource) { $0[0][key] = value }
                rejected(resource)
                try saved.write(to: url)
            }
            try edit(resource) { $0.append($0[0]) }
            rejected(resource)
            try saved.write(to: url)
            if resource != "chs-tombstones" {
                try edit(resource) { $0[0]["timezone"] = "not/a/timezone" }
                rejected(resource)
                try saved.write(to: url)
            }
        }
    }

    func testModelsAndReferences() throws {
        for (key, value) in [("constituents", [] as Any), ("reference", "missing")] {
            rejectedTides { rows in
                let index = rows.firstIndex { $0["reference"] == nil }!
                rows[index][key] = value
            }
        }
        for (key, value) in [("constituents", [] as Any), ("tideReference", "missing")] {
            rejectedCurrents { rows in
                let index = rows.firstIndex { $0["reference"] == nil }!
                rows[index][key] = value
            }
        }
        let mutations: [(String, String, Any)] = [
            ("chs-gates", "reference", "missing"), ("chs-current-gates", "tideReference", "missing")]
        for (resource, key, value) in mutations {
            let url = directory.appendingPathComponent(resource + ".json")
            let saved = try Data(contentsOf: url)
            try edit(resource) {
                let index = $0.firstIndex { $0["reference"] == nil } ?? 0
                $0[index][key] = value
            }
            rejected(resource)
            try saved.write(to: url)
        }
    }

    func testSubordinateCurrentCorrectionsAndReference() throws {
        for field in ["slackBeforeFloodOffset", "slackBeforeEbbOffset", "floodTimeOffset", "ebbTimeOffset", "floodSpeedRatio", "ebbSpeedRatio"] {
            rejectedCurrents { rows in
                let i = rows.firstIndex { $0["reference"] != nil }!
                rows[i].removeValue(forKey: field)
            }
        }
        for reference in ["missing", "self"] {
            rejectedCurrents { rows in
                let i = rows.firstIndex { $0["reference"] != nil }!
                rows[i]["reference"] = reference == "self" ? rows[i]["id"] : reference
            }
        }
        for ratios in [(-1.0, 1.0), (1.0, -1.0), (0.0, 0.0)] {
            rejectedCurrents { rows in
                let i = rows.firstIndex { $0["reference"] != nil }!
                rows[i]["floodSpeedRatio"] = ratios.0
                rows[i]["ebbSpeedRatio"] = ratios.1
            }
        }
    }

    /// The one check that needs the file rather than records: the record
    /// cannot tell a missing direction from due north, a missing mean flow
    /// from none, or a missing region from an empty one.
    func testCurrentMissingAFieldTheRecordDefaultsIsRefused() throws {
        let url = directory.appendingPathComponent("currents.tcdb")
        let saved = try Data(contentsOf: url)
        let clears: [(inout StationInput) -> Void] = [
            { $0.current?.floodDirection = nil }, { $0.current?.ebbDirection = nil },
            { $0.current?.meanFlow = nil }, { $0.region = nil },
            // JSON could not spell these; float32 can.
            { $0.current?.floodDirection = .nan }, { $0.current?.meanFlow = .infinity }]
        for clear in clears {
            let database = try currentDatabase(directory: directory)
            var stations = database.map(StationInput.init)
            let i = try XCTUnwrap(stations.firstIndex { $0.current?.offsets == nil })
            clear(&stations[i])
            try StationDatabase.build(stations, version: database.version).write(to: url)
            rejected("currents")
            try saved.write(to: url)
        }
    }

    func testSubordinateTideRequiresOffsetsAndHarmonicReference() throws {
        rejectedTides { rows in
            let i = rows.firstIndex { $0["reference"] != nil }!
            rows[i].removeValue(forKey: "offsets")
        }
        rejectedTides { rows in
            let i = rows.firstIndex { $0["reference"] != nil }!
            rows[i]["reference"] = rows[i]["id"]
        }
    }

    func testNonfiniteNumbersAndUnusableConstituents() throws {
        for constituents: [[String: Any]] in [
            [["name": "M2", "amplitude": -1, "phase": 0]],
            [["name": "M2", "amplitude": 0, "phase": 0]],
            [["name": "", "amplitude": 1, "phase": 0]]
        ] {
            rejectedTides { rows in
                let i = rows.firstIndex { $0["reference"] == nil }!
                rows[i]["constituents"] = constituents
            }
            rejectedCurrents { rows in
                let i = rows.firstIndex { $0["reference"] == nil }!
                rows[i]["constituents"] = constituents
            }
        }
        // JSON cannot spell infinity, but the database's float32 can, so
        // validation is what keeps it out of a correction.
        rejectedRecords("currents", file: #filePath, line: #line) {
            try snapshot(records: { records in
                let i = records.firstIndex(where: \.isSubordinate)!
                records[i].floodTimeOffset = .infinity
            })
        }
    }

    func testFixedOffsetIsNotAnIANAIdentifier() throws {
        for zone in ["GMT+0100", "UTC+0100", "GMT+0000", "UTC-0000"] {
            rejectedTides { $0[0]["timezone"] = zone }
        }
        for zone in ["UTC", "Etc/GMT+5", "US/Pacific"] {
            XCTAssertNoThrow(try snapshot(tides: { $0[0]["timezone"] = zone }))
        }
    }

    func testHistoricalTombstonesPersistUnlessStationReturns() throws {
        let active = try CatalogSnapshot(directory: directory)
        try edit("chs-tombstones") { $0.removeFirst() }
        rejected("chs-tombstones", active: active)
        let retired = try XCTUnwrap(active.tombstones.first)
        try edit("chs-stations") { rows in
            var restored = rows[0]
            restored["id"] = retired.id
            restored["name"] = retired.name
            rows.append(restored)
        }
        XCTAssertNoThrow(try CatalogSnapshot(directory: directory, active: active))
    }

    func testRenderedCollisionAndTombstonedRemoval() throws {
        let active = try CatalogSnapshot(directory: directory)
        let gate = try XCTUnwrap(active.chsGates.first)
        try edit("chs-tombstones") { $0[0]["id"] = gate.id }
        rejected("chs-tombstones")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("chs-tombstones.json"))
        try FileManager.default.copyItem(at: XCTUnwrap(Bundle.main.url(forResource: "chs-tombstones", withExtension: "json")),
                                        to: directory.appendingPathComponent("chs-tombstones.json"))
        try edit("chs-current-gates") { $0[0]["id"] = gate.id }
        rejected("chs-current-gates")
        try edit("chs-current-gates") { $0[0]["id"] = active.chsCurrents[0].id }
        // Remove a current: its rendered ID differs from its record ID.
        let references = Set(Self.currentRows.compactMap { $0["reference"] as? String })
        let index = try XCTUnwrap(Self.currentRows.firstIndex { !references.contains($0["id"] as! String) })
        let removeCurrent = { (rows: inout [[String: Any]]) in _ = rows.remove(at: index) }
        rejectedRecords("chs-tombstones", file: #filePath, line: #line) {
            try snapshot(currents: removeCurrent, active: active)
        }
        try edit("chs-tombstones") {
            var removed = Self.currentRows[index]
            removed["id"] = "current:" + (removed["id"] as! String)
            $0.append(removed)
        }
        XCTAssertNoThrow(try snapshot(currents: removeCurrent, active: active))
    }
}
