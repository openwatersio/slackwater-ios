// Slackwater — GPL v3. The CHS detail route. Every CHS tap — list row, search
// result, map pin — lands here, fitted or not: a tap must never be a dead tap.
//
// Fitted, this is a pass-through to the ordinary detail view (identical
// surface, identical provenance footer). Unfitted, it is the status card that
// used to be missing: what is happening, where the station sits in the queue,
// roughly how long, and that it only ever happens once. Viewing a station also
// jumps it to the FRONT of the download queue — the thing you are looking at
// downloads first — and the page fills in live the moment its fit lands.
import SwiftUI

/// A CHS station as a navigation value. Carries identity only; the record (if
/// any) is looked up at render time, so the same value renders the warning
/// before the fit and the real detail after it.
enum ChsRoute: Hashable {
    case port(ChsStationInfo)
    case currentGate(ChsCurrentGateInfo)
    /// A derived gate has no download of its own — it is predictable exactly
    /// when its reference PORT is fitted, so that is the job it waits on.
    case derivedGate(ChsGateInfo)

    /// This route's own station — the navigation destination's identity, so
    /// opening a second CHS station replaces the view rather than reusing it
    /// (see `navigationDestination` in SlackwaterApp). Not `jobID`: two derived
    /// gates can share a reference port and would collide there.
    var stationID: String {
        switch self {
        case .port(let info): info.id
        case .currentGate(let gate): gate.id
        case .derivedGate(let gate): gate.id
        }
    }

    /// The queue job this route waits on.
    var jobID: String {
        switch self {
        case .port(let info): info.id
        case .currentGate(let gate): gate.id
        case .derivedGate(let gate): gate.reference
        }
    }
}

struct ChsDetailView: View {
    let route: ChsRoute
    @ObservedObject private var service = ChsFitService.shared

    var body: some View {
        Group {
            switch route {
            case .port(let info):
                if case .fitted(let record) = service.state(info.id) {
                    TideDetailView(record: record)
                } else {
                    waiting(name: info.name, region: info.region, favoriteId: info.id, needs: nil)
                }
            case .currentGate(let gate):
                if gate.isOnline {
                    // The 7 fit-rejects: no on-device model ever exists for
                    // these, so there is no fit to wait on — a fetched
                    // window or the honest why-not, never the waiting page.
                    OnlineGateDetailView(gate: gate)
                } else if case .fitted(let record) = service.currentState(gate.id) {
                    CurrentDetailView(record: record)
                } else {
                    // Bare id: CHS gates key the catalog without the NOAA
                    // "current:" prefix — see CurrentStationRecord.itemId.
                    waiting(name: gate.name, region: gate.region, favoriteId: gate.id, needs: nil)
                }
            case .derivedGate(let gate):
                if case .fitted(let port) = service.state(gate.reference) {
                    DerivedGateDetailView(record: DerivedGateRecord(gate: gate, port: port))
                } else {
                    waiting(name: gate.name, region: gate.region, favoriteId: gate.id,
                            needs: gate.referenceName)
                }
            }
        }
        // Viewing moves pending work to the front without interrupting the
        // station already downloading. Online gates never join this queue.
        .onAppear { if !isOnlineGate { service.promote(route.jobID) } }
    }

    /// True only for `.currentGate` routes on one of the 7 online gates.
    private var isOnlineGate: Bool {
        if case .currentGate(let gate) = route { return gate.isOnline }
        return false
    }

    private func waiting(name: String, region: String, favoriteId: String,
                         needs: String?) -> some View {
        ChsWaitingView(jobID: route.jobID, name: name, region: region,
                       favoriteId: favoriteId, referenceName: needs)
    }
}

/// The unfitted station page: the same name header the four scrub details
/// wear (so it is recognisably this station, and back/favourite work), then
/// the live status in place of the chart. Never an empty chart, never a
/// spinner to nothing.
struct ChsWaitingView: View {
    let jobID: String
    let name: String
    let region: String
    let favoriteId: String
    /// Set for a derived gate: the reference port whose tide it waits on.
    let referenceName: String?

    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared
    @State private var showDownloads = false
    // Re-forwarded onto the sheet below — `.sheet` content doesn't inherit a
    // custom `@Environment` key set above the presenting view on its own
    // (SlackwaterApp.swift's `.sheet(showDownloads)` comment has the story).
    @Environment(\.openChsRoute) private var openChsRoute

