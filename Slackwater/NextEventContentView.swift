// Slackwater — GPL v3. The small widget's content: the station card's reading
// over its own curve (current-charts §15.5).
import SwiftUI

/// The small widget is the card one row shorter: the name, the compact
/// reading (`ConditionsItem`, one row), and the card curve below, whose own
/// labels name the next turn.
struct NextEventContentView: View {
    let card: WidgetCard
    /// Clears the name and hero rows above the curve, and scales with them.
    @ScaledMetric(relativeTo: .title3) private var graphInset: CGFloat = 58
    /// The medium card's own points, cropped to half a swing back and one
    /// and a half ahead; nothing is resampled.
    private var graph: StationCardGraph? {
        guard var g = card.graph else { return nil }
        g.back = 0.5 * StationCardGraph.swing
        g.forward = 1.5 * StationCardGraph.swing
        return g
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.name).font(.caption2).foregroundStyle(SN.foam).lineLimit(1)
            ConditionsItem(reading: card.reading, compact: true)
            // A derived gate has no curve, so its next slack has no other
            // home than a line.
            if let next = card.nextSlack {
                Text("Slack · \(cardTime(next.time, next.tz))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.92))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                SN.cardFill
                // The horizontal bleed lets the line exit through the edge
                // on its own slope.
                if let graph { graph.padding(.top, graphInset).padding(.horizontal, -3) }
            }
        }
    }
}
