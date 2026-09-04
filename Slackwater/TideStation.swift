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
    /// Subordinate station (#229): NOAA time and height corrections against a
    /// bundled reference, and no constituents of its own — the generator
    /// guarantees the reference ships (tools/gen-tides.mjs, isSubordinate).
    var reference: String? = nil
    var offsets: TideOffsets? = nil

    var isSubordinate: Bool { reference != nil }
    var referenceRecord: TideStationRecord? { reference.flatMap { TideStationRecord.byId[$0] } }

    var engineStation: any TidePredicting {
        engineStation(referenceRecord: referenceRecord)
    }

    func engineStation(referenceRecord: TideStationRecord?) -> any TidePredicting {
        guard let offsets, let ref = referenceRecord else { return harmonicStation }
        let h = offsets.height
        return SubordinateTideStation(
            reference: ref.harmonicStation,
            highTimeOffset: offsets.time.high * 60, lowTimeOffset: offsets.time.low * 60,
            height: h.type == "fixed" ? .fixed(high: h.high, low: h.low) : .ratio(high: h.high, low: h.low))
    }

    /// The constituent model itself. A CHS-fitted port is always harmonic, and
    /// a derived gate lags its extremes directly.
    var harmonicStation: Station {
        Station(constituents: constituents.map { HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) },
                offset: datumOffset)
    }

    var tz: TimeZone { TimeZone(identifier: timezone) ?? .current }

    /// A Salish Sea station kept only as a stable, well-known id for tests —
    /// no longer pinned to the head of the list (world coverage: a home-water
    /// courtesy that reads as a bug from anywhere else).
    static let fridayHarborID = "noaa/9449880"

    /// All bundled stations, alphabetical.
    static let all: [TideStationRecord] = bundled("stations")
    static let byId: [String: TideStationRecord] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
}

/// Minutes and metres (or a ratio), exactly as NOAA publishes them.
struct TideOffsets: Decodable, Hashable {
    struct Time: Decodable, Hashable { let high: Double; let low: Double }
    struct Height: Decodable, Hashable { let type: String; let high: Double; let low: Double }
    let time: Time
    let height: Height
}

/// What every tide consumer needs: a harmonic `Station` or a subordinate
/// reduced from one, behind the same three calls.
protocol TidePredicting {
    func heights(from: Date, to: Date, step: TimeInterval) -> [TidePoint]
    func rates(from: Date, to: Date, step: TimeInterval) -> [TideRatePoint]
    func extremes(from: Date, to: Date) -> [TideExtreme]
}
extension Station: TidePredicting {}
extension SubordinateTideStation: TidePredicting {}

/// What a list card shows: height now, direction, next turn. Heights in metres.
struct CardState {
    let height: Double
    let rising: Bool
    let next: TideExtreme?
}

extension TideStationRecord {
    var detailsDatum: String {
        if isChs { return "LLWLT (CHS chart datum)" }
        if id.hasPrefix("noaa/") { return "\(chartDatum) (NOAA chart datum)" }
        return "\(chartDatum) chart datum"
    }

    func cardState(at now: Date) -> CardState {
        cardState(at: now, station: engineStation)
    }

    func cardState(at now: Date, station: any TidePredicting) -> CardState {
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

extension TidePredicting {
    /// dh/dt at `t` in metres/hour — the rate-of-rise readout (#95 part 1).
    /// The engine's analytic derivative (v0.4.0), same evaluation the strip's
    /// rate ramp draws from.
    func rateOfChange(at t: Date) -> Double {
        rates(from: t, to: t.addingTimeInterval(1), step: 1).first?.rate ?? 0
    }
}
