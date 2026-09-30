// Slackwater — GPL v3. One place in the watch list: the small widget's card,
// with a corner mark in place of a group heading (#521).
import SwiftUI

/// The card is the small widget's own (`NextEventContentView`), from one
/// record resolved off the main thread. Never a catalog (#317).
struct StationRow: View {
    let item: StationItem
    let mark: PlaceMark?
    /// When the wearer last raised the app: the card reads at this instant.
    let now: Date
    // Read by `WidgetCard.build`; iCloud can deliver the phone's units after
    // a card has loaded, and a card must not keep the fallback ones.
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = ""
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = ""
    @State private var card: WidgetCard?

    var body: some View {
        Group {
            if let card {
                NextEventContentView(card: card, mark: mark)
            } else {
                // While the record loads, and for good when this device
                // cannot predict the place.
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.name).font(.caption2).foregroundStyle(SN.foam).lineLimit(1)
                    Text(verbatim: item.kindLabel).font(.footnote).foregroundStyle(SN.foam.opacity(0.6))
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(SN.cardFill)
            }
        }
        .frame(height: 150)
        .background(SN.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: "\(item.id)|\(now.timeIntervalSince1970)|\(units)|\(speedUnit)") {
            let id = item.id, now = now
            let next = await Task.detached(priority: .utility) {
                WidgetStationLoader.loadRecord(id: id, at: now).map { WidgetCard.build($0, now: now) }
            }.value
            guard !Task.isCancelled else { return }
            card = next
        }
    }
}
