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
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Next Event")
        .description("The next slack or tide turn at your station.")
        .supportedFamilies([.systemSmall])
    }
}

struct NextEventView: View {
    let entry: SlackwaterEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = entry.snapshot {
                Text(s.stationName).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                if let next = s.next {
                    Image(systemName: next.symbol).font(.title3)
                    Text(next.time, style: .time)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .environment(\.timeZone, s.tz)
                    // .monospacedDigit(): `next.label` carries a formatted
                    // height/speed (H2's formatHeight/formatSpeed) — same
                    // no-jitter rule as every other numeric reading
                    // (TypeScaleTests.testNumericFormattersAreMonospacedDigit).
                    Text(next.label).font(.caption.monospacedDigit()).lineLimit(1)
                } else {
                    Text("—").font(.title)
                }
            } else {
                Text("Open Slackwater to prepare this station")
                    .font(.caption).foregroundStyle(.secondary)
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
                .containerBackground(SN.cardFill, for: .widget)
        }
        .configurationDisplayName("Today's Curve")
        .description("Today's tide or current curve, with the next event.")
        .supportedFamilies([.systemMedium])
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
