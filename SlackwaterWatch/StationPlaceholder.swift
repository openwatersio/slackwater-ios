// Slackwater — GPL v3. A place's page on the watch until the Crown-scrubbed
// timeline lands (#522).
import SwiftUI

struct StationPlaceholder: View {
    let item: StationItem
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var resolved: Bool?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: item.name).font(.headline)
                Text(verbatim: item.placeLabel).font(.footnote).foregroundStyle(.secondary)
                Text(verbatim: item.kindLabel).font(.footnote).foregroundStyle(.secondary)
                if resolved == false {
                    Text("Predictions unavailable", comment: "Prediction download status.")
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { favorites.toggle(item.id) } label: {
                    Image(systemName: favorites.contains(item.id) ? "star.fill" : "star")
                }
                .accessibilityLabel(favorites.contains(item.id)
                    ? String(localized: "Unfavorite", comment: "Station discovery interface text.")
                    : String(localized: "Favorite", comment: "Station discovery interface text."))
            }
        }
        .onAppear { RecentsStore.shared.record(item.id) }
        .task(id: item.id) {
            let id = item.id
            resolved = await Task.detached(priority: .userInitiated) {
                WidgetStationLoader.loadRecord(id: id) != nil
            }.value
        }
    }
}
