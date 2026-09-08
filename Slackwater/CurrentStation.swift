// Slackwater — GPL v3. Bundled NOAA Salish current stations (public domain
// data, the same file slackwater-web ships as currents.json, enriched with
// resolved names/regions/aliases from @sailingnaturali/station-corrections —
// harmonic and subordinate stations, primary bin plus the bins subordinates
// reduce from).
import CoreLocation
import Foundation
import TideEngine

/// Below this magnitude the water reads "Slack", not a direction (web chs/current.ts SLACK_KN).
let slackKn = 0.15

// MARK: - Geo

/// Great-circle distance in kilometres.
func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    CLLocation(latitude: lat1, longitude: lon1)
        .distance(from: CLLocation(latitude: lat2, longitude: lon2)) / 1000
}

/// Great-circle distance in kilometres (the labelled spelling; forwards to
/// the positional one above).
func distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    distanceKm(lat1, lon1, lat2, lon2)
}

// MARK: - Shared station identity

/// The stored identity every bundled station type carries — one search
/// ranking and one bundle loader for all five.
protocol StationIdentity {
    var id: String { get }
    var name: String { get }
    var region: String { get }
    var aliases: [String] { get }
    var latitude: Double { get }
    var longitude: Double { get }
}

extension StationIdentity {
    /// Name, region, then alias — same ranking as the web (search.ts): a name
    /// match is what the user typed on purpose; region/aliases are how you find
    /// a station when you only know the water.
    func searchRank(_ query: String) -> Int? {
        if name.lowercased().contains(query) { return 0 }
        if region.lowercased().contains(query) { return 1 }
        if aliases.contains(where: { $0.contains(query) }) { return 2 }
        return nil
    }
}

/// A harmonic constituent as it appears in bundled and on-device JSON.
struct Con: Codable, Hashable { let name: String; let amplitude: Double; let phase: Double }

/// Reads a required catalog from a directory without converting failures to an invented empty array.
func requiredCatalog<T: Decodable & StationIdentity>(
    _ resource: String, directory: URL
) throws -> [T] {
    try readCatalog(resource, directory: directory)
}

/// A bundled JSON station catalog, name-sorted; a missing or undecodable bundle is terminal.
func bundled<T: Decodable & StationIdentity>(_ resource: String) -> [T] {
    do {
        return try requiredCatalog(
            resource, directory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
    } catch {
        CatalogDiagnostics.log(error)
        assertionFailure(String(describing: error))
        preconditionFailure(String(describing: error))
    }
}

/// Decode one record without materializing a multi-megabyte catalog in a
/// memory-limited extension.
/// ponytail: relies on generated compact JSON keeping `id` first; add an
/// offset index if that catalog format changes.
func bundled<T: Decodable & StationIdentity>(_ resource: String, id: String) -> T? {
    guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
          let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    return try? decodeCatalogRecord(data, id: id)
}

func catalogRecord<T: Decodable & StationIdentity>(
    _ resource: String, id: String, directory: URL
) throws -> T? {
    let url = directory.appendingPathComponent(resource + ".json")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CatalogError(resource: resource, stage: .lookup, reason: "file missing")
    }
    let data: Data
    do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
    catch { throw CatalogError(resource: resource, stage: .read, reason: "unable to read file") }
    do { return try decodeCatalogRecord(data, id: id) }
    catch { throw CatalogError(resource: resource, stage: .decode, reason: "invalid catalog record") }
}