    private var job: ChsJob? { service.queue.job(jobID) }
    private var isCurrent: Bool { job?.isCurrent ?? false }
    /// "tidal" / "current" — the established plain register (ChsPendingCard).
    var body: some View {
        // GeometryReader reads the real top inset for DetailHeader (only the
        // ScrollView below ignores the safe area) — the scaffold in
        // Theme.swift does the same.
        GeometryReader { geo in
            ScrollView {
                // spacing 0: the hero→card seam is flush (2026-08-03 spec §2
                // "Flush"), same as the four scrubbable details' scaffold. The
                // status card's own interior `.padding(.vertical, 18)` is the
                // inset the pill sits on — inside the tinted card, like the
                // scrub card's interior 14 — so the seam doesn't double up.
                VStack(spacing: 0) {
                    // No map while a station downloads: the header names the
                    // station and gets out of the way, so the status card is
                    // the whole page.
                    DetailHeader(name: name, region: region, favoriteId: favoriteId,
                                 topSafeInset: geo.safeAreaInsets.top)
                    statusCard
                    footer
                }
                .padding(.bottom, 42)
            }
            .ignoresSafeArea(edges: .top)
            .background(CanvasBackground())
            .toolbar(.hidden, for: .navigationBar)
            // A shared link's moment stops here: there is no strip to scrub,
            // and left waiting it would follow the user to whichever station
            // they open next (a list row pushes without resetting it).
            .onAppear { _ = LinkedInstant.shared.take(for: favoriteId) }
            .sheet(isPresented: $showDownloads) { OfflineManagerView().environment(\.openChsRoute, openChsRoute) }
        }
        .onAppear { RecentsStore.shared.record(favoriteId) }
    }

    private var status: CardStatus {
        cardStatus(id: jobID)
    }

    private var title: String {
        switch status {
        case .downloading: String(localized: "Downloading…", comment: "Station download-card title.")
        case .queued: String(localized: "Waiting", comment: "Station download-card title.")
        case .retrying: String(localized: "Retrying", comment: "Station download-card title.")
        case .offline: String(localized: "Waiting for signal", comment: "Station download-card title while offline.")
        case .failed: String(localized: "Download failed", comment: "Station download-card title.")
        default: status.label
        }
    }

    private var statusCard: some View {
        VStack(spacing: 8) {
            ChsAmberCard(title: title, headline: headline, expectation: expectation,
                         action: status == .failed
                            ? String(localized: "Retry", comment: "Retry a failed station download.")
                            : String(localized: "See all downloads", comment: "Open the offline-download manager."),
                         identifier: "chs-waiting-warning", status: status) {
                if status == .failed { service.promote(jobID) }
                else { showDownloads = true }
            }
            if status == .failed {
                Button("See all downloads") { showDownloads = true }
                    .font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 20)
            }
        }
    }

    /// The one-line "what is happening", in the same plain register as the
    /// download manager.
    private var headline: String {
        if !net.online {
            return referenceName.map {
                String(localized: "\($0)'s tide predictions need a connection before they can download.", comment: "Station download explanation. The value is a reference-station name.")
            } ?? String(localized: "This station's predictions need a connection before they can download.", comment: "Station download explanation.")
        }
        if status == .retrying {
            return referenceName.map {
                String(localized: "\($0)'s tide predictions didn't finish downloading. Slackwater will try again.", comment: "Station download retry explanation. The value is a reference-station name.")
            } ?? String(localized: "This station's predictions didn't finish downloading. Slackwater will try again.", comment: "Station download retry explanation.")
        }
        switch job?.status {
        case .failed:
            return referenceName.map {
                String(localized: "\($0)'s tide predictions couldn't be downloaded.", comment: "Station download failure. The value is a reference-station name.")
            } ?? String(localized: "This station's predictions couldn't be downloaded.", comment: "Station download failure.")
        case .downloading:
            return isCurrent
                ? String(localized: "Downloading Canadian current predictions…", comment: "Station download progress.")
                : String(localized: "Downloading Canadian tidal predictions…", comment: "Station download progress.")
        default:
            if let referenceName {
                return isCurrent
                    ? String(localized: "\(referenceName)'s tide predictions aren't on this device yet. Downloading Canadian current predictions…", comment: "Station download explanation. The value is a reference-station name.")
                    : String(localized: "\(referenceName)'s tide predictions aren't on this device yet. Downloading Canadian tidal predictions…", comment: "Station download explanation. The value is a reference-station name.")
            }
            return isCurrent
                ? String(localized: "This station's predictions aren't on this device yet. Downloading Canadian current predictions…", comment: "Station download explanation.")
                : String(localized: "This station's predictions aren't on this device yet. Downloading Canadian tidal predictions…", comment: "Station download explanation.")
        }
    }

    /// What to expect: where it sits in the queue, roughly how long, and that
    /// it is once-and-for-all.
    private var expectation: String {
        guard net.online else {
            return String(localized: "Connect once to download this station for permanent offline use.", comment: "Station download expectation while offline.")
        }
        if job?.status == .failed {
            return String(localized: "Retry this station. Once downloaded, it stays available offline.", comment: "Station download expectation after failure.")
        }
        if status == .retrying {
            return String(localized: "Slackwater retries automatically when a connection is available.", comment: "Station download retry expectation.")
        }
        if let job, job.status == .downloading, job.total > 0 {
            return String(localized: "\(job.done) of \(job.total) requests downloaded. This station stays available offline when finished.", comment: "Station download progress. Values are completed and total request counts.")
        }
        let queued = service.queue.position(jobID).map { at -> String in
            at <= 1
                ? String(localized: "It's first in line — moved to the front because you opened it.", comment: "Station download queue position.")
                : String(localized: "It's \(ordinal(at)) in line — moved up because you opened it.", comment: "Station download queue position. The value is a locale-formatted ordinal.")
        } ?? ""
        let wait = durationPhrase(service.queue.waitSeconds(jobID, perRequest: service.observedSecondsPerRequest))
        return queued.isEmpty
            ? String(localized: "Estimated wait: \(wait). The station downloads once and stays available offline.", comment: "Station download expectation. The value is an approximate duration.")
            : String(localized: "\(queued) Estimated wait: \(wait). The station downloads once and stays available offline.", comment: "Station download expectation. Values are a localized queue sentence and approximate duration.")
    }

    private var footer: some View {
        MonoLabel(text: String(localized: "Predictions — not for navigation", comment: "Safety disclaimer above station provenance."),
                  color: SN.foam.opacity(0.4), tracking: 1.4)
            .frame(maxWidth: .infinity)
            // 14, matching the scaffold's standard below-card gap — spacing 0
            // above means this padding is the whole card→footer gap now.
            .padding(.top, 14)
    }
}

