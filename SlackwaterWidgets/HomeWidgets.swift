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
                    Text(next.label).font(.caption).lineLimit(1)
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
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today's Curve")
        .description("Today's tide or current curve, with the next event.")
        .supportedFamilies([.systemMedium])
    }
}

struct DayCurveView: View {
    let entry: SlackwaterEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = entry.snapshot {
                HStack {
                    Text(s.stationName).font(.caption).lineLimit(1)
                    Spacer()
                    if let next = s.next {
                        Image(systemName: next.symbol).font(.caption2)
                        Text(next.time, style: .time)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .environment(\.timeZone, s.tz)
                        Text(next.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                SparklineView(values: s.sparkline, nowFraction: s.nowFraction)
            } else {
                Text("Open Slackwater to prepare this station")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLink(entry))
    }
}

struct SparklineView: View {
    let values: [Double]
    let nowFraction: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Path { p in
                    for (i, v) in values.enumerated() {
                        let pt = CGPoint(x: w * CGFloat(i) / CGFloat(values.count - 1),
                                         y: h * (1 - CGFloat(v)))
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                }
                .stroke(.tint, lineWidth: 2)
                Rectangle().fill(.secondary).frame(width: 1)
                    .position(x: w * CGFloat(nowFraction), y: h / 2)
            }
        }
    }
}

func deepLink(_ entry: SlackwaterEntry) -> URL? {
    // Station route lands in Task 9; harmless until the app registers the scheme.
    guard entry.snapshot != nil else { return URL(string: "slackwater://station") }
    return URL(string: "slackwater://station")  // refined to carry the id in Task 9
}
