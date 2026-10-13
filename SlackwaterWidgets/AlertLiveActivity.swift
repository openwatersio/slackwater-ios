// Slackwater — GPL v3. The alert's Live Activity: two faces off one scheduled start (docs/alerts.md §5.3).
import ActivityKit
import SwiftUI
import WidgetKit

struct AlertLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlertLiveActivityAttributes.self) { context in
            // Lock Screen and banner
            HStack(spacing: 12) {
                glyph(context)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.headline)
                    detail(context).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                timer(context).font(.title3.monospacedDigit())
            }
            .padding()
            .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { glyph(context) }
                DynamicIslandExpandedRegion(.trailing) { timer(context).monospacedDigit() }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.title).font(.headline) }
                DynamicIslandExpandedRegion(.bottom) { detail(context).font(.caption) }
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
        case .moment:
            if let h = a.heightM {
                Text("\(a.event.formatted(date: .omitted, time: .shortened)) · \(formatHeight(h, imperial: a.imperial)) \(heightUnit(imperial: a.imperial))")
            } else {
                Text(a.event.formatted(date: .omitted, time: .shortened))
            }
        }
    }

    /// System timers: down to the event, then across the window. A moment with no window shows
    /// its time once stale; the next run ends it.
    @ViewBuilder
    private func timer(_ c: ActivityViewContext<AlertLiveActivityAttributes>) -> some View {
        let a = c.attributes
        switch liveActivityFace(a, stale: c.isStale) {
        case .countdown: Text(timerInterval: Date.now...a.event, countsDown: true)
        case .open: Text(timerInterval: a.event...(a.end ?? a.event), countsDown: true)
        case .moment: Text(a.event.formatted(date: .omitted, time: .shortened))
        }
    }
}
