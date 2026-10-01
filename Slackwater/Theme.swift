// Slackwater — GPL v3. Detail-view chrome and list state; the palette and formatters live in Palette.swift so the widget can share them.
import Almanac
import SwiftUI
import WidgetKit

// MARK: - The scrub-detail scaffold (tide / current / derived gate / online gate)

private struct DetailTopHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The four scrub details' shared anatomy: header, the caller's lead reading,
/// the strip, the caller's links (summary tiles, tide-at-port), the rolling
/// schedule card, and the bottom slot (footer — or the
/// online gate's honesty card, which is also what shows while `timeline` is
/// nil).
///
/// Return-to-now is the caller's, not the scaffold's: it resets the window's
/// `anchor` as well as the scrub, and only the detail view holds that. The
/// strip takes it directly.
struct ScrubDetailScaffold<Above: View, Card: View, Links: View, Bottom: View>: View {
    let name: String
    let region: String
    let favoriteId: String
    let tz: TimeZone
    let timeline: TimelineData?
    let entries: (TimelineData) -> [ScheduleEntry]
    @Binding var scrubTime: Date
    /// The window's anchor. The scaffold moves it (via the picker) but does not
    /// own it — it lives in the detail view, alongside return-to-now.
    @Binding var anchor: Date
    /// Whether the week-range bar stays up when there is no timeline. The
    /// three constituent-backed details always have somewhere to go; an
    /// online gate with nothing downloaded yet does not — every week the
    /// picker can reach lands on the same honesty card (#172).
    var canPickDate = true
    /// Fired when the picker OPENS, before a date is chosen. Only an online
    /// gate has anything to do here (speculatively fetch the next block); the
    /// other three are constituents and pass a no-op.
    var onPickerOpen: () -> Void = {}
    /// Fired after the anchor moves, with the picked date. The three
    /// `@State`-backed views rebuild here; the online gate re-checks coverage.
    var onPicked: (Date) -> Void = { _ in }
    /// A detail can supply its scrub-time sky without changing the scaffold's
    /// generic signature.
    var topBackdrop: AnyView? = nil
    @State private var topHeight: CGFloat = 0
    @State private var showPicker = false
    /// Between the header and the scrub card (the fast-answer amber card).
    @ViewBuilder var above: () -> Above
    /// Readout + strip (+ any notes), in the caller's order — everything in
    /// the scrub card above its shared tail.
    @ViewBuilder var card: (TimelineData) -> Card
    /// Under the strip, above the schedule (summary tiles, TideAtPortLink).
    /// Handed the same `TimelineData` the card gets, so a consumer reads the
    /// timeline the page is already drawing rather than deriving a second one —
    /// and `jump(to:)`, for the Moon sheet's eclipse rows.
    @ViewBuilder var links: (TimelineData, @escaping (Date) -> Void) -> Links
    /// Below the schedule card; each element gets the standard 14pt top gap.
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        // GeometryReader sits inside the safe area (only the ScrollView below
        // ignores it), so the proxy reads the real top inset for DetailHeader —
        // per device and per iPad split-view pane, live across rotation.
        GeometryReader { geo in
            ScrollView {
                ZStack(alignment: .top) {
                    if let topBackdrop, let timeline {
                        // Down to the plot's floor, so a body's glow reaches
                        // the water; the strip paints the water over it.
                        topBackdrop
                            .frame(maxWidth: .infinity)
                            .frame(height: topHeight + TimelineGeo(data: timeline).bodyBottom)
                    }
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            DetailHeader(name: name, region: region,
                                         favoriteId: favoriteId,
                                         topSafeInset: geo.safeAreaInsets.top,
                                         shareInstant: scrubTime, tz: tz)
                            above()
                        }
                            .background {
                                GeometryReader { top in
                                    Color.clear.preference(key: DetailTopHeightKey.self,
                                                           value: top.size.height)
                                }
                            }
                        if let timeline {
                            scrubCard(timeline)
                            scheduleCard(timeline)
                                .padding(.top, 14)
                        } else if anchor != .distantPast, canPickDate {
                        // #67 item 2: no timeline means the caller is showing its
                        // honesty card below — but the bar (and its picker) need
                        // no timeline, and without them that card is a dead end
                        // with no way back to a covered week — when there IS one
                        // (`canPickDate`). Guarded on anchor:
                        // all four details start at .distantPast (real anchor
                        // arrives in onAppear), and weekRangeLabel force-unwraps
                        // a Calendar.date(byAdding:) against it — the pre-onAppear
                        // frame must render nothing here, as it always has.
                            WeekRangeBar(anchor: anchor, today: todayLocal(tz), tz: tz,
                                         onTap: { showPicker = true })
                                .background(SN.cardFill)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(SN.cardStroke, lineWidth: 0.5))
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                        }
                        bottom()
                            .padding(.top, 14)
                        if let item = StationItem.byId[favoriteId] {
                            NearbySection(item: item)
                                .padding(.top, 28)
                        }
                    }
                    .padding(.bottom, 42)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(CanvasBackground())
            .onPreferenceChange(DetailTopHeightKey.self) { topHeight = $0 }
            .environment(\.timeZone, tz)
            .environment(\.openWeekPicker, { showPicker = true })
            .toolbar(.hidden, for: .navigationBar)
            // A shared link's moment (#187): on appear, and again if another
            // link lands while this detail is already up — a second link to the
            // open station re-pushes the same value, so nothing else re-appears.
            .onAppear(perform: applyLinkedInstant)
            .onChange(of: LinkedInstant.shared.pending) { _, _ in applyLinkedInstant() }
            .sheet(isPresented: $showPicker) {
                WeekPickerSheet(anchor: $anchor, tz: tz, onOpen: onPickerOpen, onPick: { picked in
                    // Park the centerline on the picked week when it isn't already
                    // there. The strip does NOT self-correct: `data.x(_:)` and
                    // `data.time(atX:)` are exact inverses, so the programmatic
                    // scroll to `scrubTime` and the scroll callback that reads it
                    // back are a fixed point, and `contentSize` is set once in
                    // `makeUIView` — nothing re-clamps an off-window offset. Left
                    // alone, picking a month out draws a blank strip under a
                    // readout frozen on the first sample, with the return-to-now
                    // button hidden because `scrubTime` is still `live`.
                    //
                    // `Timeline.window` asks the question, not hand-rolled hours:
                    // it is the span the strip actually draws. A pick that lands
                    // on today leaves an in-window `scrubTime` alone, so it stays
                    // live and the return-to-now slot stays correctly empty.
                    //
                    // NOON of the picked day, not its midnight. Midnight is the
                    // window's first instant, so `x(scrubTime) - width/2` is
                    // negative and the strip opens on half a viewport of dead space
                    // before the curve starts — and the readout reads "12:00 AM",
                    // which looks like a boundary artefact rather than a reading.
                    // With the unconditional 48h back-pad, noon has 60h (1080pt) of
                    // data behind it — no pane is that wide, so the park never
                    // opens on dead space (#67 item 1). Calendar noon, not +12h:
                    // a spring-forward day would otherwise open at 13:00.
                    let week = Timeline.window(anchor: picked)
                    if scrubTime < week.start || scrubTime > week.end {
                        scrubTime = noonLocal(picked, tz)
                    }
                    onPicked(picked)
                })
            }
        }
    }

    /// Scrub to the link's moment, if one is waiting for THIS station — or the
    /// screenshot walk's seeded one (`seededScrubInstant`). Applied at once,
    /// not after the caller's first timeline: an online gate only ever loads
    /// the block covering its anchor, so a link into a cached week must set
    /// the anchor before that lookup — and offline, with no block for today,
    /// a timeline would never have come. SwiftUI does not promise whose
    /// onAppear runs first, so the callers' own anchor set-up yields to an
    /// anchor already placed (their `anchor == .distantPast` guards), and
    /// `onPicked` builds or re-checks coverage around the new one.
    private func applyLinkedInstant() {
        guard let t = LinkedInstant.shared.take(for: favoriteId) ?? seededScrubInstant else { return }
        jump(to: t)
    }

    /// Park the centerline on `t`, moving the window when `t` is not on it.
    ///
    /// Shared by the two things that arrive holding an instant: a shared link
    /// (#187) and the Moon sheet's eclipse rows (#222). The window test is
    /// `linkedAnchor`'s — the picker's rule inverted, so a jump to later today
    /// doesn't re-key the schedule off today.
    private func jump(to t: Date) {
        scrubTime = t
        if let day = linkedAnchor(for: t, anchor: anchor, tz: tz) {
            anchor = day
            onPicked(day)
        } else if anchor == .distantPast {
            // Landed before the caller's own set-up. Place today's anchor
            // anyway: a placed anchor is how the caller knows a moment is
            // here, and opens its first build on `scrubTime` rather than now.
            anchor = todayLocal(tz)
        }
    }

    private func scrubCard(_ tl: TimelineData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Full bleed, no chrome: the curve is the hero and the page is its
            // frame. No "‹ swipe to scrub ›" label here, and none is coming
            // back (#58): "scrubber" is audio-editing jargon, and testers who
            // read the label still didn't find the horizontal scroll. The
            // strip's own opening slide-into-place is the affordance now —
            // `TimelineScrubber.centerIfNeeded`.
            card(tl)

            links(tl, jump)
                .padding(.top, 12)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    private func scheduleCard(_ tl: TimelineData) -> some View {
        VStack(spacing: 0) {
            WeekRangeBar(anchor: tl.anchor, today: tl.today, tz: tz, onTap: { showPicker = true })
            Divider().overlay(Color.white.opacity(0.08))
            // Both dates, never one: `anchor` keys the day groups (it is what
            // `days` offsets are relative to), `today` only says Today/Tomorrow.
            // The eclipse row is merged HERE, not in the four detail views:
            // an eclipse belongs to the sky, not to the station, so every kind
            // of detail gets it from one place.
            MultiDaySchedule(entries: (entries(tl) + eclipseEntries(tl)).sorted { $0.time < $1.time },
                             tz: tz, anchor: tl.anchor,
                             today: tl.today, days: tl.days,
                             scrubTime: scrubTime, onTap: { scrubTime = $0 })
        }
        .background(SN.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
        .padding(.horizontal, 16)
    }
}

/// Where a shared link's moment `t` parks the window: nil when it is already
/// on the strip hung from `anchor` (today's, when the detail has not set one
/// yet), else the local midnight of its own day. The week picker's rule,
/// inverted — a link to later today must not open on "not this week".
func linkedAnchor(for t: Date, anchor: Date, tz: TimeZone) -> Date? {
    let week = Timeline.window(anchor: anchor == .distantPast ? todayLocal(tz) : anchor)
    return (t < week.start || t > week.end) ? dayLocal(t, tz) : nil
}

/// The span on screen, and the way to change it.
///
/// It heads the SCHEDULE card rather than sitting in the scrub card: it names
/// the list's range, and putting it in the scrub card would land it below the
/// swipe hint, the readout and the tide-at-port link — much further down the
/// page than "just under the scrubber" suggests — while reopening the
/// 2026-08-03 rule that the `when` row is always last in that card.
struct WeekRangeBar: View {
    let anchor: Date
    let today: Date
    let tz: TimeZone
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.7))
                // No away badge: the strip's Now button already says it, and another week isn't a fault.
                Text(weekRangeLabel(anchor: anchor, today: today, tz: tz))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SN.foam.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("week-range-bar")
        .accessibilityLabel("Showing \(weekRangeLabel(anchor: anchor, today: today, tz: tz)). Tap to choose a date.")
    }
}