/// Shared with candidate validation so downloaded NOAA files must satisfy the
/// exact same compact-record contract as widget lookups.
func decodeCatalogRecord<T: Decodable>(_ data: Data, id: String) throws -> T? {
    guard data.first == 91, data.last == 93 else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid compact catalog framing"))
    }
    let marker = Data("{\"id\":\"".utf8) + Data(id.utf8) + Data("\"".utf8)
    guard let start = data.range(of: marker)?.lowerBound else {
        guard data == Data("[]".utf8) || data.starts(with: Data("[{\"id\":\"".utf8)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid compact catalog framing"))
        }
        var stack: [UInt8] = [], quoted = false, escaped = false, expectsRecord = true
        let bytes = Array(data)
        for (index, byte) in bytes.enumerated() {
            if quoted { if escaped { escaped = false } else if byte == 92 { escaped = true } else if byte == 34 { quoted = false }; continue }
            if stack.count == 1 {
                if byte == 123 {
                    guard expectsRecord, bytes[index...].starts(with: [123, 34, 105, 100, 34, 58, 34]) else {
                        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid compact catalog outer grammar"))
                    }
                    expectsRecord = false
                } else if byte == 44 {
                    guard !expectsRecord else {
                        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid compact catalog outer grammar"))
                    }
                    expectsRecord = true
                } else if byte == 93 {
                    guard index == bytes.count - 1, !expectsRecord || bytes == [91, 93] else {
                        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "multiple compact catalog roots"))
                    }
                } else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid compact catalog outer grammar"))
                }
            }
            if byte == 34 { quoted = true }
            else if byte == 91 || byte == 123 { stack.append(byte) }
            else if byte == 93 || byte == 125 {
                guard let open = stack.popLast(), (open == 91 && byte == 93) || (open == 123 && byte == 125) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid compact catalog delimiters"))
                }
            }
        }
        guard !quoted, !escaped, stack.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "truncated compact catalog"))
        }
        return nil
    }
    guard let arrayEnd = data.lastIndex(of: 93) else { return nil }
    let separator = Data(",{\"id\":".utf8)
    let afterMarker = data.index(start, offsetBy: marker.count)
    guard arrayEnd >= afterMarker else { return nil }
    let end = data.range(of: separator, in: afterMarker..<data.endIndex)?.lowerBound ?? arrayEnd
    return try JSONDecoder().decode(T.self, from: data[start..<end])
}

struct CurrentStationRecord: Decodable, Identifiable, Hashable, StationIdentity {
    let id: String
    let name: String
    let region: String
    let aliases: [String]
    let latitude: Double
    let longitude: Double
    let timezone: String
    let floodDirection: Double
    let ebbDirection: Double
    /// Z0 net mean flow along the major axis, knots, signed.
    let meanFlow: Double
    /// Bundled tide station id whose water pairs with this gate (current-detail
    /// spec §2/§9 — a data-layer field written by tools/enrich-currents.mjs
    /// against station-corrections v2.5.0; absent = current-only fallback).
    let tideReference: String?
    let constituents: [Con]
    /// Subordinate station (#268): NOAA's four time offsets (seconds) and two
    /// speed ratios against a bundled reference, and no constituents of its
    /// own — the generator guarantees the reference ships.
    var reference: String? = nil
    var slackBeforeFloodOffset: Double? = nil
    var slackBeforeEbbOffset: Double? = nil
    var floodTimeOffset: Double? = nil
    var ebbTimeOffset: Double? = nil
    var floodSpeedRatio: Double? = nil
    var ebbSpeedRatio: Double? = nil
    /// A non-primary bin carried only as a subordinate's reference (#269):
    /// harmonic shape, in `all` and `byId`, never in `StationItem.all`.
    var referenceOnly: Bool? = nil

    var isSubordinate: Bool { reference != nil }
    var referenceRecord: CurrentStationRecord? { reference.flatMap { CurrentStationRecord.byId[$0] } }

    var engineStation: any CurrentPredicting {
        engineStation(referenceRecord: referenceRecord)
    }

    func engineStation(referenceRecord: CurrentStationRecord?) -> any CurrentPredicting {
        guard reference != nil, let ref = referenceRecord else { return harmonicStation }
        return SubordinateStation(
            reference: ref.harmonicStation,
            slackBeforeFloodOffset: slackBeforeFloodOffset ?? 0, slackBeforeEbbOffset: slackBeforeEbbOffset ?? 0,
            floodTimeOffset: floodTimeOffset ?? 0, ebbTimeOffset: ebbTimeOffset ?? 0,
            floodSpeedRatio: floodSpeedRatio ?? 1, ebbSpeedRatio: ebbSpeedRatio ?? 1,
            floodDirection: floodDirection, ebbDirection: ebbDirection)
    }

