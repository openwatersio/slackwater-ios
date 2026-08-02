// Slackwater — GPL v3. The offline-downloads surface, ported from
// slackwater-web (OfflineStatus.tsx + OfflineManager.tsx and their tests):
//
//   OfflineStatusButton — the indicator beside the settings gear. Answers
//     "what is this app doing about my connection" at a glance, and opens the
//     manager on tap (web OfflineStatus's onOpen).
//   OfflineManagerView  — the download manager: per-station state, progress,
//     what's queued / downloading / done / failed, and retry (web
//     OfflineManager's dialog).
//
// Deviations from the web, and why:
//   - No pause. The web pauses to ration a weekly cache re-fetch; here a
//     station is fitted once and never re-downloaded, so there is nothing to
//     ration and nothing to pause for.
//   - No Clear cache / expiry / "offline through <date>". A fitted harmonic
//     model does not expire — that whole axis of the web's UI has no meaning
//     on device.
//   - ONE list in queue order, not the web's Currents/Tides grouping. Order is
//     the feature here (proximity, and the promotion of whatever you opened);
//     grouping would hide exactly the thing the manager has to make visible.
//     The series is a per-row tag instead.
import SwiftUI
import Network

/// Is there a network path right now. Its own tiny observable so the indicator
/// can say offline/online without any of it leaking into the fit service.
@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()

    @Published private(set) var online: Bool
    private let monitor = NWPathMonitor()

    private init() {
        // The kill switch is the UI tests' airplane mode: stay offline, and
        // don't start a monitor that would immediately contradict it.
        online = !CommandLine.arguments.contains("-networkKillSwitch")
        guard online else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in self?.online = up }
        }
        monitor.start(queue: .global(qos: .utility))
    }
}

/// What the indicator beside the gear is saying.
///
/// ponytail: three states today. The reserved fourth is `.live` — when a
/// connection will mean we're serving realtime observations in preference to
/// the offline predictions. Deliberately NOT built; adding the case and one
/// branch below is the whole change when it is.
enum OfflineIndicatorState: Equatable {
    case downloading(ready: Int, total: Int)
    case online
    case offline
}

struct OfflineStatusButton: View {
    let onOpen: () -> Void
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared

    private var state: OfflineIndicatorState {
        let queue = service.queue
        if net.online, queue.active, !service.networkDisabled {
            return .downloading(ready: queue.ready, total: queue.total)
        }
        return net.online ? .online : .offline
    }

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                if case .downloading(let ready, let total) = state {
                    Circle()
                        .trim(from: 0, to: total > 0 ? CGFloat(ready) / CGFloat(total) : 0)
                        .stroke(SN.leaf, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 28, height: 28)
                }
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)  // List rows: keep the tap on the control itself
        .accessibilityLabel("Offline downloads")
        .accessibilityValue(spoken)
        .accessibilityIdentifier("offline-status")
    }

    private var icon: String {
        switch state {
        case .downloading: "arrow.down"
        case .online: "antenna.radiowaves.left.and.right"
        case .offline: "antenna.radiowaves.left.and.right.slash"
        }
    }

    /// Amber only when the state actually needs attention: stalled downloads,
    /// or no signal with stations still missing. Everything else is calm.
    private var tint: Color {
        switch state {
        case .downloading: service.queue.failed > 0 ? SN.amber : SN.leaf
        case .online: service.queue.failed > 0 ? SN.amber : SN.foam.opacity(0.8)
        case .offline: service.queue.complete ? SN.leaf : SN.amber
        }
    }

    private var spoken: String {
        switch state {
        case .downloading(let ready, let total): "Downloading, \(ready) of \(total) ready"
        case .online: service.queue.complete ? "Online, all stations downloaded" : "Online"
        case .offline: service.queue.complete ? "Offline, all stations downloaded"
                                              : "Offline, \(service.queue.total - service.queue.ready) still to download"
        }
    }
}

// MARK: - The manager

