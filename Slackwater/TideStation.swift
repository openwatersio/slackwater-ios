// Slackwater — GPL v3. Bundled NOAA Salish tide stations (public domain data,
// same file slackwater-web ships, enriched with resolved names/regions/aliases
// from @sailingnaturali/station-corrections so both apps say the same thing).
import Foundation
import TideEngine

struct TideStationRecord: Decodable, Identifiable, Hashable, StationIdentity {
    let id: String
    let name: String
    let region: String
    let aliases: [String]
    let latitude: Double
    let longitude: Double
    let timezone: String
    let chartDatum: String
    let datumOffset: Double
    let constituents: [Con]

    var engineStation: Station {
        Station(constituents: constituents.map { HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) },
                offset: datumOffset)
    }

    var tz: TimeZone { TimeZone(identifier: timezone) ?? .current }

    static let fridayHarborID = "noaa/9449880"

    /// All bundled stations, Friday Harbor first, rest alphabetical.
    static let all: [TideStationRecord] = {
        let sorted: [TideStationRecord] = bundled("stations")
        return sorted.filter { $0.id == fridayHarborID } + sorted.filter { $0.id != fridayHarborID }
    }()
}

/// What a list card shows: height now, direction, next turn. Heights in metres.
struct CardState {
    let height: Double
    let rising: Bool
    let next: TideExtreme?
}

extension TideStationRecord {
    func cardState(at now: Date) -> CardState {
        let station = engineStation
        // 30h forward guarantees a "next" exists (web predicts ±30h for the same reason).
        let extremes = station.extremes(from: now, to: now.addingTimeInterval(30 * 3600))
        let next = extremes.first { $0.time > now }
        let height = station.heights(from: now, to: now.addingTimeInterval(1), step: 1).first?.height ?? 0
        // Direction from the next turn, not neighbouring samples (web tides.ts:
        // near a turn the curve is flat and sampling picks up numerical noise).
        let rising = next.map { $0.kind == .high } ?? true
        return CardState(height: height, rising: rising, next: next)
    }
}
