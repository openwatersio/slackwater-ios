// Slackwater — GPL v3. What each watch complication draws (#524). Faces tint
// complications to one colour, so everything reads by shape: a dot at now,
// the past at 35%, slack as a thicker line, and no unit beside a value.
import SwiftUI
import WidgetKit

private let pastOpacity = 0.35
/// The app's slack-window colour, for faces that draw full colour.
private let slackColor = SN.go

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
        if !entry.premium { Text("Premium", comment: "Locked watch complication.") }
        else if let r = entry.complication {
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

/// The line over `hours`, scaled to its own extremes (and zero, for a
/// current), dim before now, thick where a current is slack, with a dot at now.
struct ComplicationLine: View {
    let reading: ComplicationReading
    let hours: ClosedRange<Double>
    /// Tinted faces get thickness alone; a full-colour face also gets the
    /// app's slack colour.
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        Canvas { context, size in
            let pts = reading.samples.filter { hours.contains($0.hours) }
            guard pts.count > 1 else { return }
            var lo = pts.map(\.value).min()!, hi = pts.map(\.value).max()!
            if reading.kind == .current { lo = min(lo, 0); hi = max(hi, 0) }
            if hi - lo < 1e-6 { hi = lo + 1 }
            let x = { (h: Double) in (h - hours.lowerBound) / (hours.upperBound - hours.lowerBound) * size.width }
            let y = { (v: Double) in size.height - (v - lo) / (hi - lo) * size.height }
            let line = max(2, size.height * 0.08)
            func path(_ part: [ComplicationReading.Sample]) -> Path {
                var p = Path()
                for (i, s) in part.enumerated() {
                    let pt = CGPoint(x: x(s.hours), y: y(s.value))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                return p
            }
            let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            for run in reading.slackRuns {
                let part = pts.filter { run.contains($0.hours) }
                if part.count > 1 {
                    let ink: Color = mode == .fullColor ? slackColor : .primary
                    context.stroke(path(part), with: .color(ink.opacity(part[0].hours < 0 ? pastOpacity : 1)),
                                   style: StrokeStyle(lineWidth: line * 2.3, lineCap: .round))
                }
            }
            context.stroke(path(pts.filter { $0.hours <= 0 }), with: .color(.primary.opacity(pastOpacity)), style: style)
            context.stroke(path(pts.filter { $0.hours >= 0 }), with: .color(.primary), style: style)
            if let nowValue = pts.min(by: { abs($0.hours) < abs($1.hours) })?.value {
                let r = line * 1.6
                let dot = CGRect(x: x(0) - r, y: y(nowValue) - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: dot.insetBy(dx: -line * 0.6, dy: -line * 0.6)), with: .color(.black))
                context.fill(Path(ellipseIn: dot), with: .color(.primary))
            }
        }
        .widgetAccentable()
    }
}

struct CornerView: View {
    let entry: SlackwaterEntry
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
                        .tint(Self.tint(g))
                    }
                }
        } else { Image(systemName: "water.waves") }
    }

    /// A system gauge cannot draw its own strokes, so its gradient does the
    /// work: the travelled side dim; for a current, the slack window bright.
    static func tint(_ g: ComplicationReading.Gauge) -> Gradient {
        let past = Color.primary.opacity(pastOpacity), ahead = Color.primary
        guard let window = g.windowStart else {
            return Gradient(colors: g.towardEnd ? [past, ahead] : [ahead, past])
        }
        return Gradient(stops: [.init(color: past, location: 0),
                                .init(color: past, location: g.fraction),
                                .init(color: ahead.opacity(0.7), location: g.fraction),
                                .init(color: ahead.opacity(0.7), location: window),
                                .init(color: slackColor, location: window),
                                .init(color: slackColor, location: 1)])
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
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(verbatim: card.name).font(.headline).lineLimit(1)
                    Spacer(minLength: 2)
                    if card.locationMark { Image(systemName: "location.fill").font(.caption2) }
                    else if favorite { Image(systemName: "star.fill").font(.caption2) }
                }
                cropped(graph).frame(maxHeight: .infinity).widgetAccentable()
            }
        } else { Text("Open Slackwater", comment: "Watch complication with nothing to show.") }
    }

    /// The small widget's crop: half a swing back, one and a half ahead.
    private func cropped(_ g: StationCardGraph) -> StationCardGraph {
        var g = g
        g.back = 0.5 * StationCardGraph.swing
        g.forward = 1.5 * StationCardGraph.swing
        return g
    }
}
