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
    var onJump: ((Date) -> Void)? = nil

    /// One scale for every bar — the fortnight's biggest swing fills the box,
    /// and every other bar is its true fraction of that. Auto-fitting each bar
    /// to itself is exactly the defect #97 found in the strip.
    static func bars(_ standing: SwingStanding, size: CGSize) -> [Bar] {
        let all = standing.all
        guard let biggest = all.map(\.height).max(), biggest > 0,
              let first = all.first?.time, let last = all.last?.time,
              last > first else { return [] }
        let seconds = last.timeIntervalSince(first)
        // Half a bar's margin at each end so the first and last are not clipped
        // by the edge of the canvas.
        let inset = size.width / CGFloat(Swift.max(all.count, 1)) / 2
        let usable = Swift.max(size.width - inset * 2, 1)
        return all.map { r in
            Bar(x: inset + usable * CGFloat(r.time.timeIntervalSince(first) / seconds),
                height: size.height * CGFloat(r.height / biggest),
                isSelected: r.time == standing.selectedTime,
                isNextBigger: r.time == standing.nextBigger?.time)
        }
    }

    private let boxHeight: CGFloat = 108

    var body: some View {
        Canvas { ctx, size in
            let baseline = size.height
            for bar in Self.bars(standing, size: CGSize(width: size.width, height: size.height - 12)) {
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
