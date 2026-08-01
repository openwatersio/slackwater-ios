// Slackwater — GPL v3. M4: first-run location gate (prototype NearMe.dc.html),
// located list (My Location tile + Near Me by distance), settings, pin map.
// M1's list + 1a gradient cards underneath, unchanged.
import SwiftUI
import TideEngine

@main
struct SlackwaterApp: App {
    init() {
        // UI-test hooks, like -chsResetModels: -resetGate forces the first-run
        // gate; -seedGate skips it (arguments-domain values would mask the
        // in-app write, so tests set persisted state explicitly instead).
        if CommandLine.arguments.contains("-resetGate") {
            UserDefaults.standard.removeObject(forKey: seenGateKey)
        }
        if CommandLine.arguments.contains("-seedGate") {
            UserDefaults.standard.set(true, forKey: seenGateKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Gate until a choice is made (prototype phase machine); list ever after.
struct RootView: View {
    @AppStorage(seenGateKey) private var seenGate = false

    var body: some View {
        if seenGate {
            StationListView()
        } else {
            GateView()
        }
    }
}

// MARK: - First-run gate (prototype NearMe.dc.html: gate + locating states)

struct GateView: View {
    @AppStorage(seenGateKey) private var seenGate = false
    @ObservedObject private var loc = LocationService.shared
    @State private var asked = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [SN.canvasGlow, SN.canvas], center: .top,
                           startRadius: 0, endRadius: 500)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    Text("Slackwater")
                        .font(.fraunces(36, .semibold))
                        .foregroundStyle(SN.paper)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)

                Spacer()

                if loc.locating {
                    ProgressView()
                        .controlSize(.large)
                        .tint(SN.leaf)
                    Text("Finding stations near you…")
                        .font(.geist(16))
                        .foregroundStyle(SN.foam.opacity(0.7))
                        .padding(.top, 22)
                } else {
                    // Pin glyph on the gradient tile, per the prototype.
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color(hex: 0x3A6D98), Color(hex: 0x184870), Color(hex: 0x083058)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 96, height: 96)
                            .shadow(color: Color(hex: 0x001432, opacity: 0.4), radius: 20, y: 16)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(SN.foam)
                    }
                    Text("See tides near you")
                        .font(.fraunces(27, .semibold))
                        .foregroundStyle(SN.paper)
                        .padding(.top, 26)
                    Text("Turn on location and we'll find the nearest tide & current stations — no searching required.")
                        .font(.geist(15))
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SN.foam.opacity(0.65))
                        .frame(maxWidth: 300)
                        .padding(.top, 10)
                    Button {
                        asked = true
                        loc.request()
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "location.fill")
                            Text("Use My Location")
                        }
                        .font(.geist(17, .semibold))
                        .foregroundStyle(SN.navyDeep)
                        .frame(maxWidth: 320)
                        .frame(height: 54)
                        .background(SN.leaf, in: Capsule())
                        .shadow(color: SN.leaf.opacity(0.3), radius: 13, y: 10)
                    }
                    .padding(.top, 30)
                    .padding(.horizontal, 22)
                    Button {
                        gateSearchHandoff = true
                        seenGate = true
                    } label: {
                        Text("Or search for a harbor, bay, or channel.")
                            .font(.geist(12))
                            .foregroundStyle(SN.foam.opacity(0.4))
                    }
                    .padding(.top, 16)
                }

                Spacer()
                Spacer()
            }
        }
        // The gate resolves when the ask resolves — a fix, or a denial. Either
        // way the choice is made and the list takes over (denied shows the
        // amber card there).
        .onChange(of: loc.locating) { _, locating in
            if asked && !locating { seenGate = true }
        }
    }
}

// MARK: - Station list

/// Set by the gate's "or search" bypass, consumed by the list's first appear —
/// the bypass lands straight in the search experience.
var gateSearchHandoff = false

