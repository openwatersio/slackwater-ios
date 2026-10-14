import SwiftUI
import SlackwaterKit

struct SlackWindowPreview: View {
    let threshold: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let start = Date(timeIntervalSince1970: 0)
    private static let span: TimeInterval = 6 * 3600
    // A cubic crossing keeps small windows legible while illustrating the full setting range.
    private static let points: [CurrentPoint] = (0...120).map { i in
        let phase = Double(i) / 60 - 1
        return CurrentPoint(time: start.addingTimeInterval(Double(i) * 180),
                            speed: 10 * phase * phase * phase)
    }

    var body: some View {
        let slacks = [Self.start.addingTimeInterval(Self.span / 2)]
        let windows = cardWindows(points: Self.points, slacks: slacks,
                                  threshold: normalizedSlackThresholdKn(threshold))
        let width = windows.first.map { $0.end.timeIntervalSince($0.start) } ?? 0
        let duration = Duration.seconds(width).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated))
        VStack(spacing: 6) {
            StationCardGraph(
                points: Self.points.map { .init(time: $0.time, value: $0.speed) },
                extremes: [], now: Self.start, back: 0, forward: Self.span,
                includesZero: true, windows: windows, slacks: slacks,
                showsReadings: false, showsTimes: false, showsNow: false, timeLabelSpace: 0)
                .frame(height: 90)
                .background {
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SN.go.opacity(0.12))
                            .frame(width: geometry.size.width * width / Self.span)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: threshold)
                }
            HStack {
                Text("Example", comment: "Label on the illustrative current curve in slack-window settings; this is not a real place prediction.")
                Spacer()
                Text(duration).monospacedDigit().foregroundStyle(SN.go)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Example slack window", comment: "Accessibility label for the illustrative current curve in settings. Its value is the example window duration, which changes with the comfort-current setting."))
        .accessibilityValue(Text(duration))
        .accessibilityIdentifier("slack-window-preview")
    }
}
