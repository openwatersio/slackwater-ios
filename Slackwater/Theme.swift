// Slackwater — GPL v3. Design tokens from the prototype design system
// (prototype/_ds/_ds_bundle.css): sn- palette, Fraunces/Geist/Geist Mono type
// roles, and the web app's unit formatting. The per-station gradient trios
// this once carried are gone (M53 layout A) — cards take a flat SN.cardFill.
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A pale tint of `hex`, blended toward white — for small text on a
    /// near-black chart, where plain `.opacity()` just reads as dim rather
    /// than pale. Takes the hex, not a Color, so callers stay one edit away
    /// from the base token instead of a second hand-picked literal.
    static func hex(_ hex: UInt32, lightenedBy t: Double) -> Color {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        return Color(red: (r + (255 - r) * t) / 255,
                     green: (g + (255 - g) * t) / 255,
                     blue: (b + (255 - b) * t) / 255)
    }
}

enum SN {
    static let navyDeep = Color(hex: 0x00183C)
    static let canvas = Color(hex: 0x05122A)      // list canvas
    static let canvasGlow = Color(hex: 0x0A2140)  // radial glow at top of list
    static let page = Color(hex: 0x00121F)        // 1b Modular detail page
    static let leaf = Color(hex: 0x88B868)
    static let steelHex: UInt32 = 0x5888A8
    static let steel = Color(hex: steelHex)
    static let foam = Color(hex: 0xE4F0E4)
    static let paper = Color(hex: 0xFCFCFC)
    // Direction is one signed diverging axis (colourblind-safe amber/blue);
    // green means only slack — never colour anything by station kind.
    // Raw hexes too: MapLibre style dicts hold strings, so MapScreen formats
    // these into "#rrggbb" rather than hand-maintaining a second palette.
    static let floodHex: UInt32 = 0x4A9FD8
    static let ebbHex: UInt32 = 0xE8A33D
    static let goHex: UInt32 = 0x88B868
    static let flood = Color(hex: floodHex)
    static let ebb = Color(hex: ebbHex)
    static let go = Color(hex: goHex)
    static let rising = flood
    static let falling = ebb
    /// Pale flood/ebb for small chart text on near-black — derived from the
    /// same hex so retargeting a token keeps its label in lockstep.
    static let floodLabel = Color.hex(floodHex, lightenedBy: 0.6)
    static let ebbLabel = Color.hex(ebbHex, lightenedBy: 0.6)
    static let cardStroke = leaf.opacity(0.16)
    static let cardFill = Color.white.opacity(0.05)
    static let night = Color(hex: 0x00101F)        // prototype night band
    static let sun = Color(hex: 0xF0C860)          // prototype sun dot
    /// Attention, never alarm: deliberately red-leaning so it cannot be
    /// misread as `ebb`. Same value the web app uses. (The retired literal is
    /// not spelled here — `testNoSourceFileSpellsARetiredColour` bans it.)
    static let amber = Color(hex: 0xEF6F4A)
    static let sunrise = Color(hex: 0xF0D890)      // prototype "☀ Rise" pill
    static let sunset = Color(hex: 0xC8A86A)       // prototype "☀ Set" pill
}

/// The uppercase mono section-label role. Sizes 9/10/11 used to be passed per
/// call site; under Dynamic Type they all collapse to `.caption2` and scale
/// with the reader's setting instead.
struct MonoLabel: View {
    let text: String
    var color: Color = SN.leaf
    var tracking: CGFloat = 1.6
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.monospaced().weight(.medium))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

// MARK: - App clock

/// Real time, or shifted by `-nowOffsetDays N` (read via UserDefaults'
/// argument domain) — the UI-test hook behind the M3 airplane-mode
/// day-after check (relaunch offline "tomorrow").
private let appNowOffset: TimeInterval =
    UserDefaults.standard.double(forKey: "nowOffsetDays") * 86_400

func appNow() -> Date { Date.now.addingTimeInterval(appNowOffset) }

/// Today's local midnight in `tz`, on the app clock. The anchor every detail
/// view starts on, and the `today` half of every `Timeline.window` call.
func todayLocal(_ tz: TimeZone) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.startOfDay(for: appNow())
}

// MARK: - Units (mirrors slackwater-web src/units.ts)

let unitsKey = "slackwater.units"  // "imperial" | "metric", same values as the web

