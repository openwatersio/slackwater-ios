// Slackwater — GPL v3. Detail-view chrome and list state; the palette and formatters live in Palette.swift so the widget can share them.
import SwiftUI
import WidgetKit

// MARK: - Detail-view shared pieces (tide + current)

/// "42m" / "2h 14m" until `target`, floored at zero.
func countdown(from: Date, to target: Date) -> String {
    let minutes = max(Int(target.timeIntervalSince(from) / 60), 0)
    return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
}

func slackWindowTiming(start: Date, end: Date, tz: TimeZone) -> (duration: String?, span: String) {
    let minutes = max(Int((end.timeIntervalSince(start) / 60).rounded()), 0)
    let hours = Int((Double(minutes) / 60).rounded())
    let duration = minutes < 60 ? "\(minutes) min"
        : hours <= 2 ? "~\(hours) \(hours == 1 ? "hr" : "hrs")"
        : nil
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = tz
    let days = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: end)).day ?? 0, 0)
    let digits = ["", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
    let suffix = days == 0 ? "" : days < 10 ? "⁺\(digits[days])" : "⁺⁺"
    return (duration, "\(clockTime(start, tz)) → \(clockTime(end, tz))\(suffix)")
}

/// The moon's dark-limb offset for a disc of radius `r`: covering at new
/// (shift 0), clear at full (2r), lit side right while waxing. (The prototype
/// export's (1-fraction)·1.9r is inverted — it blacks out a full moon.)
/// Shared by `MoonGlyph` and the strip's night moons: the SwiftUI and
/// GraphicsContext renderers can't merge, so the geometry must.
func moonLimbShift(fraction: Double, waxing: Bool, radius: CGFloat) -> CGFloat {
    (waxing ? -1 : 1) * CGFloat(fraction) * 2 * radius
}

/// The prototype's moon glyph (moonGlyphEl): a lit disc with the dark limb as
/// an offset circle clipped to the disc — fullness and waxing side track the
/// illumination as you scrub across days.
struct MoonGlyph: View {
    let fraction: Double
    let waxing: Bool
    var size: CGFloat = 20

    var body: some View {
        let r = size / 2 - 1
        let shift = moonLimbShift(fraction: fraction, waxing: waxing, radius: r)
        ZStack {
            Circle().fill(SN.foam)
            Circle().fill(SN.moonLimb).offset(x: shift)
        }
        .frame(width: 2 * r, height: 2 * r)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "Aug 7" — the when-row's date. No weekday and no TODAY/TOMORROW: the
/// scrubber's day headers already carry those, and repeating them here read
/// as "SUN · SUN, AUG 9" the moment you scrubbed (design feedback 2026-08-07).
func monthDay(_ date: Date, _ tz: TimeZone) -> String {
    formatter("MMM d", tz).string(from: date)
}

/// The schedule's span, as the range bar prints it: `Aug 11 – 17`,
/// `Aug 28 – Sep 3`, `Dec 29 – Jan 4, 2027`.
///
/// The second date is the LAST DAY SHOWN — `anchor + 6` — not the exclusive
/// `scheduleRange` upper bound. The window is rolling rather than a calendar
/// week, so this bar is the only thing on screen that says what span you are
/// looking at; naming a day that is not in the list below it would be the
/// same defect as calling a Tue→Mon window "Week of Aug 9 – 16".
///
/// The month repeats only when it changes, and the year appears only when the
/// range crosses one — a bar that printed "2026" every week would be teaching
/// the user to stop reading it.
func weekRangeLabel(anchor: Date, tz: TimeZone) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let last = cal.date(byAdding: .day, value: Int(Timeline.scheduleDays) - 1, to: anchor)!

    let head = formatter("MMM d", tz).string(from: anchor)

    let sameMonth = cal.isDate(anchor, equalTo: last, toGranularity: .month)
    let sameYear = cal.isDate(anchor, equalTo: last, toGranularity: .year)
    let tailPattern = sameYear ? (sameMonth ? "d" : "MMM d") : "MMM d, yyyy"
    return "\(head) – \(formatter(tailPattern, tz).string(from: last))"
}

/// The *when* of a scrub reading — clock time stacked over the date, the
/// return-to-now slot directly beside them, moon trailing. The LAST row of
/// every scrub card: it is the calendar of the reading, secondary to what the
/// water is doing (2026-08-03 hero-crop spec §3). The slot lives HERE, in one
/// shared row, because giving it a home per-card had it bouncing between
/// layouts and dragging row alignment around with it (2026-08-07).
struct ScrubWhen: View {
    let scrubTime: Date
    let live: Date
    let tz: TimeZone
    let onReturn: () -> Void
    var summary: (label: String, value: String)? = nil

