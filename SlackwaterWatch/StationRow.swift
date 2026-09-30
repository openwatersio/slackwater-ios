// Slackwater — GPL v3. One place in the watch list: its name, then the
// reading and next event once its station loads (#521).
import SwiftUI

/// The reading is the widgets' own (`WidgetSnapshot`), from one record
/// resolved off the main thread. Never a catalog (#317).
struct StationRow: View {
    let item: StationItem
    var km: Double? = nil
    let now: Date
    @State private var snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: item.name)
                .font(.headline)
                .lineLimit(2)
            if let s = snapshot {
                Text(verbatim: "\(s.value) · \(s.state)")
                    .font(.footnote.monospacedDigit())
                if let next = s.next {
                    HStack(spacing: 4) {
                        Image(systemName: next.symbol)
                        Text(verbatim: "\(next.label) \(cardTime(next.time, s.tz))")
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            } else {
                Text(verbatim: [item.kindLabel, km.map { formatNm($0) }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: "\(item.id)|\(now.timeIntervalSince1970)") {
            let id = item.id, now = now
            let next = await Task.detached(priority: .utility) {
                WidgetStationLoader.load(id: id).map { WidgetSnapshot.build($0, now: now) }
            }.value
            guard !Task.isCancelled else { return }
            snapshot = next
        }
    }
}
