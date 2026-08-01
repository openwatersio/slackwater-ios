// Slackwater — GPL v3. The CHS detail route. Every CHS tap — list row, search
// result, map pin — lands here, fitted or not: a tap must never be a dead tap.
//
// Fitted, this is a pass-through to the ordinary detail view (identical
// surface, identical provenance footer). Unfitted, it is the warning that used
// to be missing: what is happening, where the station sits in the queue,
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
                if case .fitted(let record) = service.currentState(gate.id) {
                    CurrentDetailView(record: record)
                } else {
                    waiting(name: gate.name, region: "\(gate.region) · current", favoriteId: "current:" + gate.id,
                            latitude: gate.latitude, longitude: gate.longitude, needs: nil)
                }
            case .derivedGate(let gate):
                if case .fitted(let port) = service.state(gate.reference) {
                    DerivedGateDetailView(record: DerivedGateRecord(gate: gate, port: port))
                } else {
                    waiting(name: gate.name, region: "\(gate.region) · current", favoriteId: gate.id,
                            latitude: gate.latitude, longitude: gate.longitude, needs: gate.referenceName)
                }
            }
        }
        // Viewing is the strongest possible signal of what to download next.
        // ponytail: takes effect at the next job boundary — a 210-day current
        // gate already in flight finishes first (≈2.5 min ceiling). Cancelling
        // mid-station would mean throwing away paid-for requests; revisit only
        // if that wait is what people complain about.
        .onAppear { service.promote(route.jobID) }
    }

    private func waiting(name: String, region: String, favoriteId: String,
                         latitude: Double, longitude: Double, needs: String?) -> some View {
        ChsWaitingView(jobID: route.jobID, name: name, region: region, favoriteId: favoriteId,
                       latitude: latitude, longitude: longitude, referenceName: needs)
    }
}

/// The unfitted station page: the ordinary map header (so it is recognisably
/// this station, and back/favourite work), then the ⚠️ explanation in place of
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

    private var job: ChsJob? { service.queue.job(jobID) }
    private var isCurrent: Bool { job?.isCurrent ?? false }
    /// "tidal" / "current" — the established plain register (ChsPendingCard).
    private var series: String { isCurrent ? "current" : "tidal" }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                MapHeader(name: name, region: region, latitude: latitude, longitude: longitude,
                          favoriteId: favoriteId, showReturn: false, onReturn: {})
                warningCard
                footer
            }
            .padding(.bottom, 42)
        }
        .ignoresSafeArea(edges: .top)
        .background(SN.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDownloads) { OfflineManagerView() }
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 21))
                    .foregroundStyle(SN.amber)
                    .frame(width: 46, height: 46)
                    .background(SN.amber.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("Warning")
                VStack(alignment: .leading, spacing: 3) {
                    Text("No predictions yet")
                        .font(.fraunces(20, .semibold))
                        .foregroundStyle(SN.paper)
                    Text(headline)
                        .font(.geist(13))
                        .foregroundStyle(SN.foam.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(expectation)
                .font(.geist(13))
                .lineSpacing(3)
                .foregroundStyle(SN.foam.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("chs-waiting-expectation")

            Button { showDownloads = true } label: {
                HStack(spacing: 4) {
                    Text(job?.status == .failed ? "Retry in Downloads" : "See all downloads")
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }
                .font(.geist(15, .semibold))
                .foregroundStyle(SN.amber)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SN.amber.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(SN.amber.opacity(0.35), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("chs-waiting-warning")
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
        guard net.online, job?.status != .failed else {
            return "Nothing downloads without a connection. Once it does, this station works offline — with no signal — for good."
        }
        let queued = service.queue.position(jobID).map { at -> String in
            at <= 1 ? "It's first in line — moved to the front because you opened it."
                    : "It's \(ordinal(at)) in line — moved up because you opened it."
        } ?? ""
        return "\(queued) Usually \(durationPhrase(service.queue.waitSeconds(jobID))). It downloads once; after that this station works offline, with no signal, for good."
    }

    private var footer: some View {
        MonoLabel(text: "Predictions — not for navigation",
                  size: 10, color: SN.foam.opacity(0.4), tracking: 1.4)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
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
