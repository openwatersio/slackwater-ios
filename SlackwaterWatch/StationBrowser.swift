// Slackwater — GPL v3. The watch's one list (#521): the place nearest the
// wearer, favorites, places near, recents, then Add Place. The phone's
// groups, with a card's corner mark where a wrist has no room for headings.
import SwiftUI
import WidgetKit

enum BrowseRoute: Hashable {
    case station(StationItem, PlaceMark?)
    case addPlace
}

struct StationBrowser: View {
    @StateObject private var location = WatchLocation()
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var recents = RecentsStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var groups: BrowseGroups?
    /// When the wearer last raised the app: rows read at this instant. No
    /// live tick; a reading refreshes on the next look, as on the phone.
    @State private var shownAt = Date()
    @State private var path: [BrowseRoute] = []

    private struct Inputs: Hashable {
        let fix: WatchLocation.Fix?
        let favorites: [String]
        let recents: [String]
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if location.fix == nil { locationCard }
                if let groups { rows(groups) }
                NavigationLink(value: BrowseRoute.addPlace) {
                    Label(String(localized: "Add Place", comment: "Watch list row that opens place search."),
                          systemImage: "plus")
                }
                .accessibilityIdentifier("add-place-row")
                footer
            }
            .navigationDestination(for: BrowseRoute.self) { route in
                switch route {
                case .station(let item, let mark):
                    PlaceDetail(item: item, mark: mark) { path.removeAll() }
                case .addPlace: AddPlace(fix: location.fix, path: $path)
                }
            }
        }
        // A complication's tap (#524): its place, on top of the list. A
        // locked complication's link has no station and just opens the list.
        .onOpenURL { url in
            guard url.scheme == "slackwater", url.host() == "station",
                  let item = StationItem.widgetItem(id: stationID(from: url)) else { return }
            path = [.station(item, nil)]
        }
        .task(id: Inputs(fix: location.fix,favorites: favorites.ids, recents: recents.ids)) {
            let fix = location.fix.map { (lat: $0.lat, lon: $0.lon) }
            // The phone's anchor without a fix: the last place opened, else its first-run default.
            let fallback = recents.lastOpened.map { (lat: $0.latitude, lon: $0.longitude) } ?? firstRunFix
            let favoriteIds = favorites.ids, recentIds = recents.ids
            // Ranking the whole catalog is too slow for the watch's main thread.
            let next = await Task.detached(priority: .userInitiated) {
                // The watch's complications follow this fix (#524); the
                // extension never asks for location itself (#566).
                if let fix, cacheNearestWidgetStations(lat: fix.lat, lon: fix.lon) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                return BrowseGroups(fix: fix, fallback: fallback, favoriteIds: favoriteIds,
                             recentIds: recentIds, fitted: ChsModelStore.fittedIDs())
            }.value
            // A newer input's ranking may have landed first.
            guard !Task.isCancelled else { return }
            groups = next
        }
        .onAppear { location.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            shownAt = .now
            location.refresh()
        }
    }

    /// Stands where My Location would be, so the top of the list is never
    /// blank while there is no fix.
    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if location.unavailable {
                Label(String(localized: "Location unavailable", comment: "Location-denied card title."),
                      systemImage: "location.slash")
                    .font(.headline)
                Text("Turn on location in Settings to find nearby tides and currents.",
                     comment: "Location-denied explanation.")
                    .font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.7))
            } else {
                HStack(spacing: 8) {
                    ProgressView().fixedSize()
                    Text("Finding your location…", comment: "Station discovery interface text.")
                        .font(.footnote)
                }
            }
        }
        .foregroundStyle(SN.foam)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SN.canvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("location-card")
    }

    @ViewBuilder private func rows(_ g: BrowseGroups) -> some View {
        ForEach(g.hero) { row($0, mark: .location) }
        ForEach(g.favorites, id: \.self) { id in
            if let item = StationItem.byId[id] {
                row(item, mark: .favorite)
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
        // Without a fix these rank around the fallback, which is not near
        // the wearer, so they carry no location mark.
        ForEach(g.nearby) { item in
            row(item, mark: location.fix == nil ? nil : .nearby)
                .swipeActions(edge: .leading) { favoriteButton(item) }
        }
        ForEach(g.recents) { item in
            row(item, mark: .recent)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { recents.remove(item.id) } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) { favoriteButton(item) }
        }
    }

    /// The phone list's sign-off.
    private var footer: some View {
        VStack(spacing: 2) {
            Text("Slackwater").font(.footnote.weight(.semibold))
            Text("by Open Waters").font(.caption2)
        }
        .foregroundStyle(SN.foam.opacity(0.55))
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }

    private func row(_ item: StationItem, mark: PlaceMark?) -> some View {
        NavigationLink(value: BrowseRoute.station(item, mark)) {
            StationRow(item: item, mark: mark, now: shownAt)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .accessibilityIdentifier("place-row")
    }

    private func favoriteButton(_ item: StationItem) -> some View {
        Button { favorites.toggle(item.id) } label: {
            Label("Favorite", systemImage: "star.fill")
        }
        .tint(SN.sun)
    }
}
