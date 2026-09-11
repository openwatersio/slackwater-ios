// Slackwater — GPL v3. The widget's `slackwater://station/<id>` deep link:
// percent-encoding shared by the widget extension (HomeWidgets.swift, which
// wraps this for its `SlackwaterEntry`) and the app's tests, so a round-trip
// test can exercise the exact encoding a widget tap produces without linking
// against appex-only types.
import Foundation

/// RFC 3986 "unreserved" only. `.urlPathAllowed` looked like the obvious
/// choice (it does escape ":", e.g. "current:PUG1515") but it does NOT escape
/// "/" — and every tide/current station id in the bundled catalogs (all 3,607
/// of them: "noaa/9454616", "current:noaa/jx0701", "ticon/aasiaat-...") has
/// one. With `.urlPathAllowed`, `url.pathComponents` splits on that "/" and
/// the receiving `.onOpenURL` only ever sees the first fragment. Only CHS
/// stations (no "/" in their ids) round-tripped by accident under the wider
/// set. Confirmed by direct round-trip test — see task-9-report.md.
let idPathCharacters = CharacterSet(charactersIn:
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

/// The widget's `slackwater://station/<id>` deep link for one station id, or
/// the Widgets gallery/explainer when there's no id to resolve (M2) — station
/// ids contain ":" and "/" (e.g. "current:noaa/jx0701"), so both get
/// percent-encoded; the receiving `.onOpenURL` reads the id back decoded via
/// `url.pathComponents`.
func deepLink(forStationID id: String?) -> URL? {
    guard let id, let encoded = id.addingPercentEncoding(withAllowedCharacters: idPathCharacters)
    else { return URL(string: "slackwater://premium") }
    return URL(string: "slackwater://station/\(encoded)")
}

/// The station id back out of a `slackwater://station/<id>` URL — the inverse
/// of `deepLink(forStationID:)`, and the only safe read of it. The id IS the
/// whole path and nearly every id carries a "/" ("noaa/9449880"), so take the
/// path whole and let it decode: a componentwise read (`pathComponents`,
/// `lastPathComponent`) splits on that "/" once the escape is resolved and
/// hands back "noaa", which matches no station and dies as a lookup miss
/// (#167). This works whichever way the URL arrives, escaped or resolved.
func stationID(from url: URL) -> String {
    String(url.path(percentEncoded: false).dropFirst())
}

/// The host whose station links this app claims, matching the
/// `applinks:` entry in Slackwater.entitlements and the
/// apple-app-site-association the slackwater.xyz Worker serves. All three have
/// to agree or the link opens Safari instead.
let stationLinkHost = "slackwater.xyz"

/// A shared station link: `https://slackwater.xyz/<kind>/<slug>[/<instant>]`.
///
/// Distinct from the widget's `slackwater://station/<id>` scheme, which stays
/// an internal hop and is deliberately not what gets shared: Messages and Mail
/// will not linkify a custom scheme, and a tap does nothing at all on a phone
/// without the app.
struct StationLink: Equatable {
    /// The URL namespace. A tide and a current station may hold the same slug,
    /// so the kind is what tells them apart - it is not decoration.
    enum Kind: String, Equatable {
        case tides
        case currents
    }

    var kind: Kind
    var slug: String
    /// The moment the sender was looking at. Absent means "now", which is what
    /// a share from an unscrubbed view means.
    var instant: Date?
}

/// The instant is written in the station's own UTC offset, so it survives the
/// receiver being in another timezone. Seconds are optional because the web
/// writes minute precision; both are accepted rather than guessing which.
private let stationLinkInstantFormats = [
    "yyyy-MM-dd'T'HH:mmZZZZZ",
    "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
]

private func stationLinkInstant(from text: String) -> Date? {
    let formatter = DateFormatter()
    // Fixed format parsing must not follow the device's locale or calendar:
    // under a non-Gregorian calendar or an odd locale the same string parses
    // to a different date, or to nothing.
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    for format in stationLinkInstantFormats {
        formatter.dateFormat = format
        if let date = formatter.date(from: text) { return date }
    }
    return nil
}

/// Parse a shared station link, or `nil` if this is not one.
///
/// Strict on purpose. This runs on every URL the app is handed, and anything it
/// accepts it also claims: a link it half-understands would swallow a URL the
/// browser should have shown. A trailing slash is tolerated because share
/// sheets and link previews add one; anything else unexpected is refused.
func stationLink(from url: URL) -> StationLink? {
    guard url.scheme == "https", url.host() == stationLinkHost else { return nil }

    // `pathComponents` is safe here, unlike for the widget's ids: a slug is
    // /^[a-z0-9-]+$/ by construction, so it carries no "/" to be split on.
    var components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
    guard let first = components.first, let kind = StationLink.Kind(rawValue: first) else { return nil }
    components.removeFirst()

    guard let slug = components.first, !slug.isEmpty else { return nil }
    components.removeFirst()

    switch components.count {
    case 0:
        return StationLink(kind: kind, slug: slug, instant: nil)
    case 1:
        // An unparseable instant is a refusal, not a fallback to "now". Landing
        // someone on the wrong moment silently is the failure this format
        // exists to prevent.
        guard let instant = stationLinkInstant(from: components[0]) else { return nil }
        return StationLink(kind: kind, slug: slug, instant: instant)
    default:
        return nil
    }
}

// MARK: - Slug ↔ station

/// Resources/slugs.json (tools/gen-slugs.mjs): the published slug of every
/// bundled station, per kind, keyed by CATALOG id — bare `noaa/…` for a
/// current; the `current:` prefix is `StationItem.id`'s own. Loaded on first
/// use only, so the widget appex, which compiles this file but bundles no
/// table, never pays for it.
private struct SlugTable: Decodable {
    let tide: [String: String]
    let current: [String: String]

    static let shared: SlugTable = {
        guard let url = Bundle.main.url(forResource: "slugs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(SlugTable.self, from: data)
        else { return SlugTable(tide: [:], current: [:]) }
        return table
    }()

    /// slug → catalog id. Two rows on one slug are one station recorded
    /// twice (station-metadata #24), so whichever wins is the same water.
    static let tideIDs = invert(shared.tide)
    static let currentIDs = invert(shared.current)
    private static func invert(_ table: [String: String]) -> [String: String] {
        Dictionary(table.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The bundled station a shared link names, or nil when this build has none
/// under that slug — an older build, or a station that has since left the
/// bundle. Never a different station: a slug is allocated once and never
/// reused, so a miss is a dead link and not the wrong water.
func stationItem(for link: StationLink) -> StationItem? {
    switch link.kind {
    case .tides:
        return SlugTable.tideIDs[link.slug].flatMap { StationItem.byId[$0] }
    case .currents:
        guard let id = SlugTable.currentIDs[link.slug] else { return nil }
        // A NOAA current keys the list with the `current:` prefix; a CHS gate
        // keys it bare (CurrentStationRecord.itemId). Try the prefix first —
        // a bare `noaa/…` is only ever a tide.
        return StationItem.byId["current:" + id] ?? StationItem.byId[id]
    }
}

/// The link to share for a station — the inverse of `stationItem(for:)`. `at`
/// is the moment the sender is looking at, written in `tz` (the station's own
/// zone, so the receiver reads the same absolute instant wherever they are);
/// nil means "now", which is what sharing an unscrubbed view means. Nil when
/// the station has no published slug, which the generator makes impossible
/// for anything bundled.
func shareURL(forStationID id: String, at instant: Date?, tz: TimeZone) -> URL? {
    guard let item = StationItem.byId[id] else { return nil }
    let kind: StationLink.Kind
    let slug: String?
    switch item {
    case .tide, .chs:
        kind = .tides; slug = SlugTable.shared.tide[id]
    case .current(let s):
        kind = .currents; slug = SlugTable.shared.current[s.id]
    case .chsGate, .chsCurrent:
        kind = .currents; slug = SlugTable.shared.current[id]
    }
    guard let slug else { return nil }
    var path = "/\(kind.rawValue)/\(slug)"
    if let instant { path += "/" + stationLinkInstant(instant, tz: tz) }
    return URL(string: "https://\(stationLinkHost)\(path)")
}

/// The instant segment as the web writes it: minute precision, the offset
/// spelled out (`ZZZZZ` writes "-07:00", and "Z" for UTC — both of which
/// `stationLinkInstant(from:)` reads back).
private func stationLinkInstant(_ instant: Date, tz: TimeZone) -> String {
    // The shared cache, not a fresh DateFormatter: minting runs inside
    // `DetailHeader`'s body, which SwiftUI re-evaluates on every scrub tick,
    // and building one costs ~40x reusing one. Its en_US_POSIX locale carries
    // the Gregorian calendar that fixed-format writing needs — under a
    // Buddhist-calendar locale this same pattern writes "2569-08-30".
    formatter(stationLinkInstantFormats[0], tz).string(from: instant)
}
