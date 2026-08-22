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
