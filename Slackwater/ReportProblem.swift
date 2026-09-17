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

    var id: String { rawValue }
}

/// The same "1.13.0 (39)" pair Settings shows, so a report and a screenshot of
/// the Settings screen name the same build.
var appVersionLabel: String {
    let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    return "\(v) (\(b))"
}

private let reportMomentFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm zzz"
    return f
}()

/// ponytail: the predicted height is deliberately absent. Station plus moment
/// IS the prediction — whoever reads the mail opens the link and sees the exact
/// curve the reporter was looking at, with none of it to keep in sync here.
func reportBody(kind: ReportKind, stationID: String, scrubTime: Date?,
                now: Date = Date(), tz: TimeZone) -> String {
    reportMomentFormatter.timeZone = tz
    let name = StationItem.byId[stationID]?.name ?? stationID
    var lines = [
        "(Tell us what you saw — what the water was doing, and when.)",
        "",
        "",
        "— details —",
        "Station: \(name) (\(stationID))",
        "Moment: \(reportMomentFormatter.string(from: scrubTime ?? now))",
    ]
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
            ForEach(ReportKind.allCases) { kind in
                Button(kind.rawValue) { send(kind) }
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

    private func send(_ kind: ReportKind) {
        guard let url = reportMailURL(kind: kind, stationID: stationID,
                                      scrubTime: scrubTime, tz: tz) else { return }
        openURL(url) { opened in
            // A device with no mail account opens nothing and says nothing;
            // the clipboard is the difference between a lost report and a
            // paste into whatever they do use.
            guard !opened else { return }
            UIPasteboard.general.string = kind.rawValue + "\n\n"
                + reportBody(kind: kind, stationID: stationID, scrubTime: scrubTime, tz: tz)
            copied = true
        }
    }
}
