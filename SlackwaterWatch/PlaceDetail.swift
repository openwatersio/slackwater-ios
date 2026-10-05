// Slackwater — GPL v3. A place on the watch: a glass reading card over the
// sky, above the phone's timeline, scrubbed with the Crown (#522, #563).
// One screen: the Crown only scrubs.
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
    @ObservedObject private var downloads = ChsFitService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = heightUnits()
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @State private var store: TimelineWindowStore?
    @State private var source: TimelineSource?
    @State private var unavailable = false
    @State private var live = Date()
    @State private var scrubTime = Date()
    @State private var anchor = Date()
    @State private var showSheet = false
    @State private var offerOnPhone = false
    @State private var showPhoneInstructions = false

    private var imperial: Bool { units != "metric" }
    private var scrubbedAway: Bool { abs(scrubTime.timeIntervalSince(live)) > Timeline.scrubbedSeconds }

    var body: some View {
        Group {
            if let tl = store?.timeline, let source {
                page(tl, source)
            } else if unavailable {
                VStack(spacing: 12) {
                    Text("Predictions unavailable", comment: "Prediction download status.")
                        .foregroundStyle(.secondary)
                    phoneButton
                }
            } else {
                ProgressView()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbar }
        .onAppear { RecentsStore.shared.record(item.id) }
        .task(id: "\(item.id)|\(downloads.modelRevision)") { await load() }
        .userActivity(stationActivityType, isActive: offerOnPhone) { activity in
            activity.title = item.name
            activity.userInfo = ["stationID": item.id]
            activity.isEligibleForHandoff = true
        }
        .alert(Text("Open on iPhone", comment: "Watch Handoff action and instructions title."),
               isPresented: $showPhoneInstructions) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("To continue, open the app switcher on your iPhone and tap Slackwater.",
                 comment: "Watch instructions for accepting a station Handoff on iPhone.")
        }
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
        guard !Task.isCancelled else { return }
        guard let record, let s = TimelineSource(record) else { unavailable = true; return }
        unavailable = false
        if source == nil {
            live = now
            scrubTime = now
            anchor = dayLocal(now, s.tz)
        }
        let st = TimelineWindowStore(source: s)
        st.start(anchor: anchor, now: live, focus: scrubTime)
        source = s
        store = st
    }

    private func page(_ tl: TimelineData, _ source: TimelineSource) -> some View {
        let sky = SkyState(time: scrubTime, latitude: source.latitude, longitude: source.longitude,
                           days: tl.days, eclipses: tl.eclipses)
        let reading = ScrubReading.at(scrubTime, in: tl, imperial: imperial, speedUnit: speedUnit,
                                      floodDeg: flow?.flood, ebbDeg: flow?.ebb)
        return VStack(spacing: 6) {
            card(reading)
                // The system clock owns the top-right corner and cannot be
                // moved, so the glass starts below it rather than under it.
                // ponytail: tuned on the 46mm simulator.
                .padding(.top, 22)
                .padding(.horizontal, 4)
            CrownScrubStrip(data: tl, scale: store?.scale, now: live, imperial: imperial,
                            speedUnit: speedUnit, floodDeg: flow?.flood, ebbDeg: flow?.ebb,
                            scrubTime: $scrubTime)
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
        }
        // Top-aligned: the hours row is the first thing a short screen loses.
        .frame(maxHeight: .infinity, alignment: .top)
        // The sky runs behind the card from the top of the screen and sets
        // at the plot's floor, so the bodies rise and set behind the glass.
        .background(alignment: .top) {
            SkyBackdrop(sky: sky, plotDepth: CrownScrubStrip.plotDepth)
                .padding(.bottom, CrownScrubStrip.belowHorizon)
                .ignoresSafeArea(edges: .top)
        }
        .ignoresSafeArea(edges: .horizontal)
    }

    private func card(_ r: ScrubReading) -> some View {
        Button { showSheet = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                // The card's first row is the title: the place, or the
                // scrubbed time while away from now.
                title.font(.headline).lineLimit(1)
                    // The scrubbed time shrinks rather than lose its minutes.
                    .minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if let value = r.value {
                        Text(verbatim: value).font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                    }
                    if let unit = r.unit { Text(verbatim: unit).font(.headline) }
                    if let set = r.set { Text(verbatim: set).font(.headline).foregroundStyle(SN.foam.opacity(0.7)) }
                    // A tide's arrow says rising, falling, or the turn; a
                    // current has no arrow, so its phase keeps the word.
                    if let symbol = r.symbol {
                        Image(systemName: symbol).font(.headline)
                    } else {
                        Text(verbatim: r.title).font(.headline)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if let next = r.next {
                    Text(verbatim: next).font(.footnote.monospacedDigit()).foregroundStyle(SN.foam.opacity(0.7)).lineLimit(1)
                }
            }
            .foregroundStyle(SN.foam)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reading-card")
    }

    /// In the bottom-left corner, under the card, so the card has the top.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if scrubbedAway {
                Button { returnToNow() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("Now", comment: "Slackwater interface text."))
                    .accessibilityIdentifier("return-to-now")
            } else {
                Button { onList() } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel(Text("Places", comment: "Watch button back to the list of places."))
                    .accessibilityIdentifier("back-to-list")
            }
            // A lone bottom-bar item centres; the spacer keeps it in the corner.
            Spacer()
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
            if case .chsCurrent(let gate) = item, downloads.isProvisional(gate.id) {
                CardStatusStrip(status: .refining(tolerance: gate.provisionalTolerance))
            }
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
            phoneButton
        }
    }

    private var phoneButton: some View {
        Button {
            offerOnPhone = true
            showPhoneInstructions = true
        } label: {
            Label(String(localized: "Open on iPhone", comment: "Watch Handoff action and instructions title."),
                  systemImage: "iphone")
        }
        .accessibilityIdentifier("open-on-phone")
    }
}