    /// The constituent model itself; a CHS-fitted gate is always harmonic.
    var harmonicStation: CurrentStation {
        CurrentStation(constituents: constituents.map { HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) },
                       floodDirection: floodDirection, ebbDirection: ebbDirection, offset: meanFlow)
    }

    var tz: TimeZone { TimeZone(identifier: timezone) ?? .current }

    static let all: [CurrentStationRecord] = bundled("currents")
    static let byId: [String: CurrentStationRecord] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
}

/// What every current consumer needs: a harmonic `CurrentStation` or a
/// subordinate reduced from one, behind the same two calls.
protocol CurrentPredicting {
    func speeds(from: Date, to: Date, step: TimeInterval) -> [CurrentPoint]
    func events(from: Date, to: Date) -> [CurrentEvent]
}
extension CurrentStation: CurrentPredicting {}
extension SubordinateStation: CurrentPredicting {}

/// The set the water flows toward at signed velocity `v` — rectilinear pass
/// stations are bimodal, so the sign fixes the bearing (web chs/current.ts).
extension CurrentStationRecord {
    func setDegrees(signed: Double) -> Double { signed >= 0 ? floodDirection : ebbDirection }
}

enum CurrentPhase {
    case flood, ebb, slack

    /// "Flooding" / "Ebbing" / "Slack" — the phase pill's word.
    var word: String {
        switch self {
        case .flood: "Flooding"
        case .ebb: "Ebbing"
        case .slack: "Slack"
        }
    }

    /// Plain-word companion for non-sailors ("Flooding · incoming", #59).
    /// Rendered only where there's room — the detail heroes; tight surfaces
    /// lead with direction instead. Slack is nil: it is always glossed by
    /// "under 0.5 kn" at its render sites.
    var gloss: String? {
        switch self {
        case .flood: "incoming"
        case .ebb: "outgoing"
        case .slack: nil
        }
    }
}

func currentPhase(signed: Double) -> CurrentPhase {
    abs(signed) < slackKn ? .slack : signed > 0 ? .flood : .ebb
}


private let points16 = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

func compass16(_ deg: Double) -> String {
    let d = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    return points16[Int((d / 22.5).rounded()) % 16]
}

// Speed formatting lives in Theme.swift (formatSpeed(_:unit:)) — the engine
// always speaks knots; the display unit is the slackwater.speedUnit setting.

/// What a current list card shows: signed velocity now + the next slack/max.
struct CurrentCardState {
    let signed: Double
    let next: CurrentEvent?
}

extension CurrentStationRecord {
    func cardState(at now: Date) -> CurrentCardState {
        cardState(at: now, station: engineStation)
    }

    func cardState(at now: Date, station: any CurrentPredicting) -> CurrentCardState {
        let signed = station.speeds(from: now, to: now.addingTimeInterval(1), step: 1).first?.speed ?? 0
        // 30h forward guarantees a "next" exists, like the tide cards.
        let next = station.events(from: now, to: now.addingTimeInterval(30 * 3600)).first { $0.time > now }
        return CurrentCardState(signed: signed, next: next)
    }
}

extension CurrentEvent {
    /// "Slack" / "Max flood" / "Max ebb" — web StationCard TURN_LABEL.
    var turnLabel: String {
        switch kind {
        case .slack: "Slack"
        case .maxFlood: "Max flood"
        case .maxEbb: "Max ebb"
        }
    }
}

// MARK: - The mixed station list (tide + current, one search)

enum StationItem: Identifiable, Hashable {
    case tide(TideStationRecord)
    case current(CurrentStationRecord)
    case chs(ChsStationInfo)   // Canadian tide port: identity bundled, model fitted on-device
    case chsGate(ChsGateInfo)  // derived current gate: slack from a reference port's fitted tide
    case chsCurrent(ChsCurrentGateInfo)  // validated CHS gate: real velocities, fitted on-device

