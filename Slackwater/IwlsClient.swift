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

struct IwlsSample: Decodable { let eventDate: String; let value: Double }

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
        try JSONDecoder().decode([IwlsStation].self, from: try await get("/stations"))
    }

    struct Metadata: Decodable { let floodDirection: Double?; let ebbDirection: Double? }

    /// Per-station metadata — the only place IWLS serves the flood/ebb axis
    /// (the /stations list entries carry none).
    func metadata(stationID: String) async throws -> Metadata {
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
        let iso = ISO8601DateFormatter()
        let path = "/stations/\(stationID)/data?time-series-code=\(code)" +
            "&from=\(iso.string(from: chunk.start))&to=\(iso.string(from: chunk.end))"
        let raw = try JSONDecoder().decode([IwlsSample].self, from: try await get(path))
        var out: [ChsSample] = []
        for s in raw {
            guard let date = iso.date(from: s.eventDate) else { continue }
            let ms = date.timeIntervalSince1970 * 1000
            if out.last?.t != ms { out.append(ChsSample(t: ms, v: s.value)) }
        }
        let samples = transform(out)
        // Only whole grid chunks are cached: the newest one runs to "now" and
        // would be a different chunk tomorrow.
        if chunk.end.timeIntervalSince(chunk.start) >= 7 * 86_400 {
            ChsChunkStore.save(samples, stationID, code, chunk)
        }
        return samples
    }
}
