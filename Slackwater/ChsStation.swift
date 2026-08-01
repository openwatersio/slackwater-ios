// Slackwater — GPL v3. Canadian (CHS) Salish tide stations: bundled identity
// from the station-corrections registry (the same source slackwater-web
// consumes — name/region/position/aliases only, nothing CHS-published), plus
// the on-device fitted harmonic model store.
//
// Licensing posture (chs-online-design §2): the app ships identity we authored.
// CHS predictions are fetched by each user under DFO's own terms, fitted
// on-device, stored locally, and never re-served. No CHS data is bundled.
import Foundation

/// Bundled identity for one CHS tide reference port (chs-stations.json).
struct ChsStationInfo: Decodable, Identifiable, Hashable {
    let id: String        // registry key, e.g. "chs-victoria"
    let name: String
    let region: String
    let aliases: [String]
    let latitude: Double
    let longitude: Double
    let timezone: String

    static let victoriaID = "chs-victoria"

    static let all: [ChsStationInfo] = {
        guard let url = Bundle.main.url(forResource: "chs-stations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let stations = try? JSONDecoder().decode([ChsStationInfo].self, from: data) else { return [] }
        return stations.sorted { $0.name < $1.name }
    }()

    /// Same ranking as TideStationRecord.searchRank (mirrors web search.ts).
    func searchRank(_ query: String) -> Int? {
        if name.lowercased().contains(query) { return 0 }
        if region.lowercased().contains(query) { return 1 }
        if aliases.contains(where: { $0.contains(query) }) { return 2 }
        return nil
    }
}

/// A harmonic model fitted on this device from IWLS `wlp` predictions —
/// the only CHS-derived artifact, and it never leaves the device.
struct ChsFittedModel: Codable {
    struct Con: Codable { let name: String; let amplitude: Double; let phase: Double }
    var schemaVersion = 1
    let stationID: String     // registry key
    let iwlsID: String        // resolved at runtime by position (never bundled)
    let iwlsName: String
    let fittedAt: Date
    let fitStartMs: Double
    let fitEndMs: Double
    /// Z0: mean level above chart datum, metres.
    let offset: Double
    /// Fit residual, metres.
    let rms: Double
    let constituents: [Con]
}

/// One JSON file per station under Application Support/ChsModels — keyed by
/// registry key, so a future second region is just more files, no migration.
enum ChsModelStore {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ChsModels", isDirectory: true)
    }()

    static func url(_ stationID: String) -> URL { dir.appendingPathComponent("\(stationID).json") }

    static func load(_ stationID: String) -> ChsFittedModel? {
        guard let data = try? Data(contentsOf: url(stationID)) else { return nil }
        return try? JSONDecoder().decode(ChsFittedModel.self, from: data)
    }

    static func save(_ model: ChsFittedModel) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(model).write(to: url(model.stationID), options: .atomic)
    }

    /// UI-test hook: `-chsResetModels` wipes the store for a clean first run —
    /// including the fetched chunks, or "first run" would silently be a resume.
    static func resetIfRequested() {
        guard CommandLine.arguments.contains("-chsResetModels") else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: ChsChunkStore.dir)
    }
}

extension ChsStationInfo {
    /// A fitted CHS station renders through the exact same record/engine/view
    /// path as a bundled NOAA station — provenance shows only in the footer.
    func record(with model: ChsFittedModel) -> TideStationRecord {
        TideStationRecord(
            id: id, name: name, region: region, aliases: aliases,
            latitude: latitude, longitude: longitude, timezone: timezone,
            chartDatum: "Chart",  // heights are above CHS chart datum
            datumOffset: model.offset,
            constituents: model.constituents.map {
                TideStationRecord.Con(name: $0.name, amplitude: $0.amplitude, phase: $0.phase)
            })
    }
}

extension TideStationRecord {
    /// Fitted-on-device CHS station, vs a bundled NOAA harmonic station.
    var isChs: Bool { id.hasPrefix("chs-") }
}
