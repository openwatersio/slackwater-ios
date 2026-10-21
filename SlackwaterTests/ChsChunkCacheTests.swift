import XCTest
import SlackwaterIWLS
@testable import Slackwater

final class ChsChunkCacheTests: XCTestCase {
    private let chunk = ChsChunk(start: .init(timeIntervalSince1970: 0), end: .init(timeIntervalSince1970: 604800))
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let samples = [ChsSample(t: 0, v: 1), ChsSample(t: 604800000, v: 2)]

    private func station() -> String { "cache-test-\(UUID().uuidString)" }

    private func cleanup(_ id: String) {
        ChsChunkStore.purge(id)
        try? FileManager.default.removeItem(at: ChsChunkStore.emptyURL(id, "wlp", chunk))
    }

    func testEnvelopeRoundTripsWithUnixMilliseconds() throws {
        let id = station()
        defer { cleanup(id) }
        ChsChunkStore.save(samples, id, "wlp", chunk, fetchedAt: now)
        XCTAssertEqual(ChsChunkStore.load(id, "wlp", chunk, now: now), samples)
        let data = try Data(contentsOf: ChsChunkStore.url(id, "wlp", chunk))
        let entry = try JSONDecoder().decode(IwlsChunkCacheEntry.self, from: data)
        XCTAssertEqual(entry.fetchedAtMs, now.timeIntervalSince1970 * 1000)
    }

    func testEmptyWeekExpiresAt24HoursAndRejectsClockReversal() throws {
        let id = station()
        defer { cleanup(id) }
        ChsChunkStore.save([], id, "wlp", chunk, fetchedAt: now)
        XCTAssertEqual(ChsChunkStore.load(id, "wlp", chunk, now: now), [])
        XCTAssertEqual(ChsChunkStore.load(id, "wlp", chunk, now: now.addingTimeInterval(86399.999)), [])
        XCTAssertNil(ChsChunkStore.load(id, "wlp", chunk, now: now.addingTimeInterval(86400)))
        ChsChunkStore.save([], id, "wlp", chunk, fetchedAt: now)
        XCTAssertNil(ChsChunkStore.load(id, "wlp", chunk, now: now.addingTimeInterval(-1)))
    }

    func testEmptyWeekSurvivesPositivePurgeAndCanResumeOffline() async throws {
        let id = station()
        defer { cleanup(id) }
        ChsChunkStore.save([], id, "wlp", chunk)
        ChsChunkStore.purge(id)
        let fetcher = IwlsFetcher(killSwitch: true)
        let result = try await fetcher.wlp(stationID: id, chunk: chunk)
        XCTAssertEqual(result, [])
    }

    func testTruncatedAndPartialResponsesNeverCreateAnEntry() {
        let id = station()
        defer { cleanup(id) }
        for values in [Array(samples.prefix(1)), Array(samples.suffix(1))] {
            ChsChunkStore.save(values, id, "wlp", chunk, fetchedAt: now)
            XCTAssertNil(ChsChunkStore.load(id, "wlp", chunk, now: now))
        }
        let partial = ChsChunk(start: chunk.start, end: .init(timeIntervalSince1970: 900))
        ChsChunkStore.save([], id, "wlp", partial, fetchedAt: now)
        XCTAssertNil(ChsChunkStore.load(id, "wlp", partial, now: now))
    }

