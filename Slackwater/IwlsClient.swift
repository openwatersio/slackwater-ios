// Slackwater — GPL v3. The IWLS client (Swift/URLSession — never JSCore), the
// sample types it decodes, and the on-disk chunk cache behind it.
//
// Constraints this client is built to:
//   - no fetch inside JSCore — IWLS goes over URLSession here
//   - series are requested at 15-min resolution (IWLS is 1-min native)
//   - 7-day request cap; queries by resolved Mongo id, never station code
import Foundation
#if DEBUG
import notify
#endif

struct IwlsStation: Decodable {
    struct Series: Decodable { let code: String }
    let id: String
    let officialName: String
    let latitude: Double
    let longitude: Double
    let timeSeries: [Series]
}

struct IwlsSample: Codable { let eventDate: String; let value: Double }

/// A decimated sample as bridged to JS: epoch-ms + metres.
struct ChsSample: Codable, Equatable { let t: Double; let v: Double }

/// One request's worth of series: a 7-day slot on the absolute epoch grid.
struct ChsChunk: Equatable { let start: Date; let end: Date }

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

actor IwlsPacer {
    private let interval: TimeInterval
    private var last = Date.distantPast

    init(interval: TimeInterval = 2.5) { self.interval = interval }

    func wait() async throws {
        let now = Date.now
        let slot = max(now, last.addingTimeInterval(interval))
        last = slot
        let gap = slot.timeIntervalSince(now)
        if gap > 0 { try await Task.sleep(for: .seconds(gap)) }
    }
}

/// Polite serial IWLS client: one request at a time, 2.5 s apart (~24/min,
/// safely under the documented 3/s and 30/min caps), 7-day chunks.
final class IwlsFetcher {
    static let base = "https://api-iwls.dfo-mpo.gc.ca/api/v1"
    private let killSwitch: Bool
    static let pacer = IwlsPacer()
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