struct StationListView: View {
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var showSettings = false
    @State private var showDownloads = false
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    // -openMap: launch straight into the map (manual offline verification hook).
    @State private var showMap = CommandLine.arguments.contains("-openMap")
    @AppStorage(unitsKey) private var units = "imperial"
    @ObservedObject private var loc = LocationService.shared
    @ObservedObject private var recents = RecentsStore.shared
    @ObservedObject private var favorites = FavoritesStore.shared
    // The rows' hidden nav links depend on fit state (navLink's .chs case),
    // so the list must re-render when a fit lands — the card itself observes,
    // but the link lives out here.
    @ObservedObject private var chs = ChsFitService.shared
    // Size class, not device, picks the layout (web styles.css breakpoints):
    // regular = the ≥62rem persistent-sidebar grid; compact = the phone stack.
    // iPad Slide Over / narrow Split View is compact and gets the phone layout.
    @Environment(\.horizontalSizeClass) private var hSize

    private var regular: Bool { hSize == .regular }
    private var imperial: Bool { units == "imperial" }
    /// The fix the list ranks by — only while authorized.
    private var fix: (lat: Double, lon: Double)? {
        guard loc.authorized, let l = loc.location else { return nil }
        return (l.coordinate.latitude, l.coordinate.longitude)
    }

