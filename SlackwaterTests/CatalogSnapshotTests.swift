import XCTest
@testable import Slackwater

final class CatalogSnapshotTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for resource in CatalogSnapshot.resources {
            let file = CatalogSnapshot.fileName(resource)
            try FileManager.default.copyItem(
                at: XCTUnwrap(Bundle.main.url(forResource: file, withExtension: nil)),
                to: directory.appendingPathComponent(file))
        }
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    private func edit(_ resource: String, _ change: (inout [[String: Any]]) -> Void) throws {
        let url = directory.appendingPathComponent(resource + ".json")
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        change(&rows)
        // Preserve the NOAA generator's compact, id-first record format while
        // mutating values; formatting failures have their own test below.
        let records = try rows.map { row -> String in
            var rest = row
            let id = rest.removeValue(forKey: "id")!
            let idJSON = try JSONSerialization.data(withJSONObject: id, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            let fieldsJSON = try JSONSerialization.data(withJSONObject: rest)
            return "{\"id\":" + String(decoding: idJSON, as: UTF8.self) + ","
                + String(decoding: fieldsJSON.dropFirst(), as: UTF8.self)
        }
        try Data(("[" + records.joined(separator: ",") + "]").utf8).write(to: url)
    }

    /// The JSON catalogs; tide stations are a binary database, edited below
    /// as decoded records instead.
    private let jsonResources = CatalogSnapshot.resources.filter { $0 != "stations" }

    /// The bundled tide records as JSON rows, encoded once. Validation reads
    /// records, so a change to a row reaches it exactly as a bad file would.
    private static let tideRows: [[String: Any]] = {
        let data = try! JSONEncoder().encode(TideStationRecord.all)
        return try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    }()

    private func snapshot(tides change: (inout [[String: Any]]) -> Void) throws -> CatalogSnapshot {
        var rows = Self.tideRows
        change(&rows)
        let tides = try JSONDecoder().decode(
            [TideStationRecord].self, from: JSONSerialization.data(withJSONObject: rows))
        return try CatalogSnapshot(tides: tides, directory: directory)
    }

    private func rejectedTides(file: StaticString = #filePath, line: UInt = #line,
                               _ change: (inout [[String: Any]]) -> Void) {
        XCTAssertThrowsError(try snapshot(tides: change), file: file, line: line) {
            guard let error = $0 as? CatalogError else { return XCTFail("Unexpected error: \($0)", file: file, line: line) }
            XCTAssertEqual(error.resource, "stations", file: file, line: line)
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

    func testRequiredCatalogNeverConvertsFailureToEmpty() throws {
        let missing = directory.appendingPathComponent("missing", isDirectory: true)
        XCTAssertThrowsError(
            try requiredCatalog("currents", directory: missing) as [CurrentStationRecord]
        ) { error in
            let catalog = error as? CatalogError
            XCTAssertEqual(catalog?.resource, "currents")
            XCTAssertEqual(catalog?.stage, .lookup)
        }
    }

    func testEveryCatalogMustRemainNonempty() throws {
        rejectedTides { $0 = [] }
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
        let mutations: [(String, String, Any)] = [
            ("currents", "constituents", []), ("currents", "tideReference", "missing"),
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
        let url = directory.appendingPathComponent("currents.json")
        let saved = try Data(contentsOf: url)
        for field in ["slackBeforeFloodOffset", "slackBeforeEbbOffset", "floodTimeOffset", "ebbTimeOffset", "floodSpeedRatio", "ebbSpeedRatio"] {
            try edit("currents") { rows in
                let i = rows.firstIndex { $0["reference"] != nil }!
                rows[i].removeValue(forKey: field)
            }
            rejected("currents")
            try saved.write(to: url)
        }
        for reference in ["missing", "self"] {
            try edit("currents") { rows in
                let i = rows.firstIndex { $0["reference"] != nil }!
                rows[i]["reference"] = reference == "self" ? rows[i]["id"] : reference
            }
            rejected("currents")
            try saved.write(to: url)
        }
        for ratios in [(-1.0, 1.0), (1.0, -1.0), (0.0, 0.0)] {
            try edit("currents") { rows in
                let i = rows.firstIndex { $0["reference"] != nil }!
                rows[i]["floodSpeedRatio"] = ratios.0
                rows[i]["ebbSpeedRatio"] = ratios.1
            }
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
        let url = directory.appendingPathComponent("currents.json")
        let saved = try Data(contentsOf: url)
        for constituents: [[String: Any]] in [
            [["name": "M2", "amplitude": -1, "phase": 0]],
            [["name": "M2", "amplitude": 0, "phase": 0]],
            [["name": "", "amplitude": 1, "phase": 0]]
        ] {
            rejectedTides { rows in
                let i = rows.firstIndex { $0["reference"] == nil }!
                rows[i]["constituents"] = constituents
            }
            try edit("currents") { rows in
                let i = rows.firstIndex { $0["reference"] == nil }!
                rows[i]["constituents"] = constituents
            }
            rejected("currents")
            try saved.write(to: url)
        }
        // JSONDecoder rejects overflowing numbers before validation; never accept
        // infinity as a correction even though it has JSON-number syntax.
        let json = try String(contentsOf: url, encoding: .utf8)
        let bad = json.replacingOccurrences(of: #""floodTimeOffset":-?[0-9]+"#,
                                           with: #""floodTimeOffset":1e999"#, options: .regularExpression)
        XCTAssertNotEqual(bad, json)
        try Data(bad.utf8).write(to: url)
        rejected("currents", stage: .decode)
    }

    func testFixedOffsetIsNotAnIANAIdentifier() throws {
        for zone in ["GMT+0100", "UTC+0100", "GMT+0000", "UTC-0000"] {
            rejectedTides { $0[0]["timezone"] = zone }
        }
        for zone in ["UTC", "Etc/GMT+5", "US/Pacific"] {
            XCTAssertNoThrow(try snapshot { $0[0]["timezone"] = zone })
        }
    }

    func testNOAACatalogRequiresWidgetFormat() throws {
        let url = directory.appendingPathComponent("currents.json")
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        try JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted).write(to: url)
        rejected("currents")
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
        var removed: [String: Any] = [:]
        // Remove a current: its rendered ID differs from its record ID.
        try edit("currents") { rows in
            let references = Set(rows.compactMap { $0["reference"] as? String })
            let i = rows.firstIndex { !references.contains($0["id"] as! String) }!
            removed = rows.remove(at: i)
        }
        try edit("chs-current-gates") { $0[0]["id"] = active.chsCurrents[0].id }
        rejected("chs-tombstones", active: active)
        try edit("chs-tombstones") {
            removed["id"] = "current:" + (removed["id"] as! String)
            $0.append(removed)
        }
        XCTAssertNoThrow(try CatalogSnapshot(directory: directory, active: active))
    }
}