    var body: some View {
        let moon = SunMoon.moonIllumination(date: scrubTime)
        if let summary {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    MonoLabel(text: summary.label, color: SN.foam.opacity(0.5))
                    Text(summary.value)
                        .font(.title.weight(.medium).monospacedDigit())
                        .foregroundStyle(SN.foam)
                }
                Spacer()
                moonPhase(moon)
            }
            .accessibilityElement(children: .contain)
        } else {
        // Wrap, never truncate (the StationCard rule): the one-line row is
        // tier 1, and when the .title time, the fixed 44pt slot and the
        // phase name outgrow the width — AX3 and up on a phone — the moon
        // drops to its own line instead of the phase clipping to "…".
        // Which tier wins is verified by geometry in ScrubWhenTests, not
        // asked directly — ViewThatFits exposes no way to ask.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                timeAndSlot
                Spacer()
                moonPhase(moon)
            }
            VStack(alignment: .leading, spacing: 10) {
                timeAndSlot
                moonPhase(moon)
            }
        }
        .accessibilityElement(children: .contain)
        }
    }

    private var timeAndSlot: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cardTime(scrubTime, tz))
                    .font(.title.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                MonoLabel(text: monthDay(scrubTime, tz))
            }
            ReturnToNowSlot(scrubTime: scrubTime, live: live, onReturn: onReturn)
        }
    }

    private func moonPhase(_ moon: SunMoon.MoonIllumination) -> some View {
        HStack(spacing: 14) {
            MoonGlyph(fraction: moon.fraction, waxing: moon.waxing, size: 22)
            Text(SunMoon.phaseName(phase: moon.phase))
                .font(.caption2)
                .foregroundStyle(SN.foam.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Return-to-now as a FIXED 44pt slot: present or not, it occupies the same
/// points, so the readout row never reflows when a scrub starts or ends (the
/// occupies-its-points-either-way reasoning the old hero overlay used).
struct ReturnToNowSlot: View {
    let scrubTime: Date
    let live: Date
    let onReturn: () -> Void

    var body: some View {
        ZStack {
            if scrubbedAway(scrubTime, from: live) {
                Button(action: onReturn) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SN.leaf)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .accessibilityLabel("Return to now")
                // Distinct from the strip's floating `detail-return-now`.
                .accessibilityIdentifier("when-row-return-now")
            }
        }
        .frame(width: 44, height: 44)
    }
}

// MARK: - The scrub-detail scaffold (tide / current / derived gate / online gate)

/// The four scrub details' shared anatomy: map-header hero, scrub card
/// (caller's readout + strip, then the shared swipe hint, ScrubWhen and card
/// chrome), the rolling schedule card, and the bottom slot (footer — or the
/// online gate's honesty card, which is also what shows while `timeline` is
/// nil). Return-to-now lives here: live = appNow(), scrub back onto it.
struct ScrubDetailScaffold<Above: View, Card: View, Links: View, Bottom: View>: View {
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double
    let favoriteId: String
    let tz: TimeZone
    let timeline: TimelineData?
    let entries: (TimelineData) -> [ScheduleEntry]
    @Binding var live: Date
    @Binding var scrubTime: Date
    /// Return-to-now, owned by the caller: it resets the window's `anchor` too,
    /// which only the detail view holds. Parking the centerline at a `now` that
    /// isn't on a September strip would be the half of the job the scaffold can
    /// see and the wrong half to do alone.
    let onReturn: () -> Void
    /// The window's anchor. The scaffold moves it (via the picker) but does not
    /// own it — it lives in the detail view, which is also what makes
    /// `onReturn` caller-owned.
    @Binding var anchor: Date
    /// Fired when the picker OPENS, before a date is chosen. Only an online
    /// gate has anything to do here (speculatively fetch the next block); the
    /// other three are constituents and pass a no-op.
    var onPickerOpen: () -> Void = {}
    /// Fired after the anchor moves, with the picked date. The three
    /// `@State`-backed views rebuild here; the online gate re-checks coverage.
    var onPicked: (Date) -> Void = { _ in }
    /// Optional aggregate reading for the bottom of the scrub card.
    var scrubSummary: (TimelineData) -> (label: String, value: String)? = { _ in nil }
    @State private var showPicker = false
    /// Between the header and the scrub card (the fast-answer amber card).
    @ViewBuilder var above: () -> Above
    /// Readout + strip (+ any notes), in the caller's order — everything in
    /// the scrub card above its shared tail.
    @ViewBuilder var card: (TimelineData) -> Card
    /// After ScrubWhen, still inside the scrub card (TideAtPortLink).
    @ViewBuilder var links: () -> Links
    /// Below the schedule card; each element gets the standard 14pt top gap.
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        // GeometryReader sits inside the safe area (only the ScrollView below
        // ignores it), so the proxy reads the real top inset for MapHeader —
        // per device and per iPad split-view pane, live across rotation.
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    MapHeader(name: name, region: region,
                              latitude: latitude, longitude: longitude,
                              favoriteId: favoriteId,
                              topSafeInset: geo.safeAreaInsets.top,
                              minHeight: (geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom) / 3)
                    above()
                    if let timeline {
                        scrubCard(timeline)
                        scheduleCard(timeline)
                            .padding(.top, 14)
                    } else if anchor != .distantPast {
                        // #67 item 2: no timeline means the caller is showing its
                        // honesty card below — but the bar (and its picker) need
                        // no timeline, and without them that card is a dead end
                        // with no way back to a covered week. Guarded on anchor:
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
                }
                .padding(.bottom, 42)
            }
            .ignoresSafeArea(edges: .top)
            .background(CanvasBackground())
            .environment(\.timeZone, tz)
            .toolbar(.hidden, for: .navigationBar)
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

    private func scrubCard(_ tl: TimelineData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            card(tl)

            // No "‹ swipe to scrub ›" label here, and none is coming back
            // (#58): "scrubber" is audio-editing jargon, and testers who read
            // the label still didn't find the horizontal scroll. The strip's
            // own opening slide-into-place is the affordance now —
            // `TimelineScrubber.centerIfNeeded`.
            ScrubWhen(scrubTime: scrubTime, live: live, tz: tz, onReturn: onReturn,
                      summary: scrubSummary(tl))
                .padding(.top, 14)

            links()
                .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(SN.cardFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SN.leaf.opacity(0.22)).frame(height: 0.5)
        }
    }

    private func scheduleCard(_ tl: TimelineData) -> some View {
        VStack(spacing: 0) {
            WeekRangeBar(anchor: tl.anchor, today: tl.today, tz: tz, onTap: { showPicker = true })
            Divider().overlay(Color.white.opacity(0.08))
            // Both dates, never one: `anchor` keys the day groups (it is what
            // `days` offsets are relative to), `today` only says Today/Tomorrow.
            MultiDaySchedule(entries: entries(tl), tz: tz, anchor: tl.anchor,
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
                Text(weekRangeLabel(anchor: anchor, tz: tz))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                if anchor != today {
                    // The bar is the clearest statement on screen that you are
                    // not looking at this week, so it carries the way back.
                    Text("not this week")
                        .font(.caption2)
                        .foregroundStyle(SN.amber)
                }
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
        .accessibilityLabel("Showing \(weekRangeLabel(anchor: anchor, tz: tz)). Tap to choose a date.")
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("Week starting", selection: $draft,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(SN.go)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("week-picker")
                Spacer()
            }
            .background(CanvasBackground())
            .navigationTitle("Choose a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") {
                        var cal = Calendar(identifier: .gregorian)
                        cal.timeZone = tz
                        let picked = cal.startOfDay(for: draft)
                        anchor = picked
                        onPick(picked)
                        dismiss()
                    }
                    .accessibilityIdentifier("week-picker-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
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
/// caption line(s).
struct DetailFooter<Note: View>: View {
    @ViewBuilder var note: () -> Note

    var body: some View {
        VStack(spacing: 6) {
            MonoLabel(text: "Predictions — not for navigation",
                      color: SN.foam.opacity(0.4), tracking: 1.4)
            note()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
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

/// Same reasoning as `openChsRoute` above: the map-header title (issue #32)
/// jumps straight to the map, focused on the detail's own station — not a
/// NavigationLink or Button, same press-tracking hazard in the iPad split
/// detail column.
private struct OpenMapFocusedKey: EnvironmentKey {
    static let defaultValue: (StationItem) -> Void = { _ in }
}

extension EnvironmentValues {
    var openMapFocused: (StationItem) -> Void {
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
            Text(text)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(SN.leaf)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        BranchLink(text: "Tide at \(port.name)", id: "tide-at-port") { openTide(port) }
    }
}

// MARK: - Recently viewed stations (prototype "Recent" list, Bryan's Recents)

/// Most-recent-first, capped at 6 (prototype addRecent slice(0,6)), persisted
/// in UserDefaults. Recorded by the detail views on appear.
final class RecentsStore: ObservableObject {
    static let shared = RecentsStore()
    private static let key = AppGroup.recentsKey

    @Published private(set) var ids: [String]

    /// Armed by the regular-width auto-selection (M52) with the id of exactly
    /// the detail it opens. The pane opening itself is not the user viewing a
    /// station, and counting it would evict a real entry from the 6-slot
    /// history on every single launch. Scoped to the id — an unfitted CHS
    /// station's waiting view records nothing at all, so a bare flag would
    /// survive it and swallow the next genuinely opened station (#3). Any
    /// record attempt disarms it.
    var skipNextRecordID: String?

    private init() {
        // UI-test hook, like -resetGate: a clean no-recents first run.
        if CommandLine.arguments.contains("-resetRecents") {
            AppGroup.defaults.removeObject(forKey: Self.key)
        }
        ids = AppGroup.defaults.stringArray(forKey: Self.key) ?? []
    }

    func record(_ id: String) {
        let skip = id == skipNextRecordID
        skipNextRecordID = nil
        if skip { return }
        var next = ids.filter { $0 != id }
        next.insert(id, at: 0)
        next = Array(next.prefix(6))
        ids = next
        AppGroup.defaults.set(next, forKey: Self.key)
    }

    /// Swipe "Remove" on a Recents row (current-detail spec §9: true deletion).
    func remove(_ id: String) {
        ids.removeAll { $0 == id }
        AppGroup.defaults.set(ids, forKey: Self.key)
    }

    var items: [StationItem] {
        ids.compactMap { id in StationItem.all.first { $0.id == id } }
    }

    /// The most recently opened station, which is the best guess at where the
    /// user is when Core Location has told us nothing.
    var lastOpened: StationItem? { items.first }
}

// MARK: - Favorites (current-detail spec §9; prototype TidesApp savedIds)

/// Starred stations, in star order, persisted on the device and in iCloud (#134).
///
/// Storage only: `ids`, `contains`, `toggle`, `forget` and `replace` are what
/// they were before the cloud existed. The App Group copy stays this device's
/// own truth — it is what the widget reads (`WidgetStationLoader
/// .defaultStationID`) and what a device without iCloud falls back to — while
/// `FavoritesCloud` carries the same list between devices.
///
/// ponytail: RecentsStore keeps the same shape and stays device-local on
/// purpose. Recents are a record of what you did on *this* device; favourites
/// are the list you curated. Sync them if that ever stops being true.
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()
    private static let key = AppGroup.favoritesKey
    /// Set once this device's list has been written out as per-station cloud
    /// keys. Until then the cloud has never heard of these stars and must be
    /// merged with rather than adopted — adopting an empty cloud is exactly
    /// how an upgrading user loses the six gates they starred.
    private static let migratedKey = "slackwater.favorites.cloudMigrated"

    @Published private(set) var ids: [String]

    private init() {
        // UI-test hook, like -resetRecents: a clean no-favorites run.
        if CommandLine.arguments.contains("-resetFavorites") {
            AppGroup.defaults.removeObject(forKey: Self.key)
        }
        // UI-test hook: `-seedFavorites a,b` starts the run with exactly those
        // ids starred. The only way to exercise a favorite whose station has
        // left the bundle (issue #91) — by construction the app can't star one,
        // and the interesting state is a device that starred it releases ago.
        if let i = CommandLine.arguments.firstIndex(of: "-seedFavorites"),
           i + 1 < CommandLine.arguments.count {
            AppGroup.defaults.set(
                CommandLine.arguments[i + 1].split(separator: ",").map(String.init), forKey: Self.key)
        }
        ids = AppGroup.defaults.stringArray(forKey: Self.key) ?? []

        // Nil under both kinds of test, so those hooks stay device-local
        // (FavoritesCloud.store).
        guard let cloud = FavoritesCloud.store else { return }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] note in self?.cloudChanged(note, cloud) }
        cloud.synchronize()
        adopt(cloud)
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if let i = ids.firstIndex(of: id) {
            ids.remove(at: i)
            unstar(id)
            // Spec §9: unfavoriting re-files to Recents, never data loss.
            RecentsStore.shared.record(id)
        } else {
            ids.append(id)
            star(id)
        }
        persist()
        // A widget's default station is "first favorite" (WidgetStationLoader
        // .defaultStationID) — starring/unstarring can change what an
        // unconfigured widget shows, so its timeline must not wait for the
        // next half-hourly tick (H1).
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// True removal, for a station that has left the bundle (issue #91).
    /// Not `toggle`: that re-files to Recents (spec §9), and a station that no
    /// longer exists is the one thing Recents cannot show.
    func forget(_ id: String) {
        guard ids.contains(id) else { return }
        ids.removeAll { $0 == id }
        unstar(id)
        persist()
    }

    /// Swap a removed station for the replacement the user picked, in place —
    /// favorites render in the order they were starred, and the replacement
    /// inherits the dead one's slot rather than jumping to the end.
    func replace(_ old: String, with new: String) {
        guard let i = ids.firstIndex(of: old) else { return }
        ids.remove(at: i)
        let inserted = !ids.contains(new)
        if inserted { ids.insert(new, at: i) }
        // The replacement inherits the dead station's *stamp* as well as its
        // slot, or the next device to sync would sort it to the end.
        let stamp = FavoritesCloud.store?.double(forKey: FavoritesCloud.prefix + old) ?? 0
        unstar(old)
        if inserted { star(new, at: stamp > 0 ? stamp : nil) }
        persist()
    }

    var items: [StationItem] {
        ids.compactMap { id in StationItem.all.first { $0.id == id } }
    }

    // MARK: - iCloud (see FavoritesCloud)

    private func persist() { AppGroup.defaults.set(ids, forKey: Self.key) }

    private func star(_ id: String, at stamp: Double? = nil) {
        FavoritesCloud.store?.set(stamp ?? Date().timeIntervalSince1970,
                                  forKey: FavoritesCloud.prefix + id)
    }

    private func unstar(_ id: String) {
        FavoritesCloud.store?.removeObject(forKey: FavoritesCloud.prefix + id)
    }

    private func cloudChanged(_ note: Notification, _ cloud: NSUbiquitousKeyValueStore) {
        // Signing in or out of iCloud hands us a different store, usually an
        // empty one. Adopting that erases a list the user can still see on this
        // device, so treat the new account as never-migrated and let this
        // device's stars seed it instead.
        if note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            == NSUbiquitousKeyValueStoreAccountChange {
            AppGroup.defaults.set(false, forKey: Self.migratedKey)
        }
        adopt(cloud)
    }

    /// Reconcile with the cloud. Everything that can lose a star lives in
    /// `FavoritesCloud.reconcile`, which is a pure function; this is its I/O.
    private func adopt(_ cloud: NSUbiquitousKeyValueStore) {
        let migrated = AppGroup.defaults.bool(forKey: Self.migratedKey)
        let (next, writes) = FavoritesCloud.reconcile(
            local: ids,
            cloud: FavoritesCloud.stamps(cloud.dictionaryRepresentation),
            migrated: migrated,
            now: Date().timeIntervalSince1970)
        for (id, stamp) in writes { cloud.set(stamp, forKey: FavoritesCloud.prefix + id) }
        if !migrated { AppGroup.defaults.set(true, forKey: Self.migratedKey) }
        guard next != ids else { return }
        ids = next
        persist()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// The one dedupe rule: each station renders in at most one group —
/// My Location > Favorites > Near Me > Recents (Bryan's M4.5 order: Recents at
/// the very bottom is the floor — a station both nearby and recent shows under
/// Near Me; Recents holds only stations not already shown above). Persisted
/// stores are untouched; exclusion is render-time only, so a station reappears
/// when it stops being the hero / a favorite / nearby.
struct ListGroups {
    let favorites: [String]
    let nearMe: [String]
    let recents: [String]

    init(heroId: String?, favoriteIds: [String], recentIds: [String],
         rankedIds: [String], nearCount: Int) {
        favorites = favoriteIds.filter { $0 != heroId }
        var shown = Set(favorites)
        if let heroId { shown.insert(heroId) }
        nearMe = Array(rankedIds.filter { !shown.contains($0) }.prefix(nearCount))
        shown.formUnion(nearMe)
        recents = recentIds.filter { !shown.contains($0) }
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
struct StationGroups {
    /// Name -> every station carrying it, nearest first.
    private let byName: [String: [StationItem]]
    /// Any station id -> the id that actually renders for its name.
    private let canonical: [String: String]

    /// `ranked` is the catalog sorted nearest-first, so the first station of a
    /// name is the nearest one — the one shown.
    init(ranked: [StationItem]) {
        var byName: [String: [StationItem]] = [:]
        for item in ranked { byName[item.name, default: []].append(item) }
        self.byName = byName
        canonical = Dictionary(ranked.map { ($0.id, byName[$0.name]?.first?.id ?? $0.id) },
                               uniquingKeysWith: { first, _ in first })
    }

    /// What renders in place of `id` — itself, unless a nearer station shares its name.
    func shown(_ id: String) -> String { canonical[id] ?? id }

    /// Collapse ids to what renders: one per name, input order kept.
    func collapse(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.map(shown).filter { seen.insert($0).inserted }
    }

    /// Every station sharing this one's name, nearest first — the chooser's rows.
    func matches(_ item: StationItem) -> [StationItem] { byName[item.name] ?? [item] }
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

    static func near(lat: Double, lon: Double) -> (ranked: [StationItem], groups: StationGroups) {
        let k = "\(Int((lat * 1000).rounded())),\(Int((lon * 1000).rounded()))"
        if k != key {
            key = k
            ranked = StationItem.all.sorted {
                $0.km(fromLat: lat, lon: lon) < $1.km(fromLat: lat, lon: lon)
            }
            groups = StationGroups(ranked: ranked)
        }
        return (ranked, groups)
    }
}