    var body: some View {
        Group {
            if regular {
                splitLayout
            } else {
                stackLayout
            }
        }
        // Search is modal: hide the base surface from accessibility while the
        // overlay is up (VoiceOver correctness, and hit-tests resolve to the
        // overlay's cards, not identically-named cards underneath).
        .accessibilityHidden(searching)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showDownloads) { OfflineManagerView() }
        // Search covers everything — list, map, and (regular) the detail pane.
        .overlay { if searching { searchOverlay } }
        .onAppear {
            loc.refreshIfAuthorized()
            if gateSearchHandoff {
                gateSearchHandoff = false
                openSearch()
            }
        }
        // First connected launch: every Canadian station downloads in the
        // background, nearest-first (M48 — no region UX; "all of Canada" is
        // the default, and a future which-regions option is a filter on this
        // one queue). Partial failure retries from the manager or next launch.
        .task {
            if let fix { ChsFitService.shared.prioritize(lat: fix.lat, lon: fix.lon) }
            ChsFitService.shared.startIfNeeded()
        }
        // A fix landing (or moving) re-orders what is still queued.
        .onChange(of: loc.location) { _, new in
            guard let l = new else { return }
            ChsFitService.shared.prioritize(lat: l.coordinate.latitude, lon: l.coordinate.longitude)
        }
    }

    /// iPhone (and iPad Slide Over): the M1–M4 stack. The map swaps in-place
    /// for the list (prototype toggleView); both FABs persist over either.
    private var stackLayout: some View {
        NavigationStack(path: $path) {
            ZStack {
                if showMap { mapPane } else { listPane }
                fabBar
            }
            .navigationDestination(for: TideStationRecord.self) { TideDetailView(record: $0) }
            .navigationDestination(for: CurrentStationRecord.self) { CurrentDetailView(record: $0) }
            .navigationDestination(for: DerivedGateRecord.self) { DerivedGateDetailView(record: $0) }
            .navigationDestination(for: ChsRoute.self) { ChsDetailView(route: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Regular width — the web's tablet-and-up layout (styles.css ≥62rem):
    /// the list earns permanent space as a 320pt sidebar (20rem on web), and
    /// the detail is the content pane with its own stack so a row or map-pin
    /// tap replaces what's shown rather than covering the list.
    /// M4.5: the FABs live in the sidebar column (the list is always on
    /// screen, so the sidebar is where you act), and the toggle drives the
    /// detail pane's content — map ⇄ placeholder/detail. Opening the map
    /// clears the shown detail; a pin tap swaps back and opens it.
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            ZStack {
                listPane
                fabBar
            }
            .navigationSplitViewColumnWidth(320)
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if showMap { mapPane } else { detailPlaceholder }
                }
                .navigationDestination(for: TideStationRecord.self) { TideDetailView(record: $0) }
                .navigationDestination(for: CurrentStationRecord.self) { CurrentDetailView(record: $0) }
                .navigationDestination(for: DerivedGateRecord.self) { DerivedGateDetailView(record: $0) }
                .navigationDestination(for: ChsRoute.self) { ChsDetailView(route: $0) }
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// The content pane before any pick — same canvas, an invitation, not blank.
    private var detailPlaceholder: some View {
        ZStack {
            RadialGradient(colors: [SN.canvasGlow, SN.canvas], center: .top,
                           startRadius: 0, endRadius: 500)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "water.waves")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(SN.foam.opacity(0.5))
                Text("Pick a station")
                    .font(.fraunces(24, .semibold))
                    .foregroundStyle(SN.paper.opacity(0.9))
                Text("Tides and currents open here.")
                    .font(.geist(14))
                    .foregroundStyle(SN.foam.opacity(0.55))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The list surface both layouts share: canvas + grouped List. Search
    /// moved to the floating button (M4.5) — no top bar.
    private var listPane: some View {
            ZStack {
                RadialGradient(colors: [SN.canvasGlow, SN.canvas], center: .top,
                               startRadius: 0, endRadius: 500)
                    .ignoresSafeArea()
                // A List (not ScrollView) so the group rows carry native
                // .swipeActions (current-detail spec §9) — restyled to the
                // same canvas: clear rows, no separators, no insets.
                List {
                    Group {
                        header
                        locatedSections
                        Color.clear.frame(height: 96)  // scroll clear of the FABs
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
            }
            .toolbar(.hidden, for: .navigationBar)
    }

    /// The in-place map surface (prototype READY·MAP): no header, no close —
    /// the toggle FAB is the only way back.
    private var mapPane: some View {
        MapViewRepresentable { item in
            if regular { showMap = false }  // the detail pane shows the pick
            open(item)
        }
        .accessibilityIdentifier("map-canvas")
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            Text("Depths not reduced to chart datum — not for navigation.")
                .font(.geist(11))
                .foregroundStyle(SN.foam.opacity(0.85))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(SN.page.opacity(0.82), in: Capsule())
                .padding(.bottom, 96)   // clear of the FABs
        }
        .background(SN.page.ignoresSafeArea())
    }

    /// Show a station picked anywhere (row tap in regular, map pin tap in
    /// both). Resets the path first: in the split layout this replaces the
    /// shown detail; in the stack the path is empty here anyway.
    private func open(_ item: StationItem) {
        // Regular width: the sidebar (and its focused search field) stays on
        // screen when a detail opens, so the keyboard would sit over the new
        // detail — drop it. On iPhone the push dismisses it anyway.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        path = NavigationPath()
        switch item {
        case .tide(let s): path.append(s)
        case .current(let s): path.append(s)
        // Every CHS station routes the same way, fitted or not: ChsDetailView
        // shows the real detail when the model is there and the ⚠️ download
        // explanation when it isn't. A tap is never a dead tap (M48).
        case .chs(let info): path.append(ChsRoute.port(info))
        case .chsGate(let gate): path.append(ChsRoute.derivedGate(gate))
        case .chsCurrent(let gate): path.append(ChsRoute.currentGate(gate))
        }
    }

    // The list (Bryan's regrouping of the prototype READY·LIST): My Location →
    // Favorites → Near Me → Recents, nothing else — search is the discovery
    // path for the rest of the catalog. Without a fix the ranking anchors on
    // the Victoria fallback (prototype FALLBACK), and the My Location slot
    // holds the amber denied card when location is off. Dedupe: ListGroups —
    // each station renders once, My Location > Favorites > Near Me > Recents.
    @ViewBuilder private var locatedSections: some View {
        let anchor = fix ?? fallbackFix
        let ranked = StationItem.all.sorted {
            $0.km(fromLat: anchor.lat, lon: anchor.lon) < $1.km(fromLat: anchor.lat, lon: anchor.lon)
        }
        let heroItem = fix == nil ? nil : ranked.first
        let groups = ListGroups(heroId: heroItem?.id, favoriteIds: favorites.ids,
                                recentIds: recents.ids, rankedIds: ranked.map(\.id),
                                // With a hero the nearest is already on screen — 4 more; without, 5.
                                nearCount: fix == nil ? 5 : 4)

        // My Location slot: the hero tile, or the amber card in its place.
        if let fix, let nearest = heroItem {
            MyLocationTile(item: nearest, fix: fix, imperial: imperial) { itemCard($0) }
                .padding(.horizontal, 16)
                .padding(.top, 14)
        } else if loc.denied {
            unavailableCard.padding(.horizontal, 16).padding(.top, 14)
        }

        // Favorites: starred stations, insertion order (spec §9 swipe-to-manage).
        let favItems = items(groups.favorites)
        if !favItems.isEmpty {
            sectionLabel("Favorites")
            ForEach(favItems) { item in
                itemCard(item)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    // Spec §9: remove re-files to Recents — neutral tint, no
                    // destructive full-swipe.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { favorites.toggle(item.id) } label: {
                            Label("Unfavorite", systemImage: "star.slash")
                        }
                        .tint(SN.steel)
                    }
            }
        }

        sectionLabel("Near Me")
        ForEach(items(groups.nearMe)) { item in
            itemCard(item)
                .overlay(alignment: .topTrailing) {
                    DistancePill(km: item.km(fromLat: anchor.lat, lon: anchor.lon))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)   // room for the straddling nm pill
                .padding(.bottom, 4)
                .swipeActions(edge: .leading) {
                    Button { favorites.toggle(item.id) } label: {
                        Label("Favorite", systemImage: "star.fill")
                    }
                    .tint(SN.sun)
                }
        }

        // Recents at the very bottom (M4.5): recently viewed, most recent
        // first, minus everything already shown above.
        let recentItems = items(groups.recents)
        if !recentItems.isEmpty {
            sectionLabel("Recents")
            ForEach(recentItems) { item in
                recentRow(item, isFirst: item.id == recentItems.first?.id,
                          isLast: item.id == recentItems.last?.id)
                    .swipeActions(edge: .trailing) {
                        // Spec §9: true deletion — red destructive full-swipe.
                        Button(role: .destructive) { recents.remove(item.id) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { favorites.toggle(item.id) } label: {
                            Label("Favorite", systemImage: "star.fill")
                        }
                        .tint(SN.sun)
                    }
            }
        }
    }

    private func items(_ ids: [String]) -> [StationItem] {
        ids.compactMap { id in StationItem.all.first { $0.id == id } }
    }

    private func sectionLabel(_ text: String) -> some View {
        MonoLabel(text: text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    /// A compact recently-viewed row (prototype recent rows: gradient chip,
    /// name over region), navigating like the full cards. First/last rows
    /// round the group's outer corners — the grouped-card look, but one List
    /// row per station so each carries its own swipe actions.
    @ViewBuilder private func recentRow(_ item: StationItem, isFirst: Bool, isLast: Bool) -> some View {
        activatable(RecentRowLabel(item: item, imperial: imperial), item)
            .overlay(alignment: .bottom) {
                if !isLast { Divider().overlay(Color.white.opacity(0.08)) }
            }
            .background(Color.white.opacity(0.05))
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: isFirst ? 20 : 0, bottomLeadingRadius: isLast ? 20 : 0,
                bottomTrailingRadius: isLast ? 20 : 0, topTrailingRadius: isFirst ? 20 : 0,
                style: .continuous))
            .padding(.horizontal, 16)
    }

    /// Row activation, per layout: compact rides the List's hidden
    /// NavigationLink (unchanged phone behavior); regular taps drive the
    /// detail column's path directly — a sidebar link would push inside the
    /// sidebar, not the content pane.
    @ViewBuilder private func activatable<V: View>(_ view: V, _ item: StationItem) -> some View {
        if regular {
            view.contentShape(Rectangle()).onTapGesture { open(item) }
        } else {
            view.background(navLink(item))
        }
    }

    /// The row's tap target: a hidden NavigationLink behind the card, so List
    /// rows navigate without growing the disclosure chevron.
    @ViewBuilder private func navLink(_ item: StationItem) -> some View {
        switch item {
        case .tide(let station):
            NavigationLink(value: station) { EmptyView() }.opacity(0)
        case .current(let station):
            NavigationLink(value: station) { EmptyView() }.opacity(0)
        // Unconditional, unlike M3–M47: an unfitted station still navigates,
        // to the page that explains why it has no numbers yet (M48).
        case .chs(let info):
            NavigationLink(value: ChsRoute.port(info)) { EmptyView() }.opacity(0)
        case .chsGate(let gate):
            NavigationLink(value: ChsRoute.derivedGate(gate)) { EmptyView() }.opacity(0)
        case .chsCurrent(let gate):
            NavigationLink(value: ChsRoute.currentGate(gate)) { EmptyView() }.opacity(0)
        }
    }

    @ViewBuilder private func itemCard(_ item: StationItem) -> some View {
        switch item {
        case .tide(let station):
            activatable(StationCardView(record: station, imperial: imperial), item)
        case .current(let station):
            activatable(CurrentCardView(record: station), item)
        case .chs(let info):
            activatable(ChsCardView(info: info, imperial: imperial), item)
        case .chsGate(let gate):
            activatable(ChsGateCardView(gate: gate), item)
        case .chsCurrent(let gate):
            activatable(ChsCurrentGateCardView(gate: gate), item)
        }
    }

    /// Location denied — amber card, deep link to the app's iOS Settings.
    private var unavailableCard: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 13) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 21))
                        .foregroundStyle(Color(hex: 0xE0B45A))
                        .frame(width: 46, height: 46)
                        .background(Color(hex: 0xE0B45A, opacity: 0.16),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location unavailable")
                            .font(.fraunces(20, .semibold))
                            .foregroundStyle(SN.paper)
                        Text("Turn on location for Slackwater to see stations near you.")
                            .font(.geist(13))
                            .foregroundStyle(SN.foam.opacity(0.62))
                    }
                }
                HStack(spacing: 4) {
                    Spacer()
                    Text("Go to Settings")
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }
                .font(.geist(15, .semibold))
                .foregroundStyle(Color(hex: 0xE0B45A))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xE0B45A, opacity: 0.1),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(hex: 0xE0B45A, opacity: 0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text("Slackwater")
                .font(.fraunces(36, .semibold))
                .foregroundStyle(SN.paper)
                // The wordmark never wraps: in the 320pt iPad sidebar it shares
                // the row with two 34pt buttons and would break as "Slackwat/er".
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
            Spacer(minLength: 8)
            // Offline / online / downloading, beside the gear — and the way in
            // to the downloads manager (M48, web OfflineStatus).
            OfflineStatusButton { showDownloads = true }
            // Units live in Settings only — no list-header pill.
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SN.foam.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)  // List rows: keep the tap on the gear itself
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    // MARK: - Floating toolbar (prototype showToggle: search bottom-left,
    // list ⇄ map toggle bottom-right, both persistent over list AND map)

    private var fabBar: some View {
        HStack {
            fab("magnifyingglass", label: "Search") { openSearch() }
            Spacer()
            fab(showMap ? "list.bullet" : "map", label: showMap ? "List" : "Map") {
                showMap.toggle()
                // Regular width: opening the map replaces the shown detail;
                // toggling back lands on the placeholder (prototype toggleView
                // is a full surface swap, not a stack push).
                if regular && showMap { path = NavigationPath() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// The prototype toolbar button: 56pt glass circle.
    private func fab(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(SN.foam)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: Circle())
                .background(Color(hex: 0x184870, opacity: 0.55), in: Circle())
                .overlay(Circle().strokeBorder(SN.leaf.opacity(0.3), lineWidth: 0.5))
                .shadow(color: Color(hex: 0x000C1E, opacity: 0.4), radius: 10, y: 6)
        }
        .accessibilityLabel(label)
    }

    // MARK: - Search (M4.5: bottom input above the keyboard, results above —
    // the Weather-app pattern from Bryan's reference; prototype openSearch)

    private func openSearch() {
        query = ""       // prototype openSearch resets the query
        searching = true
    }

    private var searchOverlay: some View {
        ZStack {
            RadialGradient(colors: [SN.canvasGlow, SN.canvas], center: .top,
                           startRadius: 0, endRadius: 500)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(StationItem.search(query)) { item in
                            resultCard(item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                searchBar
            }
        }
        .onAppear { searchFocused = true }  // keyboard up immediately
    }

    /// A search result: the ordinary card, tapping opens the detail and
    /// closes search (the overlay sits outside the nav stacks, so results
    /// drive `open` directly rather than riding hidden links).
    @ViewBuilder private func resultCard(_ item: StationItem) -> some View {
        Group {
            switch item {
            case .tide(let s): StationCardView(record: s, imperial: imperial)
            case .current(let s): CurrentCardView(record: s)
            case .chs(let info): ChsCardView(info: info, imperial: imperial)
            case .chsGate(let gate): ChsGateCardView(gate: gate)
            case .chsCurrent(let gate): ChsCurrentGateCardView(gate: gate)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            searching = false
            open(item)
        }
    }

    /// The bottom bar: input pill + the X glass circle beside it (Bryan's
    /// Weather-app reference — one tap exits search and drops the keyboard).
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SN.foam.opacity(0.7))
                TextField("Harbor, bay, or channel", text: $query)
                    .font(.geist(17))
                    .foregroundStyle(SN.paper)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SN.foam.opacity(0.5))
                    }
                    .accessibilityLabel("Clear search text")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(SN.leaf.opacity(0.25), lineWidth: 0.5))

            Button {
                searching = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SN.foam)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
                    .background(Color(hex: 0x184870, opacity: 0.55), in: Circle())
                    .overlay(Circle().strokeBorder(SN.leaf.opacity(0.3), lineWidth: 0.5))
            }
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// The prototype's My Location hero: MY LOCATION eyebrow with the location
/// arrow, the nearest station's ordinary card wearing the same nm pill the
/// Near Me cards wear, then the fix coordinates in mono (NearMe.dc.html
/// fmtCoord — 3 decimal places).
struct MyLocationTile<Card: View>: View {
    let item: StationItem
    let fix: (lat: Double, lon: Double)
    let imperial: Bool
    @ViewBuilder let card: (StationItem) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 10))
                    .rotationEffect(.degrees(45))
                MonoLabel(text: "My Location", size: 11, color: SN.foam.opacity(0.9))
            }
            .foregroundStyle(SN.foam.opacity(0.9))
            .padding(.horizontal, 6)
            card(item)
                .overlay(alignment: .topTrailing) {
                    DistancePill(km: item.km(fromLat: fix.lat, lon: fix.lon))
                }
            Text(formatCoord(lat: fix.lat, lon: fix.lon))
                .font(.geistMono(11))
                .foregroundStyle(SN.foam.opacity(0.55))
                .padding(.horizontal, 6)
        }
        .padding(8)
        .background(Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(SN.leaf.opacity(0.22), lineWidth: 0.5))
    }
}