/// How the strip's day row reaches the picker the range bar owns. An
/// environment closure rather than four more callback parameters: the strip is
/// three views deep in every detail, and none of the layers between it and the
/// scaffold has anything to say about dates.
private struct OpenWeekPickerKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openWeekPicker: () -> Void {
        get { self[OpenWeekPickerKey.self] }
        set { self[OpenWeekPickerKey.self] = newValue }
    }
}

/// A native graphical `DatePicker`, in a sheet.
///
/// Native rather than a hand-rolled month grid: Dynamic Type, VoiceOver, and
/// localization arrive for nothing, and this app adds no dependency it can
/// avoid. Unbounded in both directions — the engine is deterministic, so last
/// Saturday costs exactly what next March costs. Online gates get the SAME
/// unbounded picker rather than a greyed-out range: two classes of station that
/// visibly disagree about how far the future goes would leave the user to work
/// out why, where an honest failure at the moment of asking says it in words.
struct WeekPickerSheet: View {
    @Binding var anchor: Date
    let tz: TimeZone
    let onOpen: () -> Void
    let onPick: (Date) -> Void

    @State private var draft = Date()
    /// The calendar's measured height plus the navigation bar, which becomes
    /// the sheet's one detent. `.medium` clipped the lower weeks on iPad, and
    /// a tap where they should be landed outside the sheet and dismissed it.
    @State private var height: CGFloat = 480
    @Environment(\.dismiss) private var dismiss

