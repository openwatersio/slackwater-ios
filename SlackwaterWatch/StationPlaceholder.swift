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
                    Text("Predictions unavailable.",
                         comment: "Watch place page when this device cannot predict the place.")
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
                    ? String(localized: "Unfavorite", comment: "Watch place page: remove from favorites.")
                    : String(localized: "Favorite", comment: "Watch place page: add to favorites."))
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
