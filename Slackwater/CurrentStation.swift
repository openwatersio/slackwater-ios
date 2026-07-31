// Slackwater — GPL v3. Bundled NOAA Salish current stations (public domain
// data, the same file slackwater-web ships as currents.json, enriched with
// resolved names/regions/aliases from @sailingnaturali/station-corrections —
// harmonic stations only, primary bin, exactly the web's bundle).
import Foundation
import TideEngine

/// Below this magnitude the water reads "Slack", not a direction (web chs/current.ts SLACK_KN).
let slackKn = 0.15

struct CurrentStationRecord: Decodable, Identifiable, Hashable {
    struct Con: Decodable, Hashable { let name: String; let amplitude: Double; let phase: Double }
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

    /// The paired reference tide port, resolved to its bundled record.
    var pairedTide: TideStationRecord? {
        tideReference.flatMap { id in TideStationRecord.all.first { $0.id == id } }
    }

    var engineStation: CurrentStation {
        CurrentStation(constituents: constituents.map { HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) },
                       floodDirection: floodDirection, ebbDirection: ebbDirection, offset: meanFlow)
    }

    var tz: TimeZone { TimeZone(identifier: timezone) ?? .current }

    static let all: [CurrentStationRecord] = {
        guard let url = Bundle.main.url(forResource: "currents", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let stations = try? JSONDecoder().decode([CurrentStationRecord].self, from: data) else { return [] }
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

/// The set the water flows toward at signed velocity `v` — rectilinear pass
/// stations are bimodal, so the sign fixes the bearing (web chs/current.ts).
extension CurrentStationRecord {
    func setDegrees(signed: Double) -> Double { signed >= 0 ? floodDirection : ebbDirection }
}

enum CurrentPhase { case flood, ebb, slack }

func currentPhase(signed: Double) -> CurrentPhase {
    abs(signed) < slackKn ? .slack : signed > 0 ? .flood : .ebb
}

func phaseWord(_ phase: CurrentPhase) -> String {
    switch phase {
    case .flood: "Flooding"
    case .ebb: "Ebbing"
    case .slack: "Slack"
    }
}

private let points16 = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

func compass16(_ deg: Double) -> String {
    let d = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    return points16[Int((d / 22.5).rounded()) % 16]
}

/// Velocity is always knots — the ft/m setting is heights only, like the web's
/// separate speedUnit preference (which defaults to kn; only kn ships here).
func formatSpeed(_ knots: Double) -> String {
    let v = abs(knots) < 0.05 ? abs(knots) : knots
    return String(format: "%.1f", v)
}

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

    var id: String {
        switch self {
        case .tide(let s): s.id
        case .current(let s): "current:" + s.id  // Friday Harbor has both a tide and a current station
        case .chs(let s): s.id
        }
    }
    var name: String {
        switch self {
        case .tide(let s): s.name
        case .current(let s): s.name
        case .chs(let s): s.name
        }
    }
    var region: String {
        switch self {
        case .tide(let s): s.region
        case .current(let s): s.region
        case .chs(let s): s.region
        }
    }
    func searchRank(_ query: String) -> Int? {
        switch self {
        case .tide(let s): s.searchRank(query)
        case .current(let s): s.searchRank(query)
        case .chs(let s): s.searchRank(query)
        }
    }
    var latitude: Double {
        switch self {
        case .tide(let s): s.latitude
        case .current(let s): s.latitude
        case .chs(let s): s.latitude
        }
    }
    var longitude: Double {
        switch self {
        case .tide(let s): s.longitude
        case .current(let s): s.longitude
        case .chs(let s): s.longitude
        }
    }
    /// Map pin class per the design tokens: tide / current / chs.
    var pinKind: String {
        switch self {
        case .tide: "tide"
        case .current: "current"
        case .chs: "chs"
        }
    }
    /// Distance from a fix, in km.
    func km(fromLat lat: Double, lon: Double) -> Double {
        distanceKm(lat1: lat, lon1: lon, lat2: latitude, lon2: longitude)
    }

    /// All bundled stations, Friday Harbor (tide) first, rest alphabetical.
    static let all: [StationItem] = {
        var merged: [StationItem] = TideStationRecord.all.map { StationItem.tide($0) }
        merged += CurrentStationRecord.all.map { StationItem.current($0) }
        merged += ChsStationInfo.all.map { StationItem.chs($0) }
        merged.sort { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        guard let friday = merged.first(where: { $0.id == TideStationRecord.fridayHarborID }) else { return merged }
        return [friday] + merged.filter { $0.id != friday.id }
    }()

    static func search(_ query: String) -> [StationItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return all }
        var ranked: [(item: StationItem, rank: Int)] = []
        for s in all {
            if let rank = s.searchRank(q) { ranked.append((s, rank)) }
        }
        ranked.sort { $0.rank == $1.rank ? $0.item.name < $1.item.name : $0.rank < $1.rank }
        return ranked.map(\.item)
    }
}
