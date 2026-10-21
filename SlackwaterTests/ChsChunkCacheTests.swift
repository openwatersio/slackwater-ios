import XCTest
import SlackwaterIWLS
@testable import Slackwater

final class ChsChunkCacheTests: XCTestCase {
    private let chunk = ChsChunk(start: .init(timeIntervalSince1970: 0), end: .init(timeIntervalSince1970: 604800))
    private let samples = [ChsSample(t: 0, v: 1), ChsSample(t: 604800000, v: 2)]

    func testConfiguredClientResumesCachedChunksOffline() async throws {
        let id = "cache-test-\(UUID().uuidString)"
        defer { IwlsFetcher.chunkCache.purge(id, includingEmpty: true) }
        _ = try await IwlsFetcher.chunkCache.samples("wlp", stationID: id, chunk: chunk) { [samples] in samples }
        let result = try await IwlsFetcher(killSwitch: true).wlp(stationID: id, chunk: chunk)
        XCTAssertEqual(result, samples)
    }

    func testEmptyWeekSurvivesFitCleanupAndResumesOffline() async throws {
        let id = "cache-test-\(UUID().uuidString)"
        defer { IwlsFetcher.chunkCache.purge(id, includingEmpty: true) }
        _ = try await IwlsFetcher.chunkCache.samples("wlp", stationID: id, chunk: chunk) { [] }
        IwlsFetcher.chunkCache.purge(id)
        let result = try await IwlsFetcher(killSwitch: true).wlp(stationID: id, chunk: chunk)
        XCTAssertEqual(result, [])
    }

    func testOnlineRequestsBypassEmptyWeeksAndReusePositiveWeeks() async throws {
        let id = "cache-test-\(UUID().uuidString)"
        defer { IwlsFetcher.chunkCache.purge(id, includingEmpty: true) }
        _ = try await IwlsFetcher.chunkCache.samples("wcsp1", stationID: id, chunk: chunk) { [] }
        let fetcher = IwlsFetcher(killSwitch: true)
        do {
            _ = try await fetcher.series("wcsp1", stationID: id, chunk: chunk, cacheEmpty: false)
            XCTFail("an online retry must reach the network after an empty week")
        } catch ChsError.networkDisabled {} catch { XCTFail("unexpected error: \(error)") }
        _ = try await IwlsFetcher.chunkCache.samples("wcsp1", stationID: id, chunk: chunk,
                                                  cacheEmpty: false) { [samples] in samples }
        let result = try await fetcher.series("wcsp1", stationID: id, chunk: chunk, cacheEmpty: false)
        XCTAssertEqual(result, samples)
    }
}
