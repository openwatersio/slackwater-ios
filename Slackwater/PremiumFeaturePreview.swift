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
                                 complication: ComplicationReading?,
                                 strip: (data: TimelineData, sky: SkyState, at: Date)?)?

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
                        if let strip = example.strip {
                            HStack(spacing: 12) {
                                skyPane(strip, bodies: true, caption: "With sky")
                                skyPane(strip, bodies: false, caption: "Without sky")
                            }
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
                var strip: (data: TimelineData, sky: SkyState, at: Date)?
                // A fixed late afternoon, so the sun, the moon and the gradient show whenever the sheet opens.
                if feature == .sky, case .tide(let info, _) = record {
                    var cal = Calendar(identifier: .gregorian)
                    cal.timeZone = info.tz
                    if let at = cal.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: 19, minute: 0)) {
                        let data = TimelineData.build(tide: info, current: nil, now: at, anchor: cal.startOfDay(for: at))
                        strip = (data, SkyState(time: at, latitude: info.latitude, longitude: info.longitude,
                                                days: data.days, eclipses: data.eclipses), at)
                    }
                }
                return (WidgetSnapshot.build(station, now: now),
                        record.accessoryGraph(at: now),
                        ComplicationReading.build(station, now: now),
                        strip)
            }.value
        }
    }

    private func skyPane(_ strip: (data: TimelineData, sky: SkyState, at: Date), bodies: Bool,
                         caption: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            SkyStripExample(data: strip.data, sky: strip.sky, at: strip.at, bodies: bodies)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(caption).font(.caption)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The chart strip's own canvas over its sky, cropped to the curve and its hours as the watch
/// crops it: Settings' switch, set either way for the pane.
private struct SkyStripExample: View {
    let data: TimelineData
    let sky: SkyState
    let at: Date
    let bodies: Bool
    private static let padTop: CGFloat = 110
    private static let plotDepth: CGFloat = 50

    var body: some View {
        let geo = TimelineGeo(data: data, padTop: Self.padTop, plotDepth: Self.plotDepth)
        let height = geo.timeY + 10
        GeometryReader { proxy in
            let center = data.x(at)
            let first = max(Int((center - proxy.size.width) / TimelineCanvas.tileWidth), 0)
            // The canvas is two tiles wide: the sky takes the pane's width, not the canvas's.
            ZStack(alignment: .topLeading) {
                TimelineCanvas(data: data, geo: geo, imperial: heightUnits() != "metric", speedUnit: "kn",
                               now: at, showsSunMarks: bodies, tileRange: first..<(first + 2))
                    .offset(x: proxy.size.width / 2 - center)
            }
            .frame(width: proxy.size.width, height: height, alignment: .topLeading)
            // Any crop cuts the labels nearest the pane's edges; fading them out keeps a half
            // label from reading as a broken time.
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                       .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    SN.canvas
                    SkyBackdrop(sky: sky, plotDepth: geo.bodyBottom - geo.bodyTop, bodies: bodies)
                        .frame(height: geo.bodyBottom)
                }
            }
            .clipped()
        }
        .frame(height: height)
    }
}

/// The watch's circular complication, as the phone can draw it: the line three hours either
/// side of now, dim before now, thicker through slack, a dot at now, the value beneath.
private struct WatchCircularExample: View {
    let reading: ComplicationReading
    var body: some View {
        VStack(spacing: 0) {
            ComplicationLineCanvas(reading: reading, hours: -3...3, fullColor: true)
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