    /// The one calendar this sheet uses, for both the grid and the commit.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("Week starting", selection: $draft,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(SN.go)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("week-picker")
                    // The grid must be drawn in the STATION's zone, because
                    // that is the zone "Show" commits in. A sheet is its own
                    // presentation hierarchy and does not inherit the
                    // detail's `\.timeZone`, so the calendar was laid out in
                    // the DEVICE's day while the commit took `startOfDay` in
                    // the station's: from a device east of the station,
                    // tapping the 8th asked for the 7th, and the week that
                    // came back was the one before the week you pointed at.
                    // Reading a phone in Halifax about Sechelt is exactly the
                    // case, and so is a UTC test runner.
                    .environment(\.timeZone, tz)
                    .environment(\.calendar, calendar)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height + $0.safeAreaInsets.top
                    } action: { height = $0 }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(CanvasBackground())
            .navigationTitle("Choose a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") {
                        let picked = calendar.startOfDay(for: draft)
                        anchor = picked
                        onPick(picked)
                        dismiss()
                    }
                    .accessibilityIdentifier("week-picker-done")
                }
            }
        }
        .presentationDetents([.height(height)])
        .onAppear {
            draft = anchor
            // Fire the speculative fetch as the sheet appears, not when a date
            // is chosen: by the time the user has picked, the round trip has
            // had the whole browsing interaction to land.
            onOpen()
        }
    }
}

