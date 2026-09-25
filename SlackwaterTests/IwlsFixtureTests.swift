import XCTest
import SlackwaterKit
@testable import Slackwater

final class IwlsFixtureTests: XCTestCase {
    func testAnExhaustedRateLimitRemainsRetryableByTheQueue() {
        XCTAssertFalse(ChsError.isPermanent(IwlsFetcher.terminalError(status: 429)))
        XCTAssert(ChsError.isPermanent(IwlsFetcher.terminalError(status: 404)))
        XCTAssertFalse(ChsError.isPermanent(IwlsFetcher.terminalError(status: 503)))
    }

    func testThePacerSerialisesAcrossFetchers() async {
        let pacer = IwlsPacer(interval: 0.1)
        let start = Date.now
        async let first: Void? = try? pacer.wait()
        async let second: Void? = try? pacer.wait()
        async let third: Void? = try? pacer.wait()
        _ = await (first, second, third)
        XCTAssertGreaterThanOrEqual(Date.now.timeIntervalSince(start), 0.2)
    }

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

    private func golden(_ key: String, resource: String = "chs-fit-parity") throws -> ChsFitResult {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: resource, withExtension: "json"))
        let golden = try JSONDecoder().decode([String: ChsFitResult].self, from: Data(contentsOf: url))
        return try XCTUnwrap(golden[key])
    }

    private func assertGolden(_ fit: ChsFitResult, _ key: String,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = try golden(key)
        XCTAssertEqual(fit.offset, expected.offset, accuracy: 1e-7, file: file, line: line)
        XCTAssertEqual(fit.rms, expected.rms, accuracy: 1e-7, file: file, line: line)
        XCTAssertEqual(fit.constituents.map(\.name), expected.constituents.map(\.name), file: file, line: line)
        for (actual, want) in zip(fit.constituents, expected.constituents) {
            XCTAssertEqual(actual.amplitude, want.amplitude, accuracy: 1e-6, file: file, line: line)
            let delta = abs(actual.phase - want.phase).truncatingRemainder(dividingBy: 360)
            XCTAssertLessThan(min(delta, 360 - delta), 1e-3, file: file, line: line)
        }
    }

    func testInvalidFitIsPermanent() async {
        do {
            _ = try await ChsFitter().fit(samples: [])
            XCTFail("empty samples must fail")
        } catch {
            XCTAssertTrue(ChsError.isPermanent(error))
        }
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

    /// A dropped link is worth another try; a server refusing this request, or
    /// a portal demanding a login, is not.
    func testRetriesOnlyWhatAnotherAttemptCouldGetPast() {
        func delay(_ outcome: Result<Int, Error>) -> Double? {
            IwlsFetcher.retryDelay(after: outcome, attempt: 1)
        }
        XCTAssertEqual(delay(.failure(URLError(.timedOut))), 2)
        XCTAssertEqual(delay(.failure(URLError(.networkConnectionLost))), 2)
        // The app suspended mid-chunk: ECONNABORTED/ECONNRESET arrive as bare
        // POSIX errors, which `error as? URLError` never matched.
        XCTAssertEqual(delay(.failure(NSError(domain: NSPOSIXErrorDomain, code: 53))), 2)
        XCTAssertEqual(delay(.failure(NSError(domain: NSPOSIXErrorDomain, code: 54))), 2)
        XCTAssertEqual(delay(.success(500)), 2)
        XCTAssertEqual(delay(.success(503)), 2)
        // A captive portal, a refused request shape, and a cancel: identical
        // answer next time, so the app should say so now.
        XCTAssertNil(delay(.success(511)))
        XCTAssertNil(delay(.success(501)))
        XCTAssertNil(delay(.success(400)))
        XCTAssertNil(delay(.success(404)))
        XCTAssertNil(delay(.failure(URLError(.cancelled))))
        XCTAssertNil(delay(.failure(URLError(.secureConnectionFailed))))
        XCTAssertNil(delay(.failure(URLError(.dataNotAllowed))))
        XCTAssertNil(delay(.failure(CancellationError())))
    }

    /// The backoff doubles, stops after `maxAttempts`, and never retries a rate
    /// limit inside the minute-long window that just rejected it.
    func testBackoffDoublesStopsAndWaitsOutARateLimitWindow() {
        let dropped = Result<Int, Error>.failure(URLError(.timedOut))
        XCTAssertEqual(IwlsFetcher.retryDelay(after: dropped, attempt: 1), 2)
        XCTAssertEqual(IwlsFetcher.retryDelay(after: dropped, attempt: 2), 4)
        XCTAssertEqual(IwlsFetcher.retryDelay(after: dropped, attempt: 3), 8)
        XCTAssertNil(IwlsFetcher.retryDelay(after: dropped, attempt: IwlsFetcher.maxAttempts),
                     "the last attempt is the last word")
        // 2/4/8 s all land inside IWLS's 30-per-minute window, and each retry
        // spends another slot in it.
        XCTAssertEqual(IwlsFetcher.retryDelay(after: .success(429), attempt: 1), 60)
        XCTAssertEqual(IwlsFetcher.retryDelay(after: .success(429), attempt: 1, retryAfter: 90), 90)
        XCTAssertEqual(IwlsFetcher.retryDelay(after: .success(503), attempt: 1, retryAfter: 30), 30,
                       "the server's own ask outranks our backoff")
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
        try assertGolden(fit, "victoria")
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
        let rmse = (errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count)).squareRoot()
        XCTAssertLessThan(rmse, 0.2)
        let legacy = try golden("victoria", resource: "chs-fit-golden")
        let legacyEngine = Station(constituents: legacy.constituents.map {
            HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase)
        }, offset: legacy.offset)
        let legacyPredicted = legacyEngine.heights(from: Date(timeIntervalSince1970: heldStart.t / 1000),
                                                   to: Date(timeIntervalSince1970: heldEnd.t / 1000), step: 900)
        let legacyByTime = Dictionary(legacyPredicted.map { ($0.time.timeIntervalSince1970 * 1000, $0.height) },
                                      uniquingKeysWith: { first, _ in first })
        let legacyErrors = held.compactMap { sample in legacyByTime[sample.t].map { $0 - sample.v } }
        XCTAssertEqual(legacyErrors.count, errors.count)
        let legacyRMSE = (legacyErrors.reduce(0) { $0 + $1 * $1 } / Double(legacyErrors.count)).squareRoot()
        XCTAssertLessThanOrEqual(rmse, legacyRMSE + 0.001)
        print("Victoria holdout RMSE: per-sample \(rmse), CHS \(legacyRMSE); fit \(fit.fitMs) ms")
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
        try assertGolden(provisional, "dodd60")
        try assertGolden(full, "doddFull")
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
        let legacyProvisional = try holdoutRMSE(golden("dodd60", resource: "chs-fit-golden"))
        let legacyFull = try holdoutRMSE(golden("doddFull", resource: "chs-fit-golden"))
        XCTAssertLessThanOrEqual(provisionalRMSE, legacyProvisional + 0.001)
        XCTAssertLessThanOrEqual(fullRMSE, legacyFull + 0.001)
        print("Dodd holdout RMSE: per-sample \(provisionalRMSE)/\(fullRMSE), CHS \(legacyProvisional)/\(legacyFull); fit \(provisional.fitMs)/\(full.fitMs) ms")
    }
}
