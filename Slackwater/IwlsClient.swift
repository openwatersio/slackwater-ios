// Slackwater — GPL v3. App-owned IWLS caches and UI-test fixtures.
// Fetching rules and HTTP behavior live in the MIT SlackwaterIWLS module.
import Foundation
#if DEBUG
import notify
#endif

import SlackwaterIWLS

typealias IwlsStation = SlackwaterIWLS.IwlsStation
typealias IwlsSample = SlackwaterIWLS.IwlsSample
typealias ChsSample = SlackwaterIWLS.ChsSample
typealias ChsChunk = SlackwaterIWLS.ChsChunk
typealias IwlsPacer = SlackwaterIWLS.IwlsPacer

/// Fetched chunks, on disk, keyed by what identifies them and nothing else —
/// so a job that retries mid-download resumes where it stopped instead of
/// paying for the same bytes twice. Purged per station once its final fit lands
/// (the harmonic model is the artifact; the samples were only scaffolding).
enum ChsChunkStore {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ChsChunks", isDirectory: true)
    }()

    static func url(_ stationID: String, _ code: String, _ chunk: ChsChunk) -> URL {
        dir.appendingPathComponent("\(stationID)-\(code)-\(Int(chunk.start.timeIntervalSince1970)).json")
    }

    static func load(_ stationID: String, _ code: String, _ chunk: ChsChunk) -> [ChsSample]? {
        guard let data = try? Data(contentsOf: url(stationID, code, chunk)) else { return nil }
        return try? JSONDecoder().decode([ChsSample].self, from: data)
    }

    static func save(_ samples: [ChsSample], _ stationID: String, _ code: String, _ chunk: ChsChunk) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Re-downloadable by definition, so it has no business in a device
        // backup (iOS Data Storage Guidelines) — the same mark the station-list
        // cache beside it carries. Set on every save rather than at creation
        // because the directory is removed outright by a reset and recreated
        // by the next fetch, and an unmarked recreation is the case that leaks.
        var marked = dir
        var exclude = URLResourceValues()
        exclude.isExcludedFromBackup = true
        try? marked.setResourceValues(exclude)
        try? JSONEncoder().encode(samples).write(to: url(stationID, code, chunk), options: .atomic)
    }

    static func purge(_ stationID: String) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where f.hasPrefix(stationID + "-") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }
}

final class IwlsFetcher {
    private let killSwitch: Bool
    private let client = IwlsClient { seconds in
        await MainActor.run { ChsFitService.shared.observeRequest(seconds: seconds) }
    }
    private var fixtureRequests: [String: Int] = [:]

#if DEBUG
    private static let fixtureToken: String? = {
        guard let i = CommandLine.arguments.firstIndex(of: "-chsFixture"),
              CommandLine.arguments.indices.contains(i + 1) else { return nil }
        return CommandLine.arguments[i + 1]
    }()
    static var usesFixture: Bool { fixtureToken != nil }
    static let fixtureScenario: String? = {
        guard let i = CommandLine.arguments.firstIndex(of: "-chsFixtureScenario"),
              CommandLine.arguments.indices.contains(i + 1) else { return nil }
        return CommandLine.arguments[i + 1]
    }()

    static func waitForFixtureRelease(_ checkpoint: String, token: String? = fixtureToken,
                                      pause: () async throws -> Void = {
                                          try await Task.sleep(for: .milliseconds(50))
                                      }) async throws {
        guard let token else { return }
        let name = "org.openwaters.slackwater.ui.\(token).\(checkpoint)"
        var registration: Int32 = 0
        let status = name.withCString { notify_register_check($0, &registration) }
        guard status == NOTIFY_STATUS_OK else {
            throw ChsError.permanent("could not register UI fixture checkpoint: \(checkpoint)")
        }
        defer { notify_cancel(registration) }
        // The test owns the deadline; slow UI navigation must not expire a held fixture.
        while true {
            try Task.checkCancellation()
            var state: UInt64 = 0
            if notify_get_state(registration, &state) == NOTIFY_STATUS_OK, state == 1 { return }
            try await pause()
        }
    }

    private static func fixtureStations() -> [IwlsStation] {
        ChsStationInfo.all.map {
            IwlsStation(id: $0.id, officialName: $0.name, latitude: $0.latitude,
                        longitude: $0.longitude, timeSeries: [.init(code: "wlp")])
        } + ChsCurrentGateInfo.all.map {
            IwlsStation(id: $0.id, officialName: $0.name, latitude: $0.latitude,
                        longitude: $0.longitude,
                        timeSeries: [.init(code: "wcsp1"), .init(code: "wcdp1")])
        }
    }

    private static func fixtureSamples(_ code: String, _ chunk: ChsChunk) -> [ChsSample] {
        var out: [ChsSample] = []
        var date = chunk.start
        while date <= chunk.end {
            let phase = 2 * Double.pi * date.timeIntervalSince1970 / (12.42 * 3600)
            let value: Double
            switch code {
            case "wcdp1": value = sin(phase) >= 0 ? 45 : 225
            case "wcsp1": value = 2.4 * abs(sin(phase))
            default: value = 3 + 1.5 * sin(phase) + 0.4 * sin(phase / 2)
            }
            out.append(ChsSample(t: date.timeIntervalSince1970 * 1000, v: value))
            date = date.addingTimeInterval(ChsGrid.seconds)
        }
        return out
    }
#else
    static let usesFixture = false
    static let fixtureScenario: String? = nil
#endif