func toFeet(_ metres: Double) -> Double { metres * 3.28084 }

/// Strip a negative zero, which appears whenever a tide sits just below datum.
private func unsign(_ n: Double) -> Double { abs(n) < 0.05 ? abs(n) : n }

func formatHeight(_ metres: Double, imperial: Bool) -> String {
    imperial ? String(format: "%.1f", unsign(toFeet(metres)))
             : String(format: "%.2f", unsign(metres))
}

func heightUnit(imperial: Bool) -> String { imperial ? "ft" : "m" }

// Current speed (web units.ts SpeedUnit): "kn" | "kmh" | "ms", same key/values.
let speedUnitKey = "slackwater.speedUnit"

func toKmh(_ knots: Double) -> Double { knots * 1.852 }
func toMs(_ knots: Double) -> Double { knots * 0.514444 }

/// Web formatSpeed: convert, strip a near-zero sign, one decimal.
func formatSpeed(_ knots: Double, unit: String) -> String {
    let v = unit == "kmh" ? toKmh(knots) : unit == "ms" ? toMs(knots) : knots
    return String(format: "%.1f", abs(v) < 0.05 ? abs(v) : v)
}

func speedUnitLabel(_ unit: String) -> String {
    unit == "kmh" ? "km/h" : unit == "ms" ? "m/s" : "kn"
}

// MARK: - Station-local time formatting

/// NSCache, not a Dictionary: thread-safe (Canvas draws can run off-main) and
/// bounded. DateFormatter itself is thread-safe for formatting since iOS 7.
private let formatterCache = NSCache<NSString, DateFormatter>()

private func formatter(_ pattern: String, _ tz: TimeZone) -> DateFormatter {
    let key = (pattern + tz.identifier) as NSString
    if let cached = formatterCache.object(forKey: key) { return cached }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = tz
    f.dateFormat = pattern
    formatterCache.setObject(f, forKey: key)
    return f
}

/// "1:42 PM" — the card/readout style (web cardTime, en-US).
func cardTime(_ date: Date, _ tz: TimeZone) -> String {
    formatter("h:mm a", tz).string(from: date)
}

/// "14:05" — the chart/table style (web en-CA 24h). Zero-padded, and that
/// padding is load-bearing in `MultiDaySchedule`: the times there are a
/// left-aligned monospaced COLUMN, and "7:03" would hang a character left of
/// "12:53" all the way down the list.
func clockTime(_ date: Date, _ tz: TimeZone) -> String {
    formatter("HH:mm", tz).string(from: date)
}

/// "4:22pm" — the strip's clock. Twelve-hour, lowercase, no space and no
/// periods: " p.m." labels were mostly meridiem and collided because of it.
/// `MultiDaySchedule` stays on 24h `clockTime` — its column needs the pad.
func chartTime(_ date: Date, _ tz: TimeZone) -> String {
    formatter("h:mma", tz).string(from: date).lowercased()
}

/// "Wed" — the strip's non-relative day label.
func shortWeekday(_ date: Date, _ tz: TimeZone) -> String {
    formatter("EEE", tz).string(from: date)
}

// MARK: - Detail-view shared pieces (tide + current)

/// "42m" / "2h 14m" until `target`, floored at zero.
func countdown(from: Date, to target: Date) -> String {
    let minutes = max(Int(target.timeIntervalSince(from) / 60), 0)
    return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
}

/// The web's CompassArrow: ↑ rotated to a true bearing, "sets this way".
struct CompassArrow: View {
    let deg: Double
    var body: some View {
        Text("↑").rotationEffect(.degrees(deg))
    }
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
            Circle().fill(Color(hex: 0x00122C, opacity: 0.92)).offset(x: shift)
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