/// The compact recent-station row body (prototype: 38pt gradient chip, name
/// over region, current reading trailing in Fraunces).
struct RecentRowLabel: View {
    let item: StationItem
    let imperial: Bool
    @AppStorage(speedUnitKey) private var speedUnit = "kn"
    // Cache the engine value, format in body — unit switches re-render live.
    @State private var height: Double?
    @State private var signed: Double?
    @State private var gatePhase: DerivedPhase?  // derived gate: phase word, never a speed

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(stationGradient(id: rawId))
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.geist(16, .medium))
                    .foregroundStyle(SN.paper)
                    .lineLimit(1)
                Text(item.region)
                    .font(.geist(12))
                    .foregroundStyle(SN.foam.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(reading)
                .font(.fraunces(17))
                .foregroundStyle(SN.foam.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .task { if height == nil && signed == nil { load() } }
    }

    private var rawId: String {
        if case .current(let s) = item { return s.id }
        return item.id
    }

    private var reading: String {
        if let gatePhase { return phaseWord(gatePhase).lowercased() }
        if let signed {
            return currentPhase(signed: signed) == .slack
                ? "slack" : "\(formatSpeed(abs(signed), unit: speedUnit)) \(speedUnitLabel(speedUnit))"
        }
        guard let height else { return "" }
        return "\(formatHeight(height, imperial: imperial)) \(heightUnit(imperial: imperial))"
    }

    private func load() {
        switch item {
        case .tide(let s):
            height = s.cardState(at: appNow()).height
        case .current(let s):
            signed = s.cardState(at: appNow()).signed
        case .chs(let info):
            guard case .fitted(let record) = ChsFitService.shared.state(info.id) else { return }
            height = record.cardState(at: appNow()).height
        case .chsGate(let gate):
            guard case .fitted(let port) = ChsFitService.shared.state(gate.reference) else { return }
            gatePhase = DerivedGateRecord(gate: gate, port: port).cardState(at: appNow()).phase
        case .chsCurrent(let gate):
            guard case .fitted(let record) = ChsFitService.shared.currentState(gate.id) else { return }
            signed = record.cardState(at: appNow()).signed
        }
    }
}

