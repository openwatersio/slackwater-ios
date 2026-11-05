// Slackwater — GPL v3. What each watch complication draws (#524). Faces tint
// complications to one colour, so everything reads by shape: a dot at now,
// the past at 35%, the slack window as a thicker line, and no unit beside a value.
import SwiftUI
import WidgetKit

private let pastOpacity = complicationPastOpacity
/// The app's slack-window colour, for faces that draw full colour.
private let slackColor = SN.slackWindow

struct LockedComplication: View {
    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "water.waves")
            Text("Premium", comment: "Locked watch complication.").font(.caption2)
        }
    }
}

struct InlineView: View {
    let entry: SlackwaterEntry
    var body: some View {
        if !entry.premium {
            Text("\(Image(systemName: "water.waves")) \(Text("Premium", comment: "Locked watch complication."))")
        } else if let r = entry.complication {
            // One text run: an inline complication keeps only one image, and
            // an image inside the text survives where a second view would not.
            Text("\(Text(verbatim: "\(r.valueText) \(r.word) "))\(Image(systemName: r.symbol))")
                .monospacedDigit()
        } else { Text("Open Slackwater", comment: "Watch complication with nothing to show.") }
    }
}

struct CircularView: View {
    let entry: SlackwaterEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if !entry.premium { LockedComplication() }
            else if let r = entry.complication {
                VStack(spacing: 0) {
                    ComplicationLine(reading: r, hours: -3...3)
                        .padding(.horizontal, 4)
                        .frame(maxHeight: .infinity)
                    Text(verbatim: r.valueText)
                        .font(.system(.body, design: .rounded).weight(.bold).monospacedDigit())
                        .minimumScaleFactor(0.7)
                }
                .padding(.vertical, 6)
            } else { Image(systemName: "water.waves") }
        }
    }
}

/// The shared line, tinted by the face's rendering mode.
struct ComplicationLine: View {
    let reading: ComplicationReading
    let hours: ClosedRange<Double>
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        ComplicationLineCanvas(reading: reading, hours: hours, fullColor: mode == .fullColor)
            .widgetAccentable()
    }
}

struct CornerView: View {
    let entry: SlackwaterEntry
    /// Tinted faces draw the window at full opacity, as `ComplicationLine` does.
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        if !entry.premium { Image(systemName: "water.waves").widgetLabel { Text("Premium", comment: "Locked watch complication.") } }
        else if let r = entry.complication {
            Text(verbatim: r.valueText)
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                .widgetCurvesContent()
                .widgetLabel {
                    if let g = r.gauge {
                        Gauge(value: g.fraction) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        } minimumValueLabel: {
                            Text(verbatim: g.startText ?? "").monospacedDigit()
                        } maximumValueLabel: {
                            Text(verbatim: g.endText ?? "").monospacedDigit()
                        }
                        .tint(Self.tint(g, slack: mode == .fullColor ? slackColor : .primary))
                    }
                }
        } else {
            Image(systemName: "water.waves")
                .widgetLabel { Text("Open Slackwater", comment: "Watch complication with nothing to show.") }
        }
    }

    /// A system gauge cannot draw its own strokes, so its gradient does the
    /// work: the travelled side dim; for a current, the slack window bright.
    static func tint(_ g: ComplicationReading.Gauge, slack: Color) -> Gradient {
        let past = Color.primary.opacity(pastOpacity), ahead = Color.primary, f = g.fraction
        guard let window = g.windowStart else {
            let (low, high) = g.towardEnd ? (past, ahead) : (ahead, past)
            return Gradient(stops: [.init(color: low, location: 0), .init(color: low, location: f),
                                    .init(color: high, location: f), .init(color: high, location: 1)])
        }
        // Inside the window now is past its start; the stops must not run backwards.
        let w = max(window, f)
        return Gradient(stops: [.init(color: past, location: 0),
                                .init(color: past, location: f),
                                .init(color: ahead.opacity(0.7), location: f),
                                .init(color: ahead.opacity(0.7), location: w),
                                .init(color: slack, location: w),
                                .init(color: slack, location: 1)])
    }
}

struct RectangularView: View {
    let entry: SlackwaterEntry
    private var favorite: Bool {
        entry.stationID.map { (AppGroup.defaults.stringArray(forKey: AppGroup.favoritesKey) ?? []).contains($0) } ?? false
    }
    var body: some View {
        if !entry.premium { LockedComplication() }
        else if let card = entry.card, let graph = card.graph {
            // No name row: the face is too narrow for one, and the curve needs
            // the height. The mark sits over the curve's top corner instead.
            ZStack(alignment: .topTrailing) {
                cropped(graph).widgetAccentable()
                if card.locationMark { Image(systemName: "location.fill").font(.caption2) }
                else if favorite { Image(systemName: "star.fill").font(.caption2) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: card.name))
        } else { Text("Open Slackwater", comment: "Watch complication with nothing to show.") }
    }

    /// The small widget's crop: half a swing back, one and a half ahead,
    /// with a lane under the curve so a hanging reading clears the times.
    private func cropped(_ g: StationCardGraph) -> StationCardGraph {
        var g = g
        g.back = 0.5 * StationCardGraph.swing
        g.forward = 1.5 * StationCardGraph.swing
        g.timeLabelSpace = 14
        return g
    }
}