    var body: some View {
        let moon = SunMoon.moonIllumination(date: scrubTime)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cardTime(scrubTime, tz))
                    .font(.title.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                MonoLabel(text: monthDay(scrubTime, tz))
            }
            ReturnToNowSlot(scrubTime: scrubTime, live: live, onReturn: onReturn)
            Spacer()
            MoonGlyph(fraction: moon.fraction, waxing: moon.waxing, size: 22)
            Text(SunMoon.phaseName(phase: moon.phase))
                .font(.caption2)
                .foregroundStyle(SN.foam.opacity(0.6))
                .lineLimit(1)
        }
        .accessibilityElement(children: .contain)
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
                .accessibilityIdentifier("detail-return-now")
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
    /// Tapping the range bar. Caller-owned for the same reason `onReturn` is:
    /// the anchor lives in the detail view, not here.
    let onPickDate: () -> Void
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
        ScrollView {
            VStack(spacing: 0) {
                MapHeader(name: name, region: region,
                          latitude: latitude, longitude: longitude,
                          favoriteId: favoriteId)
                above()
                if let timeline {
                    scrubCard(timeline)
                    scheduleCard(timeline)
                        .padding(.top, 14)
                }
                bottom()
                    .padding(.top, 14)
            }
            .padding(.bottom, 42)
        }
        .ignoresSafeArea(edges: .top)
        .background(SN.page.ignoresSafeArea())
        .environment(\.timeZone, tz)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func scrubCard(_ tl: TimelineData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            card(tl)

            MonoLabel(text: "‹ swipe to scrub ›",
                      color: SN.foam.opacity(0.4), tracking: 1.4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            ScrubWhen(scrubTime: scrubTime, live: live, tz: tz, onReturn: onReturn)
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
            WeekRangeBar(anchor: tl.anchor, today: tl.today, tz: tz, onTap: onPickDate)
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

/// The provisional ("fast answer") marking on a LIST card: the ⚠️ family and
/// nothing else — the detail view carries the explanation. Amber on the flat
/// card fill clears WCAG 1.4.11's 3:1 on both grounds (4.71:1 worst case;
/// the measured numbers and their M52/M53 history live in docs/testflight.md).
struct ProvisionalBadge: View {
    /// Tracks the icon's own `.caption2` so the disc keeps containing the
    /// triangle at the largest accessibility sizes.
    @ScaledMetric(relativeTo: .caption2) private var badgeSize: CGFloat = 22

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(SN.amber)
            .frame(width: badgeSize, height: badgeSize)
            .background(SN.canvas, in: Circle())
            // A fixed 1pt hairline, deliberately not scaled: a separator, not
            // a mark that needs to read at a distance.
            .overlay(Circle().strokeBorder(SN.amber, lineWidth: 1))
            .accessibilityLabel("Fast answer — still refining")
            .accessibilityIdentifier("provisional-badge")
    }
}

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
    private static let key = "slackwater.recents"

    @Published private(set) var ids: [String]

    /// Set by the regular-width auto-selection (M52) for exactly the detail it
    /// opens. The pane opening itself is not the user viewing a station, and
    /// counting it would evict a real entry from the 6-slot history on every
    /// single launch.
    var skipNextRecord = false

    private init() {
        // UI-test hook, like -resetGate: a clean no-recents first run.
        if CommandLine.arguments.contains("-resetRecents") {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
        ids = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func record(_ id: String) {
        if skipNextRecord { skipNextRecord = false; return }
        var next = ids.filter { $0 != id }
        next.insert(id, at: 0)
        next = Array(next.prefix(6))
        ids = next
        UserDefaults.standard.set(next, forKey: Self.key)
    }

    /// Swipe "Remove" on a Recents row (current-detail spec §9: true deletion).
    func remove(_ id: String) {
        ids.removeAll { $0 == id }
        UserDefaults.standard.set(ids, forKey: Self.key)
    }

    var items: [StationItem] {
        ids.compactMap { id in StationItem.all.first { $0.id == id } }
    }
}

// MARK: - Favorites (current-detail spec §9; prototype TidesApp savedIds)

/// Starred stations, insertion order, persisted. Toggled by the detail-header
/// star and the list swipe actions.
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()
    private static let key = "slackwater.favorites"

    @Published private(set) var ids: [String]

    private init() {
        // UI-test hook, like -resetRecents: a clean no-favorites run.
        if CommandLine.arguments.contains("-resetFavorites") {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
        ids = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if let i = ids.firstIndex(of: id) {
            ids.remove(at: i)
            // Spec §9: unfavoriting re-files to Recents, never data loss.
            RecentsStore.shared.record(id)
        } else {
            ids.append(id)
        }
        UserDefaults.standard.set(ids, forKey: Self.key)
    }

    var items: [StationItem] {
        ids.compactMap { id in StationItem.all.first { $0.id == id } }
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
