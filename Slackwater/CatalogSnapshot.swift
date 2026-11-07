// Slackwater — GPL v3. Pure validation boundary for bundled and downloaded catalogs.
import Foundation
import SlackwaterDatabase

struct CatalogError: Error, CustomStringConvertible {
    enum Stage: String { case lookup, read, decode, validation }
    let resource: String
    let stage: Stage
    let reason: String

    var description: String { "\(resource): \(stage.rawValue): \(reason)" }
}

/// Reads one complete catalog or throws; recovery belongs to the snapshot store.
/// The widget's mapped single-record loader deliberately does not use this.
func readCatalog<T: Decodable & StationIdentity>(_ resource: String, directory: URL) throws -> [T] {
    let url = directory.appendingPathComponent(resource + ".json")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CatalogError(resource: resource, stage: .lookup, reason: "file missing")
    }
    let data: Data
    do { data = try Data(contentsOf: url) }
    catch { throw CatalogError(resource: resource, stage: .read, reason: "unable to read file") }
    let records: [T]
    do { records = try JSONDecoder().decode([T].self, from: data) }
    catch {
        // Do not include the payload or decoder debugDescription in release logs.
        throw CatalogError(resource: resource, stage: .decode, reason: "invalid catalog JSON or record schema")
    }
    return records.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
}

/// Decoded candidate with validated identities, model structure, joins and removals.
/// No global catalog accessors are used: validation also works before app startup.
struct CatalogSnapshot {
    static let resources = ["stations", "currents", "chs-stations", "chs-gates", "chs-current-gates", "chs-tombstones"]
    /// The two NOAA catalogs are station databases (TideStationDatabase.swift,
    /// CurrentStationDatabase.swift); the CHS catalogs are JSON.
    static func fileName(_ resource: String) -> String {
        resource == "stations" || resource == "currents" ? resource + ".tcdb" : resource + ".json"
    }

    let tides: [TideStationRecord]
    let currents: [CurrentStationRecord]
    let chsStations: [ChsStationInfo]
    let chsGates: [ChsGateInfo]
    let chsCurrents: [ChsCurrentGateInfo]
    let tombstones: [StationTombstone]
    let items: [StationItem]
    let byID: [String: StationItem]

    init(directory: URL, active: CatalogSnapshot? = nil) throws {
        try self.init(tides: stationDatabase("stations", directory: directory, verifying: true)
                        .map(TideStationRecord.init),
                      currents: Self.currentRecords(stationDatabase("currents", directory: directory, verifying: true)),
                      directory: directory, active: active)
    }