/// The provenance footer: the not-for-navigation label over the caller's
/// caption line(s), followed by the report menu on its own line.
struct DetailFooter<Note: View>: View {
    /// The station a report is about — the same id the header favourites.
    let stationID: String
    /// The moment the strip is parked on, so a report names what they saw.
    var scrubTime: Date? = nil
    var tz: TimeZone = .current
    @ViewBuilder var note: () -> Note

    var body: some View {
        VStack(spacing: 6) {
            // 0.62: 0.4 measures 3.4:1 over the canvas, under WCAG's 4.5. The
            // platform audit only caught it on the CHS waiting page, where
            // the footer is above the fold; it is the same line everywhere.
            MonoLabel(text: String(localized: "Predictions — not for navigation", comment: "Safety disclaimer above station provenance."),
                      color: SN.foam.opacity(0.62), tracking: 1.4)
                .frame(maxWidth: .infinity)
            note()
            ReportProblemMenu(stationID: stationID, scrubTime: scrubTime, tz: tz)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

/// The collapsed provenance section (#170): where the numbers came from, for
/// the minority who want to know, without any of it intruding on the reader
/// who just wants the next slack. The container is shared; the rows are the
/// caller's, because a current gate wants its set bearings and its reference
/// offsets where a tide wants its datum.
struct StationDetails<Rows: View>: View {
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                rows()
            }
            .padding(.top, 8)
        } label: {
            Text("Station details").frame(minHeight: 44)
        }
        .font(.subheadline)
        .foregroundStyle(SN.foam.opacity(0.7))
        .tint(SN.foam.opacity(0.55))
        .padding(.horizontal, 24)
    }
}

/// One label/value line inside `StationDetails`.
struct StationDetailRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            // Every value in this column is a reading — a position, a bearing,
            // an offset, a speed — so the column carries the mono trait rather
            // than each caller remembering it (TypeScaleTests attests to this
            // for the formatter that reaches here through `detailsMeanFlow`).
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

