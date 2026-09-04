// Slackwater — GPL v3. Bundled NOAA Salish current stations (public domain
// data, the same file slackwater-web ships as currents.json, enriched with
// resolved names/regions/aliases from @sailingnaturali/station-corrections —
// harmonic stations only, primary bin, exactly the web's bundle).
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

/// A bundled JSON station catalog, name-sorted; missing or undecodable → empty.
func bundled<T: Decodable & StationIdentity>(_ resource: String) -> [T] {
    guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let items = try? JSONDecoder().decode([T].self, from: data) else { return [] }
    return items.sorted { $0.name < $1.name }
}

/// Decode one record without materializing a multi-megabyte catalog in a
/// memory-limited extension.
/// ponytail: relies on generated compact JSON keeping `id` first; add an
/// offset index if that catalog format changes.
func bundled<T: Decodable & StationIdentity>(_ resource: String, id: String) -> T? {
    guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
          let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    let marker = Data("{\"id\":\"".utf8) + Data(id.utf8) + Data("\"".utf8)
    guard let start = data.range(of: marker)?.lowerBound,
          let arrayEnd = data.lastIndex(of: 93) else { return nil }
    let separator = Data(",{\"id\":".utf8)
    let afterMarker = data.index(start, offsetBy: marker.count)
    let end = data.range(of: separator, in: afterMarker..<data.endIndex)?.lowerBound ?? arrayEnd
    return try? JSONDecoder().decode(T.self, from: data[start..<end])
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

    var engineStation: CurrentStation {
        CurrentStation(constituents: constituents.map { HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) },
                       floodDirection: floodDirection, ebbDirection: ebbDirection, offset: meanFlow)
    }

    var tz: TimeZone { TimeZone(identifier: timezone) ?? .current }

    static let all: [CurrentStationRecord] = bundled("currents")
}

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
        let station = engineStation
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

    /// All bundled stations, alphabetical. World coverage: no station is
    /// pinned to the head of the list — that read as a bug from anywhere but
    /// the Salish Sea.
    static let all: [StationItem] = {
        var merged: [StationItem] = TideStationRecord.all.map { StationItem.tide($0) }
        merged += CurrentStationRecord.all.map { StationItem.current($0) }
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
    static func widgetItem(id: String) -> StationItem? {
        if id.hasPrefix("current:") {
            let record: CurrentStationRecord? = bundled(
                "currents", id: String(id.dropFirst("current:".count)))
            return record.map { .current($0) }
        }
        if id.hasPrefix("chs-") {
            if let record = ChsStationInfo.all.first(where: { $0.id == id }) { return .chs(record) }
            if let record = ChsGateInfo.all.first(where: { $0.id == id }) { return .chsGate(record) }
            return ChsCurrentGateInfo.all.first(where: { $0.id == id }).map { .chsCurrent($0) }
        }
        let record: TideStationRecord? = bundled("stations", id: id)
        return record.map { .tide($0) }
    }

    /// How many results the search screen shows.
    ///
    /// This is the search change national scale actually forced. "port"
    /// matches 214 stations and "b" over a thousand; the old screen handed
    /// every one of them to a `ForEach`, so SwiftUI diffed a thousand rows per
    /// keystroke to show the six you can see. Sixty is more than anyone
    /// scrolls, and the screen says when it has truncated (M53).
    static let searchLimit = 60

    /// Matches, best first. Rank is the web's (name > region > alias) and
    /// DISTANCE breaks the tie — the other thing national scale forces, since
    /// alphabetical order across 3,125 stations answers "port" in Boston with
    /// Alaska. Ties on distance break on id, so the order is total.
    ///
    /// ponytail: a plain scan, no index. Lowercasing three strings per station
    /// measured the same as a prebuilt lowercased index at 3,125 stations
    /// (~6 ms per keystroke, debug simulator), and the index was 35 lines of
    /// cache that moved no number.
    /// `near` has no default on purpose: defaulting it to `firstRunFix` is the
    /// exact bug this branch exists to fix (search ranked from Victoria in the
    /// Solent), and a default would let a future caller reintroduce it by
    /// omission rather than by decision.
    static func search(_ query: String, near anchor: (lat: Double, lon: Double)) -> [StationItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var ranked: [(item: StationItem, rank: Int, km: Double)] = []
        ranked.reserveCapacity(128)
        for s in all {
            guard let rank = q.isEmpty ? 0 : s.searchRank(q) else { continue }
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