    /// Validates tide and current records already read from a directory's
    /// databases, with that directory's JSON catalogs.
    init(tides: [TideStationRecord], currents: [CurrentStationRecord], directory: URL,
         active: CatalogSnapshot? = nil) throws {
        self.tides = tides.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        self.currents = currents.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        chsStations = try readCatalog("chs-stations", directory: directory)
        chsGates = try readCatalog("chs-gates", directory: directory)
        chsCurrents = try readCatalog("chs-current-gates", directory: directory)
        tombstones = try readCatalog("chs-tombstones", directory: directory)

        try Self.validateIdentity(tides, resource: "stations", timezone: { $0.timezone })
        try Self.validateIdentity(currents, resource: "currents", timezone: { $0.timezone })
        try Self.validateIdentity(chsStations, resource: "chs-stations", timezone: { $0.timezone })
        try Self.validateIdentity(chsGates, resource: "chs-gates", timezone: { $0.timezone })
        try Self.validateIdentity(chsCurrents, resource: "chs-current-gates", timezone: { $0.timezone })
        try Self.validateIdentity(tombstones, resource: "chs-tombstones", timezone: { _ in nil })

        // Uniqueness is checked before constructing dictionaries (no traps or discarded rows).
        let tideByID = Dictionary(uniqueKeysWithValues: tides.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: currents.map { ($0.id, $0) })
        let chsIDs = Set(chsStations.map(\.id))
        for tide in tides {
            if let reference = tide.reference {
                guard let ref = tideByID[reference], !ref.isSubordinate,
                      Self.validConstituents(ref.constituents), let offsets = tide.offsets,
                      [offsets.time.high, offsets.time.low, offsets.height.high, offsets.height.low].allSatisfy(\.isFinite),
                      ["fixed", "ratio"].contains(offsets.height.type) else {
                    throw Self.invalid("stations", "invalid subordinate reference or offsets for \(tide.id)")
                }
            } else if !Self.validConstituents(tide.constituents) {
                throw Self.invalid("stations", "unusable constituents for \(tide.id)")
            }
        }
        for current in currents {
            if let reference = current.reference {
                let offsets = [current.slackBeforeFloodOffset, current.slackBeforeEbbOffset,
                               current.floodTimeOffset, current.ebbTimeOffset]
                guard let ref = currentByID[reference], !ref.isSubordinate, Self.validConstituents(ref.constituents),
                      offsets.allSatisfy({ $0?.isFinite == true }),
                      let flood = current.floodSpeedRatio, let ebb = current.ebbSpeedRatio,
                      flood.isFinite, ebb.isFinite, flood >= 0, ebb >= 0, flood > 0 || ebb > 0 else {
                    throw Self.invalid("currents", "invalid subordinate reference or corrections for \(current.id)")
                }
            } else if !Self.validConstituents(current.constituents) {
                throw Self.invalid("currents", "unusable constituents for \(current.id)")
            }
            if let reference = current.tideReference, tideByID[reference] == nil {
                throw Self.invalid("currents", "unresolved tideReference for \(current.id)")
            }
        }
        for gate in chsGates where !chsIDs.contains(gate.reference) {
            throw Self.invalid("chs-gates", "unresolved reference for \(gate.id)")
        }
        for gate in chsCurrents {
            if let reference = gate.tideReference, !chsIDs.contains(reference) {
                throw Self.invalid("chs-current-gates", "unresolved tideReference for \(gate.id)")
            }
        }

        let groups: [(String, [StationItem])] = [
            ("stations", tides.map { StationItem.tide(StationIndexInfo($0)) }),
            ("currents", currents.filter { $0.referenceOnly != true }.map { StationItem.current(StationIndexInfo($0)) }),
            ("chs-stations", chsStations.map(StationItem.chs)), ("chs-gates", chsGates.map(StationItem.chsGate)),
            ("chs-current-gates", chsCurrents.map(StationItem.chsCurrent))]
        var ids = Set<String>()
        for (resource, records) in groups {
            for record in records where !ids.insert(record.id).inserted {
                throw Self.invalid(resource, "duplicate rendered ID \(record.id)")
            }
        }
        let removedIDs = Set(tombstones.map(\.id))
        if let collision = ids.intersection(removedIDs).sorted().first {
            throw Self.invalid("chs-tombstones", "live/tombstone collision for \(collision)")
        }
        if let active {
            let previousIDs = Set(active.byID.keys).union(active.tombstones.map(\.id))
            let missing = previousIDs.subtracting(ids).subtracting(removedIDs)
            if let id = missing.sorted().first {
                throw Self.invalid("chs-tombstones", "removal without tombstone for \(id)")
            }
        }
        items = groups.flatMap(\.1).sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    /// A database's current stations as the app's records. The record reads a
    /// missing direction or mean flow as zero, and a missing region as empty;
    /// currents.json could not decode without them, so a station missing one
    /// is refused here rather than drawn or predicted wrong.
    private static func currentRecords(_ database: StationDatabase) throws -> [CurrentStationRecord] {
        try database.map { station in
            guard let current = station.current, current.floodDirection != nil, current.ebbDirection != nil,
                  current.meanFlow != nil, station.region != nil else {
                throw invalid("currents", "missing direction, mean flow or region for \(station.id)")
            }
            // JSON could not spell a non-finite number; float32 can.
            let axes = [current.floodDirection, current.ebbDirection, current.meanFlow,
                        current.minorMeanFlow, current.azimuth].compactMap { $0 }
                + (current.minorConstituents ?? []).flatMap { [$0.amplitude, $0.phase] }
            guard axes.allSatisfy(\.isFinite) else {
                throw invalid("currents", "non-finite direction, flow or minor axis for \(station.id)")
            }
            return CurrentStationRecord(station)
        }
    }

    private static func invalid(_ resource: String, _ reason: String) -> CatalogError {
        CatalogError(resource: resource, stage: .validation, reason: reason)
    }

    private static func validateIdentity<T: StationIdentity>(
        _ records: [T], resource: String, timezone: (T) -> String?
    ) throws {
        guard !records.isEmpty else { throw invalid(resource, "empty catalog") }
        var ids = Set<String>()
        for record in records {
            guard !record.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.latitude.isFinite, (-90...90).contains(record.latitude),
                  record.longitude.isFinite, (-180...180).contains(record.longitude) else {
                throw invalid(resource, "invalid station identity")
            }
            guard ids.insert(record.id).inserted else { throw invalid(resource, "duplicate ID \(record.id)") }
            if let zone = timezone(record) {
                guard TimeZone(identifier: zone) != nil,
                      !["GMT+", "GMT-", "UTC+", "UTC-"].contains(where: zone.hasPrefix) else {
                    throw invalid(resource, "invalid IANA time zone for \(record.id)")
                }
            }
        }
    }

    private static func validConstituents(_ constituents: [Con]) -> Bool {
        // This checks structure only. Before enabling remote activation, SlackwaterKit
        // needs a public recognized-name lookup (it currently drops unknown names).
        !constituents.isEmpty && constituents.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.amplitude.isFinite && $0.amplitude >= 0 && $0.phase.isFinite
        } && constituents.contains { $0.amplitude > 0 }
    }
}
