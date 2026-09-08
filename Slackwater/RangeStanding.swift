// Slackwater — GPL v3. Where the swing under the centerline sits among the
// tides either side of it (#217) — the facts behind the Range tile's sheet.
//
// No new astronomy. The constituents already carry spring/neap (M2⊕S2), the
// perigean beat (M2⊕N2) and the seasonal envelope (Sa, Ssa), plus whatever
// the local shallow water does to them. A king tide is a top-percentile low,
// so ranking `extremes()` finds one — including the local distortion a
// "new moon plus perigee" rule would miss.
//
// The scan is a year of extremes. Expensive, and run ONCE off the main actor
// when the sheet opens; nothing here is on the scrub path.
//
// **Two gates, and they are not the same gate.** `latDatum`/`hatDatum` is the
// agency's published 19-year envelope — the absolute yardstick.
// `resolvesTheYear` is whether THIS station's constituents carry a seasonal
// term, which is what makes a year-long ranking mean anything. 228 bundled
// stations have the first and not the second, and 2 have the second and not
// the first. Read them separately or a station will claim what it cannot see.
import Foundation
import TideEngine

/// Where one number sits among the same kind of number around it. `rank` is
/// the fraction of the window at or below `value` — read from the bottom for
/// a low, from the top for a high or a swing.
struct Standing: Sendable {
    let value: Double
    let rank: Double
    /// The window's own record of this kind, and when it falls.
    let recordValue: Double
    let recordTime: Date
    /// The next one out in the remarkable tail — the next big low, the next
    /// big swing. Nil when the rest of the window holds none.
    let nextValue: Double?
    let nextTime: Date?
    /// The last time the water went past `value` in the remarkable direction.
    /// Nil means nothing in the window did: this is the lowest low, or the
    /// biggest swing, since the window opened.
    let previousTime: Date?
}

/// One metric's samples across the window, in time order.
typealias TideSeries = [(time: Date, value: Double)]

/// `lower` picks which end is remarkable: a low's record is the minimum and
/// its tail the bottom 5%, a high's and a swing's are the maximum and the top.
///
/// The tail is a percentile of THIS station's own window, never an absolute
/// height — 5% of Friday Harbor's lows and 5% of Ile Haute's are both "the
/// big ones here", which is the only comparison a reader standing on one
/// beach can use.
func standing(of value: Double, in series: TideSeries, at now: Date,
              lower: Bool, tail: Double = 0.05) -> Standing? {
    let values = series.map(\.value)
    guard let rank = values.percentileRank(of: value),
          let threshold = values.percentile(lower ? tail : 1 - tail),
          let record = lower ? series.min(by: { $0.value < $1.value })
                             : series.max(by: { $0.value < $1.value })
    else { return nil }

    let remarkable: (Double) -> Bool = lower ? { $0 <= threshold } : { $0 >= threshold }
    let beyond: (Double) -> Bool = lower ? { $0 < value } : { $0 > value }
    let next = series.first { $0.time > now && remarkable($0.value) }
    return Standing(value: value, rank: rank,
                    recordValue: record.value, recordTime: record.time,
                    nextValue: next?.value, nextTime: next?.time,
                    previousTime: series.last { $0.time < now && beyond($0.value) }?.time)
}

/// Everything the Range sheet says, computed once.
struct RangeFacts: Sendable {
    /// The swing the centerline stands in — the turn behind it to the turn
    /// ahead, the same pair the Range tile already shows.
    let swing: TideRange
    /// That swing's low against the window's lows, its high against the
    /// highs, and the swing itself against the window's swings. Three
    /// rankings because a station can have a big range on a day whose low is
    /// unremarkable, and the reader digging clams cares about only one.
    let low: Standing?
    let high: Standing?
    let range: Standing?
    /// The window actually scanned. The copy says "since March" and has to be
    /// able to name the month it means.
    let from: Date
    let to: Date
    /// True when the window is a year and the constituents can see one.
    let yearly: Bool
}

extension TideStationRecord {
    /// Half-width of the ranking window. Six months either side when the model
    /// resolves the year; thirty days when it does not, which is every CHS
    /// station (a 60-day fit) and 233 NOAA references besides. A seasonless
    /// model ranked over a year returns an envelope narrowed by the Sa+Ssa it
    /// never fitted — and returns it confidently, which is the failure mode
    /// worth spending a narrower window to avoid.
    var rankingWindowMonths: Int { resolvesTheYear ? 6 : 1 }

    /// Rank the swing at `at` against the tides either side of it. Nil when
    /// the window holds no complete swing — a station whose predictor returns
    /// nothing, which the callers already treat as "no card".
    ///
    /// `nonisolated` and `Sendable`-clean throughout: the caller runs this in
    /// a detached task, because a year of extremes is ~35 ms of release-build
    /// arithmetic and the sheet animates in over it.
    func rangeFacts(at: Date, station: any TidePredicting) -> RangeFacts? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let months = rankingWindowMonths
        guard let from = cal.date(byAdding: .month, value: -months, to: at),
              let to = cal.date(byAdding: .month, value: months, to: at)
        else { return nil }

        let extremes = station.extremes(from: from, to: to)
        let ranges = extremes.ranges()
        // The swing you are standing in is the first one still to complete:
        // `TideRange.time` is its later turn. Matches the Range tile exactly.
        guard let swing = ranges.first(where: { $0.time > at }) else { return nil }

        let lows: TideSeries = extremes.filter { $0.kind == .low }.map { ($0.time, $0.height) }
        let highs: TideSeries = extremes.filter { $0.kind == .high }.map { ($0.time, $0.height) }
        let swings: TideSeries = ranges.map { ($0.time, $0.height) }

        return RangeFacts(
            swing: swing,
            low: standing(of: swing.low.height, in: lows, at: at, lower: true),
            high: standing(of: swing.high.height, in: highs, at: at, lower: false),
            range: standing(of: swing.height, in: swings, at: at, lower: false),
            from: from, to: to, yearly: resolvesTheYear)
    }
}

/// The sentence a `Standing` becomes: "97% of lows this year go lower", or the
/// superlative when nothing in the window goes past it.
///
/// Free rather than a method on the view, because its polarity is the one
/// thing here that is easy to get backwards and impossible to eyeball. `rank`
/// is the fraction at or BELOW, so a low reads it straight and a high or a
/// swing reads its complement.
///
/// Phrased as a count of what goes past — never "lower than 3% of lows", which
/// reads both ways (is this in the bottom 3%, or is only 3% below it?) and
/// lands a reader on the wrong one about half the time.
func standingSentence(_ s: Standing, lower: Bool, noun: String, verb: String,
                      span: String) -> String {
    // The record check runs against the window's own extreme rather than a
    // look-back, so a low that nothing beats still reads as "the lowest low"
    // when the record itself is still ahead of the scrub.
    if abs(s.value - s.recordValue) < 0.001 {
        let superlative = noun == "swing" ? "biggest" : lower ? "lowest" : "highest"
        return "the \(superlative) \(noun) \(span)"
    }
    // Ties count as at-or-below, so this overstates by one member out of the
    // window's ~1,400 — under a twentieth of the percent it is rounded to.
    let share = Int(((lower ? s.rank : 1 - s.rank) * 100).rounded())
    return "\(share)% of \(noun)s \(span) \(verb)"
}