/// A sentence inside `StationDetails` — the explanations that sit under a row
/// rather than beside a label.
struct StationDetailNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(SN.foam.opacity(0.55))
    }
}

// `ProvisionalBadge` — the ⚠️ disc that used to sit beside the region on a
// provisional card — is gone (#93). One marking per state: the fast answer is
// now `CardStatus.refining`'s strip, which says the word and the tolerance
// instead of leaving the reader to decode a triangle. Its contrast measurement
// (docs/testflight.md) still governs, and CardStatus.tint cites it.

// MARK: - Detail-to-detail navigation

/// Detail views push the paired port's own detail through this, not a
/// NavigationLink: NavigationLink is a Button, and Button press tracking
/// goes dead below the strip in the iPad split detail column while tap
/// gestures keep working (see MultiDaySchedule's row comment).
private struct OpenTideDetailKey: EnvironmentKey {
    static let defaultValue: (TideStationRecord) -> Void = { _ in }
}

extension EnvironmentValues {
    var openTideDetail: (TideStationRecord) -> Void {
        get { self[OpenTideDetailKey.self] }
        set { self[OpenTideDetailKey.self] = newValue }
    }
}

/// Same reasoning as `openTideDetail` above, generalized to any CHS route: a
/// detail or the Downloads sheet pushes a port/gate through this, not a
/// NavigationLink or a Button — NavigationLink is a Button, and Button press
/// tracking goes dead below the strip in the iPad split detail column (same
/// hazard `openTideDetail` avoids). One closure for every CHS push — the
/// online gate's nearest-shipped link and the downloads-row tap both go
/// through this, rather than each carrying its own single-case key.
private struct OpenChsRouteKey: EnvironmentKey {
    static let defaultValue: (ChsRoute) -> Void = { _ in }
}

extension EnvironmentValues {
    var openChsRoute: (ChsRoute) -> Void {
        get { self[OpenChsRouteKey.self] }
        set { self[OpenChsRouteKey.self] = newValue }
    }
}

/// `openTideDetail` generalized to any station kind: the nearby-station
/// discovery link can land on a NOAA current, a CHS port or a gate, and each
/// pushes a different route. Same closure-not-NavigationLink reasoning.
private struct OpenStationItemKey: EnvironmentKey {
    static let defaultValue: (StationItem) -> Void = { _ in }
}

extension EnvironmentValues {
    var openStationItem: (StationItem) -> Void {
        get { self[OpenStationItemKey.self] }
        set { self[OpenStationItemKey.self] = newValue }
    }
}

/// Same reasoning as `openChsRoute` above: the detail-header title (issue #32)
/// and the Nearby map jump straight to the map, focused on the detail's own
/// station at the zoom they pass — not a NavigationLink or Button, same
/// press-tracking hazard in the iPad split detail column.
private struct OpenMapFocusedKey: EnvironmentKey {
    static let defaultValue: (StationItem, Double) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var openMapFocused: (StationItem, Double) -> Void {
        get { self[OpenMapFocusedKey.self] }
        set { self[OpenMapFocusedKey.self] = newValue }
    }
}

/// The quiet branch-affordance row (matching stations, tide at port, nearest
/// gate): leaf caption text after a branch icon. A tap gesture, not a Button —
/// Button press tracking goes dead below the strip in the iPad split detail
/// column (see the environment keys below).
struct BranchLink: View {
    let text: String
    let id: String
    var chevron = true
    let action: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2.weight(.semibold))
            // Mono digits: a branch label can carry a reading (a match count,
            // the nearby link's distance), and numbers hold their width.
            Text(text)
                .monospacedDigit()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(SN.leaf)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }
}

/// The one tide affordance on a current/gate detail (split-scrubbers spec
/// §2): navigating to the port's own TideDetailView. No tide numbers here.
struct TideAtPortLink: View {
    let port: TideStationRecord
    @Environment(\.openTideDetail) private var openTide

    var body: some View {
        BranchLink(text: String(localized: "Tide at \(port.name)", comment: "Link to a related tide station. The value is a station name."), id: "tide-at-port") { openTide(port) }
    }
}

