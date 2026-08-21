// Slackwater — GPL v3. Premium lock-screen widgets (spec §4). Without the
// entitlement they render the quiet locked state — wave glyph + "Premium",
// no data, no urgency. Tapping any of them opens the in-app Widgets page.
import SwiftUI
import WidgetKit

private struct Locked: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "water.waves")
            Text("Premium").font(.caption2)
        }
        .widgetURL(URL(string: "slackwater://premium"))
    }
}

struct SlackInlineWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SlackInline", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            if !entry.premium { Locked() }
            else if let s = entry.snapshot, let next = s.next {
                // e.g. "Slack 14:32 · Race Passage"
                Text("\(next.label) \(next.time.formatted(.dateTime.hour().minute())) · \(s.stationName)")
                    .environment(\.timeZone, s.tz)
            } else { Text("Open Slackwater") }
        }
        .configurationDisplayName("Next Slack")
        .description("The next event, above the clock.")
        .supportedFamilies([.accessoryInline])
    }
}

struct SlackCircularWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SlackCircular", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            ZStack {
                AccessoryWidgetBackground()
                if !entry.premium { Locked() }
                else if let s = entry.snapshot, let next = s.next {
                    VStack(spacing: 0) {
                        Image(systemName: next.symbol).font(.caption2)
                        Text(next.time, style: .time)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .environment(\.timeZone, s.tz)
                    }
                } else { Image(systemName: "water.waves") }
            }
        }
        .configurationDisplayName("Next Event")
        .description("Next slack or turn at a glance.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct SlackRectangularWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SlackRectangular", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            if !entry.premium { Locked() }
            else if let s = entry.snapshot, let next = s.next {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.stationName).font(.caption2).lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: next.symbol)
                        Text(next.time, style: .time).fontWeight(.semibold)
                            .environment(\.timeZone, s.tz)
                        Text(next.label).lineLimit(1)
                    }
                    .font(.caption)
                    if let w = s.window {
                        Text("window \(w.start.formatted(.dateTime.hour().minute()))–\(w.end.formatted(.dateTime.hour().minute()))")
                            .font(.caption2).foregroundStyle(.secondary)
                            .environment(\.timeZone, s.tz)
                    }
                }
            } else { Text("Open Slackwater") }
        }
        .configurationDisplayName("Slack Window")
        .description("Next event plus the workable window.")
        .supportedFamilies([.accessoryRectangular])
    }
}
