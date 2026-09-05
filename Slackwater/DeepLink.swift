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