/// The ⚠️ card: the app's one shape for "these numbers aren't what you think".
/// Shared by the not-yet-downloaded station, the provisional fast answer and
/// the location-denied card, on purpose — a user who has learned to read the
/// amber block once has learned to read it everywhere.
struct ChsAmberCard: View {
    let title: String
    let headline: String
    var expectation: String? = nil
    let action: String
    let identifier: String
    var icon = "exclamationmark.triangle.fill"
    /// Amber is this app's warning language and the comment on `unavailableCard`
    /// keeps it scarce on purpose. An invitation is not a warning: the location
    /// ask card passes leaf, the same green the gate's location
    /// button uses, so a user who simply never opted in isn't nagged in the
    /// colour reserved for something being wrong. `status` still wins when set.
    var accent = SN.amber
    /// What VoiceOver calls the icon when no `status` supplies one. Defaults
    /// to the shape's own meaning; the unavailable-station card (issue #401)
    /// passes its own, because "Warning" on a card whose text says it is not
    /// a warning is the screen reader telling a different story than the
    /// screen.
    var iconLabel = String(localized: "Warning", comment: "VoiceOver label for a warning icon.")
    var status: CardStatus? = nil
    let onAction: () -> Void

    /// Tracks the icon's own `.title3` so the tile keeps containing the
    /// triangle instead of being outgrown by it (sweep finding: Step 5b's
    /// text-companion conversion scaled the icon but left this frame literal,
    /// same failure shape as `ProvisionalBadge` before its own fix).
    @ScaledMetric(relativeTo: .title3) private var iconTileSize: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                Image(systemName: status?.icon ?? icon)
                    .font(.title3)
                    .foregroundStyle(status?.tint ?? accent)
                    .frame(width: iconTileSize, height: iconTileSize)
                    .background((status?.tint ?? accent).opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(status?.accessibilityLabel ?? iconLabel)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SN.paper)
                    Text(headline)
                        .font(.footnote)
                        .foregroundStyle(SN.foam.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if status == .downloading {
                ProgressView()
                    .tint(status?.tint ?? SN.leaf)
            }

            if let expectation {
                Text(expectation)
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(SN.foam.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chs-waiting-expectation")
            }

            Button(action: onAction) {
                HStack(spacing: 4) {
                    Text(action)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status?.tint ?? accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status == nil ? accent.opacity(0.1) : SN.cardFill,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(status == nil ? accent.opacity(0.35) : SN.cardStroke, lineWidth: 0.5))
        .padding(.horizontal, 16)
        .accessibilityIdentifier(identifier)
    }
}

/// A locale-aware queue position ("1st", "1er", …).
func ordinal(_ n: Int, locale: Locale = .autoupdatingCurrent) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .ordinal
    return formatter.string(from: NSNumber(value: n)) ?? String(n)
}

/// "under a minute" / "about 3 minutes" — deliberately coarse: the estimate is
/// a pacing constant, and a ticking countdown would claim precision it hasn't.
func durationPhrase(_ seconds: Double) -> String {
    if seconds < 90 { return String(localized: "under a minute", comment: "Approximate download duration under ninety seconds.") }
    let minutes = Int((seconds / 60).rounded())
    if minutes < 60 { return String(localized: "about \(minutes) minutes", comment: "Approximate duration. The integer is a number of minutes; vary by plural.") }
    let hours = Int((Double(minutes) / 60).rounded())
    return hours <= 1
        ? String(localized: "about an hour", comment: "Approximate duration of one hour.")
        : String(localized: "about \(hours) hours", comment: "Approximate duration. The integer is a number of hours; vary by plural.")
}
