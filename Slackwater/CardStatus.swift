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
    /// Tides ship worldwide; the bundled current stations are NOAA (US) and
    /// CHS (Canada) only. Outside that footprint the absence must be STATED
    /// — an empty currents list where a mariner expects a reading reads as
    /// "the water is slack here", which is false and dangerous (#T6).
    case noCurrentCoverage

    var icon: String {
        switch self {
        case .downloading: "arrow.down.circle"
        case .queued: "clock"
        case .offline: "wifi.slash"
        case .expired: "clock.badge.exclamationmark"
        case .notDownloaded: "arrow.down.circle.dotted"
        case .failed: "exclamationmark.triangle.fill"
        case .refining: "brain"
        case .noCurrentCoverage: "slash.circle"
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
        case .noCurrentCoverage: "Current predictions not available here"
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
        case .noCurrentCoverage:
            return "Current predictions not available here — the bundled current stations cover NOAA and Canada's CHS waters only. Tide predictions are unaffected."
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
        case .expired, .failed, .refining, .noCurrentCoverage: SN.amber
        case .queued, .offline, .notDownloaded: SN.foam.opacity(0.85)
        }
    }
}

/// NOT a political box (US/Canada) — currents are hyper-local (even a 1.5km
/// ocean model can't resolve a tidal gate, per the currents research this app
/// is built on), so a station 100km away describes different water, not this
/// water, regardless of whose waters it's in. A political-box reading of
/// "coverage" put San Diego Bay Entrance (25.8km) inside "coverage" for
/// Tijuana and Lake Worth Inlet (135.8km) inside "coverage" for Freeport,
/// Bahamas — both dishonest silences the political framing produced.
///
/// 20km is measured, not guessed: it sits between the bundled network's own
/// p90 (16.1km) and p95 (22.5km) nearest-neighbor spacing — i.e. inside the
/// gap where 90-95% of real stations sit relative to their closest neighbor,
/// the normal spacing of a genuinely local cluster (Golden Gate 0.6km,
/// Deception Pass 0.7km, NY Narrows 0.7km, Sidney BC 12.3km, Long Island
/// Sound mid-channel 10.8km — all real, all under 13km). Every cross-border
/// reach case measured (Tijuana 25.8km, Ensenada 108.3km, Freeport 135.8km,
/// Havana 161.1km, Nassau 289.4km) clears 20km by 29%+, so there is no
/// ambiguous middle ground between "same water" and "reaching for a stranger's
/// water" in the data actually checked.
///
/// This also, correctly, reports "not available" inside real US/Canada gaps
/// where the network has nothing hyper-local to offer (Desolation Sound BC —
/// ~30km from the nearest gate, Beazley Passage; central Oregon coast
/// ~258km) — silence there is honest, not a regression, because the app
/// genuinely cannot describe that water either.
///
/// Checks all three current sources the app ships, the same three
/// `StationItem.all` (`CurrentStation.swift`) treats as "the currents we
/// have": NOAA (`CurrentStationRecord`), validated CHS gates
/// (`ChsCurrentGateInfo` — Seymour Narrows, Active Pass, Dodd Narrows and 19
/// more), and the one derived gate (`ChsGateInfo`). An earlier version of
/// this function checked NOAA only, so it told a mariner at Seymour Narrows —
/// one of this coast's fiercest tidal passes, and a gate the app ships a
/// validated model for — that predictions were "not available here". A
/// missed source is the same class of dishonest silence as a missed radius.
func hasCurrentCoverage(latitude: Double, longitude: Double) -> Bool {
    func near<T: StationIdentity>(_ items: [T]) -> Bool {
        items.contains { distanceKm(latitude, longitude, $0.latitude, $0.longitude) < 20 }
    }
    return near(CurrentStationRecord.all) || near(ChsCurrentGateInfo.all) || near(ChsGateInfo.all)
}

/// Where a fittable CHS station stands, in precedence order: what is happening
/// right now beats what is merely true. Replaces the five sentences
/// `chsPendingMessage` used to build.
@MainActor func cardStatus(id: String, fitting: Bool = false, failed: Bool = false) -> CardStatus {
    if fitting { return .downloading }
    if failed { return .failed }
    // Not in the download set at all (M53 — most of Canada). Opening it is what
    // downloads it, so this is the honest state connected or not; it must not
    // claim a queue it isn't in.
    if !ChsFitService.shared.isQueued(id) { return .notDownloaded }
    return Connectivity.shared.online ? .queued : .offline
}

/// The 7 online (fit-reject) gates: never queued, never fitted, so the only
/// question is what is on disk. Called with a window that does NOT cover the
/// strip on screen — a covering one renders as an ordinary reading.
///
/// Pure, and split from the view for it: the nil/stale distinction is the bug
/// #93 named, and it needs a test that doesn't build a card.
func onlineGateStatus(_ window: ChsOnlineWindow?, online: Bool) -> CardStatus {
    // Offline first: with no signal, neither tapping nor waiting fetches
    // anything, so "get online" is the only true thing to say.
    guard online else { return .offline }
    return window == nil ? .notDownloaded : .expired
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
