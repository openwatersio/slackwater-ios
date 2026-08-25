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

enum ManagedDownloadState: Equatable {
    case downloading, queued, failed, expired, notDownloaded, available, permanent
}

func downloadSortRank(_ state: ManagedDownloadState, remainingDays: Int?) -> Int {
    switch state {
    case .downloading: 0
    case .queued: 100_000
    case .failed, .expired, .notDownloaded: 200_000
    case .available where (remainingDays ?? 0) <= 3: 200_000
    case .available: 300_000 + (remainingDays ?? 0)
    case .permanent: 400_000
    }
}

func downloadIsReady(_ state: ManagedDownloadState) -> Bool {
    state == .available || state == .permanent
}

private enum ManagedDownload: Identifiable {
    case fitted(ChsJob)
    case online(ChsCurrentGateInfo)

    var id: String {
        switch self {
        case .fitted(let job): "fitted-\(job.id)"
        case .online(let gate): "online-\(gate.id)"
        }
    }
}

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
        online = !networkKillSwitch
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
        if net.online, queue.active, !networkKillSwitch {
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
                // Fixed, not scaled: this button is one of the two 34pt chrome
                // circles the list header's wordmark comment is calibrated
                // against (SlackwaterApp.swift `header`, beside the gear,
                // which stays fixed too) — the same 320pt iPad sidebar row.
                // Step 5b's table called this a text companion; it isn't one —
                // reverted to its pre-Task-5 literal size (sweep finding).
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openChsRoute) private var openChsRoute
    @State private var fetchingOnline: Set<String> = []
    @State private var failedOnline: Set<String> = []
    // Same glyph-in-slot sizing RecentRowLabel carries (issue #14): the glyph
    // scales with type, the slot scales with it so it can't overflow the row.

    private var queue: ChsQueue { service.queue }
    private var onlineGates: [ChsCurrentGateInfo] { ChsCurrentGateInfo.all.filter(\.isOnline) }
    private var downloads: [ManagedDownload] {
        let items = queue.jobs.map(ManagedDownload.fitted) + onlineGates.map(ManagedDownload.online)
        return items.enumerated().sorted { lhs, rhs in
            let left = sortRank(lhs.element)
            let right = sortRank(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    var body: some View {
        ScrollView {
            // Lazy, and the list is bounded by construction (M53): the queue
            // is the DOWNLOAD SET — the nearest few, whatever you opened, and
            // whatever is already on disk — not the 1,097-station catalog.
            // Rendering all of Canada here was the old shape and would have
            // been an unbounded list of rows nobody scrolls.
            LazyVStack(alignment: .leading, spacing: 14) {
                summary
                ForEach(downloads) { download in
                    switch download {
                    case .fitted(let job): row(job)
                    case .online(let gate): onlineRow(gate)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .background(SN.page.ignoresSafeArea())
        .accessibilityIdentifier("downloads-manager")
        .onChange(of: net.online) { _, online in
            guard online else { return }
            for id in Array(failedOnline) {
                if let gate = onlineGates.first(where: { $0.id == id }) { fetch(gate) }
            }
        }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: "\(readyCount) of \(downloads.count) ready")
            ProgressView(value: Double(readyCount), total: Double(max(downloads.count, 1)))
                .tint(failedCount > 0 ? SN.amber : SN.leaf)
            Text(summaryLine)
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(SN.foam.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            if failedCount > 0 {
                Button {
                    service.retryFailed()
                    for id in Array(failedOnline) {
                        if let gate = onlineGates.first(where: { $0.id == id }) { fetch(gate) }
                    }
                } label: {
                    Text("Retry \(failedCount) failed")
                        .font(.subheadline.weight(.semibold))
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
        if readyCount == downloads.count, !downloads.isEmpty {
            return "Downloaded predictions are ready offline. Downloads that expire show their remaining time below.\(onDemandLine)"
        }
        if !net.online {
            return "Waiting for signal. Downloads resume when you're connected; anything already available keeps working offline.\(onDemandLine)"
        }
        return "Downloading Canadian tidal and current predictions… Nearest to you first, and whatever you open jumps the queue. Usually \(durationPhrase(remainingSeconds)) for the rest. Expiring downloads can be refreshed below.\(onDemandLine)"
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

    private var readyCount: Int { downloads.filter { downloadIsReady(managedState($0).state) }.count }
    private var failedCount: Int { queue.failed + failedOnline.count }

    // MARK: Rows

    /// Web OfflineManager STATUS_TEXT, verbatim — except for the gate that is
    /// usable but not finished, which the web has no equivalent of.
    private func statusText(_ job: ChsJob) -> String {
        if service.isProvisional(job.id) { return "Refining…" }
        switch job.status {
        case .pending: return "Waiting"
        case .downloading: return "Downloading…"
        case .ready: return "Available offline"
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

    private func onlineWindow(_ gate: ChsCurrentGateInfo) -> ChsOnlineWindow? {
        ChsModelStore.loadOnline(gate.id)?.blocks.last
    }

    private func remainingDays(_ gate: ChsCurrentGateInfo) -> Int? {
        guard let window = onlineWindow(gate) else { return nil }
        let calendar = gateCalendar(gate)
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: appNow()),
                                       to: calendar.startOfDay(for: window.offlineValidUntil)).day
    }

    private func managedState(_ download: ManagedDownload) -> (state: ManagedDownloadState, days: Int?) {
        switch download {
        case .fitted(let job):
            if job.status == .downloading || service.isProvisional(job.id) { return (.downloading, nil) }
            if job.status == .pending { return (.queued, nil) }
            if job.status == .failed { return (.failed, nil) }
            return (.permanent, nil)
        case .online(let gate):
            if fetchingOnline.contains(gate.id) { return (.downloading, nil) }
            if failedOnline.contains(gate.id) { return (.failed, nil) }
            guard onlineWindow(gate) != nil else { return (.notDownloaded, nil) }
            let days = remainingDays(gate) ?? 0
            return (days < 0 ? .expired : .available, days)
        }
    }

    private func sortRank(_ download: ManagedDownload) -> Int {
        let value = managedState(download)
        return downloadSortRank(value.state, remainingDays: value.days)
    }

    private func onlineStatus(_ gate: ChsCurrentGateInfo) -> String {
        if fetchingOnline.contains(gate.id) { return "Downloading…" }
        if failedOnline.contains(gate.id) { return "Download failed" }
        guard let window = onlineWindow(gate) else { return "Not downloaded" }
        return onlineDownloadValidity(end: window.offlineValidUntil, calendar: gateCalendar(gate))
    }

    private func gateCalendar(_ gate: ChsCurrentGateInfo) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = gate.tz
        return calendar
    }

    private func fetch(_ gate: ChsCurrentGateInfo) {
        guard net.online, !fetchingOnline.contains(gate.id) else { return }
        fetchingOnline.insert(gate.id)
        failedOnline.remove(gate.id)
        Task { @MainActor in
            do {
                _ = try await ChsFitService.fetchOnlineWindow(for: gate, from: todayLocal(gate.tz))
            } catch {
                failedOnline.insert(gate.id)
            }
            fetchingOnline.remove(gate.id)
        }
    }

    private func onlineRow(_ gate: ChsCurrentGateInfo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(gate.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(SN.paper)
                    .lineLimit(1)
                Text("Current · \(gate.region)")
                    .font(.caption)
                    .foregroundStyle(SN.foam.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(onlineStatus(gate))
                    .font(.footnote)
                    .foregroundStyle(failedOnline.contains(gate.id) ? SN.amber : SN.leaf)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                if fetchingOnline.contains(gate.id) {
                    ProgressView().tint(SN.leaf)
                } else {
                    Button { fetch(gate) } label: {
                        Text(onlineWindow(gate) == nil ? "Download" : "Refresh")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(net.online ? SN.leaf : SN.foam.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .disabled(!net.online)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
            openChsRoute(.currentGate(gate))
        }
        .accessibilityIdentifier("download-row-\(gate.id)")
    }

    /// This job's navigation target — a job is identity only (ChsJob's doc
    /// comment), so the route is looked up from the same bundled catalogs the
    /// list and search already key off of. `ChsFitService.candidates` builds
    /// every job from exactly these two arrays, so the lookup always succeeds
    /// in practice; `nil` is handled anyway (issue #33's own instruction) so a
    /// row can never crash if that ever stops being true.
    private func route(for job: ChsJob) -> ChsRoute? {
        if job.isCurrent {
            return ChsCurrentGateInfo.all.first { $0.id == job.id }.map { .currentGate($0) }
        }
        return ChsStationInfo.all.first { $0.id == job.id }.map { .port($0) }
    }

    /// The job as a `StationItem`, for the row glyph's tone binding.
    private func item(for job: ChsJob) -> StationItem? {
        switch route(for: job) {
        case .currentGate(let gate): .chsCurrent(gate)
        case .port(let port): .chs(port)
        case .derivedGate, nil: nil  // derived gates never hold a job
        }
    }

    /// A tap opens the station's own detail — closes Downloads first, then
    /// pushes: `openChsRoute` always appends to the ROOT stack's path, so this
    /// works identically whether Downloads was reached from the list's status
    /// button or a detail's amber "See all downloads" card. A detail that
    /// presented the sheet stays exactly where it was on the back stack, under
    /// the newly pushed route — correct back-stack behavior (issue #33 §3),
    /// not something to special-case per presenting context.
    private func row(_ job: ChsJob) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(SN.paper)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    // The promotion, made visible: this is the one you opened.
                    // On the subtitle line, so a badge never truncates a name.
                    if queue.isPromoted(job.id) {
                        MonoLabel(text: "You opened", color: SN.amber, tracking: 1.2)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(SN.amber.opacity(0.16), in: Capsule())
                    }
                    // Usable now, not finished — and it says by how much.
                    if service.isProvisional(job.id),
                       let gate = ChsCurrentGateInfo.all.first(where: { $0.id == job.id }) {
                        MonoLabel(text: "Fast answer \(gate.provisionalTolerance)",
                                  color: SN.amber, tracking: 1.2)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(SN.amber.opacity(0.18), in: Capsule())
                    }
                    Text("\(job.isCurrent ? "Current" : "Tide") · \(job.region)")
                        .font(.caption)
                        .foregroundStyle(SN.foam.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if job.status == .failed {
                Button { service.promote(job.id) } label: {
                    Text("Retry")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SN.amber)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(SN.amber.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text(statusText(job))
                    .font(.footnote)
                    .foregroundStyle(statusTint(job))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Gesture, never a Button/NavigationLink wrapper: this sheet can be
        // presented over the iPad split detail column, where Button press
        // tracking goes dead below the strip but tap gestures keep working
        // (same rule `activatable`/`TideAtPortLink` follow). The Retry button
        // above sits inside this HStack, ahead of the gesture in the
        // hierarchy, so its own tap still wins there — this only catches taps
        // elsewhere on the row.
        .contentShape(Rectangle())
        .onTapGesture {
            guard let route = route(for: job) else { return }
            dismiss()
            openChsRoute(route)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("download-row-\(job.id)")
    }
}
