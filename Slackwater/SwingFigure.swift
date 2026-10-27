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
        /// The day's biggest peak: what a finger lifted on this bar goes to.
        let peak: Peak
        let isSelected: Bool
        let isNextBigger: Bool
    }

    let standing: PeakStanding
    /// The station's own zone: the days this aggregates are the station's,
    /// never the device's.
    var tz: TimeZone = .current
    /// Where a finger lifted on a bar goes: that bar's own peak, the same
    /// contract as the "next bigger" caption. Nil leaves the bars inert.
    var onJump: ((Date) -> Void)? = nil
    /// A bar's magnitude as the sheet prints it, unit included ("10.6 ft",
    /// "3.2 kn"). The figure ranks sizes without knowing what they measure,
    /// so the sheet that does supplies the words. Nil draws no label.
    var format: ((Double) -> String)? = nil

    /// The bar under the finger, by index into `bars`, while a finger is down.
    @State private var lit: Int? = nil
    /// The canvas width, for finding the bar under an x outside the draw call.
    @State private var width: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    /// Touch means "go there", so with nowhere to go there is nothing to touch.
    var respondsToTouch: Bool { onJump != nil }

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
    static func dailyPeaks(_ standing: PeakStanding, tz: TimeZone) -> [Peak] {
        dailyPeaks(standing.all, tz: tz, window: standing.window)
    }

    static func dailyPeaks(_ peaks: [Peak], tz: TimeZone,
                           window: (start: Date, end: Date)) -> [Peak] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var biggestOfDay: [Date: Peak] = [:]
        for peak in peaks {
            let day = cal.startOfDay(for: peak.time)
            guard day >= window.start,
                  let next = cal.date(byAdding: .day, value: 1, to: day), next <= window.end
            else { continue }
            if peak.magnitude > (biggestOfDay[day]?.magnitude ?? -.infinity) { biggestOfDay[day] = peak }
        }
        return biggestOfDay.keys.sorted().compactMap { biggestOfDay[$0] }
    }

    static func bars(_ standing: PeakStanding, tz: TimeZone, size: CGSize) -> [Bar] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let peaks = dailyPeaks(standing, tz: tz)
        let days = peaks.map { cal.startOfDay(for: $0.time) }
        guard let biggest = peaks.map(\.magnitude).max(), biggest > 0,
              days.count > 1 else { return [] }
        let selectedDay = cal.startOfDay(for: standing.selected.time)
        let nextDay = standing.nextBigger.map { cal.startOfDay(for: $0.time) }
        // Half a bar's margin at each end so neither is clipped by the edge.
        let step = size.width / CGFloat(days.count)
        return days.enumerated().map { i, day in
            Bar(x: step * (CGFloat(i) + 0.5),
                height: size.height * CGFloat(peaks[i].magnitude / biggest),
                peak: peaks[i],
                isSelected: day == selectedDay,
                isNextBigger: day == nextDay && day != selectedDay)
        }
    }

    /// The bar under an x, by the same layout `bars` uses. Clamped, so a drag
    /// that leaves the canvas still holds the nearest edge bar.
    static func barIndex(atX x: CGFloat, count: Int, width: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        let step = width / CGFloat(count)
        return min(max(Int(floor(x / step)), 0), count - 1)
    }

    /// Room above the tallest bar for the lit bar's label, which sits on top
    /// of a bar that may already fill the box.
    private let headroom: CGFloat = 28
    private let boxHeight: CGFloat = 124

    private var bars: [Bar] {
        Self.bars(standing, tz: tz, size: CGSize(width: width, height: boxHeight - headroom))
    }

    var body: some View {
        Canvas { ctx, size in
            let baseline = size.height
            let bars = Self.bars(standing, tz: tz,
                                 size: CGSize(width: size.width, height: size.height - headroom))
            for (i, bar) in bars.enumerated() {
                let isLit = i == lit
                var path = Path()
                path.move(to: CGPoint(x: bar.x, y: baseline))
                path.addLine(to: CGPoint(x: bar.x, y: baseline - bar.height))
                // The beat is the message, so the crowd is drawn as texture and
                // only the bars a reader acts on carry full weight.
                ctx.stroke(path, with: .color(SN.graphLine.opacity(bar.isSelected || isLit ? 1 : 0.34)),
                           lineWidth: bar.isSelected || isLit ? 3.2 : 2)
                if bar.isSelected || isLit {
                    CurveDrawing.dot(ctx, at: CGPoint(x: bar.x, y: baseline - bar.height), color: SN.graphLine)
                }
                if bar.isNextBigger {
                    var tick = Path()
                    tick.move(to: CGPoint(x: bar.x, y: baseline - bar.height - 10))
                    tick.addLine(to: CGPoint(x: bar.x, y: baseline - bar.height - 3))
                    ctx.stroke(tick, with: .color(SN.foam.opacity(0.5)))
                }
                if isLit, let format {
                    // The day and its size, over the finger. Kept inside the
                    // canvas at either edge rather than centred and clipped.
                    var label = ctx.resolve(
                        Text("\(monthDay(bar.peak.time, tz)) · \(format(bar.peak.magnitude))")
                            .font(.caption2.monospacedDigit()))
                    label.shading = .color(SN.foam)
                    let half = label.measure(in: size).width / 2
                    let x = min(max(bar.x, half), size.width - half)
                    ctx.draw(label, at: CGPoint(x: x, y: baseline - bar.height - 12), anchor: .bottom)
                }
            }
        }
        .frame(height: boxHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .gesture(slide, including: respondsToTouch ? .all : .none)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// A finger on the bars lights the one under it; lifting goes there and
    /// closes the sheet. Zero distance so the first touch already lights,
    /// and a tick each time the lit bar changes so a slide reads as steps.
    private var slide: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let i = Self.barIndex(atX: value.location.x, count: bars.count, width: width)
                guard i != lit else { return }
                lit = i
                UISelectionFeedbackGenerator().selectionChanged()
            }
            .onEnded { _ in
                if let i = lit, bars.indices.contains(i) {
                    onJump?(bars[i].peak.time)
                    dismiss()
                }
                lit = nil
            }
    }

    /// The shape is unavailable to VoiceOver, so the ranking is said outright.
    private var spoken: String {
        let bigger = standing.all.filter { $0.magnitude > standing.selected.magnitude }.count
        return bigger == 0
            ? String(localized: "The biggest swing of the fortnight.",
                     comment: "VoiceOver for the swing figure.")
            : String(localized: "Bigger than all but \(bigger) of this fortnight's \(standing.all.count) swings.",
                     comment: "VoiceOver for the swing figure. Both values are counts of tide swings.")
    }
}
