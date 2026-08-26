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
                    waiting(name: info.name, region: info.region, favoriteId: info.id,
                            latitude: info.latitude, longitude: info.longitude, needs: nil)
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
                    waiting(name: gate.name, region: gate.region, favoriteId: gate.id,
                            latitude: gate.latitude, longitude: gate.longitude, needs: nil)
                }
            case .derivedGate(let gate):
                if case .fitted(let port) = service.state(gate.reference) {
                    DerivedGateDetailView(record: DerivedGateRecord(gate: gate, port: port))
                } else {
                    waiting(name: gate.name, region: gate.region, favoriteId: gate.id,
                            latitude: gate.latitude, longitude: gate.longitude, needs: gate.referenceName)
                }
            }
        }
        // Viewing is the strongest possible signal of what to download next,
        // and M51 made it act like one: the running job steps aside at its next
        // CHUNK boundary (~2.5 s), not its next station boundary (up to ~2.5
        // min for a 210-day gate). Nothing paid for is thrown away — chunks are
        // cached, so the yielded job resumes exactly where it stopped.
        //
        // An online gate has no job — it was never queued (isOnline never
        // queued, ChsFitService.candidates) — so there is nothing to promote.
        .onAppear { if !isOnlineGate { service.promote(route.jobID) } }
    }

    /// True only for `.currentGate` routes on one of the 7 online gates.
    private var isOnlineGate: Bool {
        if case .currentGate(let gate) = route { return gate.isOnline }
        return false
    }

    private func waiting(name: String, region: String, favoriteId: String,
                         latitude: Double, longitude: Double, needs: String?) -> some View {
        ChsWaitingView(jobID: route.jobID, name: name, region: region, favoriteId: favoriteId,
                       latitude: latitude, longitude: longitude, referenceName: needs)
    }
}

/// The unfitted station page: the ordinary map header (so it is recognisably
/// this station, and back/favourite work), then the live status in place of
/// the chart. Never an empty chart, never a spinner to nothing.
struct ChsWaitingView: View {
    let jobID: String
    let name: String
    let region: String
    let favoriteId: String
    let latitude: Double
    let longitude: Double
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
    private var series: String { isCurrent ? "current" : "tidal" }

    var body: some View {
        // GeometryReader reads the real top inset for MapHeader (only the
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
                    MapHeader(name: name, region: region, latitude: latitude, longitude: longitude,
                              favoriteId: favoriteId, topSafeInset: geo.safeAreaInsets.top)
                    statusCard
                    footer
                }
                .padding(.bottom, 42)
            }
            .ignoresSafeArea(edges: .top)
            .background(CanvasBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDownloads) { OfflineManagerView().environment(\.openChsRoute, openChsRoute) }
        }
    }

    private var status: CardStatus {
        if !net.online { return .offline }
        switch job?.status {
        case .failed: return .failed
        case .downloading: return .downloading
        default: return .queued
        }
    }

    private var title: String {
        switch status {
        case .downloading: "Downloading…"
        case .queued: "Waiting"
        case .offline: "Waiting for signal"
        case .failed: "Download failed"
        default: status.label
        }
    }

    private var statusCard: some View {
        VStack(spacing: 8) {
            ChsAmberCard(title: title, headline: headline, expectation: expectation,
                         action: status == .failed ? "Retry" : "See all downloads",
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

    /// The one-line "what is happening". The established plain register is
    /// kept verbatim — "Downloading Canadian tidal/current predictions…".
    private var headline: String {
        let what = referenceName.map { "\($0)'s tide predictions" } ?? "This station's predictions"
        if !net.online {
            return "\(what) need a moment of signal — Canadian \(series) predictions download once, then work offline."
        }
        switch job?.status {
        case .failed:
            return "\(what) didn't finish downloading."
        case .downloading:
            return "Downloading Canadian \(series) predictions…"
        default:
            return "\(what) haven't downloaded yet. Downloading Canadian \(series) predictions…"
        }
    }

    /// What to expect: where it sits in the queue, roughly how long, and that
    /// it is once-and-for-all.
    private var expectation: String {
        guard net.online else {
            return "Nothing downloads without a connection. Once it does, this station works offline — with no signal — for good."
        }
        if job?.status == .failed {
            return "Try this station again here. Once it downloads, it works offline — with no signal — for good."
        }
        let queued = service.queue.position(jobID).map { at -> String in
            at <= 1 ? "It's first in line — moved to the front because you opened it."
                    : "It's \(ordinal(at)) in line — moved up because you opened it."
        } ?? ""
        return "\(queued) Usually \(durationPhrase(service.queue.waitSeconds(jobID))). It downloads once; after that this station works offline, with no signal, for good."
    }

    private var footer: some View {
        MonoLabel(text: "Predictions — not for navigation",
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
                    .foregroundStyle(status?.tint ?? SN.amber)
                    .frame(width: iconTileSize, height: iconTileSize)
                    .background((status?.tint ?? SN.amber).opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(status?.accessibilityLabel ?? "Warning")
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
                .foregroundStyle(status?.tint ?? SN.amber)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status == nil ? SN.amber.opacity(0.1) : SN.cardFill,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(status == nil ? SN.amber.opacity(0.35) : SN.cardStroke, lineWidth: 0.5))
        .padding(.horizontal, 16)
        .accessibilityIdentifier(identifier)
    }
}

/// "1st" … — small enough that NumberFormatter's .ordinal (and its locale
/// machinery) would be the heavier option.
func ordinal(_ n: Int) -> String {
    let suffix: String
    switch (n % 10, n % 100) {
    case (1, 11), (2, 12), (3, 13): suffix = "th"
    case (1, _): suffix = "st"
    case (2, _): suffix = "nd"
    case (3, _): suffix = "rd"
    default: suffix = "th"
    }
    return "\(n)\(suffix)"
}

/// "under a minute" / "about 3 minutes" — deliberately coarse: the estimate is
/// a pacing constant, and a ticking countdown would claim precision it hasn't.
func durationPhrase(_ seconds: Double) -> String {
    if seconds < 90 { return "under a minute" }
    let minutes = Int((seconds / 60).rounded())
    if minutes < 60 { return "about \(minutes) minutes" }
    let hours = Int((Double(minutes) / 60).rounded())
    return hours <= 1 ? "about an hour" : "about \(hours) hours"
}