    /// The payload's shared identity — one switch, not one per field.
    var info: StationIdentity {
        switch self {
        case .tide(let s): s
        case .current(let s): s
        case .chs(let s): s
        case .chsGate(let s): s
        case .chsCurrent(let s): s
        }
    }

    var id: String {
        // Friday Harbor has both a tide and a current station.
        if case .current(let s) = self { return "current:" + s.id }
        return info.id
    }
    var name: String { info.name }
    var region: String { info.region }
    func searchRank(_ query: String) -> Int? { info.searchRank(query) }
    var latitude: Double { info.latitude }
    var longitude: Double { info.longitude }
    /// "Current · NOAA" — what this station measures and whose data it is.
    /// The matching-station chooser's disambiguator: when two entries share a
    /// name, series and provider are the difference that isn't distance.
    var kindLabel: String {
        switch self {
        case .tide: "Tide · NOAA"
        case .current: "Current · NOAA"
        case .chs: "Tide · CHS"
        case .chsGate, .chsCurrent: "Current · CHS"
        }
    }
    /// Map pin class per the design tokens: tide / current / chs. A derived
    /// gate is a current gate (web chsStations.ts: series "current").
    var pinKind: String {
        switch self {
        case .tide: "tide"
        case .current, .chsGate, .chsCurrent: "current"
        case .chs: "chs"
        }
    }
    /// Distance from a fix, in km.
    func km(fromLat lat: Double, lon: Double) -> Double {
        distanceKm(lat1: lat, lon1: lon, lat2: latitude, lon2: longitude)
    }

    /// The catalog ranked nearest first, one `km` per station.
    ///
    /// A comparator that calls `km` runs it twice per comparison — about
    /// 200,000 great-circle calls over the 7,400-station catalog, each one two
    /// `CLLocation` allocations. Ties break on catalog position so the order is
    /// total and deterministic: `StationGroups` reads the first station of a
    /// name as the nearest one.
    static func rankedByDistance(_ items: [StationItem],
                                 lat: Double, lon: Double) -> [StationItem] {
        var keyed: [(km: Double, rank: Int, item: StationItem)] = []
        keyed.reserveCapacity(items.count)
        for (rank, item) in items.enumerated() {
            keyed.append((item.km(fromLat: lat, lon: lon), rank, item))
        }
        keyed.sort { $0.km == $1.km ? $0.rank < $1.rank : $0.km < $1.km }
        return keyed.map(\.item)
    }

