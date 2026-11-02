// Slackwater — GPL v3. The alert's Live Activity: two faces off one scheduled start (docs/alerts.md §5.3).
import ActivityKit
import SwiftUI
import WidgetKit

struct AlertLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlertLiveActivityAttributes.self) { context in
            // Lock Screen and banner: the title row, the station's six hours, the line.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    glyph(context)
                    Text(context.attributes.title).font(.headline)
                    Spacer()
                    timer(context).font(.title3.monospacedDigit())
                }
                if let curve = context.attributes.curve {
                    AlertCurveView(curve: curve, event: context.attributes.event, end: context.attributes.end,
                                   water: context.attributes.water)
                        .frame(height: 44)
                }
                detail(context).font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            // The app's own dark canvas, so the white curve and its fill read in both
            // appearances instead of vanishing on a light platter.
            .activityBackgroundTint(SN.canvas)
            .foregroundStyle(.white)
            .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { glyph(context) }
                DynamicIslandExpandedRegion(.trailing) { timer(context).monospacedDigit() }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.title).font(.headline) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let curve = context.attributes.curve {
                            AlertCurveView(curve: curve, event: context.attributes.event, end: context.attributes.end,
                                           water: context.attributes.water)
                                .frame(height: 36)
                        }
                        detail(context).font(.caption)
                    }
                }
            } compactLeading: {
                glyph(context)
            } compactTrailing: {
                timer(context).monospacedDigit()
            } minimal: {
                glyph(context)
            }
            .widgetURL(context.attributes.url)
        }
    }

    private func glyph(_ c: ActivityViewContext<AlertLiveActivityAttributes>) -> some View {
        Image(systemName: c.attributes.water == .tide ? "water.waves" : "arrow.left.and.right")
    }

    /// Counting down: the §5.2 body line. Open: "Open" and the line. A moment with no window:
    /// the time and, for a tide, the height.
    @ViewBuilder
    private func detail(_ c: ActivityViewContext<AlertLiveActivityAttributes>) -> some View {
        let a = c.attributes
        switch liveActivityFace(a, stale: c.isStale) {
        case .countdown: Text(a.line)
        case .open: Text("Open · \(a.line)", comment: "Live Activity line while a slack window is open; the rest is the notification's body.")
        case .moment: Text(liveActivityMoment(a)).monospacedDigit()
        }
    }

    /// System timers: down to the event, then across the window. A moment with no window shows
    /// its time once stale; the next run ends it.
    @ViewBuilder
    private func timer(_ c: ActivityViewContext<AlertLiveActivityAttributes>) -> some View {
        let a = c.attributes
        switch liveActivityFace(a, stale: c.isStale) {
        case .countdown: Text(timerInterval: liveActivityCountdown(now: .now, event: a.event), countsDown: true)
        case .open: Text(timerInterval: a.event...(a.end ?? a.event), countsDown: true)
        case .moment: Text(a.event.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: a.tz)))
        }
    }
}

/// Six hours of the station around its event, drawn the way the strip draws it: the curve, a
/// fill beneath, the window shaded, the moment marked. Static: the timers beside it move.
struct AlertCurveView: View {
    let curve: AlertLiveActivityCurve
    let event: Date
    let end: Date?
    let water: AlertLiveActivityAttributes.Water

    var body: some View {
        Canvas { ctx, size in
            let n = curve.values.count
            guard n > 1 else { return }
            let lo = curve.values.min()!, hi = curve.values.max()!
            // A flat slice is a flat line, never a division by zero.
            let span = max(hi - lo, 0.01)
            let total = curve.step * Double(n - 1)
            // Clamped: a window longer than the three hours after the event stops at the edge.
            func x(_ t: Date) -> CGFloat { min(max(CGFloat(t.timeIntervalSince(curve.start) / total) * size.width, 0), size.width) }
            func y(_ v: Double) -> CGFloat { size.height - CGFloat((v - lo) / span) * (size.height - 6) - 3 }

            if let end {
                let r = CGRect(x: x(event), y: 0, width: max(x(end) - x(event), 2), height: size.height)
                ctx.fill(Path(r), with: .color(.yellow.opacity(0.18)))
            }
            var line = Path()
            for (i, v) in curve.values.enumerated() {
                let p = CGPoint(x: CGFloat(i) / CGFloat(n - 1) * size.width, y: y(v))
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(.white.opacity(0.10)))
            ctx.stroke(line, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
            if water == .current {
                let zero = y(0)
                if zero > 0, zero < size.height {
                    var axis = Path()
                    axis.move(to: CGPoint(x: 0, y: zero)); axis.addLine(to: CGPoint(x: size.width, y: zero))
                    ctx.stroke(axis, with: .color(.white.opacity(0.25)), lineWidth: 0.5)
                }
            }
            ctx.fill(Path(CGRect(x: x(event) - 0.75, y: 0, width: 1.5, height: size.height)),
                     with: .color(.yellow.opacity(0.9)))
        }
    }
}
