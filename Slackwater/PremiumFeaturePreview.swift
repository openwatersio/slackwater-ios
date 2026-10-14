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
    enum Feature: String { case lockScreen, calendar, alert }
    let feature: Feature
    @State private var example: (snapshot: WidgetSnapshot, graph: StationCardGraph)?

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
                    } else if let next = example.snapshot.next {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: feature == .calendar ? "calendar" : "bell.badge.fill")
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
                                if feature == .alert {
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
                return (WidgetSnapshot.build(WidgetStationLoader.station(from: record), now: now),
                        record.accessoryGraph(at: now))
            }.value
        }
    }
}
