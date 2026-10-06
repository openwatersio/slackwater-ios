// Slackwater — GPL v3. Every swing in the fortnight, as a bar on a time axis.
//
// This answers "is this swing beyond normal here", and the honest answer is a
// shape rather than a number: swing size beats with springs and neaps, so a
// swing standing near a peak of that beat IS a spring tide and the picture says
// so without a sentence. A first attempt drew the same ranking as a strip of
// ticks sorted by size; it had no shape to read and was dropped.
//
// It also places the next bigger swing, which is the fact worth tapping — a
// reader who has just learned this one is big immediately asks when the next
// one comes.
import SwiftUI
import SlackwaterKit

struct SwingFigure: View {
    struct Bar: Equatable {
        /// Centre of the bar, points from the left edge.
        let x: CGFloat
        /// Points, measured up from the baseline.
        let height: CGFloat
        let isSelected: Bool
        let isNextBigger: Bool
    }

    let standing: SwingStanding
    /// The station's own zone: the days this aggregates are the station's,
    /// never the device's.
    var tz: TimeZone = .current
    var onJump: ((Date) -> Void)? = nil

    /// One bar per whole station-local day, carrying that day's biggest swing.
    ///
    /// Per-day rather than per-swing because the fortnightly beat is what
    /// answers "beyond normal", and every swing buries it: rises and falls
    /// alternate large and small four times a day, against a beat that turns
    /// over a fortnight. On real Friday Harbor predictions the daily maximum
    /// runs 1.8 → 3.7 → 1.9 → 3.0 → 1.8 ft across the window and the beat is
    /// plain; the 99-swing series is noise.
    ///
    /// Only whole days. The window runs local midnight to local midnight, so
    /// anything after its last midnight is a fragment — 0.1 ft at Friday
    /// Harbor — and would draw as a bar collapsed to nothing at the edge.
    ///
    /// One scale for every bar: the biggest day fills the box and the rest are
    /// their true fraction of it. Auto-fitting each bar to itself is exactly
    /// the defect #97 found in the strip.
    static func bars(_ standing: SwingStanding, tz: TimeZone, size: CGSize) -> [Bar] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var biggestOfDay: [Date: TideRange] = [:]
        for r in standing.all {
            let day = cal.startOfDay(for: r.time)
            guard day >= standing.window.start,
                  let next = cal.date(byAdding: .day, value: 1, to: day), next <= standing.window.end
            else { continue }
            if r.height > (biggestOfDay[day]?.height ?? -.infinity) { biggestOfDay[day] = r }
        }
        let days = biggestOfDay.keys.sorted()
        guard let biggest = biggestOfDay.values.map(\.height).max(), biggest > 0,
              days.count > 1 else { return [] }
        let selectedDay = cal.startOfDay(for: standing.selectedTime)
        let nextDay = standing.nextBigger.map { cal.startOfDay(for: $0.time) }
        // Half a bar's margin at each end so neither is clipped by the edge.
        let step = size.width / CGFloat(days.count)
        return days.enumerated().map { i, day in
            Bar(x: step * (CGFloat(i) + 0.5),
                height: size.height * CGFloat(biggestOfDay[day]!.height / biggest),
                isSelected: day == selectedDay,
                isNextBigger: day == nextDay && day != selectedDay)
        }
    }

    private let boxHeight: CGFloat = 108

    var body: some View {
        Canvas { ctx, size in
            let baseline = size.height
            for bar in Self.bars(standing, tz: tz,
                                 size: CGSize(width: size.width, height: size.height - 12)) {
                var path = Path()
                path.move(to: CGPoint(x: bar.x, y: baseline))
                path.addLine(to: CGPoint(x: bar.x, y: baseline - bar.height))
                // The beat is the message, so the crowd is drawn as texture and
                // only the two bars a reader acts on carry full weight.
                ctx.stroke(path, with: .color(SN.graphLine.opacity(bar.isSelected ? 1 : 0.34)),
                           lineWidth: bar.isSelected ? 3.2 : 2)
                if bar.isSelected {
                    CurveDrawing.dot(ctx, at: CGPoint(x: bar.x, y: baseline - bar.height), color: SN.graphLine)
                }
                if bar.isNextBigger {
                    var tick = Path()
                    tick.move(to: CGPoint(x: bar.x, y: baseline - bar.height - 10))
                    tick.addLine(to: CGPoint(x: bar.x, y: baseline - bar.height - 3))
                    ctx.stroke(tick, with: .color(SN.foam.opacity(0.5)))
                }
            }
        }
        .frame(height: boxHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The shape is unavailable to VoiceOver, so the ranking is said outright.
    private var spoken: String {
        let bigger = standing.all.filter { $0.height > standing.selectedHeight }.count
        return bigger == 0
            ? String(localized: "The biggest swing of the fortnight.",
                     comment: "VoiceOver for the swing figure.")
            : String(localized: "Bigger than all but \(bigger) of this fortnight's \(standing.all.count) swings.",
                     comment: "VoiceOver for the swing figure. Both values are counts of tide swings.")
    }
}