/// Variant 1a card: per-station sky gradient, Fraunces name, big height numeral.
struct StationCardView: View {
    let record: TideStationRecord
    let imperial: Bool
    @State private var state: CardState?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(.fraunces(23, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(record.region)
                        .font(.geist(13))
                        .foregroundStyle(SN.foam.opacity(0.78))
                    if let next = state?.next {
                        Text("\(next.kind == .high ? "High" : "Low") \(formatHeight(next.height, imperial: imperial)) \(heightUnit(imperial: imperial)) · \(cardTime(next.time, record.tz))")
                            .font(.geist(12))
                            .foregroundStyle(SN.foam.opacity(0.92))
                            .padding(.top, 10)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    if let state {
                        (Text(formatHeight(state.height, imperial: imperial))
                            .font(.fraunces(42))
                         + Text(" \(heightUnit(imperial: imperial))")
                            .font(.fraunces(17)))
                            .foregroundStyle(.white)
                        HStack(spacing: 4) {
                            Text(state.rising ? "▲" : "▼").font(.geist(9))
                            Text(state.rising ? "Rising" : "Falling").font(.geist(11))
                        }
                        .foregroundStyle(SN.foam.opacity(0.9))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(stationGradient(id: record.id))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: 0x001432, opacity: 0.24), radius: 12, y: 10)
        .task { if state == nil { state = record.cardState(at: appNow()) } }
    }
}

/// A Canadian (CHS) tide port. Fitted: the ordinary tide card, navigable.
/// Not yet fitted: the same gradient shell with identity and an honest message
/// (chs-online spec §7c — never an empty chart, never a spinner to nothing).
struct ChsCardView: View {
    let info: ChsStationInfo
    let imperial: Bool
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared

