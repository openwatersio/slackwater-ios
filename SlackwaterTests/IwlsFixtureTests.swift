import XCTest
import TideEngine
@testable import Slackwater

final class IwlsFixtureTests: XCTestCase {
    struct Recording: Decodable {
        struct Station: Decodable {
            struct Metadata: Decodable { let floodDirection: Double?; let ebbDirection: Double? }
            let key: String
            let metadata: Metadata?
            let series: [String: [IwlsSample]]
        }
        let stations: [Station]
    }

    private func recording() throws -> Recording {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "iwls-recording", withExtension: "json") else {
            XCTFail("IWLS fixture missing; run: node scripts/iwls-fixtures.mjs prepare")
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Recording.self, from: Data(contentsOf: url))
    }

    private func samples(_ station: Recording.Station, _ code: String) throws -> [ChsSample] {
        try IwlsFetcher.decode(JSONEncoder().encode(try XCTUnwrap(station.series[code], "\(station.key): missing \(code)")))
    }

    func testDecoderRejectsMalformedJSONAndDropsBadDatesAndDuplicateTimestamps() throws {
        XCTAssertThrowsError(try IwlsFetcher.decode(Data("{}".utf8)))
        let data = Data("""
        [{"eventDate":"2026-01-01T00:00:00Z","value":1},
         {"eventDate":"bad","value":2},
         {"eventDate":"2026-01-01T00:00:00Z","value":3}]
        """.utf8)
        XCTAssertEqual(try IwlsFetcher.decode(data), [ChsSample(t: 1_767_225_600_000, v: 1)])
    }

    func testRecordedResponsesDecodeAndProjectWithoutChunkCache() throws {
        let fixture = try recording()
        XCTAssertEqual(Set(fixture.stations.map(\.key)), ["victoria", "active", "dodd", "sechelt"])
        for station in fixture.stations where station.key != "victoria" {
            let speeds = try samples(station, "wcsp1")
            let directions = try samples(station, "wcdp1")
            let projected = ChsFitService.project(speeds: speeds, dirs: directions,
                                                  floodDirection: try XCTUnwrap(station.metadata?.floodDirection))
            XCTAssertEqual(projected.count, speeds.count, station.key)
            XCTAssert(projected.allSatisfy { $0.v.isFinite }, station.key)
            XCTAssertGreaterThan(projected.map { abs($0.v) }.max() ?? 0, 0.5, station.key)
        }

        let victoria = try XCTUnwrap(fixture.stations.first { $0.key == "victoria" })
        let decoded = try samples(victoria, "wlp")
        XCTAssert(decoded.contains { $0.t.truncatingRemainder(dividingBy: 900_000) != 0 },
                  "the raw recording must retain one native off-grid wlp sample")
        XCTAssertGreaterThan(decoded.filter { $0.t.truncatingRemainder(dividingBy: 900_000) == 0 }.count, 5_000)
    }

    func testRealFitterPredictsHeldOutVictoriaSamples() async throws {
        let fixture = try recording()
        let victoria = try XCTUnwrap(fixture.stations.first { $0.key == "victoria" })
        let all = try samples(victoria, "wlp").filter { $0.t.truncatingRemainder(dividingBy: 900_000) == 0 }
        let split = all.count * 5 / 6
        let fit = try await ChsFitter().fit(samples: Array(all[..<split]))
        XCTAssertGreaterThanOrEqual(fit.constituents.count, 20)
        XCTAssertLessThan(fit.rms, 0.15)

        let engine = Station(constituents: fit.constituents.map {
            HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase)
        }, offset: fit.offset)
        let held = Array(all[split...])
        let heldStart = try XCTUnwrap(held.first)
        let heldEnd = try XCTUnwrap(held.last)
        let predicted = engine.heights(from: Date(timeIntervalSince1970: heldStart.t / 1000),
                                       to: Date(timeIntervalSince1970: heldEnd.t / 1000), step: 900)
        let byTime = Dictionary(predicted.map { ($0.time.timeIntervalSince1970 * 1000, $0.height) },
                                uniquingKeysWith: { first, _ in first })
        let errors = held.compactMap { sample in byTime[sample.t].map { $0 - sample.v } }
        XCTAssertGreaterThan(errors.count, 800)
        XCTAssertLessThan((errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count)).squareRoot(), 0.2)
    }

    func testRealFitterComparesDoddProvisionalAndFullFitsOnHoldout() async throws {
        let fixture = try recording()
        let dodd = try XCTUnwrap(fixture.stations.first { $0.key == "dodd" })
        let flood = try XCTUnwrap(dodd.metadata?.floodDirection)
        let ebb = try XCTUnwrap(dodd.metadata?.ebbDirection)
        let projected = ChsFitService.project(speeds: try samples(dodd, "wcsp1"),
                                              dirs: try samples(dodd, "wcdp1"),
                                              floodDirection: flood)
        XCTAssertGreaterThan(projected.count, 20_000)
        let holdoutStart = try XCTUnwrap(projected.last).t - 7 * 86_400_000
        let training = projected.filter { $0.t < holdoutStart }
        let provisionalStart = holdoutStart - 60 * 86_400_000
        let provisional = try await ChsFitter().fit(samples: training.filter { $0.t >= provisionalStart })
        let full = try await ChsFitter().fit(samples: training)
        XCTAssertGreaterThanOrEqual(provisional.constituents.count, 20)
        XCTAssertGreaterThanOrEqual(full.constituents.count, 20)

        func holdoutRMSE(_ fit: ChsFitResult) throws -> Double {
            let engine = CurrentStation(constituents: fit.constituents.map {
                HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase)
            }, floodDirection: flood, ebbDirection: ebb, offset: fit.offset)
            let held = projected.filter { $0.t >= holdoutStart }
            let heldStart = try XCTUnwrap(held.first)
            let heldEnd = try XCTUnwrap(held.last)
            let predicted = engine.speeds(from: Date(timeIntervalSince1970: heldStart.t / 1000),
                                          to: Date(timeIntervalSince1970: heldEnd.t / 1000), step: 900)
            let byTime = Dictionary(predicted.map { ($0.time.timeIntervalSince1970 * 1000, $0.speed) },
                                    uniquingKeysWith: { first, _ in first })
            let errors = held.compactMap { sample in byTime[sample.t].map { $0 - sample.v } }
            XCTAssertGreaterThan(errors.count, 600)
            return (errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count)).squareRoot()
        }
        let provisionalRMSE = try holdoutRMSE(provisional)
        let fullRMSE = try holdoutRMSE(full)
        XCTAssertLessThan(provisionalRMSE, 0.75)
        XCTAssertLessThan(fullRMSE, 0.75)
        XCTAssertNotEqual(provisionalRMSE, fullRMSE, accuracy: 0.000_001)
    }
}
