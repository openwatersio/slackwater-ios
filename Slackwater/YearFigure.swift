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

struct YearFigure: View {
    struct Month: Equatable {
        /// Local midnight on the first of the month.
        let start: Date
        let highest: Double
        let lowest: Double
        var span: Double { highest - lowest }
    }

    let months: [Month]
    let now: Date
    var tz: TimeZone = .current
    var imperial = false

    /// One entry per whole calendar month inside `window`, carrying the
    /// highest high and lowest low that month reaches.
    static func months(_ extremes: [TideExtreme], tz: TimeZone,
                       window: (start: Date, end: Date),
                       calendar: Calendar = .current) -> [Month] {
        var cal = calendar
        cal.timeZone = tz
        var highs: [Date: Double] = [:], lows: [Date: Double] = [:]
        for e in extremes {
            guard e.time >= window.start, e.time < window.end,
                  let month = cal.date(from: cal.dateComponents([.year, .month], from: e.time))
            else { continue }
            highs[month] = Swift.max(highs[month] ?? -.infinity, e.height)
            lows[month] = Swift.min(lows[month] ?? .infinity, e.height)
        }
        return highs.keys.sorted().compactMap { m in
            guard let hi = highs[m], let lo = lows[m], hi > lo else { return nil }
            return Month(start: m, highest: hi, lowest: lo)
        }
    }

    /// The months a reader would plan around: where the water runs widest.
    /// Two of them, because the tide's seasonal structure is semi-annual at
    /// most stations — the equinoxes, not one peak.
    static func standout(_ months: [Month]) -> [Month] {
        Array(months.sorted { $0.span > $1.span }.prefix(2))
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

            // The months worth planning around, named where they stand.
            let marked = Self.standout(months)
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            for m in marked {
                guard let i = months.firstIndex(where: { $0.start == m.start }) else { continue }
                var rule = Path()
                rule.move(to: CGPoint(x: x(i), y: y(m.highest) - 6))
                rule.addLine(to: CGPoint(x: x(i), y: y(m.lowest) + 6))
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
        if names.count < 2 {
            return String(localized: "The water here runs widest in \(first).",
                          comment: "VoiceOver for the year figure. The value is a month name.")
        }
        return String(localized: "The water here runs widest in \(first) and \(names[1]).",
                      comment: "VoiceOver for the year figure. Both values are month names.")
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
