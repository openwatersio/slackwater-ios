// Slackwater — GPL v3. Design tokens from the prototype design system
// (prototype/_ds/_ds_bundle.css): sn- palette, Fraunces/Geist/Geist Mono type
// roles, per-station gradient trios, and the web app's unit formatting.
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum SN {
    static let navyDeep = Color(hex: 0x00183C)
    static let canvas = Color(hex: 0x05122A)      // list canvas
    static let canvasGlow = Color(hex: 0x0A2140)  // radial glow at top of list
    static let page = Color(hex: 0x00121F)        // 1b Modular detail page
    static let leaf = Color(hex: 0x88B868)
    static let steel = Color(hex: 0x5888A8)
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
    static let flood = Color(hex: 0x4A9FD8)
    static let ebb = Color(hex: 0xE8A33D)
    static let go = Color(hex: 0x88B868)
    static let rising = flood
    static let falling = ebb
    static let cardStroke = leaf.opacity(0.16)
    static let cardFill = Color.white.opacity(0.05)
    static let night = Color(hex: 0x00101F)        // prototype night band
    static let sun = Color(hex: 0xF0C860)          // prototype sun dot
    /// Attention, never alarm: the location-denied card, and the unfitted
    /// station's ⚠️ download warning. Deliberately red-leaning rather than
    /// golden — the old 0xE0B45A sat close enough to `ebb` to be misread as a
    /// tide state. Same value the web app uses for the same job.
    static let amber = Color(hex: 0xEF6F4A)
    static let sunrise = Color(hex: 0xF0D890)      // prototype "☀ Rise" pill
    static let sunset = Color(hex: 0xC8A86A)       // prototype "☀ Set" pill
}

extension Font {
    static func fraunces(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        switch weight {
        case .semibold, .bold: .custom("Fraunces-SemiBold", size: size)
        case .medium: .custom("Fraunces-Medium", size: size)
        default: .custom("Fraunces-Regular", size: size)
        }
    }
    static func geist(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        switch weight {
        case .semibold, .bold: .custom("Geist-SemiBold", size: size)
        case .medium: .custom("Geist-Medium", size: size)
        default: .custom("Geist-Regular", size: size)
        }
    }
    static func geistMono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        weight == .medium || weight == .semibold
            ? .custom("GeistMono-Medium", size: size)
            : .custom("GeistMono-Regular", size: size)
    }
}

/// The Geist Mono uppercase section-label role from the prototype.
struct MonoLabel: View {
    let text: String
    var size: CGFloat = 11
    var color: Color = SN.leaf
    var tracking: CGFloat = 1.6
    var body: some View {
        Text(text.uppercased())
            .font(.geistMono(size, .medium))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

// MARK: - Per-station sky gradients (variant 1a list cards)

/// The prototype's hand-tuned gradient trios (prototype/NearMe.dc.html DATA()).
/// Assignment is a stable hash of the station id — deterministic, no semantics.
private let gradientTrios: [(UInt32, UInt32, UInt32)] = [
    (0x88B0CC, 0x3A6D98, 0x184870), (0x3A6D98, 0x184870, 0x083058),
    (0x9AC0B0, 0x4A8F78, 0x184860), (0x78A8B8, 0x2F7088, 0x0D3A58),
    (0x184870, 0x0D3358, 0x00183C), (0x88B0CC, 0x4A7BA0, 0x20486A),
    (0xA8C4D4, 0x5888A8, 0x28587C), (0x7098B8, 0x2F6390, 0x153F66),
    (0x88AECB, 0x3D6F9A, 0x1A4A70), (0x8AB8A0, 0x3D8068, 0x154A44),
    (0x96BCD2, 0x4E84A8, 0x265678), (0x7FA6C6, 0x356690, 0x184568),
]

func stationGradient(id: String) -> LinearGradient {
    // Friday Harbor keeps the prototype's teal trio; the rest hash into the family.
    let index = id == TideStationRecord.fridayHarborID
        ? 2
        : Int(id.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) } % UInt64(gradientTrios.count))
    let (a, b, c) = gradientTrios[index]
    // CSS linear-gradient(150deg, a, b 55%, c)
    return LinearGradient(
        stops: [.init(color: Color(hex: a), location: 0),
                .init(color: Color(hex: b), location: 0.55),
                .init(color: Color(hex: c), location: 1)],
        startPoint: UnitPoint(x: 0.15, y: 0), endPoint: UnitPoint(x: 0.85, y: 1))
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

/// The schedule table's sunrise/sunset pill (prototype PILL.sunrise/.sunset:
/// outlined, amber family, "☀ Rise" / "☀ Set").
struct SunPill: View {
    let kind: SunMoon.SunEventKind
    var body: some View {
        let color = kind == .sunrise ? SN.sunrise : SN.sunset
        Text(kind == .sunrise ? "☀ RISE" : "☀ SET")
            .font(.geistMono(10, .medium)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.5))
    }
}

/// The provisional ("fast answer") marking on a LIST card: the ⚠️ family and
/// nothing else — the detail view carries the explanation.
///
/// M52 accessibility fix. The old treatment wrote amber (#E0B45A) prose and an
/// amber badge straight onto the station gradient, and amber sits at almost
/// exactly the luminance of the palette's pale stops: #E0B45A on #A8C4D4 is
/// **1.06:1**, and 1.03:1 on #9AC0B0 — literally unreadable, which is what
/// Bryan saw on device. So the glyph gets the app's own over-an-unpredictable-
/// background chrome (MapHeader's dark disc + ring): amber on an SN.canvas disc
/// is 6.25:1, the disc reads 10.22:1 against the palest stop, and the ring
/// reads 5.89:1 against the darkest.
///
/// KNOWN GAP (2026-08-02, M53 amber move to #EF6F4A): the old #E0B45A cleared
/// ≥3.14:1 on every trio in the palette; the new amber does not — the worst
/// boundary (max of disc-vs-stop, ring-vs-stop) is **2.54:1** on `#28587C`
/// (also 2.62:1 on `#265678`, 2.94:1 on `#2F6390`), under WCAG 1.4.11's 3:1 for
/// non-text on those three station cards. Flagged, not fixed here — the amber
/// value was fixed by the direction-token change above (0xEF6F4A, chosen to
/// clear `ebb`), and re-balancing the badge chrome for it is its own task.
/// Numbers in docs/testflight.md — also stale, needs the same update.
struct ProvisionalBadge: View {
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SN.amber)
            .frame(width: 22, height: 22)
            .background(SN.canvas, in: Circle())
            .overlay(Circle().strokeBorder(SN.amber, lineWidth: 1))
            .accessibilityLabel("Fast answer — still refining")
            .accessibilityIdentifier("provisional-badge")
    }
}

/// The Near Me cards' nautical-miles pill; straddles a card's top-right
/// corner (also overlaid on the My Location tile — same component).
struct DistancePill: View {
    let km: Double
    var body: some View {
        Text(formatNm(km))
            .font(.geistMono(11, .medium))
            .foregroundStyle(SN.navyDeep)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(SN.foam.opacity(0.92), in: Capsule())
            .shadow(color: Color(hex: 0x001432, opacity: 0.3), radius: 4, y: 2)
            .offset(x: -14, y: -8)
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