/// The cross-series discovery affordance: the nearest station of the other
/// series, offered by proximity alone. The distance is in the label because
/// nearness is the whole claim — unlike `TideAtPortLink`, nothing curated
/// says this station governs or matches this water.
struct NearbyStationLink: View {
    let item: StationItem
    let km: Double
    @Environment(\.openStationItem) private var open

    var body: some View {
        let currents = item.series == .current
        BranchLink(text: currents
            ? String(localized: "Currents at \(item.name) · \(formatNm(km))", comment: "Link to a nearby current station. Values are station name and localized distance.")
            : String(localized: "Tide at \(item.name) · \(formatNm(km))", comment: "Link to a nearby tide station. Values are station name and localized distance."),
                   id: currents ? "nearby-currents" : "nearby-tide") { open(item) }
    }
}

/// A station page's link row: its tide or current link on the left, the
/// chooser for its namesakes on the right.
struct StationLinksRow<Leading: View>: View {
    let stationId: String
    @ViewBuilder let leading: () -> Leading
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let chooser = StationItem.byId[stationId].map { MatchingStationsLink(item: $0) }
        // Side by side leaves neither half room at accessibility sizes.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                leading()
                chooser
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                leading()
                chooser.fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// The persisted Tides/Currents pick. Standard defaults, not the App Group:
/// no widget reads it.
let seriesFilterKey = "slackwater.seriesFilter"

/// The Tides/Currents narrowing — three quiet capsules over one persisted
/// filter, shared by Near Me, search and every detail's Nearby. Tapping the
/// active one is a second way back to All, for a thumb already on it.
struct SeriesFilterChips: View {
    @AppStorage(seriesFilterKey) private var filter: StationSeries?

    var body: some View {
        let all = chip(String(localized: "All", comment: "Station series filter showing all stations."), nil)
        let tides = chip(String(localized: "Tides", comment: "Station series filter showing tide stations."), .tide)
        let currents = chip(String(localized: "Currents", comment: "Station series filter showing current stations."), .current)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { all; tides; currents }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) { all; tides }
                currents
            }
            VStack(alignment: .leading, spacing: 0) { all; tides; currents }
        }
    }

    private func chip(_ label: String, _ series: StationSeries?) -> some View {
        let selected = filter == series
        let accessibility = switch series {
        case nil: String(localized: "Show all", comment: "Accessibility label for the station filter that shows all stations.")
        case .tide: String(localized: "Show tides", comment: "Accessibility label for the station filter that shows tide stations.")
        case .current: String(localized: "Show currents", comment: "Accessibility label for the station filter that shows current stations.")
        }
        // A tap gesture, not a Button: Nearby puts these below the strip,
        // where Button press tracking goes dead in the iPad split detail column.
        return Text(label)
            .font(.caption.weight(.medium))
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(selected ? SN.leaf : SN.foam.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(selected ? .regular.tint(SN.leaf.opacity(0.25)).interactive()
                                  : .regular.interactive(), in: Capsule())
            // The capsule stays compact; the target is the 44-point row.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture { filter = selected ? nil : series }
            .accessibilityLabel(accessibility)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("series-filter-\(series.map { $0.rawValue + "s" } ?? "all")")
    }
}

/// The stations picked in the matching-station chooser. The list shows a pick
/// in place of the nearest namesake (`RankedStations`), and the widget's
/// nearest-station ids resolve to it (`LocationService.cacheNearestWidgetStation`).
/// The App Group copy is this device's truth; iCloud carries picks between devices.
///
/// A pick is a station id, not a place: a place is a series and a name, and a
/// name is the database's to change between catalog releases. Keyed by name,
/// a pick was orphaned by every rename; as an id it survives them, and the
/// group it answers for is found again from the id at read time.
final class ChosenStationsStore: ObservableObject {
    static let shared = ChosenStationsStore()
    static let cloudPrefix = "slackwater.pick."

    @Published private(set) var ids: Set<String>

