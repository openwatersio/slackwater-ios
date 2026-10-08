import XCTest
import SlackwaterDatabase
@testable import Slackwater

/// stations.tcdb and stations.json come out of the same gen-tides run (#459).
/// The app reads the database; the JSON stays in the repository as the
/// reviewable record of what it holds and as input to the other generators.
/// These hold the two to the same stations and the same predictions. The
/// database stores values as float32, so numbers agree to float32 precision
/// rather than exactly.
final class TideStationDatabaseTests: XCTestCase {
    private static let json: [TideStationRecord] = {
        let url = repoRoot.appendingPathComponent("Slackwater/Resources/stations.json")
        return try! JSONDecoder().decode([TideStationRecord].self, from: Data(contentsOf: url))
    }()

    func testHoldsExactlyTheGeneratedStations() {
        XCTAssertEqual(TideStationRecord.database.map(\.id), Self.json.map(\.id).sorted())
        XCTAssertEqual(TideStationRecord.all.count, Self.json.count)
    }

    func testRecordsMatchTheGeneratedJSON() {
        for json in Self.json {
            guard let tcdb = TideStationRecord.record(id: json.id) else { return XCTFail("\(json.id) missing") }
            XCTAssertEqual(tcdb.name, json.name, json.id)
            XCTAssertEqual(tcdb.region, json.region, json.id)
            XCTAssertEqual(tcdb.aliases, json.aliases, json.id)
            XCTAssertEqual(tcdb.latitude, json.latitude, json.id)
            XCTAssertEqual(tcdb.longitude, json.longitude, json.id)
            XCTAssertEqual(tcdb.timezone, json.timezone, json.id)
            XCTAssertEqual(tcdb.chartDatum, json.chartDatum, json.id)
            XCTAssertEqual(tcdb.datumOffset, json.datumOffset, accuracy: 1e-5, json.id)
            XCTAssertEqual(tcdb.reference, json.reference, json.id)
            XCTAssertEqual(tcdb.offsets?.time, json.offsets?.time, json.id)
            XCTAssertEqual(tcdb.offsets?.height.type, json.offsets?.height.type, json.id)
            XCTAssertEqual(tcdb.offsets?.height.high, json.offsets?.height.high, json.id)
            XCTAssertEqual(tcdb.offsets?.height.low, json.offsets?.height.low, json.id)
            XCTAssertEqual(tcdb.constituents.map(\.name), json.constituents.map(\.name), json.id)
            for (t, j) in zip(tcdb.constituents, json.constituents) {
                XCTAssertEqual(t.amplitude, j.amplitude, accuracy: 1e-6, "\(json.id) \(j.name)")
                XCTAssertEqual(t.phase, j.phase, accuracy: 1e-4, "\(json.id) \(j.name)")
            }
        }
    }

    /// The astronomical floor and ceiling reach the app the same way every
    /// other field does — through the tcdb, not the JSON. gen-tides computes
    /// the pair in JavaScript for stations.json (#315); the library computes it
    /// again in Swift from the raw datums, rebasing to chart datum and reducing
    /// a subordinate through its reference. This holds the two to each other,
    /// so a divergence in either implementation fails here rather than shipping.
    func testAstronomicalBoundsMatchTheGeneratedJSON() {
        var compared = 0
        for json in Self.json {
            guard let tcdb = TideStationRecord.record(id: json.id) else { return XCTFail("\(json.id) missing") }
            if let lat = json.latDatum, let hat = json.hatDatum {
                XCTAssertEqual(tcdb.latDatum ?? .nan, lat, accuracy: 0.001, json.id)
                XCTAssertEqual(tcdb.hatDatum ?? .nan, hat, accuracy: 0.001, json.id)
                compared += 1
            } else {
                // Absence is a state, not a zero: the database withholds the
                // pair where Sa and Ssa are both zero amplitude.
                XCTAssertNil(tcdb.latDatum, json.id)
            }
        }
        XCTAssertGreaterThan(compared, 4_700, "#315 ships bounds on 4,772 of 4,782")
    }

    /// The tide footer names the publisher from this field.
    func testRecordsCarryTheirPublisher() {
        XCTAssertEqual(TideStationRecord.record(id: "kartverket/ANX")?.source,
                       "Kartverket / Norwegian Mapping Authority, Hydrographic Service")
        XCTAssertEqual(TideStationRecord.record(id: Self.json.first { $0.id.hasPrefix("ticon/") }!.id)?.source, "TICON-4")
    }

    /// A subordinate predicts through its reference and carries no datums of
    /// its own in the tcdb, so bounds can only reach it if the reader resolves
    /// the reference and reduces by the offsets. All 2,016 of them have bounds.
    func testSubordinatesCarryReducedBounds() {
        let subordinates = Self.json.filter { $0.reference != nil }
        XCTAssertGreaterThan(subordinates.count, 2_000)
        for json in subordinates.prefix(50) {
            guard let tcdb = TideStationRecord.record(id: json.id) else { return XCTFail("\(json.id) missing") }
            XCTAssertEqual(tcdb.latDatum ?? .nan, json.latDatum ?? .nan, accuracy: 0.001, json.id)
        }
    }

    /// Every 20th station, which reaches references and both kinds of
    /// subordinate offset, over one day of extremes.
    func testPredictionsMatchTheGeneratedJSON() {
        let byID = Dictionary(uniqueKeysWithValues: Self.json.map { ($0.id, $0) })
        let day = Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-14
        let end = day.addingTimeInterval(86_400)
        let sample = stride(from: 0, to: Self.json.count, by: 20).map { Self.json[$0] }
        XCTAssertTrue(sample.contains { $0.offsets?.height.type == "ratio" })
        XCTAssertTrue(sample.contains { $0.offsets?.height.type == "fixed" })
        for json in sample {
            guard let tcdb = TideStationRecord.record(id: json.id) else { return XCTFail("\(json.id) missing") }
            let expected = json.engineStation(referenceRecord: json.reference.flatMap { byID[$0] })
                .extremes(from: day, to: end)
            let actual = tcdb.engineStation.extremes(from: day, to: end)
            XCTAssertEqual(actual.count, expected.count, json.id)
            for (a, e) in zip(actual, expected) {
                XCTAssertEqual(a.kind, e.kind, json.id)
                XCTAssertEqual(a.height, e.height, accuracy: 1e-4, json.id)
                XCTAssertEqual(a.time.timeIntervalSince(e.time), 0, accuracy: 1, json.id)
            }
        }
    }

    func testLooksUpOneStationInADirectory() throws {
        let bundle = try XCTUnwrap(Bundle.main.resourceURL)
        XCTAssertEqual(try tideRecord(id: TideStationRecord.fridayHarborID, directory: bundle)?.id,
                       TideStationRecord.fridayHarborID)
        XCTAssertNil(try tideRecord(id: "noaa/missing", directory: bundle))
    }

    func testRejectsBytesThatAreNotAStationDatabase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try tideDatabase(directory: directory)) {
            XCTAssertEqual(($0 as? CatalogError)?.stage, .lookup)
        }
        try Data("[{\"id\":\"noaa/9447130\"}]".utf8).write(to: directory.appendingPathComponent("stations.tcdb"))
        XCTAssertThrowsError(try tideDatabase(directory: directory)) {
            XCTAssertEqual(($0 as? CatalogError)?.stage, .decode)
        }
    }
}
