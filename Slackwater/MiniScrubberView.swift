// Slackwater — GPL v3. Compact, non-interactive form of the detail scrubber,
// shared with the app target so its actual Canvas output can be tested.
import SwiftUI

struct DayCurveContentView: View {
    let snapshot: WidgetSnapshot

    private var stateColor: Color {
        switch snapshot.state {
        case "Slack": .green
        case "Flooding": .blue
        case "Ebbing": .orange
        default: .secondary
        }
    }

    private var curveAccessibilityValue: String {
        let now = "Now is \(Int((snapshot.nowFraction * 100).rounded())) percent through today."
        switch snapshot.curveKind {
        case .tide:
            return "\(snapshot.state), \(snapshot.value). \(now)"
        case .current:
            return "\(snapshot.state), \(snapshot.value). \(now) Green band marks the usable current threshold; orange and red mark stronger water."
        case .schematic:
            return "\(snapshot.state), timing only; speed is not predicted. \(now)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(snapshot.stationName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(snapshot.state.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(stateColor)
                Text(snapshot.value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
            }
            MiniScrubberView(snapshot: snapshot)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("24-hour curve")
                .accessibilityValue(curveAccessibilityValue)
            if let window = snapshot.window {
                let windowMinutes = Int((window.end.timeIntervalSince(window.start) / 60).rounded())
                HStack(alignment: .top, spacing: 8) {
                    Text("SLACK")
                        .font(.caption.weight(.semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 3) {
                            Text(window.start, style: .time)
                            Text("–")
                            Text(window.end, style: .time)
                        }
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .environment(\.timeZone, snapshot.tz)
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                            Text(window.start, style: .relative)
                            Text("·").foregroundStyle(.tertiary)
                            Text("\(windowMinutes) min")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Slack window")
            } else if let next = snapshot.next {
                HStack(spacing: 4) {
                    Image(systemName: next.symbol)
                        .font(.caption2.weight(.semibold))
                    Text(next.label)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(next.time, style: .time)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .environment(\.timeZone, snapshot.tz)
                    Text("·").foregroundStyle(.secondary)
                    Text(next.time, style: .relative)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct MiniScrubberView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                guard snapshot.sparkline.count > 1 else { return }
                let maxAbs = max(snapshot.sparkline.map(abs).max() ?? 1,
                                 (snapshot.threshold ?? 0) * 1.25, 0.01)
                let x: (Int) -> CGFloat = {
                    size.width * CGFloat($0) / CGFloat(snapshot.sparkline.count - 1)
                }
                let y: (Double) -> CGFloat = { value in
                    switch snapshot.curveKind {
                    case .tide:
                        size.height * (1 - CGFloat(value))
                    case .current, .schematic:
                        size.height / 2 - CGFloat(value / maxAbs) * size.height * 0.44
                    }
                }

                if snapshot.curveKind == .current, let threshold = snapshot.threshold {
                    let top = y(threshold), bottom = y(-threshold)
                    context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: bottom - top)),
                                 with: .color(.green.opacity(0.08)))
                    for speed in [-threshold, threshold] {
                        var rule = Path()
                        rule.move(to: CGPoint(x: 0, y: y(speed)))
                        rule.addLine(to: CGPoint(x: size.width, y: y(speed)))
                        context.stroke(rule, with: .color(.green.opacity(0.7)), lineWidth: 0.75)
                    }
                }

                if snapshot.curveKind != .tide {
                    var zero = Path()
                    zero.move(to: CGPoint(x: 0, y: y(0)))
                    zero.addLine(to: CGPoint(x: size.width, y: y(0)))
                    context.stroke(zero, with: .color(.secondary.opacity(0.35)), lineWidth: 0.75)
                }

                for i in 1..<snapshot.sparkline.count {
                    let a = snapshot.sparkline[i - 1], b = snapshot.sparkline[i]
                    let magnitude = abs((a + b) / 2)
                    let color: Color
                    switch snapshot.curveKind {
                    case .tide: color = .blue
                    case .schematic: color = .cyan
                    case .current:
                        if magnitude <= snapshot.threshold ?? 0 { color = .green }
                        else if widgetSpeedRampT(magnitude) >= 2.0 / 3.0 { color = .red }
                        else { color = .orange }
                    }

                    if snapshot.curveKind == .current, let threshold = snapshot.threshold,
                       magnitude > threshold, a * b > 0 {
                        let edge = a > 0 ? threshold : -threshold
                        var excess = Path()
                        excess.move(to: CGPoint(x: x(i - 1), y: y(a)))
                        excess.addLine(to: CGPoint(x: x(i), y: y(b)))
                        excess.addLine(to: CGPoint(x: x(i), y: y(edge)))
                        excess.addLine(to: CGPoint(x: x(i - 1), y: y(edge)))
                        excess.closeSubpath()
                        context.fill(excess, with: .color(color.opacity(0.2)))
                    }

                    var segment = Path()
                    segment.move(to: CGPoint(x: x(i - 1), y: y(a)))
                    segment.addLine(to: CGPoint(x: x(i), y: y(b)))
                    context.stroke(segment, with: .color(color),
                                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }

                let position = snapshot.nowFraction * Double(snapshot.sparkline.count - 1)
                let lower = min(Int(position), snapshot.sparkline.count - 2)
                let fraction = position - Double(lower)
                let nowValue = snapshot.sparkline[lower]
                    + (snapshot.sparkline[lower + 1] - snapshot.sparkline[lower]) * fraction
                let nowX = size.width * CGFloat(snapshot.nowFraction)
                var marker = Path()
                marker.move(to: CGPoint(x: nowX, y: 0))
                marker.addLine(to: CGPoint(x: nowX, y: size.height))
                context.stroke(marker, with: .color(.primary.opacity(0.55)), lineWidth: 1)
                context.fill(Path(ellipseIn: CGRect(x: nowX - 3.5, y: y(nowValue) - 3.5,
                                                     width: 7, height: 7)),
                             with: .color(.primary))
            }
        }
    }
}
