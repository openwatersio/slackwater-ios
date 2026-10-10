// Slackwater — GPL v3. SPIKE, throwaway: answers docs/alerts.md §11 on a phone. Never merge.
import ActivityKit
import SwiftUI
import WidgetKit

/// Two faces off one scheduled start: counting down until `staleDate` (= event), then "Open".
struct LiveActivitySpike: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitySpikeAttributes.self) { context in
            // Lock Screen / banner
            HStack {
                Image(systemName: "water.waves")
                VStack(alignment: .leading) {
                    Text(context.attributes.label).font(.headline)
                    face(context)
                }
                Spacer()
                timer(context)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "water.waves") }
                DynamicIslandExpandedRegion(.trailing) { timer(context) }
                DynamicIslandExpandedRegion(.bottom) { face(context) }
            } compactLeading: {
                Image(systemName: "water.waves")
            } compactTrailing: {
                timer(context).monospacedDigit()
            } minimal: {
                Image(systemName: "water.waves")
            }
        }
    }

    private func face(_ c: ActivityViewContext<LiveActivitySpikeAttributes>) -> some View {
        Text(c.isStale ? "Open — closes \(c.attributes.end.formatted(date: .omitted, time: .shortened))"
                       : "Opens \(c.attributes.event.formatted(date: .omitted, time: .shortened))")
            .font(.caption)
    }

    private func timer(_ c: ActivityViewContext<LiveActivitySpikeAttributes>) -> some View {
        c.isStale
            ? Text(timerInterval: c.attributes.event...c.attributes.end, countsDown: true)
            : Text(timerInterval: Date.now...c.attributes.event, countsDown: true)
    }
}
