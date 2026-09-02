// Slackwater — GPL v3. One state model for a list card that has no reading to
// show (#93). The card gets an icon and two words; the explanation — what CHS
// is, why a gate has no offline model, what "queued" means — stays on the
// detail views, which have room for it.
import SwiftUI

/// What a station card is waiting on. Six states with no reading at all, plus
/// `.refining` — the one state that HAS a reading and isn't final yet.
///
/// One enum rather than a sentence built at each site: the online-gate path
/// used to compose its own literal and so could not tell "never fetched" from
/// "the window ran out of coverage", which is exactly the distinction the strip
/// has to draw (#93).
enum CardStatus: Equatable {
    /// This station's fetch is in flight right now.
    case downloading
    /// Online and in the download set, but not its turn yet.
    case queued
    /// Not connected — nothing moves until signal returns.
    case offline
    /// Fetched before; the stored window no longer covers the window on screen.
    /// A COVERAGE question, not a staleness heuristic — see `ChsOnlineWindow`.
    case expired
    /// Never fetched and not queued (M53 — most of Canada): opening it is what
    /// starts it, which stays true offline, so this outranks `.offline`.
    case notDownloaded
    /// The last attempt didn't finish.
    case failed
    /// Showing the 60-day fast answer while the full model downloads. Carries
    /// this gate's own measured slack tolerance ("±35 min") — the number the
    /// ⚠️ badge it replaced could only gesture at.
    case refining(tolerance: String?)
    var icon: String {
        switch self {
        case .downloading: "arrow.down.circle"
        case .queued: "clock"
        case .offline: "wifi.slash"
        case .expired: "clock.badge.exclamationmark"
        case .notDownloaded: "arrow.down.circle.dotted"
        case .failed: "exclamationmark.triangle.fill"
        case .refining: "brain"
        }
    }

    /// Scannable, not read. Two or three words, no sentence.
    var label: String {
        switch self {
        case .downloading: "Downloading"
        case .queued: "Queued"
        case .offline: "Offline"
        case .expired: "Expired"
        case .notDownloaded: "Tap to download"
        case .failed: "Download failed"
        case .refining(let tolerance): tolerance.map { "Refining · \($0)" } ?? "Refining"
        }
    }

    /// VoiceOver keeps the sentence the strip dropped — an icon and two words
    /// must not be LESS legible than the prose they replaced (#93). Each one
    /// STARTS with `label`, so a locator matching the visible words still finds
    /// the element.
    var accessibilityLabel: String {
        let once = "Canadian predictions download once, then work offline."
        switch self {
        case .downloading: return "Downloading — \(once)"
        case .queued: return "Queued — \(once)"
        case .offline: return "Offline — needs a moment of signal. \(once)"
        case .expired: return "Expired — the downloaded predictions no longer cover the dates on screen. Open it to fetch more."
        case .notDownloaded: return "Tap to download — \(once)"
        case .failed: return "Download failed — open it to retry."
        case .refining(let tolerance):
            let howWrong = tolerance.map { ", slack accurate to \($0)" } ?? ""
            return "Refining — showing the fast answer\(howWrong). The full model is still downloading."
        }
    }

    /// Amber where the card can't be taken as final, leaf where something is
    /// actually happening, quiet foam otherwise. Amber (`#EF6F4A`) on the
    /// composited card background measures 4.71:1–5.59:1 (docs/testflight.md),
    /// which clears AA for text as well as 1.4.11's 3:1 for the icon — that
    /// measurement is why the fast answer can be plain text here at all, where
    /// the badge it replaced needed its own opaque disc.
    var tint: Color {
        switch self {
        case .downloading: SN.leaf
        case .expired, .failed, .refining: SN.amber
        case .queued, .offline, .notDownloaded: SN.foam.opacity(0.85)
        }
    }
}

/// Calendar-day copy for cached official predictions. The station's data
/// source is irrelevant here; people only need to know how long the local
/// copy remains useful.
func onlineDownloadValidity(end: Date, now: Date = appNow(), calendar: Calendar = .current) -> String {
    guard end > now else { return "Offline download expired" }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: end)).day ?? 0
    if days <= 0 { return "Expires today" }
    if days <= 3 { return "Expires in \(days) day\(days == 1 ? "" : "s")" }
    return "Available offline for \(days) more days"
}

/// Icon + two words, one line, in place of the paragraph a pending card used to
/// carry. Sits below the identity row at full card width.
struct CardStatusStrip: View {
    let status: CardStatus

    var body: some View {
        Label {
            Text(status.label)
        } icon: {
            Image(systemName: status.icon)
        }
        .font(.caption)
        .foregroundStyle(status.tint)
        // Wrap, never truncate — a Text given too little room drops content
        // instead (see StationCard's name).
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
        // No accessibilityIdentifier of its own, deliberately: a pending card
        // stamps `chs-pending-<id>` (M53) on the whole shell, and SwiftUI
        // PROPAGATES a container's identifier down over every descendant's —
        // verified in an a11y dump, where this element came back carrying the
        // card's id and not its own. A per-state locator would work on a
        // refining card and silently not on a pending one, which is worse than
        // none. Tests locate the strip by label; every `accessibilityLabel`
        // above starts with the words on screen so both readings match.
    }
}
