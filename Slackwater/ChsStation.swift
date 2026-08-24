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
struct ChsStationInfo: Decodable, Identifiable, Hashable, StationIdentity {
    let id: String        // registry key, e.g. "chs-victoria"
    let name: String
    let region: String
    let aliases: [String]
    let latitude: Double
    let longitude: Double
    let timezone: String

    static let all: [ChsStationInfo] = bundled("chs-stations")
}

/// Identity for a station that HAS shipped and no longer does
/// (chs-tombstones.json, issue #91). Favorites persist a bare `StationItem.id`
/// and nothing else, so when a station leaves the bundle this file is the only
/// thing left that can name what someone starred — and its last known position
/// is what a replacement gets offered from.
///
/// Written by `gen-chs-stations.mjs`, which is also the only producer today;
/// the app looks tombstones up by id, so a NOAA one would just be more rows.
struct StationTombstone: Decodable, Identifiable, Hashable, StationIdentity {
    let id: String
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double
    /// StationIdentity's search hook, computed rather than stored: a removed
    /// station is never searched, and a stored-with-default property would
    /// depend on synthesised-Decodable behaviour that `bundled`'s `try?` would
    /// swallow into an empty catalog if it went the other way.
    var aliases: [String] { [] }

    static let all: [StationTombstone] = bundled("chs-tombstones")
    static let byId: [String: StationTombstone] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
}

/// A harmonic model fitted on this device from IWLS predictions (`wlp` for a
/// tide port, `wcsp1`/`wcdp1` for a current gate) — the only CHS-derived
/// artifact, and it never leaves the device. One shape for both series; the
/// optionals are nil for a tide port, and stay optional so every model file
/// either pre-merge shape ever wrote to a device still decodes.
struct ChsModel: Codable {
    var schemaVersion = 1
    let stationID: String     // registry key
    let iwlsID: String        // resolved at runtime by position (never bundled)
    let iwlsName: String
    let fittedAt: Date
    let fitStartMs: Double
    let fitEndMs: Double
    /// Days of data behind a gate fit. Less than the gate's `fitDays` means
    /// this is the PROVISIONAL fast answer, not the final model. Optional so a
    /// model stored by build ≤14 (always the full window) still decodes.
    var fitDays: Double? = nil
    /// The flood/ebb axis — IWLS station metadata, fetched by this user, kept
    /// local, never re-served. Gate models only.
    var floodDirection: Double? = nil
    var ebbDirection: Double? = nil
    /// Z0: mean level above chart datum (metres) — for a gate, net mean flow
    /// along the flood axis (knots, signed).
    let offset: Double
    /// Fit residual: metres for a tide port, knots for a gate.
    let rms: Double
    let constituents: [Con]
}

/// The app-only side effect of a fitted model landing on disk: reload the
/// widget's timelines so a freshly-fitted station shows up without waiting
/// for the next half-hourly tick (H1). A closure, not a direct
/// `WidgetCenter.shared.reloadAllTimelines()` call, because this file also
/// compiles into the widget extension (see the appex source list in
/// project.yml) — the appex has no reason to reload itself mid-fit, so it
/// keeps the default no-op and only `SlackwaterApp.init()` assigns the real
/// trigger.
enum WidgetReload {
    static var trigger: () -> Void = {}
}

/// One JSON file per station under Application Support/ChsModels — keyed by
/// registry key, so a future second region is just more files, no migration.
enum ChsModelStore {
    static let dir: URL = {
        let dest = AppGroup.container.appendingPathComponent("ChsModels", isDirectory: true)
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask)[0]
            .appendingPathComponent("ChsModels", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dest.path), fm.fileExists(atPath: legacy.path) {
            try? fm.createDirectory(at: dest.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            try? fm.moveItem(at: legacy, to: dest)
        }
        return dest
    }()

    static func url(_ stationID: String, suffix: String = "") -> URL {
        dir.appendingPathComponent("\(stationID)\(suffix).json")
    }

    static func load<T: Decodable>(_ stationID: String, suffix: String) -> T? {
        guard let data = try? Data(contentsOf: url(stationID, suffix: suffix)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, id: String, suffix: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url(id, suffix: suffix), options: .atomic)
        // The one place every model write funnels through — tide (suffix
        // ""), current (suffix "-current") and online-window (suffix
        // "-online") saves all land here, so one call covers all three
        // rather than each public entry point remembering its own (H1).
        WidgetReload.trigger()
    }

    static func load(_ stationID: String) -> ChsModel? { load(stationID, suffix: "") }
    static func save(_ model: ChsModel) throws { try save(model, id: model.stationID, suffix: "") }
}

extension ChsStationInfo {
    /// A fitted CHS station renders through the exact same record/engine/view
    /// path as a bundled NOAA station — provenance shows only in the footer.
    func record(with model: ChsModel) -> TideStationRecord {
        TideStationRecord(
            id: id, name: name, region: region, aliases: aliases,
            latitude: latitude, longitude: longitude, timezone: timezone,
            chartDatum: "LLWLT",  // CHS chart datum: Lower Low Water, Large Tide
            datumOffset: model.offset,
            constituents: model.constituents)
    }
}

extension TideStationRecord {
    /// Fitted-on-device CHS station, vs a bundled NOAA harmonic station.
    var isChs: Bool { id.hasPrefix("chs-") }
}