/// Sheet presentation (from the indicator): the list plus its own Done.
struct OfflineManagerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            OfflineManagerList()
                .navigationTitle("Downloads")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(SN.page, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(SN.leaf)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

/// The manager proper — also pushed from Settings, hence no chrome of its own.
struct OfflineManagerList: View {
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared

    private var queue: ChsQueue { service.queue }

    var body: some View {
        ScrollView {
            // Lazy, and the list is bounded by construction (M53): the queue
            // is the DOWNLOAD SET — the nearest few, whatever you opened, and
            // whatever is already on disk — not the 1,097-station catalog.
            // Rendering all of Canada here was the old shape and would have
            // been an unbounded list of rows nobody scrolls.
            LazyVStack(alignment: .leading, spacing: 14) {
                summary
                ForEach(queue.jobs) { row($0) }
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .background(SN.page.ignoresSafeArea())
        .accessibilityIdentifier("downloads-manager")
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: "\(queue.ready) of \(queue.total) ready")
            ProgressView(value: Double(queue.ready), total: Double(max(queue.total, 1)))
                .tint(queue.failed > 0 ? SN.amber : SN.leaf)
            Text(summaryLine)
                .font(.geist(14))
                .lineSpacing(3)
                .foregroundStyle(SN.foam.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            if queue.failed > 0 {
                Button { service.retryFailed() } label: {
                    Text("Retry \(queue.failed) failed")
                        .font(.geist(15, .semibold))
                        .foregroundStyle(SN.amber)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
    }

    /// What the manager is honest about at national scale (M53): this list is
    /// the download SET, not the catalog. "Done" means the nearest stations
    /// are on the device — and the sentence has to say, every time, that the
    /// rest of Canada is one tap away rather than missing.
    private var summaryLine: String {
        if queue.complete {
            return "The Canadian stations nearest you are on this device. Slackwater works with no signal.\(onDemandLine)"
        }
        if !net.online {
            return "Waiting for signal. Downloading Canadian tidal and current predictions resumes as soon as you're connected — each station downloads once, then works offline for good.\(onDemandLine)"
        }
        return "Downloading Canadian tidal and current predictions… Nearest to you first, and whatever you open jumps the queue. Usually \(durationPhrase(remainingSeconds)) for the rest.\(onDemandLine)"
    }

    private var onDemandLine: String {
        let rest = service.notQueued
        guard rest > 0 else { return "" }
        return " \(rest) more Canadian stations are searchable everywhere — open one and it downloads."
    }

    private var remainingSeconds: Double {
        queue.jobs.filter { $0.status == .pending || $0.status == .downloading }
            .reduce(0) { $0 + $1.estimatedSeconds }
    }

    // MARK: Rows

    /// Web OfflineManager STATUS_TEXT, verbatim — except for the gate that is
    /// usable but not finished, which the web has no equivalent of.
    private func statusText(_ job: ChsJob) -> String {
        if service.isProvisional(job.id) { return "Refining…" }
        switch job.status {
        case .pending: return "Waiting"
        case .downloading: return "Downloading…"
        case .ready: return "Offline ✓"
        case .failed: return "Failed"
        }
    }

    private func statusTint(_ job: ChsJob) -> Color {
        if service.isProvisional(job.id) { return SN.amber }
        switch job.status {
        case .pending: return SN.foam.opacity(0.5)
        case .downloading: return SN.leaf
        case .ready: return SN.leaf
        case .failed: return SN.amber
        }
    }

    private func row(_ job: ChsJob) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(stationGradient(id: job.id))
                .frame(width: 38, height: 38)
                // Provisional sits between the two: usable, not finished.
                .opacity(job.status == .ready ? 1 : service.isProvisional(job.id) ? 0.75 : 0.45)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.geist(16, .medium))
                    .foregroundStyle(SN.paper)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    // The promotion, made visible: this is the one you opened.
                    // On the subtitle line, so a badge never truncates a name.
                    if queue.isPromoted(job.id) {
                        MonoLabel(text: "You opened", size: 9, color: SN.amber, tracking: 1.2)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(SN.amber.opacity(0.16), in: Capsule())
                    }
                    // Usable now, not finished — and it says by how much.
                    if service.isProvisional(job.id),
                       let gate = ChsCurrentGateInfo.all.first(where: { $0.id == job.id }) {
                        MonoLabel(text: "Fast answer \(gate.provisionalTolerance)",
                                  size: 9, color: SN.amber, tracking: 1.2)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(SN.amber.opacity(0.18), in: Capsule())
                    }
                    Text("\(job.isCurrent ? "Current" : "Tide") · \(job.region)")
                        .font(.geist(12))
                        .foregroundStyle(SN.foam.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if job.status == .failed {
                Button { service.promote(job.id) } label: {
                    Text("Retry")
                        .font(.geist(13, .semibold))
                        .foregroundStyle(SN.amber)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(SN.amber.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text(statusText(job))
                    .font(.geist(13))
                    .foregroundStyle(statusTint(job))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("download-row-\(job.id)")
    }
}