    var body: some View {
        // Navigation comes from the enclosing row's hidden link (itemCard).
        switch service.state(info.id) {
        case .fitted(let record):
            StationCardView(record: record, imperial: imperial)
        case .fitting:
            ChsPendingCard(name: info.name, region: info.region, id: info.id,
                           message: "Downloading Canadian tidal predictions…")
        case .pending:
            ChsPendingCard(name: info.name, region: info.region, id: info.id,
                           message: chsPendingMessage("tidal"))
        case .failed:
            ChsPendingCard(name: info.name, region: info.region, id: info.id,
                           message: "Canadian tidal predictions didn't finish downloading — open it to retry.")
        }
    }
}

/// A queued station's line. Both halves of "pending" are honest, and they are
/// different situations: connected, it is simply in line behind the nearer
/// stations; with no signal, nothing is moving at all. The established
/// moment-of-signal copy is kept verbatim for the second.
@MainActor func chsPendingMessage(_ series: String) -> String {
    Connectivity.shared.online
        ? "Queued — Canadian \(series) predictions download once, then work offline."
        : "Needs a moment of signal — Canadian \(series) predictions download once, then work offline."
}

/// The not-yet-fitted CHS shell: identity + an honest message, no numbers
/// (chs-online spec §7c). Shared by the tide ports and the derived gates —
/// a gate is pending exactly while its reference port is.
struct ChsPendingCard: View {
    let name: String
    let region: String
    let id: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.fraunces(23, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(region)
                        .font(.geist(13))
                        .foregroundStyle(SN.foam.opacity(0.78))
                }
                Spacer(minLength: 8)
            }
            Text(message)
                .font(.geist(12))
                .foregroundStyle(SN.foam.opacity(0.85))
                .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(stationGradient(id: id))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: 0x001432, opacity: 0.24), radius: 12, y: 10)
        .opacity(0.82)  // visibly quieter than a station with numbers
    }
}

