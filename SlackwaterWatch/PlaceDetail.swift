// Slackwater — GPL v3. A place on the watch: the reading card under the
// phone's timeline, scrubbed with the Crown (#522). One screen: the Crown
// only scrubs.
import SwiftUI

extension TimelineSource {
    /// The detail's source from the widget's one-record load (#317). Online
    /// Canadian gates have no source here: the watch hides them (#523).
    init?(_ record: WidgetRecord) {
        switch record {
        case .tide(let r, _): self = .tide(r)
        case .current(_, let station) where station is ChsOnlineWindow: return nil
        case .current(let r, let station): self = .current(r, threshold: slackThresholdKn, station: station)
        case .derived(let g): self = .gate(g)
        }
    }
}

struct PlaceDetail: View {
    let item: StationItem
    let mark: PlaceMark?
    let onList: () -> Void

    @ObservedObject private var favorites = FavoritesStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @State private var store: TimelineWindowStore?
    @State private var source: TimelineSource?
    @State private var unavailable = false
    @State private var live = Date()
    @State private var scrubTime = Date()
    @State private var anchor = Date()
    @State private var showSheet = false

    private var imperial: Bool { units != "metric" }
    private var scrubbedAway: Bool { abs(scrubTime.timeIntervalSince(live)) > Timeline.scrubbedSeconds }

    var body: some View {
        Group {
            if let tl = store?.timeline, let source {
                page(tl, source)
            } else if unavailable {
                Text("Predictions unavailable", comment: "Prediction download status.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .navigationBarBackButtonHidden(true)
        // watchOS sets an inline title under the clock: the place, or the
        // scrubbed time while away from now.
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onAppear { RecentsStore.shared.record(item.id) }
        .task(id: item.id) { await load() }
        .onChange(of: scrubTime) { _, t in store?.focus(t, viewportPts: 200) }
        // A scrub at rest outside the loaded window re-anchors, as on the phone.
        .task(id: scrubTime) {
            guard (try? await Task.sleep(for: .milliseconds(600))) != nil,
                  let tl = store?.timeline, let source,
                  let next = Timeline.reanchor(settledAt: scrubTime, anchor: tl.anchor, tz: source.tz) else { return }
            anchor = next
            store?.setAnchor(next)
        }
        .sheet(isPresented: $showSheet) { sheet }
        // A raised wrist is a new look, as reopening is on the phone: at now,
        // follow now; scrubbed away, stay there against the new now.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, store != nil else { return }
            if scrubbedAway { live = Date() } else { returnToNow() }
        }
    }

    private func load() async {
        let id = item.id, now = Date()
        let record = await Task.detached(priority: .userInitiated) {
            WidgetStationLoader.loadRecord(id: id, at: now)
        }.value
        guard let record, let s = TimelineSource(record) else { unavailable = true; return }
        live = now
        scrubTime = now
        anchor = dayLocal(now, s.tz)
        let st = TimelineWindowStore(source: s)
        st.start(anchor: anchor, now: now)
        source = s
        store = st
    }

    private func page(_ tl: TimelineData, _ source: TimelineSource) -> some View {
        let sky = SkyState(time: scrubTime, latitude: source.latitude, longitude: source.longitude,
                           days: tl.days, eclipses: tl.eclipses)
        let reading = ScrubReading.at(scrubTime, in: tl, imperial: imperial, speedUnit: speedUnit,
                                      floodDeg: flow?.flood, ebbDeg: flow?.ebb)
        return VStack(spacing: 6) {
            CrownScrubStrip(data: tl, scale: store?.scale, now: live, imperial: imperial,
                            speedUnit: speedUnit, floodDeg: flow?.flood, ebbDeg: flow?.ebb,
                            scrubTime: $scrubTime)
                .background(alignment: .top) {
                    SkyBackdrop(sky: sky, plotDepth: CrownScrubStrip.plotDepth)
                        .frame(height: CrownScrubStrip.skyHeight)
                }
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: item.name))
                .accessibilityValue(Text(verbatim: [spokenWhen(scrubTime, source.tz), reading.title,
                                                    reading.value, reading.unit.map(spokenUnit), reading.set]
                    .compactMap { $0 }.joined(separator: " ")))
                .accessibilityAdjustableAction { direction in
                    let step: TimeInterval = direction == .increment ? 300 : -300
                    scrubTime = scrubTime.addingTimeInterval(step)
                }
                .accessibilityAction(named: Text("Next event", comment: "VoiceOver chart action.")) {
                    if let t = tl.snapTimes.first(where: { $0 > scrubTime.addingTimeInterval(1) }) { scrubTime = t }
                }
                .accessibilityAction(named: Text("Previous event", comment: "VoiceOver chart action.")) {
                    if let t = tl.snapTimes.last(where: { $0 < scrubTime.addingTimeInterval(-1) }) { scrubTime = t }
                }
            card(reading)
        }
        .ignoresSafeArea(edges: .horizontal)
    }

