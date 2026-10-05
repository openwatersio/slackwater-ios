// Slackwater — GPL v3. Download progress without exposing an unfitted place.
import SwiftUI

struct WatchDownloadStatus: View {
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var network = Connectivity.shared

    var body: some View {
        if let job = service.queue.jobs.first(where: { $0.status == .downloading })
            ?? service.queue.jobs.first(where: { $0.status == .pending })
            ?? service.queue.jobs.first(where: { $0.status == .failed }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloads").font(.headline)
                Text(verbatim: job.name).font(.footnote).lineLimit(2)
                CardStatusStrip(status: status(job))
                if job.status == .downloading {
                    StationDownloadProgress(value: job.downloadProgress)
                }
                Text("\(service.queue.ready) of \(service.queue.total)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                if job.status == .failed {
                    Button("Try again") { service.retryNow() }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("watch-download-status")
        }
    }

    private func status(_ job: ChsJob) -> CardStatus {
        switch job.status {
        case .ready: .queued
        case .failed: .failed
        case .downloading: .downloading
        case .pending:
            if !network.online { .offline }
            else if (job.retryAfter ?? .distantPast) > appNow() { .retrying }
            else { .queued }
        }
    }
}
