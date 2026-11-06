// Slackwater — GPL v3. The line a watch complication draws, shared so the
// Premium sheet's example is the same drawing and not a copy of it.
import SwiftUI

let complicationPastOpacity = 0.35

/// The line over `hours`, scaled to its own extremes (and zero, for a
/// current), dim before now, thick where a current is slack, with a dot at now.
/// Tinted faces get thickness alone; `fullColor` also gets the app's slack colour.
struct ComplicationLineCanvas: View {
    let reading: ComplicationReading
    let hours: ClosedRange<Double>
    let fullColor: Bool

    var body: some View {
        Canvas { context, size in
            let pts = reading.samples.filter { hours.contains($0.hours) }
            guard pts.count > 1 else { return }
            var lo = pts.map(\.value).min()!, hi = pts.map(\.value).max()!
            if reading.kind == .current { lo = min(lo, 0); hi = max(hi, 0) }
            if hi - lo < 1e-6 { hi = lo + 1 }
            let x = { (h: Double) in (h - hours.lowerBound) / (hours.upperBound - hours.lowerBound) * size.width }
            let y = { (v: Double) in size.height - (v - lo) / (hi - lo) * size.height }
            let line = max(2, size.height * 0.08)
            func path(_ part: [ComplicationReading.Sample]) -> Path {
                var p = Path()
                for (i, s) in part.enumerated() {
                    let pt = CGPoint(x: x(s.hours), y: y(s.value))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                return p
            }
            let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            if reading.kind == .current {
                var zero = Path()
                zero.move(to: CGPoint(x: 0, y: y(0)))
                zero.addLine(to: CGPoint(x: size.width, y: y(0)))
                context.stroke(zero, with: .color(.primary.opacity(complicationPastOpacity)),
                               style: StrokeStyle(lineWidth: line / 2, dash: [line, line]))
            }
            let ink: Color = fullColor ? (reading.runsAreSlack ? SN.go : SN.slackWindow) : .primary
            for run in reading.slackRuns {
                if reading.runsAreSlack, run.lowerBound == run.upperBound {
                    var mark = Path()
                    let centre = x(run.lowerBound)
                    mark.move(to: CGPoint(x: centre - line, y: y(0)))
                    mark.addLine(to: CGPoint(x: centre + line, y: y(0)))
                    context.stroke(mark, with: .color(ink.opacity(run.lowerBound < 0 ? complicationPastOpacity : 1)),
                                   style: StrokeStyle(lineWidth: line * 2.3, lineCap: .round))
                    continue
                }
                let part = pts.filter { run.contains($0.hours) }
                for (half, opacity) in [(part.filter { $0.hours <= 0 }, complicationPastOpacity),
                                        (part.filter { $0.hours >= 0 }, 1.0)] where half.count > 1 {
                    context.stroke(path(half), with: .color(ink.opacity(opacity)),
                                   style: StrokeStyle(lineWidth: line * 2.3, lineCap: .round))
                }
            }
            context.stroke(path(pts.filter { $0.hours <= 0 }), with: .color(.primary.opacity(complicationPastOpacity)), style: style)
            context.stroke(path(pts.filter { $0.hours >= 0 }), with: .color(.primary), style: style)
            if let nowValue = pts.min(by: { abs($0.hours) < abs($1.hours) })?.value {
                let r = line * 1.6
                let dot = CGRect(x: x(0) - r, y: y(nowValue) - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: dot.insetBy(dx: -line * 0.6, dy: -line * 0.6)), with: .color(.black))
                context.fill(Path(ellipseIn: dot), with: .color(.primary))
            }
        }
    }
}
