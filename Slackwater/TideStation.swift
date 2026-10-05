// Slackwater — GPL v3. Bundled tide stations, named and placed by the station
// database so the app and slackwater.xyz say the same thing.
import Foundation
import SlackwaterKit

struct TideStationRecord: Codable, Identifiable, Hashable, StationIdentity {
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
    /// The station's yearly swing is larger than its largest tidal constituent:
    /// a Great Lakes gauge, a river reach, a Baltic bodden. The database decides
    /// this (`quality.seasonal_dominant`) so the app and slackwater.xyz cannot
    /// describe the same water two ways; the detail view decides what to say.
    ///
    /// Optional for the same reason `reference` is: gen-tides writes it into
    /// stations.json only where it is true, and a non-optional `Bool` would make
    /// the synthesized decoder demand the key on all 4,409 records that omit it.
    var seasonalDominant: Bool? = nil

    var isSubordinate: Bool { reference != nil }

    /// Above this, the yearly swing is not merely comparable to the tide, it is
    /// the signal — so the detail view leads with it rather than footnoting it.
    ///
    /// 3 is where the bundle turns into rivers, lakes and lagoons: Rochester on
    /// Lake Ontario at 273x, Algonac on the St Clair at 100x. Below it are Gulf
    /// and Chesapeake ports with a real tide and a comparable annual signal, and
    /// Annapolis is why the line is not at 1 — it carries the database's flag at
    /// 1.008 and calling that "mostly seasonal" would be false in effect while
    /// true in arithmetic. slackwater.xyz splits at the same place, which is the
    /// point: the flag is the database's and the loudness has to agree too.
    static let seasonalLeadRatio = 3.0

    /// How many times the yearly swing exceeds the largest tidal constituent,
    /// for a flagged station. Computed rather than stored: the bundle carries
    /// the database's verdict as one bit and the constituents are already here,
    /// so a second field would be a second thing to keep in step.
    ///
    /// Measured on the model the station predicts from, which for a subordinate
    /// is its reference's — it ships none of its own, and reading its empty list
    /// would drop a flagged subordinate into the quieter band by accident.
    var seasonalRatio: Double? {
        guard seasonalDominant == true else { return nil }
        let model = constituents.isEmpty ? referenceRecord?.constituents ?? [] : constituents
        let amplitude = { (name: String) in
            abs(model.first { $0.name == name }?.amplitude ?? 0)
        }
        let seasonal = max(amplitude("SA"), amplitude("SSA"))
        let tidal = TideStationRecord.tidalConstituents.map(amplitude).max() ?? 0
        guard tidal > 0 else { return nil }
        return seasonal / tidal
    }

    /// The constituents that are the tide itself, mirroring the database's own
    /// list. The minor terms are not padding: at some flagged stations the
    /// largest tidal constituent is one of them, and dropping them would inflate
    /// the ratio and make those screens overstate their case.
    private static let tidalConstituents = [
        "M2", "S2", "N2", "K2", "L2", "T2", "NU2", "MU2", "2N2", "LDA2",
        "K1", "O1", "P1", "Q1", "J1", "M1", "OO1", "RHO1", "2Q1", "SIGMA1",
        "CHI1", "PI1", "PHI1", "THETA1", "S1",
    ]
    var referenceRecord: TideStationRecord? { reference.flatMap(TideStationRecord.record(id:)) }

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
}

/// The Range tile's caption where the water is seasonal: two words standing in
/// for the swing's direction, graded by how far the tide has been left behind.
/// The sheet behind the tile carries the rest.
func seasonalCaption(_ ratio: Double) -> String {
    ratio >= TideStationRecord.seasonalLeadRatio
        ? String(localized: "mostly seasonal", comment: "Tide-range caption where the yearly cycle dwarfs the daily tide.")
        : String(localized: "partly seasonal", comment: "Tide-range caption where the yearly cycle rivals the daily tide.")
}

/// A seasonal ratio as a screen says it: rounded to a ten once there is a ten
/// to round to, so the number reads as the estimate "about" promises. 43.3 is
/// "about 40", not "about 43", which invites a reader to trust a figure that
/// came out of a constituent fit. slackwater.xyz rounds identically.
func seasonalTimes(_ ratio: Double) -> String {
    let rounded = ratio >= 10 ? (ratio / 10).rounded() * 10 : (ratio * 10).rounded() / 10
    return rounded.formatted(.number.grouping(.automatic))
}

/// Minutes and metres (or a ratio), exactly as NOAA publishes them.
struct TideOffsets: Codable, Hashable {
    struct Time: Codable, Hashable { let high: Double; let low: Double }
    struct Height: Codable, Hashable { let type: String; let high: Double; let low: Double }
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
extension ChsTidePreview: TidePredicting {}

/// What a list card shows: height now, direction, next turn. Heights in metres.
struct CardState {
    let height: Double
    let rising: Bool
    let next: TideExtreme?
}

extension TideStationRecord {
    var detailsDatum: String {
        if isChs { return String(localized: "LLWLT (CHS chart datum)", comment: "Station-detail datum. Keep LLWLT and CHS exact.") }
        if id.hasPrefix("noaa/") { return String(localized: "\(chartDatum) (NOAA chart datum)", comment: "Station-detail datum. The value is a datum acronym; keep NOAA exact.") }
        return String(localized: "\(chartDatum) chart datum", comment: "Station-detail datum. The value is a datum acronym.")
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
        let rising = next.map { $0.kind == .high } ?? (station as? ChsTidePreview).map { $0.rateOfChange(at: now) >= 0 } ?? true
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
