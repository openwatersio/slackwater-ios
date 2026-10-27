// Slackwater — GPL v3. When this station sees its extremes, across the year.
//
// The third question the Range sheet answers, and the only one that genuinely
// needs the annual constituent. "Is this swing beyond normal" and "where does
// this turn sit between the station's ends" both resolve inside a fortnight;
// "when does the water here run biggest" is a seasonal fact, and a constituent
// set with Sa and Ssa at zero would return twelve confident months that all
// look alike. So this section is absent — not flat, absent — wherever the
// station has no astronomical bounds, which is every CHS fit.
//
// A calendar question, so a time axis rather than a level axis: the envelope
// the monthly extremes trace, and the months worth planning around.
import SwiftUI
import SlackwaterKit
import Almanac

struct YearFigure: View {
    struct Month: Equatable {
        /// Local midnight on the first of the month.
        let start: Date
        let highest: Double
        let lowest: Double
        var span: Double { highest - lowest }
    }

    /// Which pair of the year's turning points a station's widest months sit
    /// nearer: the solstices, where the day's two tides are most unequal, or
    /// the equinoxes, where a semidiurnal tide runs biggest.
    enum SeasonPair { case solstices, equinoxes }

    let months: [Month]
    let now: Date
    var tz: TimeZone = .current
    var imperial = false
    /// The solstices and equinoxes around the window: the sun's declination
    /// is what shapes the year, so they are ruled where they fall. Searched
    /// wider than the window so `follows` scores an edge month against its
    /// true nearest; only those inside the months are drawn.
    var seasons: [SeasonEvent] = []

    /// One entry per whole calendar month inside `window`, carrying the
    /// highest high and lowest low that month reaches.
    /// `series` is signed values over time: tide heights above chart datum, or
    /// current speeds with flood positive and ebb negative. Either way the
    /// month's envelope is its largest value and its smallest, and the shape
    /// the year traces is the same question.
    nonisolated static func months(_ series: [Peak], tz: TimeZone,
                       window: (start: Date, end: Date),
                       calendar: Calendar = .current) -> [Month] {
        var cal = calendar
        cal.timeZone = tz
        var highs: [Date: Double] = [:], lows: [Date: Double] = [:]
        for e in series {
            guard e.time >= window.start, e.time < window.end,
                  let month = cal.date(from: cal.dateComponents([.year, .month], from: e.time))
            else { continue }
            highs[month] = Swift.max(highs[month] ?? -.infinity, e.magnitude)
            lows[month] = Swift.min(lows[month] ?? .infinity, e.magnitude)
        }
        return highs.keys.sorted().compactMap { m in
            guard let hi = highs[m], let lo = lows[m], hi > lo else { return nil }
            return Month(start: m, highest: hi, lowest: lo)
        }
    }

    /// The months a reader would plan around: where the water runs widest.
    /// Two of them, because the tide's seasonal structure is semi-annual at
    /// most stations — a pair of peaks, not one.
    nonisolated static func standout(_ months: [Month]) -> [Month] {
        Array(months.sorted { $0.span > $1.span }.prefix(2))
    }

