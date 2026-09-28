// Slackwater — GPL v3. One state model for a list card that has no reading to
// show (#93). The explanation — what CHS is, why a gate has no offline model,
// what "queued" means — stays on the detail views, which have room for it.
import SwiftUI

/// What a station card is waiting on. States with no reading at all, plus
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
    case retrying
    /// Not in the automatic download set. The card stays a skeleton without
    /// telling someone to tap; opening a station remains ordinary navigation.
    case notQueued
    /// Not connected — nothing moves until signal returns.
    case offline
    /// Fetched before; the stored window no longer covers the window on screen.
    /// A COVERAGE question, not a staleness heuristic — see `ChsOnlineWindow`.
    case expired
    /// Never fetched and not queued (M53 — most of Canada): opening it is what
    /// starts it, which stays true offline, so this outranks `.offline`.
    case notDownloaded
    /// Another attempt would get the same answer.
    case failed
    /// Showing the 60-day fast answer while the full model downloads. Carries
    /// this gate's own measured slack tolerance ("±35 min") — the number the
    /// ⚠️ badge it replaced could only gesture at.
    case refining(tolerance: String?)

    var showsPlaceholder: Bool {
        switch self {
        case .downloading, .queued, .retrying, .notQueued, .notDownloaded: true
        default: false
        }
    }

    var showsAutomaticStatus: Bool {
        switch self {
        case .downloading, .queued, .retrying: true
        default: false
        }
    }

    var showsIndicator: Bool { self != .notQueued }

    var icon: String {
        switch self {
        case .downloading: "arrow.down.circle"
        case .queued: "clock"
        case .retrying, .notQueued: "clock"
        case .offline: "wifi.slash"
        case .expired, .notDownloaded: "wifi.slash"
        case .failed: "exclamationmark.triangle.fill"
        case .refining: "brain"
        }
    }

    /// Scannable, not read. Two or three words, no sentence.
    var label: String {
        switch self {
        case .downloading: String(localized: "Downloading", comment: "Compact download status.")
        case .queued: String(localized: "Queued", comment: "Compact download status.")
        case .retrying: String(localized: "Retrying", comment: "Compact download status.")
        case .notQueued: ""
        case .offline: String(localized: "Offline", comment: "Compact network status.")
        case .expired: String(localized: "Expired", comment: "Compact offline-download status.")
        case .notDownloaded: String(localized: "Not downloaded", comment: "Compact offline-download status.")
        case .failed: String(localized: "Failed", comment: "Compact download status.")
        case .refining(let tolerance):
            tolerance.map {
                String(localized: "Refining · \($0)", comment: "Compact prediction status. The value is a measured time tolerance.")
            } ?? String(localized: "Refining", comment: "Compact prediction status.")
        }
    }

    /// VoiceOver keeps the sentence the strip dropped — including when the
    /// active queue states reduce to an icon (#93).
    var accessibilityLabel: String {
        switch self {
        case .downloading: return String(localized: "Downloading — Canadian predictions download once, then work offline.", comment: "VoiceOver download status.")
        case .queued: return String(localized: "Queued — Canadian predictions download once, then work offline.", comment: "VoiceOver download status.")
        case .retrying: return String(localized: "Retrying — Slackwater tries again on its own. Canadian predictions download once, then work offline.", comment: "VoiceOver download status.")
        case .notQueued: return String(localized: "Predictions are not downloaded.", comment: "VoiceOver download status.")
        case .offline: return String(localized: "Offline — needs a moment of signal. Canadian predictions download once, then work offline.", comment: "VoiceOver download status.")
        case .expired: return String(localized: "Expired — get back online to download current predictions.", comment: "VoiceOver download status.")
        case .notDownloaded: return String(localized: "Not downloaded — get back online to download predictions.", comment: "VoiceOver download status.")
        case .failed: return String(localized: "Station unavailable.", comment: "VoiceOver station status.")
        case .refining(let tolerance):
            if let tolerance {
                return String(localized: "Refining — showing the fast answer, slack accurate to \(tolerance). The full model is still downloading.", comment: "VoiceOver prediction status. The value is a measured time tolerance.")
            }
            return String(localized: "Refining — showing the fast answer. The full model is still downloading.", comment: "VoiceOver prediction status.")
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
        case .failed, .refining: SN.amber
        case .queued, .retrying, .notQueued, .offline, .expired, .notDownloaded: SN.foam.opacity(0.85)
        }
    }
}

/// Calendar-day copy for cached official predictions. The station's data
/// source is irrelevant here; people only need to know how long the local
/// copy remains useful.
func onlineDownloadValidity(end: Date, now: Date = appNow(), calendar: Calendar = .current) -> String {
    guard end > now else { return String(localized: "Offline download expired", comment: "Offline-download expiry status.") }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: end)).day ?? 0
    if days <= 0 { return String(localized: "Expires today", comment: "Offline-download expiry status.") }
    if days <= 3 { return String(localized: "Expires in \(days) days", comment: "Offline-download expiry. The integer is a number of calendar days; vary by plural.") }
    return String(localized: "Available offline for \(days) more days", comment: "Offline-download validity. The integer is a number of calendar days; vary by plural.")
}

/// Compact status used in the reading slot for automatic work and below the
/// identity row for offline or exceptional states.
struct CardStatusStrip: View {
    let status: CardStatus
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.icon)
            Text(detail ?? status.label)
        }
        .font(.caption)
        .foregroundStyle(status.tint)
        // Wrap, never truncate — a Text given too little room drops content
        // instead (see StationCard's name).
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\($0). \(status.accessibilityLabel)" }
                            ?? status.accessibilityLabel)
        // No accessibilityIdentifier of its own, deliberately: a pending card
        // stamps `chs-pending-<id>` (M53) on the whole shell, and SwiftUI
        // PROPAGATES a container's identifier down over every descendant's —
        // verified in an a11y dump, where this element came back carrying the
        // card's id and not its own. A per-state locator would work on a
        // refining card and silently not on a pending one, which is worse than
        // none. Tests locate the strip by its full accessibility label.
    }
}
