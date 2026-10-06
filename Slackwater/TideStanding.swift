// Slackwater — GPL v3. Where one high or low sits among the tides around it.
//
// The engine ranks (`Ranking.swift`: `percentileRank`, `ranges()`); this decides
// what a ranking MEANS on a screen. Two judgements live here and nowhere else:
// the window a tide is judged against, and how far into the tail it has to sit
// before saying so is worth the reader's attention.
import Foundation
import SlackwaterKit

struct TideStanding {
    /// The extreme being judged.
    let selected: TideExtreme
    /// Its position among the window's same-kind extremes, 0…1. For a high,
    /// larger is more remarkable; for a low, smaller is. Ties count as below,
    /// so the window's lowest low ranks 1/count and never 0 — nothing here may
    /// test for an exact 0.
    let rank: Double
    let windowHighest: TideExtreme
    let windowLowest: TideExtreme
    /// The next same-kind extreme, after this one, that beats it. Nil when
    /// nothing ahead in the window does — which is the fact worth printing.
    let nextMoreExtreme: TideExtreme?

    /// Half-width of the comparison window, in calendar days either side.
    ///
    /// Fifteen rather than a calendar month: a superlative that blinks out at
    /// midnight on the 1st is worse than one with longer copy, and on the 30th
    /// a reader cares about the fortnight ahead, not the one ending tomorrow.
    ///
    /// Thirty days also needs no annual constituent. M2, S2, N2, K1 and O1, and
    /// the fortnightly and perigean beats between them, all resolve inside the
    /// 60-day CHS fit, so this ranking holds at every station — unlike the
    /// absolute claims, which need Sa or Ssa and are gated on the bounds.
    static let halfWindowDays = 15

    /// How far into the tail an extreme sits before it is worth marking.
    ///
    /// A fortnight holds about 29 highs, so the top tenth is roughly the three
    /// of one spring series: two or three marked days per fortnight. Lower this
    /// and the mark is on screen more often than not, which is the failure the
    /// whole feature exists to avoid — a mark that is usually true says
    /// nothing. `testTheMarkStaysRare` is what holds the line.
    static let markThreshold = 0.9

    var isWindowExtreme: Bool { nextMoreExtreme == nil }

    var marks: Bool {
        selected.kind == .high ? rank >= Self.markThreshold : rank <= 1 - Self.markThreshold
    }

    /// Calendar days in the station's own zone. A local day is 23 or 25 hours
    /// across a DST transition, so this cannot be arithmetic on seconds.
    static func window(around date: Date, tz: TimeZone,
                       calendar: Calendar = .current) -> (start: Date, end: Date) {
        var cal = calendar
        cal.timeZone = tz
        let day = cal.startOfDay(for: date)
        return (cal.date(byAdding: .day, value: -halfWindowDays, to: day) ?? date,
                cal.date(byAdding: .day, value: halfWindowDays, to: day) ?? date)
    }

    /// Nil when the window cannot support a ranking: fewer than two same-kind
    /// extremes, or no high or no low to bound the band with.
    static func at(_ selected: TideExtreme, among extremes: [TideExtreme]) -> TideStanding? {
        let kin = extremes.filter { $0.kind == selected.kind }
        guard kin.count > 1,
              let rank = kin.map(\.height).percentileRank(of: selected.height),
              let highest = extremes.filter({ $0.kind == .high }).max(by: { $0.height < $1.height }),
              let lowest = extremes.filter({ $0.kind == .low }).min(by: { $0.height < $1.height })
        else { return nil }
        // Forward in time only: the question a reader asks of a big tide is
        // when the next bigger one arrives, not when the last one was.
        let beats = { (e: TideExtreme) in
            selected.kind == .high ? e.height > selected.height : e.height < selected.height
        }
        return TideStanding(
            selected: selected, rank: rank,
            windowHighest: highest, windowLowest: lowest,
            nextMoreExtreme: kin.filter { $0.time > selected.time && beats($0) }
                .min { $0.time < $1.time })
    }
}
