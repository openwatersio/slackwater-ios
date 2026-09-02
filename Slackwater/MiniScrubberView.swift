// Slackwater — GPL v3. Compact, non-interactive form of the detail scrubber,
// shared with the app target so its actual Canvas output can be tested.
import SwiftUI

func widgetStationPresentation(_ stationName: String) -> (name: String, isCurrentLocation: Bool) {
    let prefix = "Current Location · "
    guard stationName.hasPrefix(prefix) else { return (stationName, false) }
    return (String(stationName.dropFirst(prefix.count)), true)
}

func tideEventValue(_ label: String) -> String {
    let prefix = ["High ", "Low "].first { label.hasPrefix($0) }
    return prefix.map { String(label.dropFirst($0.count)) } ?? label
}

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
