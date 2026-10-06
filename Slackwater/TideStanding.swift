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

    /// Twelve whole calendar months around a date, in the station's own zone.
    ///
    /// Whole months rather than six months either side of the day: a window cut
    /// mid-month leaves a half-month at each end whose extremes are shallower
    /// than that month's really are, which draws as a seasonal signal that is
    /// only an artefact of where the cut fell.
    static func yearWindow(around date: Date, tz: TimeZone,
                           calendar: Calendar = .current) -> (start: Date, end: Date) {
        var cal = calendar
        cal.timeZone = tz
        let month = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        let start = cal.date(byAdding: .month, value: -6, to: month) ?? date
        return (start, cal.date(byAdding: .month, value: 12, to: start) ?? date)
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

/// Where one swing sits among the swings around it.
///
/// Separate from `TideStanding` because they are different judgements about
/// different quantities, and a station can have a big swing on a day whose low
/// is unremarkable. The Range tile prints a swing, so the Range tile ranks a
/// swing; the levels question belongs to its own section of the sheet.
struct SwingStanding {
    /// Every swing in the window, in time order — the figure draws all of them.
    let all: [TideRange]
    /// The swing being judged, carried so the figure can mark it without being
    /// handed the same two values a second time.
    let selectedHeight: Double
    let selectedTime: Date
    /// This swing's position among them, 0…1.
    let rank: Double
    /// The next swing, after this one, that goes further.
    let nextBigger: TideRange?
    /// The window these swings came from. The figure needs it to tell a whole
    /// local day from the fragment after the window's last midnight.
    let window: (start: Date, end: Date)

    var marks: Bool { rank >= TideStanding.markThreshold }
    var isWindowBiggest: Bool { nextBigger == nil && rank >= 1 }

    /// `nil` when the window holds too few swings to rank one against.
    static func at(_ height: Double, time: Date, among extremes: [TideExtreme],
                   window: (start: Date, end: Date)) -> SwingStanding? {
        let all = extremes.ranges()
        guard all.count > 1, let rank = all.map(\.height).percentileRank(of: height) else { return nil }
        return SwingStanding(
            all: all, selectedHeight: height, selectedTime: time, rank: rank,
            nextBigger: all.filter { $0.time > time && $0.height > height }.min { $0.time < $1.time },
            window: window)
    }
}

/// One line of the sheet. `jumpTo` non-nil makes it a button that moves the
/// scrubber, the way a tapped Moon fact already does.
struct StandingFact: Equatable {
    let text: String
    var jumpTo: Date? = nil
}

/// What the sheet says beneath the figure.
///
/// The figure carries the comparison; these put numbers and names on it. Two
/// tiers, and the second is absent rather than zeroed at a station whose
/// constituents cannot bound a year — which is every CHS fit and about a fifth
/// of NOAA's references. `latDatum` of exactly 0.0 is a floor, not a gap: 887
/// shipped stations have one, because their chart datum IS LAT.
func standingFacts(_ standing: TideStanding, latDatum: Double?, hatDatum: Double?,
                   imperial: Bool, unit: String, tz: TimeZone, now: Date,
                   calendar: Calendar = .current) -> [StandingFact] {
    var cal = calendar
    cal.timeZone = tz
    let low = standing.selected.kind == .low
    var out: [StandingFact] = []

    if let next = standing.nextMoreExtreme {
        // Calendar days in the station's zone, as `onlineDownloadValidity`
        // counts them — "in 12 days" across a DST change is still 12 days.
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: standing.selected.time),
                                      to: cal.startOfDay(for: next.time)).day ?? 0
        out.append(StandingFact(
            text: low
                ? String(localized: "The next lower low is in \(days) days.",
                         comment: "Sheet fact. The integer is a number of calendar days; vary by plural.")
                : String(localized: "The next higher high is in \(days) days.",
                         comment: "Sheet fact. The integer is a number of calendar days; vary by plural."),
            jumpTo: next.time))
    } else {
        out.append(StandingFact(text: low
            ? String(localized: "The lowest low of the fortnight.",
                     comment: "Sheet fact: nothing within fifteen days either side goes lower.")
            : String(localized: "The highest high of the fortnight.",
                     comment: "Sheet fact: nothing within fifteen days either side goes higher.")))
    }

    // The end that matters: under a low it is the floor — how much water could
    // still go away — and under a high it is the ceiling.
    if low, let latDatum {
        out.append(StandingFact(text: gapSentence(standing.selected.height - latDatum,
                                                  low: true, imperial: imperial, unit: unit)))
    } else if !low, let hatDatum {
        out.append(StandingFact(text: gapSentence(hatDatum - standing.selected.height,
                                                  low: false, imperial: imperial, unit: unit)))
    }
    return out
}

/// The distance to the station's own floor or ceiling, as a sentence.
///
/// Its own function, declared on one line, because TypeScaleTests' scanner
/// attributes a `formatHeight(` call to the nearest declaration line that ENDS
/// in a brace — and `standingFacts`' signature does not fit on one. The
/// exception it registers has to name a symbol the scanner actually computes.
private func gapSentence(_ gap: Double, low: Bool, imperial: Bool, unit: String) -> String {
    low
        ? String(localized: "\(formatHeight(gap, imperial: imperial)) \(unit) above the lowest water this station ever sees.",
                 comment: "Sheet fact. Values are a formatted height and its unit.")
        : String(localized: "\(formatHeight(gap, imperial: imperial)) \(unit) below the highest water this station ever sees.",
                 comment: "Sheet fact. Values are a formatted height and its unit.")
}

/// The Range tile's one caption line, in precedence order.
///
/// Three things want this line and only one fits. Seasonal first: at a lake or
/// a river reach, "this number is not really a tide" outranks "this one is
/// big", and a reader who does not know the first will misread the second.
/// Then the standing, the rarer and more useful fact. Then the direction, which
/// is the lesser fact — the curve and the schedule both already show it.
func rangeCaption(record: TideStationRecord, swing: SwingStanding?, direction: String) -> String {
    if let ratio = record.seasonalRatio { return seasonalCaption(ratio) }
    guard let swing, swing.marks else { return direction }
    return swing.isWindowBiggest
        ? String(localized: "the fortnight's biggest",
                 comment: "Tide-range caption: no swing within fifteen days either side goes further.")
        : String(localized: "beyond normal here",
                 comment: "Tide-range caption: this swing is far larger than this station's usual.")
}
