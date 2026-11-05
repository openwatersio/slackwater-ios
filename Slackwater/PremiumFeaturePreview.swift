// Slackwater — GPL v3. Product examples use the same predictions and widget views as the app.
import SwiftUI

struct PremiumRequirement: View {
    var title: LocalizedStringKey = "Requires Slackwater Premium"
    @ObservedObject private var premium = PremiumStore.shared
    @State private var showPremium = false

    var body: some View {
        Group {
            if premium.isPremium {
                Label("Slackwater Premium", systemImage: "sparkles")
            } else {
                Button { showPremium = true } label: {
                    Label(title, systemImage: "sparkles")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(SN.leaf)
        .sheet(isPresented: $showPremium) { PremiumView() }
    }
}

struct PremiumFeaturePreview: View {
    let feature: PremiumFeature
    @State private var example: (snapshot: WidgetSnapshot, graph: StationCardGraph,
                                 complication: ComplicationReading?, sky: SkyState)?

    var body: some View {
        VStack {
            if let example {
                VStack(alignment: .leading, spacing: 12) {
                    if feature == .lockScreen {
                        if let next = example.snapshot.next {
                            Label {
                                Text("\(next.label) \(cardTime(next.time, example.snapshot.tz)) · \(example.snapshot.stationName)")
                                    .monospacedDigit()
                            } icon: { Image(systemName: "water.waves") }
                            .font(.caption)
                        }
                        HStack(spacing: 20) {
                            AccessoryCircularContent(snapshot: example.snapshot, graph: example.graph)
                                .frame(width: 72, height: 72)
                                .background(SN.cardFill, in: Circle())
                            AccessoryRectangularContent(snapshot: example.snapshot, graph: example.graph)
                                .frame(maxWidth: .infinity)
                                .frame(height: 80)
                        }
                        .dynamicTypeSize(.medium)
                    } else if feature == .watch {
                        if let reading = example.complication {
                            // The watch's own views are not in this target: this is the circular
                            // face's line and value, drawn from the same ComplicationReading.
                            HStack(spacing: 20) {
                                WatchCircularExample(reading: reading)
                                    .frame(width: 84, height: 84)
                                Text(verbatim: "\(reading.valueText) \(reading.word) ")
                                    + Text(Image(systemName: reading.symbol))
                            }
                            .font(.footnote.monospacedDigit())
                        }
                    } else if feature == .sky {
                        HStack(spacing: 12) {
                            skyPane(example.sky, bodies: true, caption: "With sky")
                            skyPane(example.sky, bodies: false, caption: "Without sky")
                        }
                    } else if let next = example.snapshot.next {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: feature == .calendars ? "calendar" : "bell.badge.fill")
                                .font(.title2)
                                .foregroundStyle(SN.leaf)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: example.snapshot.stationName)
                                    .font(.subheadline.weight(.semibold))
                                Text(verbatim: next.label)
                                    .font(.headline.monospacedDigit())
                                Text(next.time, format: Date.FormatStyle(date: .abbreviated, time: .shortened,
                                                                        timeZone: example.snapshot.tz))
                                    .font(.footnote.monospacedDigit())
                                if feature == .alerts {
                                    Text("A reminder before you go")
                                        .font(.caption)
                                        .foregroundStyle(SN.leaf)
                                }
                            }
                        }
                    }
                    Text("Example")
                        .font(.caption2)
                        .foregroundStyle(SN.foam.opacity(0.5))
                }
                .foregroundStyle(SN.foam)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SN.canvas, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Example")
                .accessibilityValue(Text(verbatim: example.snapshot.stationName + " · " + (example.snapshot.next?.label ?? example.snapshot.value)))
                .accessibilityIdentifier("premium-preview-\(feature.rawValue)")
                .allowsHitTesting(false)
            }
        }
        .task {
            example = await Task.detached {
                // A bundled tide station keeps examples available without location or downloads.
                guard let record = WidgetStationLoader.loadRecord(id: "noaa/9444900") else { return nil }
                let now = appNow()
                let station = WidgetStationLoader.station(from: record)
                var place = (latitude: 48.12, longitude: -122.76)
                if case .tide(let info, _) = record { place = (info.latitude, info.longitude) }
                return (WidgetSnapshot.build(station, now: now),
                        record.accessoryGraph(at: now),
                        ComplicationReading.build(station, now: now),
                        SkyState(time: now, latitude: place.latitude, longitude: place.longitude))
            }.value
        }
    }

    private func skyPane(_ sky: SkyState, bodies: Bool, caption: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            SkyBackdrop(sky: sky, plotDepth: 30, bodies: bodies)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(caption).font(.caption)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The watch's circular complication, as the phone can draw it: the line three hours either
/// side of now, dim before now, thicker through slack, a dot at now, the value beneath.
private struct WatchCircularExample: View {
    let reading: ComplicationReading
    private let past = 0.35

    var body: some View {
        VStack(spacing: 0) {
            Canvas { context, size in
                let pts = reading.samples
                guard pts.count > 1 else { return }
                var lo = pts.map(\.value).min()!, hi = pts.map(\.value).max()!
                if reading.kind == .current { lo = min(lo, 0); hi = max(hi, 0) }
                if hi - lo < 1e-6 { hi = lo + 1 }
                let x = { (h: Double) in (h + 3) / 6 * size.width }
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
                let ink = reading.runsAreSlack ? SN.go : SN.slackWindow
                for run in reading.slackRuns {
                    let part = pts.filter { run.contains($0.hours) }
                    for (half, opacity) in [(part.filter { $0.hours <= 0 }, past),
                                            (part.filter { $0.hours >= 0 }, 1.0)] where half.count > 1 {
                        context.stroke(path(half), with: .color(ink.opacity(opacity)),
                                       style: StrokeStyle(lineWidth: line * 2.3, lineCap: .round))
                    }
                }
                let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
                context.stroke(path(pts.filter { $0.hours <= 0 }), with: .color(.white.opacity(past)), style: style)
                context.stroke(path(pts.filter { $0.hours >= 0 }), with: .color(.white), style: style)
                if let now = pts.min(by: { abs($0.hours) < abs($1.hours) }) {
                    let r = line * 1.6
                    context.fill(Path(ellipseIn: CGRect(x: x(0) - r, y: y(now.value) - r, width: r * 2, height: r * 2)),
                                 with: .color(.white))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .frame(maxHeight: .infinity)
            Text(verbatim: reading.valueText)
                .font(.system(.body, design: .rounded).weight(.bold).monospacedDigit())
        }
        .padding(.bottom, 8)
        .background(SN.cardFill, in: Circle())
    }
}
