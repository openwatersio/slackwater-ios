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

/// The small widget is the card's reading over two swings, now a quarter in:
/// the reading now with its arrow over the curve, whose own labels name the
/// next turn.
struct NextEventView: View {
    let entry: SlackwaterEntry
    /// The medium card's own points, cropped to half a swing back and one
    /// and a half ahead; nothing is resampled.
    private var graph: StationCardGraph? {
        guard var g = entry.card?.graph else { return nil }
        g.back = 0.5 * StationCardGraph.swing
        g.forward = 1.5 * StationCardGraph.swing
        return g
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let card = entry.card {
                Text(card.name).font(.caption2).foregroundStyle(SN.foam).lineLimit(1)
                if case .tide(let state, let imperial) = card.reading {
                    // The card's reading with the arrow on the number's line
                    // and no word: the small face has one row for the hero.
                    (Text(formatHeight(state.height, imperial: imperial))
                        .font(.title3.monospacedDigit()).fontWeight(.bold)
                     + Text(" \(heightUnit(imperial: imperial))").font(.body)
                     + Text(" \(state.rising ? "▲" : "▼")").font(.caption)
                        .foregroundStyle(state.rising ? SN.rising : SN.falling))
                        .foregroundStyle(.white)
                } else if case .current(let signed, let deg, let unit, let tilde, let inWindow) = card.reading {
                    // Speed with the set on the same line (current-charts
                    // §15.2, one row): Slack in the go colour inside a window,
                    // the cardinal and arrow by the sign, a neutral mark
                    // under 0.05 kn. The phase word is the arrow's colour.
                    let phase = currentPhase(signed: signed)
                    let slack = inWindow || phase == .slack
                    let tint = slack ? SN.go : phase == .flood ? SN.flood : SN.ebb
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        (Text((tilde ? "~" : "") + formatSpeed(abs(signed), unit: unit))
                            .font(.title3.monospacedDigit()).fontWeight(.bold)
                         + Text(" \(speedUnitLabel(unit))").font(.body))
                            .foregroundStyle(.white)
                        if slack { Text("Slack").font(.caption).foregroundStyle(tint) }
                        if abs(signed) < 0.05 {
                            Text("•").font(.caption).foregroundStyle(SN.foam.opacity(0.4))
                        } else {
                            HStack(spacing: 2) {
                                CompassArrow(deg: deg)
                                Text(compass16(deg))
                            }.font(.caption).foregroundStyle(tint)
                        }
                    }
                } else {
                    // A derived gate has no curve, so its next slack has no
                    // other home than a line.
                    ConditionsItem(reading: card.reading)
                    if let next = card.nextSlack {
                        Text("Slack · \(cardTime(next.time, next.tz))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SN.foam.opacity(0.92))
                    }
                }
            } else {
                Text("Open Slackwater to prepare this station")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                SN.cardFill
                // Top inset clears the name and hero rows; the horizontal
                // bleed lets the line exit through the edge on its own slope.
                if let graph { graph.padding(.top, 58).padding(.horizontal, -3) }
            }
        }
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
