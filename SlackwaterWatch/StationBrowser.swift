// Slackwater — GPL v3. The watch's one list (#521): My Location, Favorites,
// Near Me, Recents, then Add Place. The phone's groups, sized for a wrist.
import SwiftUI

enum BrowseRoute: Hashable {
    case station(StationItem)
    case addPlace
}

struct StationBrowser: View {
    @StateObject private var location = WatchLocation()
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var recents = RecentsStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var groups: BrowseGroups?
    @State private var path: [BrowseRoute] = []

    private struct Inputs: Hashable {
        let fix: WatchLocation.Fix?
        let favorites: [String]
        let recents: [String]
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let groups { sections(groups) }
                NavigationLink(value: BrowseRoute.addPlace) {
                    Label(String(localized: "Add Place", comment: "Watch list row that opens place search."),
                          systemImage: "plus")
                }
            }
            .navigationTitle(Text(verbatim: "Slackwater"))
            .navigationDestination(for: BrowseRoute.self) { route in
                switch route {
                case .station(let item): StationPlaceholder(item: item)
                case .addPlace: Text(verbatim: "")  // Task 6
                }
            }
        }
        .task(id: Inputs(fix: location.fix, favorites: favorites.ids, recents: recents.ids)) {
            let fix = location.fix.map { (lat: $0.lat, lon: $0.lon) }
            let favoriteIds = favorites.ids, recentIds = recents.ids
            // Ranking the whole catalog is too slow for the watch's main thread.
            groups = await Task.detached(priority: .userInitiated) {
                BrowseGroups(fix: fix, favoriteIds: favoriteIds, recentIds: recentIds,
                             fitted: ChsModelStore.fittedIDs())
            }.value
        }
        .onAppear { location.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { location.refresh() }
        }
    }

    @ViewBuilder private func sections(_ g: BrowseGroups) -> some View {
        if !g.hero.isEmpty {
            Section(String(localized: "My Location", comment: "Current-location section heading.")) {
                ForEach(g.hero) { row($0) }
            }
        }
        if !g.favorites.isEmpty {
            Section(String(localized: "Favorites", comment: "Favorite-stations section heading.")) {
                ForEach(g.favorites, id: \.self) { id in
                    if let item = StationItem.byId[id] {
                        row(item)
                            // Re-files to Recents, as on the phone: no destructive full swipe.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button { favorites.toggle(id) } label: {
                                    Label("Unfavorite", systemImage: "star.slash")
                                }
                                .tint(SN.steel)
                            }
                    } else {
                        Text("Place removed", comment: "Watch favorite whose place has left the app.")
                            .foregroundStyle(.secondary)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { favorites.forget(id) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        if !g.nearby.isEmpty {
            Section(String(localized: "Near Me", comment: "Nearby-stations section heading.")) {
                ForEach(g.nearby) { item in
                    row(item, km: location.fix.map { item.km(fromLat: $0.lat, lon: $0.lon) })
                        .swipeActions(edge: .leading) { favoriteButton(item) }
                }
            }
        }
        if !g.recents.isEmpty {
            Section(String(localized: "Recents", comment: "Recent-stations section heading.")) {
                ForEach(g.recents) { item in
                    row(item)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { recents.remove(item.id) } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) { favoriteButton(item) }
                }
            }
        }
    }

    private func row(_ item: StationItem, km: Double? = nil) -> some View {
        NavigationLink(value: BrowseRoute.station(item)) { StationRow(item: item, km: km) }
    }

    private func favoriteButton(_ item: StationItem) -> some View {
        Button { favorites.toggle(item.id) } label: {
            Label("Favorite", systemImage: "star.fill")
        }
        .tint(SN.sun)
    }
}
