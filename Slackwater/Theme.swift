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
    static let sky = Color(hex: 0xC0D8E4)
    static let foam = Color(hex: 0xE4F0E4)
    static let paper = Color(hex: 0xFCFCFC)
    // Direction is one signed diverging axis; green means only slack.
    //
    // This replaced a green/blue direction pair that collided with the map's
    // green/blue *kind* pins — a green dot meant "current station" on one
    // screen and "flooding" on the next. Amber/blue is the standard
    // colourblind-safe diverging pair and it frees green, which matters: for an
    // app called Slackwater the moment you wait for is slack, and green names
    // it. Never colour anything by station kind.
    // Raw hexes, not just the Colors: MapLibre style dicts hold strings and
    // cannot read a Swift `Color`, so `MapScreen` formats these into "#rrggbb"
    // rather than hand-maintaining a second copy of the palette.
    static let floodHex: UInt32 = 0x4A9FD8
    static let ebbHex: UInt32 = 0xE8A33D
    static let goHex: UInt32 = 0x88B868
    static let flood = Color(hex: floodHex)
    static let ebb = Color(hex: ebbHex)
    static let go = Color(hex: goHex)
    static let rising = flood
    static let falling = ebb
    /// Pale flood/ebb, for the chart's max-speed dot labels and FLOOD/EBB
    /// reference-line legends — 9pt text on a near-black background, where
    /// the saturated token is too heavy. Derived from the same hex as
    /// `flood`/`ebb` so retargeting either token keeps its label in lockstep
    /// instead of drifting the way the pre-rebrand pastel literals did.
    static let floodLabel = Color.hex(floodHex, lightenedBy: 0.6)
    static let ebbLabel = Color.hex(ebbHex, lightenedBy: 0.6)
    static let cardStroke = leaf.opacity(0.16)
    static let cardFill = Color.white.opacity(0.05)
    static let night = Color(hex: 0x00101F)        // prototype night band
    static let sun = Color(hex: 0xF0C860)          // prototype sun dot
    /// Attention, never alarm: the location-denied card, and the unfitted
    /// station's ⚠️ download warning. Deliberately red-leaning rather than
    /// golden — the retired golden amber sat close enough to `ebb` to be
    /// misread as a tide state. Same value the web app uses for the same job.
    /// (The retired literal is deliberately not spelled here: it is one of the
    /// values `testNoSourceFileSpellsARetiredColour` bans from `Slackwater/`,
    /// and a doc comment naming it would need a whitelist to survive.)
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
    /// Opt-out, `nil` everywhere but the two `TimelineStrip` track labels
    /// ("TIDE" / "CURRENT"), which are `.position()`-pinned into `TimelineGeo`'s
    /// literal-point geometry — see that type's doc comment. Scaling them
    /// walks them off the chart rather than reflowing anything.
    var fixedSize: CGFloat? = nil
    var body: some View {
        Text(text.uppercased())
            .font(fixedSize.map { .system(size: $0, weight: .medium).monospaced() }
                    ?? .caption2.monospaced().weight(.medium))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

// MARK: - App clock

/// Real time, or shifted by `-nowOffsetDays N` — the UI-test hook behind the
/// M3 airplane-mode day-after check (relaunch offline "tomorrow").
private let appNowOffset: TimeInterval = {
    guard let i = CommandLine.arguments.firstIndex(of: "-nowOffsetDays"),
          i + 1 < CommandLine.arguments.count,
          let days = Double(CommandLine.arguments[i + 1]) else { return 0 }
    return days * 86_400
}()

func appNow() -> Date { Date.now.addingTimeInterval(appNowOffset) }

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

private var formatterCache: [String: DateFormatter] = [:]

private func formatter(_ pattern: String, _ tz: TimeZone) -> DateFormatter {
    let key = pattern + tz.identifier
    if let cached = formatterCache[key] { return cached }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = tz
    f.dateFormat = pattern
    formatterCache[key] = f
    return f
}

/// "1:42 PM" — the card/readout style (web cardTime, en-US).
func cardTime(_ date: Date, _ tz: TimeZone) -> String {
    formatter("h:mm a", tz).string(from: date)
}

/// "14:05" — the chart/table style (web en-CA 24h).
func clockTime(_ date: Date, _ tz: TimeZone) -> String {
    formatter("HH:mm", tz).string(from: date)
}

/// "Wed, Jul 30" — the schedule date line.
func dayLine(_ date: Date, _ tz: TimeZone) -> String {
    formatter("EEE, MMM d", tz).string(from: date)
}

func weekdayName(_ date: Date, _ tz: TimeZone) -> String {
    formatter("EEEE", tz).string(from: date)
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

/// The prototype's moon glyph (moonGlyphEl): a lit disc with the dark limb as
/// an offset circle clipped to the disc — fullness and waxing side track the
/// illumination as you scrub across days.
struct MoonGlyph: View {
    let fraction: Double
    let waxing: Bool
    var size: CGFloat = 20

    var body: some View {
        let r = size / 2 - 1
        // Dark limb slides off as illumination grows: covering at new (shift 0),
        // clear at full (shift 2r), lit side right while waxing. (The prototype
        // export's (1-fraction)·1.9r is inverted — it blacks out a full moon.)
        let shift = (waxing ? -1.0 : 1.0) * fraction * 2 * r
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

/// The schedule table's sunrise/sunset pill (prototype PILL.sunrise/.sunset:
/// outlined, amber family, "☀ Rise" / "☀ Set").
struct SunPill: View {
    let kind: SunMoon.SunEventKind
    var body: some View {
        let color = kind == .sunrise ? SN.sunrise : SN.sunset
        Text(kind == .sunrise ? "☀ RISE" : "☀ SET")
            .font(.caption2.monospaced().weight(.medium)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.5))
    }
}

/// The provisional ("fast answer") marking on a LIST card: the ⚠️ family and
/// nothing else — the detail view carries the explanation.
///
/// M52 accessibility fix. The old treatment wrote amber (#E0B45A) prose and an
/// amber badge straight onto the per-station gradient, and amber sat at almost
/// exactly the luminance of the palette's pale stops: #E0B45A on #A8C4D4 was
/// **1.06:1**, and 1.03:1 on #9AC0B0 — literally unreadable, which is what
/// Bryan saw on device. So the glyph got the app's own over-an-unpredictable-
/// background chrome (MapHeader's dark disc + ring).
///
/// RESOLVED (2026-08-02, M53 layout A): `stationGradient` is gone, so the
/// question is no longer "does this clear every one of 12 gradient trios" —
/// the card background is flat `SN.cardFill` (≈5% white) over the list's
/// `SN.canvas`/`SN.canvasGlow` radial ground. Composited worst case (nearest
/// the brighter `canvasGlow` top-of-list) is `#162C4A`; new amber `#EF6F4A`
/// against it is **4.71:1**, rising to 5.59:1 lower in the list — clear of
/// WCAG 1.4.11's 3:1 for non-text either way. The glyph-on-disc contrast
/// (amber icon on the `SN.canvas` disc, 6.25:1) is unaffected by the
/// background change and was never the tight number. Numbers in
/// docs/testflight.md updated to match.
struct ProvisionalBadge: View {
    /// Tracks the icon's own `.caption2` so the disc keeps containing the
    /// triangle instead of being outgrown by it (Task 5 fix round: the icon
    /// was scaled here but the frame was left literal, and `.caption2` at the
    /// largest accessibility category overflows a fixed 22pt circle).
    @ScaledMetric(relativeTo: .caption2) private var badgeSize: CGFloat = 22

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(SN.amber)
            .frame(width: badgeSize, height: badgeSize)
            .background(SN.canvas, in: Circle())
            // Stroke stays a fixed 1pt hairline outline, not scaled: it's a
            // thin separator against the canvas, not a mark that needs to
            // read at a distance, and a 1pt ring looks correct at every size
            // tried (default through AX5) — unlike the icon, it was never
            // sized to be legible, only to be visible.
            .overlay(Circle().strokeBorder(SN.amber, lineWidth: 1))
            .accessibilityLabel("Fast answer — still refining")
            .accessibilityIdentifier("provisional-badge")
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