    func testLegacyDenseArraysMigrateOnlyAfterFilteringAndEndpointValidation() throws {
        let id = station()
        defer { cleanup(id) }
        let legacy = ChsChunkStore.legacyURL(id, "wlp", chunk)
        try FileManager.default.createDirectory(at: ChsChunkStore.dir, withIntermediateDirectories: true)
        let dense = samples + [ChsSample(t: 60000, v: 3)]
        try JSONEncoder().encode(dense).write(to: legacy)
        let finer = try IwlsSampleGrid(sampleMinutes: 5)
        XCTAssertNil(ChsChunkStore.load(id, "wlp", chunk, grid: finer, now: now))
        XCTAssertEqual(ChsChunkStore.load(id, "wlp", chunk, now: now), samples)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ChsChunkStore.url(id, "wlp", chunk).path))
    }

    func testLegacyEmptyAndTruncatedArraysMiss() throws {
        let id = station()
        defer { cleanup(id) }
        let legacy = ChsChunkStore.legacyURL(id, "wlp", chunk)
        try FileManager.default.createDirectory(at: ChsChunkStore.dir, withIntermediateDirectories: true)
        let legacyValues: [[ChsSample]] = [[], Array(samples.prefix(1))]
        for values in legacyValues {
            try JSONEncoder().encode(values).write(to: legacy)
            XCTAssertNil(ChsChunkStore.load(id, "wlp", chunk, now: now))
        }
    }

    func testAnEmptyResponseCannotReplaceACompleteCachedWeek() throws {
        let id = station()
        defer { cleanup(id) }
        ChsChunkStore.save(samples, id, "wlp", chunk, fetchedAt: now)
        ChsChunkStore.save([], id, "wlp", chunk, fetchedAt: now)
        XCTAssertEqual(ChsChunkStore.load(id, "wlp", chunk, now: now), samples)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ChsChunkStore.emptyURL(id, "wlp", chunk).path))
    }

    func testAnEmptyResponsePreservesCompleteLegacySamples() throws {
        let id = station()
        defer { cleanup(id) }
        try FileManager.default.createDirectory(at: ChsChunkStore.dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(samples).write(to: ChsChunkStore.legacyURL(id, "wlp", chunk))
        ChsChunkStore.save([], id, "wlp", chunk, fetchedAt: now)
        XCTAssertEqual(ChsChunkStore.load(id, "wlp", chunk, now: now), samples)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ChsChunkStore.emptyURL(id, "wlp", chunk).path))
    }

    func testConcurrentReadsAndSavesNeverLoseAnExistingWeek() {
        let id = station()
        let chunk = chunk
        let samples = samples
        let now = now
        defer { cleanup(id) }
        ChsChunkStore.save([], id, "wlp", chunk, fetchedAt: now)
        DispatchQueue.concurrentPerform(iterations: 400) { index in
            if index % 3 == 0 {
                ChsChunkStore.save(samples, id, "wlp", chunk, fetchedAt: now)
            } else if index % 3 == 1 {
                ChsChunkStore.save([], id, "wlp", chunk, fetchedAt: now)
            } else {
                XCTAssertNotNil(ChsChunkStore.load(id, "wlp", chunk, now: now))
            }
        }
    }

    func testFailedMigrationPreservesLegacySamplesForOfflineResume() throws {
        let id = station()
        defer { cleanup(id) }
        try FileManager.default.createDirectory(at: ChsChunkStore.url(id, "wlp", chunk), withIntermediateDirectories: true)
        let legacy = ChsChunkStore.legacyURL(id, "wlp", chunk)
        try JSONEncoder().encode(samples).write(to: legacy)
        XCTAssertEqual(ChsChunkStore.load(id, "wlp", chunk, now: now), samples)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testRollbackSamplesSupersedeAnEarlierNegativeEntry() throws {
        let id = station()
        defer { cleanup(id) }
        ChsChunkStore.save([], id, "wlp", chunk, fetchedAt: now)
        try JSONEncoder().encode(samples).write(to: ChsChunkStore.legacyURL(id, "wlp", chunk))
        XCTAssertEqual(ChsChunkStore.load(id, "wlp", chunk, now: now), samples)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ChsChunkStore.emptyURL(id, "wlp", chunk).path))
    }

    func testOnlineRetriesBypassEmptyWeeksButReusePositiveWeeks() async throws {
        let id = station()
        defer {
            ChsChunkStore.purge(id, includingEmpty: true)
        }
        let fetcher = IwlsFetcher(killSwitch: true)
        ChsChunkStore.save([], id, "wcsp1", chunk)
        do {
            _ = try await fetcher.series("wcsp1", stationID: id, chunk: chunk, cacheEmpty: false)
            XCTFail("an online retry must reach the network after an empty week")
        } catch ChsError.networkDisabled {} catch { XCTFail("unexpected error: \(error)") }
        ChsChunkStore.save(samples, id, "wcsp1", chunk)
        let hit = try await fetcher.series("wcsp1", stationID: id, chunk: chunk, cacheEmpty: false)
        XCTAssertEqual(hit, samples)
    }

    func testPurgeExpiresEmptyWeeksAndOrphanPurgeRemovesFreshOnes() {
        let id = station()
        let other = station()
        defer {
            ChsChunkStore.purge(id, includingEmpty: true)
            ChsChunkStore.purge(other, includingEmpty: true)
        }
        let older = ChsChunk(start: chunk.start.addingTimeInterval(-604800), end: chunk.start)
        ChsChunkStore.save([], id, "wlp", older, fetchedAt: now.addingTimeInterval(-86400))
        ChsChunkStore.save([], id, "wlp", chunk, fetchedAt: now)
        ChsChunkStore.save([], other, "wlp", chunk, fetchedAt: now)
        ChsChunkStore.purge(id, now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ChsChunkStore.emptyURL(id, "wlp", older).path))
        XCTAssertEqual(ChsChunkStore.load(id, "wlp", chunk, now: now), [])
        ChsChunkStore.purge(id, includingEmpty: true, now: now)
        XCTAssertNil(ChsChunkStore.load(id, "wlp", chunk, now: now))
        XCTAssertEqual(ChsChunkStore.load(other, "wlp", chunk, now: now), [])
    }

    func testGridAndWindowAreValidatedEvenUnderTheWrongFilename() throws {
        let id = station()
        defer { cleanup(id) }
        let finer = try IwlsSampleGrid(sampleMinutes: 5)
        ChsChunkStore.save(samples, id, "wlp", chunk, fetchedAt: now)
        XCTAssertNotEqual(ChsChunkStore.url(id, "wlp", chunk), ChsChunkStore.url(id, "wlp", chunk, grid: finer))
        XCTAssertNil(ChsChunkStore.load(id, "wlp", chunk, grid: finer, now: now))
        try Data(contentsOf: ChsChunkStore.url(id, "wlp", chunk))
            .write(to: ChsChunkStore.url(id, "wlp", chunk, grid: finer))
        defer { try? FileManager.default.removeItem(at: ChsChunkStore.url(id, "wlp", chunk, grid: finer)) }
        XCTAssertNil(ChsChunkStore.load(id, "wlp", chunk, grid: finer, now: now))
        let other = ChsChunk(start: .init(timeIntervalSince1970: 604800), end: .init(timeIntervalSince1970: 1209600))
        try Data(contentsOf: ChsChunkStore.url(id, "wlp", chunk)).write(to: ChsChunkStore.url(id, "wlp", other))
        XCTAssertNil(ChsChunkStore.load(id, "wlp", other, now: now))
    }
}