    /// The solstices and equinoxes six months either side of a window, or
    /// none where Almanac cannot say.
    nonisolated static func seasonsAround(_ window: (start: Date, end: Date), tz: TimeZone) -> [SeasonEvent] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        guard let from = cal.date(byAdding: .month, value: -6, to: window.start),
              let to = cal.date(byAdding: .month, value: 6, to: window.end) else { return [] }
        return (try? Almanac.seasons(from: from, to: to)) ?? []
    }

    /// How many days the two standout months' midpoints sit from the nearest
    /// solstice, summed, against the same for the equinoxes. Months resolve
    /// only to their midpoint, so the sums step in month-sized jumps; a 50-day
    /// band is what lets a station between kinds (May/November at 71 against
    /// 112, February/August at 69 against 114) make no claim while the months
    /// beside a turning point (April/October at 51 against 132) still decide.
    /// 50 rather than 45 because February/August sits 44.65 apart at Friday
    /// Harbor in 2026 and a station three hours east, or another year, would
    /// have tipped it over.
    nonisolated static func follows(months: [Month], seasons: [SeasonEvent], tz: TimeZone) -> SeasonPair? {
        let marked = standout(months)
        guard marked.count == 2, !seasons.isEmpty else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        func nearest(_ month: Month, _ kinds: Set<SeasonKind>) -> Double {
            let mid = cal.date(byAdding: DateComponents(day: 15, hour: 12), to: month.start) ?? month.start
            return seasons.filter { kinds.contains($0.kind) }
                .map { abs($0.time.timeIntervalSince(mid)) / 86_400 }.min() ?? .infinity
        }
        let toSolstice = marked.map { nearest($0, [.juneSolstice, .decemberSolstice]) }
        let toEquinox = marked.map { nearest($0, [.marchEquinox, .septemberEquinox]) }
        let solstices = toSolstice.reduce(0, +), equinoxes = toEquinox.reduce(0, +)
        guard solstices.isFinite, equinoxes.isFinite, abs(solstices - equinoxes) > 50 else { return nil }
        // Each month must itself sit nearer the winning kind: August and
        // December sum to solstices, but "Widest around August, near the
        // solstice" would be false, and so would VoiceOver's "widest in
        // December and August, near the solstices".
        let pair: SeasonPair = solstices < equinoxes ? .solstices : .equinoxes
        let agree = zip(toSolstice, toEquinox).allSatisfy { s, e in pair == .solstices ? s < e : e < s }
        return agree ? pair : nil
    }

    /// Where a season falls on the month axis: inside its month's cell, the
    /// fraction of the month elapsed. Nil when its month is not drawn.
    nonisolated static func seasonX(_ event: SeasonEvent, months: [Month], tz: TimeZone, step: CGFloat) -> CGFloat? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        guard let i = months.lastIndex(where: { $0.start <= event.time }),
              let next = cal.date(byAdding: .month, value: 1, to: months[i].start),
              event.time < next else { return nil }
        let fraction = event.time.timeIntervalSince(months[i].start) / next.timeIntervalSince(months[i].start)
        return step * (CGFloat(i) + CGFloat(fraction))
    }

    private let boxHeight: CGFloat = 120

    var body: some View {
        Canvas { ctx, size in
            guard let lo = months.map(\.lowest).min(), let hi = months.map(\.highest).max(),
                  hi > lo, months.count > 1 else { return }
            let span = hi - lo
            let step = size.width / CGFloat(months.count)
            func y(_ v: Double) -> CGFloat { size.height - CGFloat((v - lo) / span) * size.height }
            func x(_ i: Int) -> CGFloat { step * (CGFloat(i) + 0.5) }

            var upper = Path(), lower = Path()
            for (i, m) in months.enumerated() {
                let p = CGPoint(x: x(i), y: y(m.highest)), q = CGPoint(x: x(i), y: y(m.lowest))
                i == 0 ? upper.move(to: p) : upper.addLine(to: p)
                i == 0 ? lower.move(to: q) : lower.addLine(to: q)
            }
            var band = upper
            band.addLine(to: CGPoint(x: x(months.count - 1), y: y(months.last!.lowest)))
            for (i, m) in months.enumerated().reversed() {
                band.addLine(to: CGPoint(x: x(i), y: y(m.lowest)))
            }
            band.closeSubpath()
            ctx.fill(band, with: .color(SN.graphLine.opacity(0.1)))
            ctx.stroke(upper, with: .color(SN.graphHigh), lineWidth: 1.8)
            ctx.stroke(lower, with: .color(SN.graphLow), lineWidth: 1.8)

            // The year's turning points, ruled where they fall inside their
            // months, so the envelope's peaks can be read against them.
            for event in seasons {
                guard let sx = Self.seasonX(event, months: months, tz: tz, step: step),
                      let i = months.lastIndex(where: { $0.start <= event.time }) else { continue }
                let m = months[i]
                var rule = Path()
                rule.move(to: CGPoint(x: sx, y: y(m.highest) - 6))
                rule.addLine(to: CGPoint(x: sx, y: y(m.lowest) + 6))
                ctx.stroke(rule, with: .color(SN.foam.opacity(0.28)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            // Where the reader is standing on the year.
            if let i = months.lastIndex(where: { $0.start <= now }) {
                var here = Path()
                here.move(to: CGPoint(x: x(i), y: 0))
                here.addLine(to: CGPoint(x: x(i), y: size.height))
                ctx.stroke(here, with: .color(SN.graphLine), lineWidth: 1.6)
            }
            // One initial per month, so the axis reads as a year at a glance.
            for (i, m) in months.enumerated() {
                var t = ctx.resolve(Text(monthInitial(m.start, tz: tz)).font(.system(size: 8.5)))
                t.shading = .color(SN.foam.opacity(0.35))
                ctx.draw(t, at: CGPoint(x: x(i), y: size.height - 2), anchor: .bottom)
            }
        }
        .frame(height: boxHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// Named months, because a shape cannot be spoken.
    private var spoken: String {
        let names = Self.standout(months).map { monthName($0.start, tz: tz) }
        guard let first = names.first else { return "" }
        let widest = names.count < 2
            ? String(localized: "The water here runs widest in \(first).",
                     comment: "VoiceOver for the year figure. The value is a month name.")
            : String(localized: "The water here runs widest in \(first) and \(names[1]).",
                     comment: "VoiceOver for the year figure. Both values are month names.")
        switch Self.follows(months: months, seasons: seasons, tz: tz) {
        case .solstices:
            return widest + " " + String(localized: "Near the solstices.", comment: "VoiceOver for the year figure.")
        case .equinoxes:
            return widest + " " + String(localized: "Near the equinoxes.", comment: "VoiceOver for the year figure.")
        case nil:
            return widest
        }
    }
}

/// A month's single initial, for the figure's axis.
func monthInitial(_ date: Date, tz: TimeZone) -> String {
    let f = DateFormatter()
    f.timeZone = tz
    f.setLocalizedDateFormatFromTemplate("MMMMM")
    return f.string(from: date)
}

/// A month's name, for the sentence beneath the figure and for VoiceOver.
func monthName(_ date: Date, tz: TimeZone) -> String {
    let f = DateFormatter()
    f.timeZone = tz
    f.setLocalizedDateFormatFromTemplate("MMMM")
    return f.string(from: date)
}