    init(killSwitch: Bool = networkKillSwitch) {
        self.killSwitch = killSwitch
    }

    // The station list changes rarely and is expensive to download repeatedly.
    static let stationListCache = ChsChunkStore.dir.deletingLastPathComponent()
        .appendingPathComponent("IwlsStations.json")

    func stationList() async throws -> [IwlsStation] {
#if DEBUG
        if Self.usesFixture { return Self.fixtureStations() }
#endif
        let cache = Self.stationListCache
        func cached() -> [IwlsStation]? {
            (try? Data(contentsOf: cache)).flatMap { try? JSONDecoder().decode([IwlsStation].self, from: $0) }
        }
        // Through FileManager, not `URL.resourceValues`: NSURL caches the values
        // it reads and only drops them for a URL used from the main thread,
        // and every caller here is off it (`run()` is detached, the online
        // fetch nonisolated). A cached date would outlive the rewrite below
        // and refetch 851 KB on every call for the life of the process. Same
        // idiom as `ChsCurrentGate`'s window age.
        let modified = (try? FileManager.default.attributesOfItem(atPath: cache.path))?[.modificationDate] as? Date
        // ponytail: a week-old list can hold an id IWLS has since retired; drop the cache on a 404 if that bites.
        if let modified, Date.now.timeIntervalSince(modified) < 7 * 86_400, let list = cached() { return list }
        do {
            guard !killSwitch else { throw ChsError.networkDisabled }
            let list = try await client.stationList()
            let data = try JSONEncoder().encode(list)
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: cache, options: .atomic)
            // Re-downloadable by definition, so it has no business in a device
            // backup (iOS Data Storage Guidelines). The chunk store beside it
            // carries the same mark, set as it writes.
            var written = cache
            var exclude = URLResourceValues()
            exclude.isExcludedFromBackup = true
            try? written.setResourceValues(exclude)
            return list
        } catch {
            // A stale list still resolves stations; failing here fails every queued job.
            guard let list = cached() else { throw error }
            return list
        }
    }

    typealias Metadata = IwlsClient.Metadata

    /// Per-station metadata — the only place IWLS serves the flood/ebb axis
    /// (the /stations list entries carry none).
    func metadata(stationID: String) async throws -> Metadata {
#if DEBUG
        if Self.usesFixture { return Metadata(floodDirection: 45, ebbDirection: 225) }
#endif
        guard !killSwitch else { throw ChsError.networkDisabled }
        return try await client.metadata(stationID: stationID)
    }

    /// A current series (wcsp1/wcdp1) for one chunk. Cached on disk,
    /// so this costs a request exactly once across retries and days.
    func series(_ code: String, stationID: String, chunk: ChsChunk) async throws -> [ChsSample] {
        try await cached(code, stationID: stationID, chunk: chunk) {
            IwlsFetch.onGrid($0)
        }
    }

    /// wlp for one chunk on the 15-min grid the fit wants. The filter holds
    /// that grid for chunks cached on disk at IWLS's native 1-min rate.
    func wlp(stationID: String, chunk: ChsChunk, cache: Bool = true) async throws -> [ChsSample] {
        try await cached("wlp", stationID: stationID, chunk: chunk, cache: cache) {
            IwlsFetch.onGrid($0)
        }
    }

    private func cached(_ code: String, stationID: String, chunk: ChsChunk,
                        cache: Bool = true,
                        _ transform: ([ChsSample]) -> [ChsSample]) async throws -> [ChsSample] {
        try Task.checkCancellation()
#if DEBUG
        if Self.usesFixture {
            if Self.fixtureScenario == "tide-preview-fail", code == "wlp" {
                throw ChsError.permanent("fixture: additional tide download failed")
            }
            let key = "\(stationID):\(code)"
            let count = fixtureRequests[key, default: 0]
            fixtureRequests[key] = count + 1
            if ["hold-first", "tide-preview-final"].contains(Self.fixtureScenario ?? ""), count == 0 {
                try await Self.waitForFixtureRelease("\(stationID)-first-chunk")
            }
            if Self.fixtureScenario == "no-interrupt", count == 0 {
                if stationID == "chs-dodd-narrows", code == "wcsp1" {
                    try await Self.waitForFixtureRelease("dodd-first-chunk")
                } else if stationID == "chs-tofino", code == "wlp" {
                    try await Self.waitForFixtureRelease("tofino-first-chunk")
                }
            }
        }
#endif
        // Builds before `canCache` stored empty weeks; treat those as misses so they refetch.
        if cache, let hit = ChsChunkStore.load(stationID, code, chunk), !hit.isEmpty { return transform(hit) }
        let raw: [ChsSample]
#if DEBUG
        if Self.usesFixture {
            raw = Self.fixtureSamples(code, chunk)
        } else {
            guard !killSwitch else { throw ChsError.networkDisabled }
            raw = try await client.series(code, stationID: stationID, chunk: chunk)
        }
#else
        guard !killSwitch else { throw ChsError.networkDisabled }
        raw = try await client.series(code, stationID: stationID, chunk: chunk)
#endif
        let samples = transform(raw)
        // Only whole, non-empty grid chunks are cached: the newest one runs to
        // "now" and would be a different chunk tomorrow, and an empty week kept
        // under a stable identity would never be fetched again.
        if cache, chunk.canCache(samples) {
            ChsChunkStore.save(samples, stationID, code, chunk)
        }
        return samples
    }
}
