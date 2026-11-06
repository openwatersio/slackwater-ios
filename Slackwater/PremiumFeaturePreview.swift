// Slackwater — GPL v3. Product examples use the same predictions and widget views as the app.
import SwiftUI

struct PremiumRequirement: View {
    var title: LocalizedStringKey = "Requires Slackwater Premium"
    var feature: PremiumFeature?
    @ObservedObject private var premium = PremiumStore.shared
    @State private var showPremium = false

    var body: some View {
        Group {
            if premium.hasPurchased {
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
        .sheet(isPresented: $showPremium) { PremiumView(opening: feature) }
    }
}

struct PremiumFeaturePreview: View {
    let feature: PremiumFeature
    @State private var example: (snapshot: WidgetSnapshot, graph: StationCardGraph,
                                 complication: ComplicationReading?,
                                 strip: (data: TimelineData, sky: SkyState, at: Date)?,
                                 page: PrintablePage?)?

    var body: some View {
        VStack {
            if let example {
                VStack(alignment: .leading, spacing: 12) {
                    if feature == .print {
                        if let page = example.page { PrintedWeekExample(page: page) }
                    } else if feature == .lockScreen {
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
                var page: PrintablePage?
                if feature == .print, case .tide(let info, _) = record {
                    let imperial = heightUnits() != "metric"
                    let config = PrintableConfig(
                        source: .computed(.tide(info)), kind: .tide(heightUnit: heightUnit(imperial: imperial)),
                        facts: PrintFacts(name: info.name, region: info.region,
                                          units: printableUnitName(heightUnit(imperial: imperial)),
                                          datum: info.chartDatum,
                                          source: printSourceLabel(id: info.id, publisher: info.source), link: nil),
                        entries: { tideScheduleEntries($0, imperial: imperial) })
                    let range = printRange(.week, anchor: now, tz: info.tz)
                    page = printablePage(config, span: .week, anchor: now, tz: info.tz,
                                         timelines: printTimelines(config.source, range: range, tz: info.tz, now: now),
                                         printedAt: now)
                }
                return (WidgetSnapshot.build(station, now: now),
                        record.accessoryGraph(at: now),
                        ComplicationReading.build(station, now: now),
                        strip, page)
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
    private static let padTop: CGFloat = 80
    private static let plotDepth: CGFloat = 44

    var body: some View {
        let geo = TimelineGeo(data: data, padTop: Self.padTop, plotDepth: Self.plotDepth)
        let height = geo.timeY + 10
        GeometryReader { proxy in
            let left = skyPaneLeft(width: proxy.size.width, center: data.x(at),
                                   turns: data.tideExtremes.map { data.x($0.time) })
            let first = max(Int(left / TimelineCanvas.tileWidth), 0)
            // The canvas is two tiles wide: the sky takes the pane's width, not the canvas's.
            ZStack(alignment: .topLeading) {
                TimelineCanvas(data: data, geo: geo, imperial: heightUnits() != "metric", speedUnit: "kn",
                               now: at, showsSunMarks: bodies, tileRange: first..<(first + 2))
                    .offset(x: -left)
            }
            .frame(width: proxy.size.width, height: height, alignment: .topLeading)
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

/// The pane's left edge nearest centring `center`, moved until each edge is at least `margin`
/// from every turn: a turn's time and reading are centred on it, so each shows whole or not
/// at all. `center` stays inside the pane; with no such edge, the centred one.
func skyPaneLeft(width: CGFloat, center: CGFloat, turns: [CGFloat], margin: CGFloat = 30) -> CGFloat {
    let centred = center - width / 2
    let clear = { (left: CGFloat) in
        turns.allSatisfy { abs($0 - left) >= margin && abs($0 - (left + width)) >= margin }
    }
    // 16 keeps the pinned instant's dot inside the pane.
    for shift in stride(from: CGFloat(0), through: width / 2 - 16, by: 2) {
        if clear(centred - shift) { return centred - shift }
        if clear(centred + shift) { return centred + shift }
    }
    return centred
}

/// The top of the printed week: its heading, then the first day's rows, set as `printableHTML`
/// sets them on paper. The page itself is HTML for the print renderer, so this redraws its rows.
private struct PrintedWeekExample: View {
    let page: PrintablePage
    private static let dayFill = Color(white: 0.95)
    private static let nightFill = Color(red: 0xe8 / 255, green: 0xec / 255, blue: 0xf2 / 255)

    var body: some View {
        let tz = page.tz
        let day = page.days.first
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: page.facts.name)
                .font(.subheadline.weight(.bold))
            Text(verbatim: [page.facts.region, tz.abbreviation(for: page.range.lowerBound) ?? tz.identifier,
                            page.facts.units, page.facts.datum ?? "", page.facts.source]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption2)
                .lineLimit(1)
                .padding(.bottom, 4)
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Text(String(localized: "Time", comment: "Column header of a printed tide or current table: the time of day."))
                    Text(String(localized: "Event", comment: "Column header of a printed tide or current table: what happens at that time."))
                    Text(String(localized: "Height", comment: "Column header of a printed tide table: the water height."))
                }
                .font(.caption.weight(.semibold))
                .modifier(PrintedCell())
                rule
                if let day {
                    GridRow {
                        Group {
                            if let rise = day.sunrise, let set = day.sunset {
                                Text(verbatim: "\(localizedFormatter("EEEMMMd", tz).string(from: day.start))   ☀︎ \(chartTime(rise, tz)) – \(chartTime(set, tz))")
                            } else {
                                Text(verbatim: "\(localizedFormatter("EEEMMMd", tz).string(from: day.start))   ☀︎ —")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .modifier(PrintedCell(fill: Self.dayFill))
                        .gridCellColumns(3)
                    }
                    rule
                    ForEach(day.entries.prefix(4), id: \.id) { e in
                        GridRow {
                            Text(verbatim: chartTime(e.time, tz))
                            Text(verbatim: eventWord(e.pill))
                            Text(verbatim: e.value ?? "—")
                        }
                        .font(.caption.monospacedDigit())
                        .modifier(PrintedCell(fill: printIsNight(e.time, nights: page.nights) ? Self.nightFill : .clear))
                        rule
                    }
                }
            }
        }
        .foregroundStyle(.black)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 6))
        .dynamicTypeSize(.medium)
    }

    private var rule: some View {
        Rectangle().fill(.black).frame(height: 0.5).gridCellUnsizedAxes(.horizontal)
    }
}

/// A printed cell's padding, filling its column so a shaded row shades edge to edge.
private struct PrintedCell: ViewModifier {
    var fill: Color = .clear
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
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