    /// All bundled stations, alphabetical. World coverage: no station is
    /// pinned to the head of the list — that read as a bug from anywhere but
    /// the Salish Sea.
    static let all: [StationItem] = {
        var merged: [StationItem] = TideStationRecord.all.map { StationItem.tide($0) }
        merged += CurrentStationRecord.all.filter { $0.referenceOnly != true }.map { StationItem.current($0) }
        merged += ChsStationInfo.all.map { StationItem.chs($0) }
        merged += ChsGateInfo.all.map { StationItem.chsGate($0) }
        merged += ChsCurrentGateInfo.all.map { StationItem.chsCurrent($0) }
        merged.sort { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        return merged
    }()

    /// Id → item, built once. Every row, every map-pin tap and every id→item
    /// lookup used to be `all.first(where:)`; at 41 stations that was free and
    /// at 3,125 it is a linear scan per row per render (M53).
    static let byId: [String: StationItem] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// Widget-safe lookup: decode only the requested large NOAA record; the
    /// three CHS identity catalogs are small enough to retain whole.
    static func widgetItem(
        id: String, locator: CatalogFileLocator = .shared
    ) -> StationItem? {
        locator.load { directory in try widgetItem(id: id, directory: directory) }
    }

    static func widgetItem(id: String, directory: URL) throws -> StationItem? {
        if id.hasPrefix("current:") {
            let record: CurrentStationRecord? = try catalogRecord(
                "currents", id: String(id.dropFirst("current:".count)), directory: directory)
            return record.map(StationItem.current)
        }
        if id.hasPrefix("chs-") {
            let stations: [ChsStationInfo] = try readCatalog("chs-stations", directory: directory)
            if let record = stations.first(where: { $0.id == id }) { return .chs(record) }
            let gates: [ChsGateInfo] = try readCatalog("chs-gates", directory: directory)
            if let record = gates.first(where: { $0.id == id }) { return .chsGate(record) }
            let currents: [ChsCurrentGateInfo] = try readCatalog("chs-current-gates", directory: directory)
            return currents.first(where: { $0.id == id }).map(StationItem.chsCurrent)
        }
        let record: TideStationRecord? = try catalogRecord("stations", id: id, directory: directory)
        return record.map(StationItem.tide)
    }

    /// How many results the search screen shows.
    ///
    /// This is the search change national scale actually forced. "port"
    /// matches 214 stations and "b" over a thousand; the old screen handed
    /// every one of them to a `ForEach`, so SwiftUI diffed a thousand rows per
    /// keystroke to show the six you can see. Sixty is more than anyone
    /// scrolls, and the screen says when it has truncated (M53).
    static let searchLimit = 60

    /// One lowercased UTF-8 key per station in `all`, built once: name, region
    /// and aliases joined by a byte no query can contain. A keystroke is one
    /// `memmem` per station — `String.contains` three times per station was
    /// 19.7 ms at 8,256 stations (#268) against the 16 ms frame budget. The
    /// first occurrence's position IS the rank, because name precedes region
    /// precedes aliases, the same order `searchRank` tries.
    struct SearchKey {
        let bytes: [UInt8]
        let regionStart: Int
        let aliasStart: Int
        init(_ s: StationIdentity) {
            let name = Array(s.name.lowercased().utf8), region = Array(s.region.lowercased().utf8)
            bytes = name + [1] + region + [1] + Array(s.aliases.joined(separator: "\u{1}").utf8)
            regionStart = name.count + 1
            aliasStart = regionStart + region.count + 1
        }
        func rank(_ q: [UInt8]) -> Int? {
            let offset: Int? = bytes.withUnsafeBufferPointer { b in
                q.withUnsafeBufferPointer { qb in
                    memmem(b.baseAddress, b.count, qb.baseAddress, qb.count)
                        .map { UnsafeRawPointer($0) - UnsafeRawPointer(b.baseAddress!) }
                }
            }
            guard let offset else { return nil }
            return offset < regionStart ? 0 : offset < aliasStart ? 1 : 2
        }
    }
    static let searchKeys: [SearchKey] = all.map { SearchKey($0.info) }

    /// Matches, best first. Rank is the web's (name > region > alias) and
    /// DISTANCE breaks the tie — the other thing national scale forces, since
    /// alphabetical order across 3,125 stations answers "port" in Boston with
    /// Alaska. Ties on distance break on id, so the order is total.
    ///
    /// A plain scan over prebuilt lowercased keys. Lowercasing three strings
    /// per station on every keystroke measured the same as an index at 3,125
    /// stations; at 8,256 (#268) it was 19.7 ms against the 16 ms frame, so
    /// the lowercasing moved to load time.
    /// `near` has no default on purpose: defaulting it to `firstRunFix` is the
    /// exact bug this branch exists to fix (search ranked from Victoria in the
    /// Solent), and a default would let a future caller reintroduce it by
    /// omission rather than by decision.
    static func search(_ query: String, near anchor: (lat: Double, lon: Double)) -> [StationItem] {
        let q = Array(query.trimmingCharacters(in: .whitespaces).lowercased().utf8)
        var ranked: [(item: StationItem, rank: Int, km: Double)] = []
        ranked.reserveCapacity(128)
        for (s, key) in zip(all, searchKeys) {
            guard let rank = q.isEmpty ? 0 : key.rank(q) else { continue }
            ranked.append((s, rank, s.km(fromLat: anchor.lat, lon: anchor.lon)))
        }
        ranked.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.km != $1.km { return $0.km < $1.km }
            return $0.item.id < $1.item.id
        }
        return ranked.prefix(searchLimit).map(\.item)
    }
}
