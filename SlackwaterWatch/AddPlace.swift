// Slackwater — GPL v3. Find a place and save it, from the wrist (#521).
// The map picker (#541) will host this search in its toolbar.
import SwiftUI

struct AddPlace: View {
    let fix: WatchLocation.Fix?
    @Binding var path: [BrowseRoute]
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var query = ""
    @State private var results: [StationItem] = []

    /// The fix, else the last place opened, else the phone's first-run anchor.
    private var anchor: (lat: Double, lon: Double) {
        if let fix { return (fix.lat, fix.lon) }
        if let last = RecentsStore.shared.lastOpened { return (last.latitude, last.longitude) }
        return firstRunFix
    }

    var body: some View {
        List {
            TextField(String(localized: "Search for a place", comment: "Station discovery interface text."),
                      text: $query)
            ForEach(results) { item in
                HStack {
                    NavigationLink(value: BrowseRoute.station(item)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: item.name).font(.headline).lineLimit(2)
                            Text(verbatim: "\(item.kindLabel) · \(formatNm(item.km(fromLat: anchor.lat, lon: anchor.lon)))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button { openAndSave(item) } label: {
                        Image(systemName: favorites.contains(item.id) ? "star.fill" : "plus")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(favorites.contains(item.id)
                        ? String(localized: "Open", comment: "Watch search result already a favorite: open it.")
                        : String(localized: "Add favorite", comment: "VoiceOver action for a station."))
                }
            }
        }
        .navigationTitle(Text("Add Place", comment: "Watch list row that opens place search."))
        .task(id: query) {
            let q = query, a = anchor
            guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
            let found = await Task.detached(priority: .userInitiated) {
                StationItem.searchResolvable(q, near: a, fitted: ChsModelStore.fittedIDs())
            }.value
            // An earlier keystroke's scan can finish after this one's.
            guard !Task.isCancelled else { return }
            results = found
        }
    }

    /// Save, then open it, as Apple's own tides app does. Never unstar: a
    /// place already saved just opens.
    private func openAndSave(_ item: StationItem) {
        if !favorites.contains(item.id) { favorites.toggle(item.id) }
        path.append(.station(item))
    }
}
