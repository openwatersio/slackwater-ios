import SwiftUI
import WidgetKit

struct AccessoryWidgetView: View {
    let entry: SlackwaterEntry
    let family: WidgetFamily

    var body: some View {
        ZStack {
            if family == .accessoryCircular { AccessoryWidgetBackground() }
            if entry.isPlaceholder || !entry.premium {
                Image(systemName: "water.waves")
                    .unredacted()
                    .accessibilityLabel(entry.isPlaceholder ? Text("Open Slackwater") : Text("Premium"))
            } else if let snapshot = entry.snapshot {
                if family == .accessoryInline, let next = snapshot.next {
                    Text("\(next.label) \(cardTime(next.time, snapshot.tz)) · \(snapshot.stationName)",
                         comment: "Inline widget event. Values are event label, localized time, and station name.")
                        .monospacedDigit()
                } else if let graph = entry.accessoryGraph {
                    if family == .accessoryCircular {
                        AccessoryCircularContent(snapshot: snapshot, graph: graph)
                    } else {
                        AccessoryRectangularContent(snapshot: snapshot, graph: graph)
                    }
                } else {
                    openApp
                }
            } else {
                openApp
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(accessoryDeepLink(entry))
    }

    // A subscriber with no data yet (an undownloaded station) needs a prompt
    // that reads differently from the locked and loading icon.
    @ViewBuilder private var openApp: some View {
        if family == .accessoryCircular {
            Image(systemName: "water.waves").unredacted()
                .accessibilityLabel(Text("Open Slackwater"))
        } else {
            Text("Open Slackwater")
        }
    }
}

extension WidgetRecord {
    func accessoryGraph(at now: Date) -> StationCardGraph {
        switch self {
        case .tide(let record, let station):
            record.cardGraph(at: now, imperial: heightUnits() != "metric",
                             station: station)
        case .current(let record, let station):
            record.cardGraph(at: now, unit: AppGroup.defaults.string(forKey: speedUnitKey) ?? "kn",
                             station: station)
        case .derived(let record):
            record.cardGraph(at: now)
        }
    }
}

struct AccessoryCircularContent: View {
    let snapshot: WidgetSnapshot
    let graph: StationCardGraph

    var body: some View {
        VStack(spacing: 1) {
            compactGraph
                .frame(maxHeight: .infinity)
                .widgetAccentable()
            if let next = snapshot.next {
                Text(next.time, style: .time)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .environment(\.timeZone, snapshot.tz)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: snapshot.stationName))
        .accessibilityValue(Text(verbatim: snapshot.next.map {
            "\($0.label) \(cardTime($0.time, snapshot.tz))"
        } ?? snapshot.value))
        .monospacedDigit()
    }

    private var compactGraph: StationCardGraph {
        var graph = graph
        graph.back = 3 * 3600
        graph.forward = 3 * 3600
        graph.showsReadings = false
        graph.showsTimes = false
        return graph
    }
}

struct AccessoryRectangularContent: View {
    let snapshot: WidgetSnapshot
    let graph: StationCardGraph

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(verbatim: snapshot.stationName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if snapshot.curveKind != .schematic {
                    Text(verbatim: snapshot.value)
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            compactGraph
                .frame(maxHeight: .infinity)
                .widgetAccentable()
        }
    }

    private var compactGraph: StationCardGraph {
        var graph = graph
        graph.back = 0.5 * StationCardGraph.swing
        graph.forward = 1.5 * StationCardGraph.swing
        graph.showsReadings = false
        graph.timeLabelSpace = 22
        return graph
    }
}