    static func waitForFixtureRelease(_ checkpoint: String) async throws {
        guard let token = fixtureToken else { return }
        let name = "org.openwaters.slackwater.ui.\(token).\(checkpoint)"
        var registration: Int32 = 0
        let status = name.withCString { notify_register_check($0, &registration) }
        guard status == NOTIFY_STATUS_OK else {
            throw ChsError.permanent("could not register UI fixture checkpoint: \(checkpoint)")
        }
        defer { notify_cancel(registration) }
        for _ in 0..<1_200 {
            var state: UInt64 = 0
            if notify_get_state(registration, &state) == NOTIFY_STATUS_OK, state == 1 { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ChsError.permanent("UI fixture checkpoint timed out: \(checkpoint)")
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
            date = date.addingTimeInterval(900)
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

    /// Waits for a network path instead of failing without one, so a queue
    /// started offline resumes when the link returns.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        // That wait is bounded by this and NOTHING else, and the default is a
        // week. A path the user has denied — cellular switched off for
        // Slackwater, with no Wi-Fi — is never coming, so an unbounded wait
        // parks the claimed job on "Downloading" and the run behind it for the
        // life of the process. Five minutes still clears the 851 KB station
        // list at ~3 KB/s, well under anything a ship link does.
        // ponytail: a blunt ceiling. The honest fix is not starting a run
        // while `Connectivity` says there is no path, and re-pumping when one
        // returns — queue work, not client work.
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    /// How many times one request is tried in total, first attempt included.
    static let maxAttempts = 4

    /// Errors a later attempt can get past: the link dropped, stalled, or was
    /// not there yet.
    ///
    /// An allowlist, deliberately. The denylist this replaced retried
    /// everything except an explicit cancel, so a TLS failure behind a marina's
    /// captive portal — which answers identically every time — cost four
    /// attempts and 14 s of backoff per request before the app could say so.
    static func isTransient(_ error: Error) -> Bool {
        if let url = error as? URLError { return transientCodes.contains(url.code) }
        // A socket torn down while the app was suspended arrives as a bare
        // POSIX error, not a URLError: ECONNABORTED, ECONNRESET, ETIMEDOUT.
        // That is the commonest drop on a phone — lock it mid-chunk and the
        // fit used to fail on exactly the case retrying exists for.
        let ns = error as NSError
        return ns.domain == NSPOSIXErrorDomain && [53, 54, 60].contains(ns.code)
    }

    private static let transientCodes: Set<URLError.Code> = [
        .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
        .networkConnectionLost, .notConnectedToInternet, .resourceUnavailable,
        .badServerResponse, .zeroByteResource,
    ]

    /// Seconds to wait before the next attempt, or nil when another attempt
    /// cannot help. `attempt` is 1-based and counts the try that just failed.
    ///
    /// Pure, and the whole retry policy: what is worth another try, and how
    /// long to leave it. `get` below only obeys it.
    static func retryDelay(after outcome: Result<Int, Error>, attempt: Int,
                           retryAfter: Double? = nil) -> Double? {
        guard attempt < maxAttempts else { return nil }
        // ponytail: fixed 2/4/8 s, no jitter; add jitter if IWLS ever rate-limits
        // many devices in step.
        let backoff = pow(2, Double(attempt))
        switch outcome {
        case .failure(let error):
            return isTransient(error) ? backoff : nil
        case .success(429):
            // A rate limit is per WINDOW — IWLS counts 30 requests a minute —
            // so 2, 4 and 8 s all land inside the window that just rejected
            // us, and each retry spends another slot in it. Wait the window
            // out, or as long as the server asked for.
            return max(retryAfter ?? 0, 60)
        case .success(let status):
            // 501 and 505 are the server refusing this request's shape, and
            // 511 is a captive portal demanding a login: same answer next time.
            guard (500...599).contains(status), ![501, 505, 511].contains(status) else { return nil }
            return max(retryAfter ?? 0, backoff)
        }
    }

    static func terminalError(status code: Int) -> ChsError {
        (400...499).contains(code) && code != 429
            ? .permanent("HTTP \(code)") : .transient("HTTP \(code)")
    }

    private func get(_ path: String) async throws -> Data {
        guard !killSwitch else { throw ChsError.networkDisabled }
        let url = URL(string: Self.base + path)!
        var attempt = 0
        while true {
            attempt += 1
            let result = await request(url)
            if let data = result.data { return data }
            guard let delay = Self.retryDelay(after: result.outcome, attempt: attempt,
                                              retryAfter: result.retryAfter) else {
                switch result.outcome {
                case .success(let code):
                    throw Self.terminalError(status: code)
                case .failure(let error): throw error
                }
            }
            try await Task.sleep(for: .seconds(delay))
        }
    }

    private func request(_ url: URL) async
        -> (data: Data?, outcome: Result<Int, Error>, retryAfter: Double?) {
        let began = Date.now
        let result: (Data?, Result<Int, Error>, Double?)
        do {
            try await Self.pacer.wait()
            let (data, response) = try await Self.session.data(from: url)
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            result = (code == 200 ? data : nil, .success(code), retryAfter)
        } catch {
            result = (nil, .failure(error), nil)
        }
        await MainActor.run {
            ChsFitService.shared.observeRequest(seconds: Date.now.timeIntervalSince(began))
        }
        return result
    }

    /// The raw /stations JSON, beside the chunk store: at ~850 KB it is the
    /// costliest request IWLS serves, and its stations rarely change.
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
            let data = try await get("/stations")
            let list = try JSONDecoder().decode([IwlsStation].self, from: data)
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

    struct Metadata: Decodable { let floodDirection: Double?; let ebbDirection: Double? }

    /// Per-station metadata — the only place IWLS serves the flood/ebb axis
    /// (the /stations list entries carry none).
    func metadata(stationID: String) async throws -> Metadata {
#if DEBUG
        if Self.usesFixture { return Metadata(floodDirection: 45, ebbDirection: 225) }
#endif
        return try JSONDecoder().decode(Metadata.self, from: try await get("/stations/\(stationID)/metadata"))
    }

    /// A current series (wcsp1/wcdp1) for one chunk. Cached on disk,
    /// so this costs a request exactly once across retries and days.
    func series(_ code: String, stationID: String, chunk: ChsChunk) async throws -> [ChsSample] {
        try await cached(code, stationID: stationID, chunk: chunk) {
            $0.filter { $0.t.truncatingRemainder(dividingBy: 900_000) == 0 }
        }
    }

    /// wlp for one chunk on the 15-min grid the fit wants. The filter holds
    /// that grid for chunks cached on disk at IWLS's native 1-min rate.
    func wlp(stationID: String, chunk: ChsChunk) async throws -> [ChsSample] {
        try await cached("wlp", stationID: stationID, chunk: chunk) {
            $0.filter { $0.t.truncatingRemainder(dividingBy: 900_000) == 0 }
        }
    }

    private func cached(_ code: String, stationID: String, chunk: ChsChunk,
                        _ transform: ([ChsSample]) -> [ChsSample]) async throws -> [ChsSample] {
#if DEBUG
        if Self.usesFixture {
            let key = "\(stationID):\(code)"
            let count = fixtureRequests[key, default: 0]
            fixtureRequests[key] = count + 1
            if Self.fixtureScenario == "hold-first", count == 0 {
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
        if let hit = ChsChunkStore.load(stationID, code, chunk) { return transform(hit) }
        let raw: [ChsSample]
#if DEBUG
        if Self.usesFixture {
            raw = Self.fixtureSamples(code, chunk)
        } else {
            raw = try Self.decode(try await get(Self.dataPath(code, stationID, chunk)))
        }
#else
        raw = try Self.decode(try await get(Self.dataPath(code, stationID, chunk)))
#endif
        let samples = transform(raw)
        // Only whole grid chunks are cached: the newest one runs to "now" and
        // would be a different chunk tomorrow.
        if chunk.end.timeIntervalSince(chunk.start) >= 7 * 86_400 {
            ChsChunkStore.save(samples, stationID, code, chunk)
        }
        return samples
    }

    /// 15-minute samples: the fit's step, and a fifteenth of the 1-minute
    /// default's bytes with identical values at those stamps.
    private static func dataPath(_ code: String, _ stationID: String, _ chunk: ChsChunk) -> String {
        let iso = ISO8601DateFormatter()
        return "/stations/\(stationID)/data?time-series-code=\(code)" +
            "&from=\(iso.string(from: chunk.start))&to=\(iso.string(from: chunk.end))" +
            "&resolution=FIFTEEN_MINUTES"
    }

    static func decode(_ data: Data) throws -> [ChsSample] {
        let iso = ISO8601DateFormatter()
        let raw = try JSONDecoder().decode([IwlsSample].self, from: data)
        var out: [ChsSample] = []
        for s in raw {
            guard let date = iso.date(from: s.eventDate) else { continue }
            let ms = date.timeIntervalSince1970 * 1000
            if out.last?.t != ms { out.append(ChsSample(t: ms, v: s.value)) }
        }
        return out
    }
}
