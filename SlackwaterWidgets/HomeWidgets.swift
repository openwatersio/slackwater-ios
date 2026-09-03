// Slackwater — GPL v3. Free home-screen widgets: next event (small) and
// today's curve (medium). The 3-second test: station, curve, next slack —
// answered before the app opens.
import SwiftUI
import WidgetKit

struct NextEventWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextEvent", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            NextEventView(entry: entry)
                .containerBackground(SN.canvas, for: .widget)
        }
        .configurationDisplayName("Next Event")
        .description("Now, which way it's going, and the next turn.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

/// The small widget IS the card's reading (current-charts §15.5): the same
/// shell the medium widget draws, one row shorter. No chrome — the widget's
/// container clips.
struct NextEventView: View {
    let entry: SlackwaterEntry
    var body: some View {
        Group {
            if let card = entry.card {
                NextEventContentView(card: card)
            } else {
                // Content margins are off, so the empty state pads itself.
                Text("Open Slackwater to prepare this station")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLink(entry))
    }
}

struct DayCurveWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DayCurve", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            DayCurveView(entry: entry)
                // The list's ground; the card paints its translucent fill over it, as on screen.
                .containerBackground(SN.canvas, for: .widget)
        }
        .configurationDisplayName("Today's Curve")
        .description("Today's tide or current curve, with the next event.")
        .supportedFamilies([.systemMedium])
        // The card IS the widget: no system inset between the container and the card's own 20/16pt padding.
        .contentMarginsDisabled()
    }
}

struct DayCurveView: View {
    let entry: SlackwaterEntry
    var body: some View {
        Group {
            if let card = entry.card {
                DayCurveContentView(card: card)
            } else {
                Text("Open Slackwater to prepare this station")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLink(entry))
    }
}

/// The encoding itself (the character set + the fallback-to-premium rule)
/// lives in `Slackwater/DeepLink.swift` (M3): a shared, appex-and-app file
/// so a round-trip test can exercise it without linking `SlackwaterEntry`.
func deepLink(_ entry: SlackwaterEntry) -> URL? { deepLink(forStationID: entry.stationID) }
