// Slackwater — GPL v3. The IWLS client (Swift/URLSession — never JSCore), the
// sample types it decodes, and the on-disk chunk cache behind it.
//
// Constraints this client is built to:
//   - no fetch inside JSCore — IWLS goes over URLSession here
//   - wlp is 1-min native → decimated to 15-min before bridging
//   - 7-day request cap; queries by resolved Mongo id, never station code
import Foundation

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
/// so a job that stepped aside mid-download resumes where it stopped instead of
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
        try? JSONEncoder().encode(samples).write(to: url(stationID, code, chunk), options: .atomic)
    }

    static func purge(_ stationID: String) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where f.hasPrefix(stationID + "-") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }
}

/// Polite serial IWLS client: one request at a time, 2.5 s apart (~24/min,
/// safely under the documented 3/s and 30/min caps), 7-day chunks.
final class IwlsFetcher {
    static let base = "https://api-iwls.dfo-mpo.gc.ca/api/v1"
    private let killSwitch: Bool
    private var lastRequest = Date.distantPast
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
        let url = URL(fileURLWithPath: "/tmp/slackwater-ui-\(token)-\(checkpoint)")
        for _ in 0..<1_200 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ChsError.failed("UI fixture checkpoint timed out: \(checkpoint)")
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

    private func get(_ path: String) async throws -> Data {
        guard !killSwitch else { throw ChsError.networkDisabled }
        let wait = 2.5 - Date.now.timeIntervalSince(lastRequest)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        lastRequest = .now
        let (data, response) = try await URLSession.shared.data(from: URL(string: Self.base + path)!)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ChsError.failed("HTTP \(code)") }
        return data
    }

    func stationList() async throws -> [IwlsStation] {
#if DEBUG
        if Self.usesFixture { return Self.fixtureStations() }
#endif
        try JSONDecoder().decode([IwlsStation].self, from: try await get("/stations"))
    }

    struct Metadata: Decodable { let floodDirection: Double?; let ebbDirection: Double? }

    /// Per-station metadata — the only place IWLS serves the flood/ebb axis
    /// (the /stations list entries carry none).
    func metadata(stationID: String) async throws -> Metadata {
#if DEBUG
        if Self.usesFixture { return Metadata(floodDirection: 45, ebbDirection: 225) }
#endif
        try JSONDecoder().decode(Metadata.self, from: try await get("/stations/\(stationID)/metadata"))
    }

    /// A natively 15-minute series (wcsp1/wcdp1) for one chunk. Cached on disk,
    /// so this costs a request exactly once — including across a job that
    /// stepped aside and came back, and across days (the grid is absolute).
    func series(_ code: String, stationID: String, chunk: ChsChunk) async throws -> [ChsSample] {
        try await cached(code, stationID: stationID, chunk: chunk) { $0 }
    }

    /// wlp for one chunk, decimated from its 1-min native rate to the 15-min
    /// grid the fit wants.
    func wlp(stationID: String, chunk: ChsChunk) async throws -> [ChsSample] {
        try await cached("wlp", stationID: stationID, chunk: chunk) {
            $0.filter { $0.t.truncatingRemainder(dividingBy: 900_000) == 0 }
        }
    }

    private func cached(_ code: String, stationID: String, chunk: ChsChunk,
                        _ transform: ([ChsSample]) -> [ChsSample]) async throws -> [ChsSample] {
        if let hit = ChsChunkStore.load(stationID, code, chunk) { return hit }
#if DEBUG
        if Self.usesFixture {
            let key = "\(stationID):\(code)"
            let count = fixtureRequests[key, default: 0]
            fixtureRequests[key] = count + 1
            if Self.fixtureScenario == "hold-first", count == 0 {
                try await Self.waitForFixtureRelease("\(stationID)-first-chunk")
            }
            if Self.fixtureScenario == "yield-resume", count == 0 {
                if stationID == "chs-dodd-narrows", code == "wcsp1" {
                    try await Self.waitForFixtureRelease("dodd-first-chunk")
                } else if stationID == "chs-tofino", code == "wlp" {
                    try await Self.waitForFixtureRelease("tofino-first-chunk")
                }
            }
            return transform(Self.fixtureSamples(code, chunk))
        }
#endif
        let iso = ISO8601DateFormatter()
        let path = "/stations/\(stationID)/data?time-series-code=\(code)" +
            "&from=\(iso.string(from: chunk.start))&to=\(iso.string(from: chunk.end))"
        let raw = try Self.decode(try await get(path))
        let samples = transform(raw)
        // Only whole grid chunks are cached: the newest one runs to "now" and
        // would be a different chunk tomorrow.
        if chunk.end.timeIntervalSince(chunk.start) >= 7 * 86_400 {
            ChsChunkStore.save(samples, stationID, code, chunk)
        }
        return samples
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
