// Slackwater — GPL v3. The tidal plane ladder (#217) — Chart No. 1's "Tidal
// Levels and Charted Data" plate, for one station at one moment.
//
// The plate does two jobs: a ladder of tidal planes at true relative spacing,
// and a set of depth and clearance annotations hung off it. Only the first is
// here. We have no bathymetry and no structures, and drawing a seabed we do
// not know would invent data on the one page whose whole job is saying which
// numbers can be trusted.
//
// What the plate cannot do and this can: it is THIS station, and the water is
// where the scrubber is standing. The spacing is the information — a reader
// sees this low sitting a third of the way down toward the floor without
// reading a percentile off anything.
//
// Plain words lead and the acronym follows, because "Lowest tide" needs no
// glossary and LAT does. Two words are deliberately NOT used:
//
//   * "recorded" — HAT and LAT are not observations. They are the ceiling and
//     the floor of the ASTRONOMY over a 19-year nodal cycle, and a storm surge
//     goes straight over the top of one.
//   * "possible" — measured over 150 stations, a single year's lowest low
//     lands below the published LAT at 5% of them (by at most 1.6 cm; the
//     median year sits 4.2 cm inside it). Published LAT is on the agency's own
//     tidal epoch and these predictions are for this year, so the two disagree
//     slightly by construction. A rung labelled "possible" sitting above a low
//     the app itself predicts is a visible contradiction; "Lowest tide" beside
//     "Lowest this year" reads as the long-run figure against the near one and
//     survives the centimetre.
import Foundation
import TideEngine

struct LadderRung: Identifiable, Sendable {
    enum Kind {
        /// A published tidal plane — the agency's number.
        case plane
        /// Chart datum: the zero every height in this app is quoted against.
        case datum
        /// The window's own record, and a moment the scrubber can reach.
        case record
        /// One end of the swing the centerline stands in.
        case swing
        /// The water right now.
        case now
    }
    var id: String { name }
    let height: Double
    /// Plain words. This is what the reader reads.
    let name: String
    /// The acronym, if the plane has one. Secondary, and never alone.
    let code: String?
    let kind: Kind
    /// Non-nil when tapping the row should scrub there.
    var jump: Date? = nil
}

/// The ladder, top to bottom. Heights are metres above chart datum — the same
/// zero `TideExtreme.height` uses, so nothing here needs rebasing.
///
/// Rungs are dropped, never faked. A station with no published envelope has no
/// ceiling and no floor; a subordinate has no mean sea level of its own (its
/// `datumOffset` is 0 because the reference's is what applies, and drawing
/// that would put MSL exactly on chart datum, which is a lie about a real
/// station rather than a gap).
func tideLadder(record: TideStationRecord, facts: RangeFacts, nowHeight: Double) -> [LadderRung] {
    let span = facts.yearly ? "this year" : "this month"
    var rungs: [LadderRung] = [
        LadderRung(height: nowHeight, name: "Now", code: nil, kind: .now),
        LadderRung(height: 0, name: "Chart datum", code: record.chartDatum, kind: .datum),
        LadderRung(height: facts.swing.high.height, name: "This high", code: nil,
                   kind: .swing, jump: facts.swing.high.time),
        LadderRung(height: facts.swing.low.height, name: "This low", code: nil,
                   kind: .swing, jump: facts.swing.low.time),
    ]
    if let high = facts.high {
        rungs.append(LadderRung(height: high.recordValue, name: "Highest \(span)",
                                code: nil, kind: .record, jump: high.recordTime))
    }
    if let low = facts.low {
        rungs.append(LadderRung(height: low.recordValue, name: "Lowest \(span)",
                                code: nil, kind: .record, jump: low.recordTime))
    }
    if let hat = record.hatDatum {
        rungs.append(LadderRung(height: hat, name: "Highest tide", code: "HAT", kind: .plane))
    }
    if let lat = record.latDatum {
        rungs.append(LadderRung(height: lat, name: "Lowest tide", code: "LAT", kind: .plane))
    }
    // A subordinate's datumOffset is 0 by construction, and a station charted
    // on MSL has one of 0 honestly — both would land this rung on top of chart
    // datum, so neither gets it.
    if !record.isSubordinate, record.datumOffset != 0 {
        rungs.append(LadderRung(height: record.datumOffset, name: "Average sea level",
                                code: "MSL", kind: .plane))
    }

    // Highest first. Two rungs on the same water are one rung: at the 887
    // stations charted on LAT the floor IS chart datum, and drawing both would
    // read as a rendering bug rather than as the fact it is. Earlier in the
    // array wins, so `Now` and `Chart datum` outrank a plane they coincide with.
    var seen: [Double] = []
    return rungs.filter { rung in
        guard !seen.contains(where: { abs($0 - rung.height) < 0.001 }) else { return false }
        seen.append(rung.height)
        return true
    }.sorted { $0.height > $1.height }
}