/// A derived current gate's card (web StationCard's derived layout): identity,
/// "Slack · time" as the next line, and a compact phase pill — a derived gate
/// has no speed, so the reading is never a number (chs/current.ts). Pending
/// while the reference port is unfitted, in the same register as the ports.
struct ChsGateCardView: View {
    let gate: ChsGateInfo
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared
    @State private var state: DerivedGateCardState?

    var body: some View {
        switch service.state(gate.reference) {
        case .fitted(let port):
            fittedCard(DerivedGateRecord(gate: gate, port: port))
        case .fitting:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id,
                           message: "Downloading Canadian tidal predictions…")
        case .pending:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id,
                           message: chsPendingMessage("tidal"))
        case .failed:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id,
                           message: "Canadian tidal predictions didn't finish downloading — open it to retry.")
        }
    }

    private func fittedCard(_ record: DerivedGateRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gate.name)
                        .font(.fraunces(23, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(gate.region)
                        .font(.geist(13))
                        .foregroundStyle(SN.foam.opacity(0.78))
                    if let next = state?.nextSlack {
                        Text("Slack · \(cardTime(next.time, gate.tz))")
                            .font(.geist(12))
                            .foregroundStyle(SN.foam.opacity(0.92))
                            .padding(.top, 10)
                    }
                }
                Spacer(minLength: 8)
                if let state {
                    // The web's phase-pill words: flood / ebb / slack.
                    Text(state.phase == .flood ? "FLOOD" : state.phase == .ebb ? "EBB" : "SLACK")
                        .font(.geistMono(11, .medium)).tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.18), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(stationGradient(id: gate.id))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: 0x001432, opacity: 0.24), radius: 12, y: 10)
        .task { if state == nil { state = record.cardState(at: appNow()) } }
    }
}

