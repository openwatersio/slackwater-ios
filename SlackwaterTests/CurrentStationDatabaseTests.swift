import XCTest
import SlackwaterDatabase
@testable import Slackwater

/// currents.tcdb and currents.json come out of the same gen-noaa-currents run
/// (#902). The app reads the database; the JSON stays in the repository as
/// the reviewable record of what it holds and as input to the other
/// generators. The reader rounds the database's float32 values back to the
/// generator's three places, so the records are equal exactly.
final class CurrentStationDatabaseTests: XCTestCase {
    private static let json: [CurrentStationRecord] = {
        let url = repoRoot.appendingPathComponent("Slackwater/Resources/currents.json")
        return try! JSONDecoder().decode([CurrentStationRecord].self, from: Data(contentsOf: url))
    }()

    func testHoldsExactlyTheGeneratedStations() {
        XCTAssertEqual(CurrentStationRecord.database.map(\.id), Self.json.map(\.id).sorted())
        XCTAssertEqual(CurrentStationRecord.all.count, Self.json.count)
    }

    func testRecordsMatchTheGeneratedJSON() {
        for json in Self.json {
            XCTAssertEqual(CurrentStationRecord.record(id: json.id), json, json.id)
        }
    }

    /// Each shape the reader has to rebuild: a two-axis harmonic, a
    /// subordinate, a reference-only bin, and a paired and an unpaired gate.
    func testCoversEveryRecordShape() {
        XCTAssertTrue(Self.json.contains { $0.minorConstituents != nil })
        XCTAssertTrue(Self.json.contains { $0.isSubordinate })
        XCTAssertTrue(Self.json.contains { $0.referenceOnly == true })
        XCTAssertTrue(Self.json.contains { $0.tideReference != nil })
        XCTAssertTrue(Self.json.contains { $0.tideReference == nil && $0.referenceOnly != true })
    }

    /// Every 20th station, which reaches harmonic, two-axis and subordinate
    /// stations, over one day of speeds and events.
    func testPredictionsMatchTheGeneratedJSON() {
        let byID = Dictionary(uniqueKeysWithValues: Self.json.map { ($0.id, $0) })
        let day = Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-14
        let end = day.addingTimeInterval(86_400)
        let sample = stride(from: 0, to: Self.json.count, by: 20).map { Self.json[$0] }
        XCTAssertTrue(sample.contains { $0.isSubordinate })
        XCTAssertTrue(sample.contains { $0.minorConstituents != nil })
        for json in sample {
            guard let tcdb = CurrentStationRecord.record(id: json.id) else { return XCTFail("\(json.id) missing") }
            let expected = json.engineStation(referenceRecord: json.reference.flatMap { byID[$0] })
            let actual = tcdb.engineStation
            let events = { (s: any CurrentPredicting) in
                s.events(from: day, to: end).map { "\($0.kind) \($0.time.timeIntervalSince1970) \($0.speed)" }
            }
            XCTAssertEqual(events(actual), events(expected), json.id)
            XCTAssertEqual(actual.speeds(from: day, to: end, step: 600).map(\.speed),
                           expected.speeds(from: day, to: end, step: 600).map(\.speed), json.id)
        }
    }

    func testLooksUpOneStationInADirectory() throws {
        let bundle = try XCTUnwrap(Bundle.main.resourceURL)
        let id = try XCTUnwrap(Self.json.first?.id)
        XCTAssertEqual(try currentRecord(id: id, directory: bundle)?.id, id)
        XCTAssertNil(try currentRecord(id: "noaa/missing", directory: bundle))
    }

    func testRejectsBytesThatAreNotAStationDatabase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try currentDatabase(directory: directory)) {
            XCTAssertEqual(($0 as? CatalogError)?.stage, .lookup)
            XCTAssertEqual(($0 as? CatalogError)?.resource, "currents")
        }
        try Data("[{\"id\":\"noaa/PUG1515\"}]".utf8).write(to: directory.appendingPathComponent("currents.tcdb"))
        XCTAssertThrowsError(try currentDatabase(directory: directory)) {
            XCTAssertEqual(($0 as? CatalogError)?.stage, .decode)
        }
    }
}
