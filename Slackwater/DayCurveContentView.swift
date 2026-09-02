// Slackwater — GPL v3. The medium widget's content: the list's station card
// (current-charts §15).
import SwiftUI

/// The medium widget IS the list card (current-charts §15): same shell,
/// same reading, same curve. No chrome — the widget's container clips.
struct DayCurveContentView: View {
    let card: WidgetCard
    var body: some View {
        StationCard(name: card.name, region: card.region, graph: card.graph, chrome: false, minHeight: 0) {
            ConditionsItem(reading: card.reading)
            if let next = card.nextSlack {
                Text("Slack · \(cardTime(next.time, next.tz))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.92))
            }
        }
    }
}