/// A validated CHS current gate. Fitted: the ordinary current card — real
/// velocities, navigable. Not yet fitted: the pending shell in the established
/// register, naming currents (chs-online spec §7c — never an empty chart).
struct ChsCurrentGateCardView: View {
    let gate: ChsCurrentGateInfo
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared

    var body: some View {
        // Navigation comes from the enclosing row's hidden link (itemCard).
        switch service.currentState(gate.id) {
        case .fitted(let record):
            CurrentCardView(record: record)
        case .fitting:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id,
                           message: "Downloading Canadian current predictions…")
        case .pending:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id,
                           message: chsPendingMessage("current"))
        case .failed:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id,
                           message: "Canadian current predictions didn't finish downloading — open it to retry.")
        }
    }
}

/// The current-station card: same 1a gradient shell, but the reading is signed
/// velocity — speed + set arrow + Flooding/Ebbing, a Slack pill at slack, and
/// the next slack/max as the detail line (web StationCard's current layout).
struct CurrentCardView: View {
    let record: CurrentStationRecord
    @AppStorage(speedUnitKey) private var speedUnit = "kn"
    @State private var state: CurrentCardState?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(.fraunces(23, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(record.region)
                        .font(.geist(13))
                        .foregroundStyle(SN.foam.opacity(0.78))
                    if let next = state?.next {
                        Text(nextLine(next))
                            .font(.geist(12))
                            .foregroundStyle(SN.foam.opacity(0.92))
                            .padding(.top, 10)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    if let state {
                        let phase = currentPhase(signed: state.signed)
                        if phase == .slack {
                            Text("SLACK")
                                .font(.geistMono(11, .medium)).tracking(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.white.opacity(0.18), in: Capsule())
                        } else {
                            (Text(formatSpeed(abs(state.signed), unit: speedUnit))
                                .font(.fraunces(42))
                             + Text(" \(speedUnitLabel(speedUnit))")
                                .font(.fraunces(17)))
                                .foregroundStyle(.white)
                            HStack(spacing: 4) {
                                CompassArrow(deg: record.setDegrees(signed: state.signed)).font(.geist(11))
                                Text(phaseWord(phase)).font(.geist(11))
                            }
                            .foregroundStyle(SN.foam.opacity(0.9))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(stationGradient(id: record.id))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: 0x001432, opacity: 0.24), radius: 12, y: 10)
        .task { if state == nil { state = record.cardState(at: appNow()) } }
    }

    private func nextLine(_ next: CurrentEvent) -> String {
        let when = cardTime(next.time, record.tz)
        return next.kind == .slack
            ? "Slack · \(when)"
            : "\(next.turnLabel) \(formatSpeed(abs(next.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit)) · \(when)"
    }
}
