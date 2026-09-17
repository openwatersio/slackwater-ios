// Slackwater — GPL v3. "Report a problem": the detail footer's quiet menu,
// turning what someone is watching at the dock into a support email in one tap.
import SwiftUI
import UIKit

let supportEmail = "slackwater@openwaters.io"

/// What a report is about. The case IS the subject line, and picking it from
/// the menu is the whole form — the note is whatever they type in Mail.
enum ReportKind: String, CaseIterable, Identifiable {
    case location = "Station is in the wrong place"
    case metadata = "Station name or details are wrong"
    case height = "Tide height looks wrong"
    /// An unavailable station's page (issue #401), where the app has no
    /// predictions and is asking for a contact or a licence instead.
    case unavailable = "I can help with an unavailable station"

    var id: String { rawValue }

    /// What the detail footer's menu offers. NOT `allCases`: `.unavailable`
    /// belongs to a station that has no footer, and offering it beside "Tide
    /// height looks wrong" on a station that works is nonsense.
    static var menuCases: [ReportKind] { allCases.filter { $0 != .unavailable } }

    /// The line the mail opens with. The three water cases ask what someone
    /// saw; the unavailable one has nothing to see, so asking would get a
    /// confused answer or none.
    var prompt: String {
        switch self {
        case .unavailable:
            "(Tell us what you know — who runs this gauge, a contact there, or "
                + "anything about how its data is licensed.)"
        case .location, .metadata, .height:
            "(Tell us what you saw — what the water was doing, and when.)"
        }
    }

    /// A station with no predictions has no moment to report, and a mail that
    /// prints one invites a reader to go look at a curve that does not exist.
    var carriesMoment: Bool { self != .unavailable }
}

/// The same "1.13.0 (39)" pair Settings shows, so a report and a screenshot of
/// the Settings screen name the same build.
var appVersionLabel: String {
    let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    return "\(v) (\(b))"
}

/// "Sep 16, 2026 · 5:36pm PDT" — the app's own clock (`chartTime`), carrying
/// the year and zone that a mail opened weeks later somewhere else still needs.
func reportMoment(_ date: Date, _ tz: TimeZone) -> String {
    let day = formatter("MMM d, yyyy", tz).string(from: date)
    let zone = formatter("zzz", tz).string(from: date)
    return "\(day) · \(chartTime(date, tz)) \(zone)"
}

/// ponytail: the predicted height is deliberately absent. Station plus moment
/// IS the prediction — whoever reads the mail opens the link and sees the exact
/// curve the reporter was looking at, with none of it to keep in sync here.
func reportBody(kind: ReportKind, stationID: String, scrubTime: Date?,
                now: Date = Date(), tz: TimeZone) -> String {
    // `UnavailableStation` second: an unavailable station's id is one
    // `StationItem.byId` misses by construction, and without this the mail
    // reads "Station: ticon/gijontg-gij-esp-cmems" instead of naming Gijon.
    let name = StationItem.byId[stationID]?.name
        ?? UnavailableStation.byId[stationID]?.name
        ?? stationID
    var lines = [
        kind.prompt,
        "",
        "",
        "— details —",
        "Station: \(name) (\(stationID))",
    ]
    if kind.carriesMoment {
        lines.append("Moment: \(reportMoment(scrubTime ?? now, tz))")
    }
    // The share button's own link, so the two never disagree about which
    // moment they mean. Nil for a station with no published slug.
    if let link = detailShareURL(stationID: stationID, scrubTime: scrubTime, now: now, tz: tz) {
        lines.append("Link: \(link.absoluteString)")
    }
    lines.append("App: \(appVersionLabel)")
    return lines.joined(separator: "\n")
}

// `&`, `=`, `?` and `+` are query-legal, so URLComponents leaves them intact
// and a station named "Wreck & Ruin" would truncate the body at the ampersand.
private let mailtoAllowed: CharacterSet = {
    var set = CharacterSet.urlQueryAllowed
    set.remove(charactersIn: "&=?+")
    return set
}()

func reportMailURL(kind: ReportKind, stationID: String, scrubTime: Date?,
                   now: Date = Date(), tz: TimeZone) -> URL? {
    let body = reportBody(kind: kind, stationID: stationID, scrubTime: scrubTime, now: now, tz: tz)
    guard let subject = kind.rawValue.addingPercentEncoding(withAllowedCharacters: mailtoAllowed),
          let encoded = body.addingPercentEncoding(withAllowedCharacters: mailtoAllowed)
    else { return nil }
    return URL(string: "mailto:\(supportEmail)?subject=\(subject)&body=\(encoded)")
}

/// Open the mail composer, or fall back to the clipboard on a device with no
/// mail account. Shared so the footer menu and the unavailable station's page
/// cannot drift on the encoding or on what the fallback copies.
@MainActor
func sendReport(_ kind: ReportKind, stationID: String, scrubTime: Date? = nil,
                tz: TimeZone = .current, openURL: OpenURLAction,
                onCopied: @escaping () -> Void) {
    guard let url = reportMailURL(kind: kind, stationID: stationID,
                                  scrubTime: scrubTime, tz: tz) else { return }
    openURL(url) { opened in
        // A device with no mail account opens nothing and says nothing; the
        // clipboard is the difference between a lost report and a paste into
        // whatever they do use.
        guard !opened else { return }
        UIPasteboard.general.string = kind.rawValue + "\n\n"
            + reportBody(kind: kind, stationID: stationID, scrubTime: scrubTime, tz: tz)
        onCopied()
    }
}

/// Below the fold and icon-quiet on purpose: a wrong tide is rare, and this
/// sits in the provenance footer next to the not-for-navigation line rather
/// than competing with the readings.
struct ReportProblemMenu: View {
    let stationID: String
    var scrubTime: Date? = nil
    var tz: TimeZone = .current
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        Menu {
            ForEach(ReportKind.menuCases) { kind in
                Button(kind.rawValue) {
                    sendReport(kind, stationID: stationID, scrubTime: scrubTime,
                               tz: tz, openURL: openURL) { copied = true }
                }
            }
        } label: {
            Image(systemName: "exclamationmark.bubble")
                .font(.caption2)
                // Sun, not amber: amber is the warning language this app keeps
                // scarce, and an invitation to tell us something is wrong is
                // not itself a warning. The same yellow the favourite star uses.
                .foregroundStyle(SN.sun.opacity(0.8))
                // Chrome in a fixed hit target: 44pt of touch around a caption
                // glyph, without the frame growing with Dynamic Type into the
                // centred label beside it.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Report a problem")
        .accessibilityIdentifier("detail-report")
        .alert("No mail app", isPresented: $copied) {
            Button("OK") {}
        } message: {
            Text("Your report was copied. Send it to \(supportEmail).")
        }
    }

}
