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
    /// The station's seasonal swing is larger than its principal tide: a Great
    /// Lakes gauge, a river reach, a Baltic bodden. The database decides
    /// this (`quality.seasonal_dominant`) so the app and slackwater.xyz cannot
    /// describe the same water two ways; the detail view decides what to say.
    ///
    /// Optional for the same reason `reference` is: gen-tides writes it into
    /// stations.json only where it is true, and a non-optional `Bool` would make
    /// the synthesized decoder demand the key on all 4,409 records that omit it.
    var seasonalDominant: Bool? = nil
    /// The floor and ceiling of this station's predictions, in metres above its
    /// chart datum — the same frame as `TideExtreme.height`, so they compare
    /// against a predicted extreme directly.
    ///
    /// Optional for the reason the fields above are, and because absence is a
    /// real state rather than a gap: the database withholds LAT and HAT where
    /// Sa and Ssa are both zero amplitude, since a seasonless constituent set
    /// narrows the envelope instead of bounding it. That is every CHS on-device
    /// fit and about a fifth of NOAA's harmonic references. `nil` means the
    /// station cannot support an absolute claim; `0.0` means its floor IS chart
    /// datum, which is true of 887 shipped stations — so nothing may read a
    /// missing value as zero.
    var latDatum: Double? = nil
    var hatDatum: Double? = nil
    /// The publisher of the constants, named as the database names it. Read
    /// from the tcdb only; stations.json does not carry it.
    var source: String? = nil

    var isSubordinate: Bool { reference != nil }

    /// Above this, the yearly swing is not merely comparable to the tide, it is
    /// the signal — so the detail view leads with it rather than footnoting it.
    ///
    /// 3 is where the bundle turns into rivers, lakes and lagoons: Rochester on
    /// Lake Ontario at 147x, Algonac on the St Clair at 55x. Below it are Gulf,
    /// Carolina and Baltic water with a real tide and a comparable seasonal
    /// swing, such as Cedar Island at 1.8, where "mostly seasonal" would be
    /// false in effect while true in arithmetic. slackwater.xyz splits at the
    /// same place, which is the point: the flag is the database's and the
    /// loudness has to agree too.
    static let seasonalLeadRatio = 3.0

    /// How many times the seasonal curve's peak exceeds the principal tide, for
    /// a flagged station: the ratio the database's `seasonal_dominant` flag is
    /// set on (slackwater-database docs/database-format.md). Any other ratio,
    /// such as the larger of Sa and Ssa over the largest single constituent,
    /// disagrees with the flag. Infinite where the principal tide is zero, which
    /// the database labels too. Computed rather than stored: the bundle carries
    /// the verdict as one bit and the constituents are already here.
    ///
    /// Measured on the model the station predicts from, which for a subordinate
    /// is its reference's — it ships none of its own, and reading its empty list
    /// would drop a flagged subordinate into the quieter band by accident.
    var seasonalRatio: Double? {
        guard seasonalDominant == true else { return nil }
        let model = constituents.isEmpty ? referenceRecord?.constituents ?? [] : constituents
        let peak = seasonalPeak(model)
        let principal = TideStationRecord.principalConstituents.reduce(0) { sum, name in
            sum + abs(model.first { $0.name == name }?.amplitude ?? 0)
        }
        guard principal > 0 else { return peak > 0 ? .infinity : nil }
        return peak / principal
    }

    /// The database's `PRINCIPAL_TIDAL_CONSTITUENTS`: their amplitudes sum to
    /// the tide's height when spring and tropic tides coincide.
    private static let principalConstituents = ["M2", "S2", "K1", "O1"]

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

/// The largest departure of the seasonal curve Sa·cos(θ − g) + Ssa·cos(2θ − g)
/// from mean level over a year, as slackwater-database's `seasonalPeak` takes
/// it: half-degree steps, and each term under every name the sources use.
/// Kartverket's SA_KV is referenced to perihelion (argument h − p′), so its
/// phase moves by p′ = 283.4° to read on SA's clock.
func seasonalPeak(_ model: [Con]) -> Double {
    let term = { (names: [String]) in model.first { names.contains($0.name) } }
    let annual = term(["SA", "Sa"]) ?? term(["SA_KV"]).map {
        Con(name: $0.name, amplitude: $0.amplitude, phase: ($0.phase + 283.4).truncatingRemainder(dividingBy: 360))
    }
    let semiannual = term(["SSA", "Ssa"])
    let rad = Double.pi / 180
    return (0..<720).reduce(0) { peak, step in
        let theta = Double(step) / 2
        let level = (annual.map { $0.amplitude * cos((theta - $0.phase) * rad) } ?? 0)
            + (semiannual.map { $0.amplitude * cos((2 * theta - $0.phase) * rad) } ?? 0)
        return max(peak, abs(level))
    }
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
/// Finite ratios only: an infinite one has no multiple to state.
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
protocol TidePredicting: Sendable {
    func heights(from: Date, to: Date, step: TimeInterval) -> [TidePoint]
    func rates(from: Date, to: Date, step: TimeInterval) -> [TideRatePoint]
    func extremes(from: Date, to: Date) -> [TideExtreme]
}
extension Station: TidePredicting {}
extension SubordinateTideStation: TidePredicting {}
extension ChsTidePreview: TidePredicting {}

/// How far ahead a card looks for its next turn. 30h guarantees one wherever
/// the tide turns by at least the engine's 1 cm (web predicts ±30h for the
/// same reason).
let TIDE_NEXT_TURN_REACH: TimeInterval = 30 * 3600

/// The heights a gauge draws between, or nil unless `prev` and `next` are a
/// low and a high and `next` is the turn the direction points at. Two searches
/// over different windows can return turns of one kind, or disagree with the
/// direction, where the engine's extremes depend on the window
/// (slackwater#436); no gauge beats one with a high for its low.
func tideGaugeBounds(prev: TideExtreme, next: TideExtreme, rising: Bool) -> (lo: Double, hi: Double)? {
    guard prev.kind != next.kind, (next.kind == .high) == rising else { return nil }
    return (min(prev.height, next.height), max(prev.height, next.height))
}

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
        let extremes = station.extremes(from: now, to: now.addingTimeInterval(TIDE_NEXT_TURN_REACH))
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
