// Slackwater — GPL v3. The medium widget's content: the list's station card
// (current-charts §15).
import SwiftUI

/// The medium widget IS the list card (current-charts §15): same shell,
/// same reading, same curve. No chrome — the widget's container clips.
struct DayCurveContentView: View {
    let card: WidgetCard
    var body: some View {
        StationCard(name: card.name, region: card.region, graph: card.graph, chrome: false, minHeight: 0,
                    locationMark: card.locationMark) {
            ConditionsItem(reading: card.reading)
            if let next = card.nextSlack {
                Text("Slack · \(cardTime(next.time, next.tz))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.92))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let countdown = card.countdown {
                // Inside a window the question is "how long do I have"
                // (current-charts §15.3). The timer floats over the faded
                // past swing — space the forecast no longer needs — so the
                // reading keeps the speed and the set.
                VStack(alignment: .leading, spacing: 1) {
                    MonoLabel(text: "Slack ends", color: SN.go.opacity(0.7), tracking: 1.2)
                    switch countdown {
                    case .until(let end) where end > Date.now:
                        Text(timerInterval: Date.now...end, countsDown: true)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    case .beyondTwoHours:
                        Text("> 2 hrs").font(.subheadline.weight(.semibold).monospacedDigit())
                    default:
                        EmptyView()
                    }
                }
                .foregroundStyle(SN.go)
                .padding(.leading, 20)
                .padding(.bottom, 34)   // clear of the axis time row
            }
        }
    }
}
