import XCTest
import SlackwaterDatabase
import SlackwaterKit
@testable import Slackwater

/// currents.tcdb and currents.json come out of the same gen-noaa-currents run
/// (#902). The app reads the database; the JSON stays in the repository as
/// the reviewable record of what it holds and as input to the other
/// generators. The reader rounds the database's float32 values back to the
/// generator's three places, so the fields common to both formats match exactly.
final class CurrentStationDatabaseTests: XCTestCase {
    private static let json: [CurrentStationRecord] = {
        let url = repoRoot.appendingPathComponent("Slackwater/Resources/currents.json")
        return try! JSONDecoder().decode([CurrentStationRecord].self, from: Data(contentsOf: url))
    }()

    func testHoldsExactlyTheGeneratedStations() {
        XCTAssertEqual(CurrentStationRecord.database.map(\.id), Self.json.map(\.id).sorted())
        XCTAssertEqual(CurrentStationRecord.all.count, Self.json.count)
    }

    func testEveryBundledRecordBuildsAPredictor() {
        let records = CurrentStationRecord.all
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for record in records {
            let reference = record.reference.flatMap { byID[$0] }
            if let id = record.reference {
                XCTAssertNotNil(reference, "\(record.id) missing reference \(id)")
            }
            XCTAssertNoThrow(try record.checkedEngineStation(referenceRecord: reference), record.id)
        }
    }

    func testRecordsMatchTheGeneratedJSON() {
        for var json in Self.json {
            let tcdb = CurrentStationRecord.record(id: json.id)
            json.predictionModel = tcdb?.predictionModel
            XCTAssertEqual(tcdb, json, json.id)
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
        for var json in sample {
            guard let tcdb = CurrentStationRecord.record(id: json.id) else { return XCTFail("\(json.id) missing") }
            json.predictionModel = tcdb.predictionModel
            var reference = json.reference.flatMap { byID[$0] }
            reference?.predictionModel = tcdb.referenceRecord?.predictionModel
            let expected = json.engineStation(referenceRecord: reference)
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

    func testCurrentPredictsBothAxesWithSchuremanAndSourceDefinitions() throws {
        let major = SlackwaterDatabase.Station.Constituent(name: "O1", amplitude: 1, phase: 0)
        let minor = SlackwaterDatabase.Station.Constituent(name: "FixtureK1", amplitude: 0.5, phase: 90)
        let shared = SlackwaterDatabase.Station.ConstituentDefinition(
            name: "O1", speed: 13.9430356, coefficients: [1, -1, 0, 0, 0, 0, 1])
        let sourceDefinition = SlackwaterDatabase.Station.ConstituentDefinition(
            name: "K1", speed: 15.0410686, coefficients: [1, 1, 0, 0, 0, 0, -1], aliases: [minor.name])
        let source = StationSource(name: "Schureman", id: "schureman", url: nil, publishedHarmonics: true,
                                   constituentDefinitions: [sourceDefinition], nodeCorrections: .schureman)
        let license = StationLicense(type: "public domain", url: nil, commercialUse: true)
        let input = StationInput(id: "test/current", name: "Current", latitude: 47, longitude: -123,
                                 timezone: "America/Los_Angeles", country: "United States", countryCode: "US",
                                 continent: "North America", source: source, license: license, constituents: [major],
                                 current: .init(floodDirection: 0, ebbDirection: 180, minorConstituents: [minor], azimuth: 0))
        let database = try StationDatabase(data: StationDatabase.build(
            [input], credits: ["Schureman": nil], constituentDefinitions: [shared]))
        let record = CurrentStationRecord(try XCTUnwrap(database.station(id: input.id)))
        let actual = try record.checkedEngineStation(referenceRecord: nil)

        let expected = try CurrentStation(
            constituents: [.init(name: major.name, amplitude: major.amplitude, phase: major.phase)],
            floodDirection: 0, ebbDirection: 180,
            minorConstituents: [.init(name: "K1", amplitude: minor.amplitude, phase: minor.phase)],
            azimuth: 0, nodeCorrections: .schureman)
        let day = Date(timeIntervalSince1970: 1_784_000_000)
        let end = day.addingTimeInterval(86_400)
        let actualPoints = actual.speeds(from: day, to: end, step: 600)
        let expectedPoints = expected.speeds(from: day, to: end, step: 600)
        XCTAssertTrue(actualPoints.contains { $0.magnitude > abs($0.speed) })
        XCTAssertEqual(actualPoints.map(\.speed), expectedPoints.map(\.speed))
        XCTAssertEqual(actualPoints.map(\.magnitude), expectedPoints.map(\.magnitude))
        XCTAssertEqual(actualPoints.map(\.direction), expectedPoints.map(\.direction))
        // The TypeScript Schureman predictor for these harmonics at 03:30 UTC.
        let first = try XCTUnwrap(actualPoints.first)
        XCTAssertEqual(first.speed, -0.9168442612697614, accuracy: 1e-6)
        XCTAssertEqual(first.magnitude, 1.0639310556448098, accuracy: 1e-6)
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