    private init() {
        ids = Self.load(AppGroup.defaults)
        // Nil under both kinds of test, like favourites (FavoritesCloud.store).
        guard let cloud = FavoritesCloud.store else { return }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.adopt(cloud) } }
        cloud.synchronize()
        MainActor.assumeIsolated { self.adopt(cloud) }
    }

    /// The picks on disk. Builds before the catalog could rename a station
    /// kept them as place key → id; the values are the ids, so that shape is
    /// read as-is and written back as the array on the next change.
    static func load(_ defaults: UserDefaults) -> Set<String> {
        if let ids = defaults.stringArray(forKey: AppGroup.chosenStationsKey) { return Set(ids) }
        let legacy = defaults.dictionary(forKey: AppGroup.chosenStationsKey) as? [String: String] ?? [:]
        return Set(legacy.values)
    }

    /// The pick that answers for a group of namesakes, nearest first: the
    /// first member chosen. Two can be chosen at once only after a rename
    /// merged two places, and the nearer is what the chooser would show anyway.
    static func chosen(in group: [StationItem], from ids: Set<String>) -> StationItem? {
        group.first { ids.contains($0.id) }
    }

    /// `ids` with `item` picked for its place: the other members of the place
    /// leave, so a pick stays one per place under the names of the day.
    static func choosing(_ item: StationItem, in ids: Set<String>) -> Set<String> {
        let place = Set((StationItem.byPlace[item.placeKey] ?? [item]).map(\.id))
        return ids.subtracting(place).union([item.id])
    }

    /// One KVS key per place, so two devices picking for the same place
    /// resolve last-writer-wins with no merge code (see FavoritesCloud). Keys
    /// cap at 64 bytes and a place key can run past that, so it is hashed.
    static func cloudKey(_ placeKey: String) -> String {
        // FNV-1a: stable across launches and devices, unlike `hashValue`.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in placeKey.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return cloudPrefix + String(hash, radix: 16)
    }

    /// The picked ids, out of `dictionaryRepresentation`. The key is only a
    /// collision slot; a pick for a station no longer bundled drops out.
    static func picks(_ raw: [String: Any]) -> Set<String> {
        var out = Set<String>()
        for (key, value) in raw where key.hasPrefix(cloudPrefix) {
            guard let id = value as? String, StationItem.byId[id] != nil else { continue }
            out.insert(id)
        }
        return out
    }

    @MainActor func choose(_ item: StationItem) {
        guard !ids.contains(item.id) else { return }
        if let cloud = FavoritesCloud.store {
            // A pick the cloud holds for another member of this place, under
            // whatever name it had when it was made, would read back beside
            // this one; it is the pick this one replaces.
            let place = Set((StationItem.byPlace[item.placeKey] ?? []).map(\.id))
            for (key, value) in cloud.dictionaryRepresentation
            where key.hasPrefix(Self.cloudPrefix) && place.contains(value as? String ?? "") {
                cloud.removeObject(forKey: key)
            }
            cloud.set(item.id, forKey: Self.cloudKey(item.placeKey))
        }
        apply(Self.choosing(item, in: ids))
    }

    /// The cloud's picks win their places. A pick only this device has, for a
    /// place the cloud has none for, is written up — how picks made before
    /// iCloud reach it.
    @MainActor private func adopt(_ cloud: NSUbiquitousKeyValueStore) {
        let picks = Self.picks(cloud.dictionaryRepresentation)
        let cloudPlaces = Set(picks.compactMap { StationItem.byId[$0]?.placeKey })
        var next = picks
        for id in ids where !picks.contains(id) {
            guard let item = StationItem.byId[id], !cloudPlaces.contains(item.placeKey) else { continue }
            cloud.set(id, forKey: Self.cloudKey(item.placeKey))
            next.insert(id)
        }
        apply(next)
    }

    @MainActor private func apply(_ next: Set<String>) {
        guard next != ids else { return }
        ids = next
        AppGroup.defaults.set(Array(ids).sorted(), forKey: AppGroup.chosenStationsKey)
        // Without a fix the widget ids catch up on the next one.
        let loc = LocationService.shared
        if loc.authorized, let c = loc.location?.coordinate,
           LocationService.cacheNearestWidgetStation(lat: c.latitude, lon: c.longitude) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

// MARK: - One entry per place (M50)

/// Same-named stations are one place answered by several stations. NOAA alone
/// ships 19 collided names in the bundle — three "Point Wilson", four "The
/// Narrows", two "Discovery Island" — and in a distance-ranked list they
/// render as identical cards stacked on each other, distinguishable only by
/// the distance pill.
///
/// So a name renders once, as its nearest station, and the rest stay one tap
/// away behind the matching-station chooser: the list-side application of the
/// web's multi-match chooser (slackwater-web `src/StationChooser.tsx`,
/// web-client-design § "the multi-match chooser" — "where more than one
/// station plausibly serves a place, say so rather than silently picking").
///
/// Favorites are deliberately *not* collapsed: a starred station is an
/// explicit pick, and quietly swapping it for a nearer namesake would override
/// a choice the user made on purpose.
///
/// A tide and a current station sharing a name are two places: the series is
/// a separate choice everywhere else, and a filter on one series must not hide
/// a station behind a namesake of the other.
struct StationGroups {
    /// Series and name -> every station carrying them, nearest first.
    private let byName: [String: [StationItem]]
    /// Any station id -> the id that actually renders for its name.
    private let canonical: [String: String]
    /// `collapse(ranked ids)`, done once here rather than per render: the
    /// list re-evaluates on every fit-queue transition, and mapping 3,600
    /// ids through a Set each time to find four is what #232 measured.
    let shownIds: [String]

    /// `ranked` is the catalog sorted nearest-first, so the first station of a
    /// name is the nearest one — the one shown, unless `chosen` (station ids,
    /// `ChosenStationsStore`) holds another station of that place.
    init(ranked: [StationItem], chosen: Set<String> = []) {
        var byName: [String: [StationItem]] = [:]
        for item in ranked { byName[item.placeKey, default: []].append(item) }
        self.byName = byName
        let shownForPlace = byName.mapValues { group in
            (ChosenStationsStore.chosen(in: group, from: chosen) ?? group[0]).id
        }
        let canonical = Dictionary(ranked.map { ($0.id, shownForPlace[$0.placeKey] ?? $0.id) },
                                   uniquingKeysWith: { first, _ in first })
        self.canonical = canonical
        var seen = Set<String>()
        shownIds = ranked.map { canonical[$0.id] ?? $0.id }.filter { seen.insert($0).inserted }
    }

    /// What renders in place of `id` — itself, unless a nearer station shares its name.
    func shown(_ id: String) -> String { canonical[id] ?? id }

    /// Collapse ids to what renders: one per name, input order kept.
    func collapse(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.map(shown).filter { seen.insert($0).inserted }
    }

    /// Every station sharing this one's series and name, nearest first — the chooser's rows.
    func matches(_ item: StationItem) -> [StationItem] { byName[item.placeKey] ?? [item] }
}

// MARK: - The distance-ranked catalog, memoised (M53)

/// The list ranks the whole catalog by distance and builds `StationGroups`
/// over it — and it does that inside `body`, which SwiftUI re-evaluates on
/// every fit that lands, every favourite toggle, every unit switch. At 41
/// bundled stations nobody could measure it. At 3,125 it is a 3,125-element
/// sort plus two dictionary builds, tens of times a second.
///
/// So it is computed once per FIX, not once per render. The key is the fix
/// rounded to ~100 m — finer than the list can show, coarser than GPS jitter,
/// so a boat at anchor pays for this exactly once.
@MainActor
enum RankedStations {
    private static var key = ""
    private static var ranked: [StationItem] = []
    private static var groups = StationGroups(ranked: [])
    private static var chosen: Set<String> = []

    /// A chooser pick regroups without re-sorting: the order depends on the fix alone.
    static func near(lat: Double, lon: Double) -> (ranked: [StationItem], groups: StationGroups) {
        let k = "\(Int((lat * 1000).rounded())),\(Int((lon * 1000).rounded()))"
        let picks = ChosenStationsStore.shared.ids
        let moved = k != key
        if moved {
            key = k
            ranked = StationItem.rankedByDistance(StationItem.all, lat: lat, lon: lon)
        }
        if moved || picks != chosen {
            chosen = picks
            groups = StationGroups(ranked: ranked, chosen: picks)
        }
        return (ranked, groups)
    }
}
