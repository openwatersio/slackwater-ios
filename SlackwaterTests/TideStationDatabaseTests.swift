import XCTest
import SlackwaterDatabase
@testable import Slackwater

/// stations.tcdb and stations.json come out of the same gen-tides run (#459).
/// Until the app reads the database, this holds the two to the same stations
/// and the same predictions. The database stores values as float32, so numbers
/// agree to float32 precision rather than exactly.
final class TideStationDatabaseTests: XCTestCase {
    private static let database: StationDatabase = {
        let url = Bundle.main.url(forResource: "stations", withExtension: "tcdb")!
        return try! StationDatabase(contentsOf: url)
    }()

    private func record(_ id: String) -> TideStationRecord? {
        Self.database.station(id: id).map(TideStationRecord.init)
    }

    func testHoldsExactlyTheBundledStations() {
        XCTAssertEqual(Set(Self.database.map(\.id)), Set(TideStationRecord.all.map(\.id)))
        XCTAssertEqual(Self.database.count, TideStationRecord.all.count)
    }

    func testRecordsMatchTheBundledJSON() {
        for json in TideStationRecord.all {
            guard let tcdb = record(json.id) else { return XCTFail("\(json.id) missing") }
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
            XCTAssertEqual(tcdb.offsets?.height.high ?? 0, json.offsets?.height.high ?? 0, accuracy: 1e-6, json.id)
            XCTAssertEqual(tcdb.offsets?.height.low ?? 0, json.offsets?.height.low ?? 0, accuracy: 1e-6, json.id)
            XCTAssertEqual(tcdb.constituents.map(\.name), json.constituents.map(\.name), json.id)
            for (t, j) in zip(tcdb.constituents, json.constituents) {
                XCTAssertEqual(t.amplitude, j.amplitude, accuracy: 1e-6, "\(json.id) \(j.name)")
                XCTAssertEqual(t.phase, j.phase, accuracy: 1e-4, "\(json.id) \(j.name)")
            }
        }
    }

    /// Every 20th station, which reaches references and both kinds of
    /// subordinate offset, over one day of extremes.
    func testPredictionsMatchTheBundledJSON() {
        let day = Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-14
        let end = day.addingTimeInterval(86_400)
        let sample = stride(from: 0, to: TideStationRecord.all.count, by: 20).map { TideStationRecord.all[$0] }
        XCTAssertTrue(sample.contains { $0.offsets?.height.type == "ratio" })
        XCTAssertTrue(sample.contains { $0.offsets?.height.type == "fixed" })
        for json in sample {
            guard let tcdb = record(json.id) else { return XCTFail("\(json.id) missing") }
            let tcdbStation = tcdb.engineStation(referenceRecord: tcdb.reference.flatMap(record))
            let expected = json.engineStation.extremes(from: day, to: end)
            let actual = tcdbStation.extremes(from: day, to: end)
            XCTAssertEqual(actual.count, expected.count, json.id)
            for (a, e) in zip(actual, expected) {
                XCTAssertEqual(a.kind, e.kind, json.id)
                XCTAssertEqual(a.height, e.height, accuracy: 1e-4, json.id)
                XCTAssertEqual(a.time.timeIntervalSince(e.time), 0, accuracy: 1, json.id)
            }
        }
    }

    func testRejectsBytesThatAreNotAStationDatabase() {
        XCTAssertThrowsError(try StationDatabase(data: Data("[{\"id\":\"noaa/9447130\"}]".utf8)))
    }
}