    private func card(_ r: ScrubReading) -> some View {
        Button { showSheet = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: r.title).font(.headline)
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(SN.steel)
                }
                if let value = r.value {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(verbatim: value).font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                        if let unit = r.unit { Text(verbatim: unit).font(.headline) }
                        if let set = r.set { Text(verbatim: set).font(.headline).foregroundStyle(SN.foam.opacity(0.7)) }
                        if let symbol = r.symbol { Image(systemName: symbol).font(.headline) }
                    }
                }
                if let next = r.next {
                    Text(verbatim: next).font(.footnote.monospacedDigit()).foregroundStyle(SN.foam.opacity(0.7)).lineLimit(1)
                }
            }
            .foregroundStyle(SN.foam)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reading-card")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if scrubbedAway {
                Button { returnToNow() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("Now", comment: "Slackwater interface text."))
                    .accessibilityIdentifier("return-to-now")
            } else {
                Button { onList() } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel(Text("Places", comment: "Watch button back to the list of places."))
                    .accessibilityIdentifier("back-to-list")
            }
        }
    }

    private var title: Text {
        if scrubbedAway, let source { return Text(verbatim: leadWhen(scrubTime, source.tz)) }
        if mark == .location { return Text("\(Image(systemName: "location.fill")) \(item.name)") }
        return Text(verbatim: item.name)
    }

    private func returnToNow() {
        live = Date()
        guard let source else { return }
        let today = dayLocal(live, source.tz)
        // The store may not hold now any more; it jumps first, as the phone's does.
        store?.jump(to: live, anchor: today)
        anchor = today
        // Beyond a week the strip under the travel is not loaded: land, as the phone's Now does.
        let far = abs(scrubTime.timeIntervalSince(live)) > Timeline.snapJumpHours * 3600
        if reduceMotion || far { scrubTime = live } else { withAnimation(.snappy) { scrubTime = live } }
    }

    /// A current's flood and ebb bearings: the strip's arrows and the card's set.
    private var flow: (flood: Double, ebb: Double)? {
        guard case .current(let r, _, _) = source else { return nil }
        return (r.floodDirection, r.ebbDirection)
    }

    private var sheet: some View {
        List {
            if let tl = store?.timeline {
                ForEach(ScrubReading.todaysEvents(after: scrubTime, in: tl, imperial: imperial,
                                                  speedUnit: speedUnit), id: \.self) { Text(verbatim: $0).monospacedDigit() }
            }
            Button {
                favorites.toggle(item.id)
            } label: {
                Label(favorites.contains(item.id)
                      ? String(localized: "Unfavorite", comment: "Station discovery interface text.")
                      : String(localized: "Favorite", comment: "Station discovery interface text."),
                      systemImage: favorites.contains(item.id) ? "star.slash" : "star.fill")
            }
            .accessibilityIdentifier("sheet-favorite")
        }
    }
}
