// Slackwater — GPL v3. The located station list (My Location tile + Near Me by
// distance), its search overlay, map pane, and floating toolbar.
import CoreLocation
import SwiftUI

// MARK: - Station list

struct StationListView: View {
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var showSettings = false
    @State private var showDownloads = false
    @State private var showWidgetsGallery = false
    @State private var searching = false
    /// Tides/Currents narrowing, nil = everything. One persisted value for
    /// Near Me, search and every detail's Nearby, so a pick carries between
    /// them; `SeriesFilterChips` writes it.
    @AppStorage(seriesFilterKey) private var seriesFilter: StationSeries?
    @FocusState private var searchFocused: Bool
    // -openMap: launch straight into the map (manual offline verification hook).
    @State private var showMap = CommandLine.arguments.contains("-openMap")
    /// One-shot: set by the detail-header title tap (issue #32) or the Nearby
    /// map, read by `mapPane` as a camera override, then cleared by
    /// `.onAppear`. The next fix landing or user pan owns the camera after that.
    @State private var mapFocus: (item: StationItem, zoom: Double)?
    /// Bumped on every focus tap and used as `mapPane`'s `.id`, so a focus
    /// always REMOUNTS the map — even on the pin-tap path where `showMap` is
    /// already true and the map instance would otherwise survive the
    /// push/pop. Distinct from the coordinate so re-focusing the SAME
    /// station twice still counts.
    @State private var mapFocusToken = 0
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @AppStorage(AppGroup.slackWindowSpeedKey, store: AppGroup.defaults)
    private var slackWindowSpeed = defaultSlackThresholdKn
    @ObservedObject private var loc = LocationService.shared
    @ObservedObject private var recents = RecentsStore.shared
    @ObservedObject private var favorites = FavoritesStore.shared
    // Size class, not device, picks the layout (web styles.css breakpoints):
    // regular = the ≥62rem persistent-sidebar grid; compact = the phone stack.
    // iPad Slide Over / narrow Split View is compact and gets the phone layout.
    @Environment(\.horizontalSizeClass) private var hSize

    /// The place whose matching stations the chooser is offering, if open.
    @State private var chooser: StationMatches?
    /// Regular width opens the first row once, on the first appearance only.
    @State private var didAutoSelect = false
    /// The real, fixed FAB footprint — named so the clearance below is tied
    /// to the actual geometry (`fab()`'s circle + `fabBar`'s bottom padding)
    /// rather than a second, independently-editable literal.
    private static let fabSize: CGFloat = 56
    private static let fabBarBottomPadding: CGFloat = 24
    private static let fabFootprint: CGFloat = fabSize + fabBarBottomPadding
    /// Footprint plus the 16pt of breathing room the design intends — the
    /// bare footprint is flush contact (last card touching the FABs), which
    /// is not the floor we want. Both the base and the clamp use this.
    private static let fabClearanceBase: CGFloat = fabFootprint + 16
    /// Extra breathing room at large text sizes. NOT a correctness
    /// requirement: `fab()` is `.font(.system(size: 21))` inside a fixed 56pt
    /// frame plus `fabBar`'s 24pt bottom padding, so the footprint this has to
    /// clear is CONSTANT at every content-size category. A flat
    /// `fabClearanceBase` would already clear the FABs everywhere — the last
    /// card is not going to end up under them.
    ///
    /// What `@ScaledMetric` buys is proportion: at large sizes the gap grows
    /// with the rows around it instead of reading as a hairline (+210pt at
    /// AX5, measured). What it costs is that
    /// `@ScaledMetric` scales in BOTH directions, so below the default
    /// category it would shrink the gap below the intended margin — which is
    /// the only thing the `max(...)` clamp at the call site undoes. Kept
    /// because it is harmless and the measured behaviour is good; if it ever
    /// needs to go, the honest replacement is the flat base, not a rewrite.
    @ScaledMetric(relativeTo: .body) private var fabClearance: CGFloat = Self.fabClearanceBase

    private var regular: Bool { hSize == .regular }
    private var imperial: Bool { units == "imperial" }
    /// The fix the list ranks by — only while authorized.
    private var fix: (lat: Double, lon: Double)? {
        guard loc.authorized, let l = loc.location else { return nil }
        return (l.coordinate.latitude, l.coordinate.longitude)
    }
    /// What distances are measured from: the fix, then the last-opened
    /// station, then the Victoria fallback on a genuine first run.
    private var anchor: (lat: Double, lon: Double) { loc.rankingAnchor }

    /// One definition, two attachment points (the root `.environment` below,
    /// and the re-forward into `.sheet(showDownloads)`) — kept as a single
    /// property so they can't drift apart.
    private var openChsRoute: (ChsRoute) -> Void { { path.append($0) } }

    /// The map-header title tap (issue #32): pop whatever detail is pushed,
    /// switch to the map, and hand it a one-shot focus on this station.
    /// Unconditional path reset (unlike the FAB toggle's `regular && showMap`
    /// case below) — this always fires FROM a pushed detail in both layouts,
    /// where the fabBar-toggle path only needs it at regular width.
    private var openMapFocused: (StationItem, Double) -> Void {
        { item, zoom in
            mapFocus = (item, zoom)
            mapFocusToken += 1
            path = NavigationPath()
            showMap = true
        }
    }

    var body: some View {
        Group {
            if regular {
                splitLayout
            } else {
                stackLayout
            }
        }
        // A pushed destination doesn't reliably
        // inherit environment attached to the NavigationStack itself when that
        // stack is NavigationSplitView's `detail:` column — attaching there
        // left `TideAtPortLink`'s `openTide` reading the default no-op on
        // iPad, tap included, in a live-logged repro. Attached here instead,
        // above BOTH layouts, delivery rides ordinary ancestor inheritance —
        // and there's exactly one attachment, so the two layouts can't drift.
        .environment(\.openTideDetail) { path.append($0) }
        // The nearby-station link's push — appends (a step deeper), never the
        // path reset `open` does: the station being left stays on the back
        // stack, exactly as TideAtPortLink behaves.
        .environment(\.openStationItem) { item in
            switch item {
            case .tide(let s): path.append(NoaaRoute.tide(s))
            case .current(let s): path.append(NoaaRoute.current(s))
            case .chs(let info): path.append(ChsRoute.port(info))
            case .chsGate(let gate): path.append(ChsRoute.derivedGate(gate))
            case .chsCurrent(let gate): path.append(ChsRoute.currentGate(gate))
            }
        }
        // Same reasoning, same attachment point — every CHS push (an online
        // gate's honesty card, a Downloads-sheet row) rides this one closure,
        // never a NavigationLink (OpenChsRouteKey doc comment, Theme.swift).
        // Dismiss-then-append (OfflineManagerView's row tap) still lands here:
        // this appends to the ROOT stack's path regardless of which presented
        // sheet or pushed screen the tap came from, so a detail that opened
        // the sheet stays under the newly pushed route on the back stack —
        // correct behavior, not a side effect to work around.
        .environment(\.openChsRoute, openChsRoute)
        // Same attachment point, same reasoning — the detail header lives
        // inside a pushed detail in both layouts, so ordinary ancestor
        // inheritance from here is enough; no `.sheet` re-forward needed
        // because a station detail never appears inside Settings or Downloads.
        .environment(\.openMapFocused, openMapFocused)
        // Search is modal: hide the base surface from accessibility while the
        // overlay is up (VoiceOver correctness, and hit-tests resolve to the
        // overlay's cards, not identically-named cards underneath).
        .accessibilityHidden(searching)
        // Re-forwarded here too: Settings pushes `OfflineManagerList` in its
        // OWN `NavigationStack` (SettingsView.swift), and that push inherits
        // fine — but SettingsView itself is this `.sheet`'s ROOT content, so
        // without this it's SettingsView's environment that's broken, not
        // OfflineManagerList's. Same boundary as the comment below.
        .sheet(isPresented: $showSettings) { SettingsView().environment(\.openChsRoute, openChsRoute) }
        // Re-forwarded explicitly, not just inherited: `.sheet` content sits in
        // a separate presentation hierarchy that only crosses SYSTEM
        // environment keys (like `\.dismiss`) automatically — a custom key set
        // above the `.sheet(...)` call resolves to `openChsRoute`'s no-op
        // `defaultValue` inside it otherwise (confirmed live: the row's
        // `dismiss()` fired, the following `openChsRoute(route)` silently did
        // nothing). Every `.sheet` that can present `OfflineManagerView` needs
        // this same re-forward — see `ChsWaitingView` and `CurrentDetailView`.
        .sheet(isPresented: $showDownloads) { OfflineManagerView().environment(\.openChsRoute, openChsRoute) }
        // No environment re-forward needed here (unlike showSettings/showDownloads
        // above): the gallery's only nested presentation is PremiumView, which
        // reads no custom environment key. If it ever grows a station link, mind
        // the reforwarding gotcha those two sheets document.
        .sheet(isPresented: $showWidgetsGallery) { WidgetsGalleryView() }
        .onOpenURL(perform: handleDeepLink)
        .sheet(item: $chooser) { place in
            StationChooserSheet(place: place,
                                anchor: place.replacing.map { (lat: $0.lat, lon: $0.lon) } ?? anchor) { item in
                if let dead = place.replacing?.id { favorites.replace(dead, with: item.id) }
                open(item)
            }
        }
        // Search covers everything — list, map, and (regular) the detail pane.
        .overlay { if searching { searchOverlay } }
        .onAppear {
            loc.refreshIfAuthorized()
            if gateSearchHandoff {
                gateSearchHandoff = false
                openSearch()
            }
            if let url = pendingDeepLink {
                pendingDeepLink = nil
                handleDeepLink(url)
            }
        }
        // First connected launch: the auto-fit set around where this list is
        // ranked downloads in the background, nearest-first, and the nearby
        // online gates prefetch (`ChsFitService.autoFitSet` /
        // `autoPrefetchGates`). Partial failure retries from the manager or
        // the next launch.
        //
        // `anchor`, not `fix` (#178): the list ranks from `rankingAnchor` —
        // fix, then last-opened, then Victoria — and adopting only on a live
        // fix would give a user who denied location, or whose fix has not
        // landed yet, a Near Me list ranked around one place and a download
        // set built around another: every row on the first screen reading
        // "Tap to download". `adopt` is accretive and `prioritize`
        // re-sorts, so a real fix landing later still wins on `.onChange`.
        .task {
            ChsFitService.shared.prioritize(lat: anchor.lat, lon: anchor.lon,
                                             favorites: favorites.ids,
                                             visibleID: firstListItem?.id)
            ChsFitService.shared.startIfNeeded()
        }
        // iCloud can deliver favorites after the first task has run.
        .onChange(of: favorites.ids) { _, ids in
            ChsFitService.shared.prioritizeFavorites(ids, after: firstListItem?.id)
        }
        // A fix landing (or moving) re-orders what is still queued.
        .onChange(of: loc.location) { _, new in
            guard let l = new else { return }
            ChsFitService.shared.prioritize(lat: l.coordinate.latitude, lon: l.coordinate.longitude)
        }
    }

    /// A NOAA station's detail, resolved from the identity on the path. The
    /// record decodes here rather than in the row that pushed it (#317); a
    /// bundled id always has one, so the empty branch is unreachable.
    @ViewBuilder private func noaaDetail(_ route: NoaaRoute) -> some View {
        switch route {
        case .tide(let info):
            if let record = info.tideRecord { TideDetailView(record: record).id(record.id) }
        case .current(let info):
            if let record = info.currentRecord { CurrentDetailView(record: record).id(record.id) }
        }
    }

    /// iPhone (and iPad Slide Over): the map swaps in-place for the list;
    /// both FABs persist over either.
    private var stackLayout: some View {
        NavigationStack(path: $path) {
            ZStack {
                if showMap { mapPane } else { listPane }
                fabBar
            }
            .navigationDestination(for: TideStationRecord.self) { TideDetailView(record: $0).id($0.id) }
            .navigationDestination(for: CurrentStationRecord.self) { CurrentDetailView(record: $0).id($0.id) }
            .navigationDestination(for: NoaaRoute.self) { noaaDetail($0) }
            .navigationDestination(for: DerivedGateRecord.self) { DerivedGateDetailView(record: $0).id($0.gate.id) }
            .navigationDestination(for: ChsRoute.self) { ChsDetailView(route: $0).id($0.stationID) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Regular width — the web's tablet-and-up layout (styles.css ≥62rem):
    /// the list earns permanent space as a 320pt sidebar (20rem on web), and
    /// the detail is the content pane with its own stack so a row or map-pin
    /// tap replaces what's shown rather than covering the list.
    /// The FABs live in the sidebar column (the list is always on
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
                // .id(station) — a second station of the SAME kind lands at the
                // same depth with the same destination type, which is the same
                // SwiftUI identity: @State survives, so the detail kept the
                // previous station's built `timeline` (guarded `if timeline ==
                // nil`) and its map camera (set once in `makeUIView`, and
                // `updateUIView` is a no-op). The header title updated, the
                // chart and map did not — build 13 on iPad, most visible in
                // the split layout where a sidebar tap swaps the pane without
                // a pop. A different station is a different view; say so.
                .navigationDestination(for: TideStationRecord.self) { TideDetailView(record: $0).id($0.id) }
                .navigationDestination(for: CurrentStationRecord.self) { CurrentDetailView(record: $0).id($0.id) }
                .navigationDestination(for: NoaaRoute.self) { noaaDetail($0) }
                .navigationDestination(for: DerivedGateRecord.self) { DerivedGateDetailView(record: $0).id($0.gate.id) }
                .navigationDestination(for: ChsRoute.self) { ChsDetailView(route: $0).id($0.stationID) }
                .toolbar(.hidden, for: .navigationBar)
            }
            // A regular-width launch opens on the first row rather than the
            // "Pick a station" placeholder: the My Location station when
            // there is a fix, else the first row the list renders. Once only,
            // and only into an empty pane — coming back from a detail leaves
            // the placeholder alone, and an existing pick is never overridden.
            .onAppear {
                guard !didAutoSelect else { return }
                didAutoSelect = true
                guard path.isEmpty, !showMap, let first = firstListItem else { return }
                RecentsStore.shared.skipNextRecordID = first.id
                open(first)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// The first row the list actually renders: the My Location hero when a fix
    /// has landed, else the leading Favorite (Favorites is the top group without
    /// a hero), else the nearest station — Near Me's first card.
    private var firstListItem: StationItem? {
        let a = anchor
        if fix == nil, let favorite = items(favorites.ids).first { return favorite }
        return RankedStations.near(lat: a.lat, lon: a.lon).ranked.first
    }

    /// The content pane before any pick — same canvas, an invitation, not blank.
    private var detailPlaceholder: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 14) {
                Image(systemName: "water.waves")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(SN.foam.opacity(0.5))
                Text("Pick a station")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SN.paper.opacity(0.9))
                Text("Tides and currents open here.")
                    .font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.55))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The list surface both layouts share: canvas + grouped List. Search
    /// lives on the floating button — no top bar.
    private var listPane: some View {
            ZStack {
                CanvasBackground()
                // A List (not ScrollView) so the group rows carry native
                // .swipeActions — restyled to the same canvas: clear rows,
                // no separators, no insets.
                List {
                    Group {
                        header
                        locatedSections
                        // max: never shrinks below the intended footprint + margin at small text sizes.
                        Color.clear.frame(height: max(fabClearance, Self.fabClearanceBase))  // scroll clear of the FABs
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
                // Named so UI tests scroll THIS container: at regular width the
                // detail pane is a scroll view too, and since it opens on a
                // station, "the first scroll view" is ambiguous.
                .accessibilityIdentifier("station-list")
            }
            .toolbar(.hidden, for: .navigationBar)
    }

    /// The in-place map surface: no header or close; the List FAB is the way
    /// back.
    private var mapPane: some View {
        // `mapFocus` wins when set (header-title tap #32, Nearby map): centers
        // on that station at the zoom it asked for rather than the
        // fix/discovery camera. `.id(mapFocusToken)` forces a remount on every
        // focus, so `makeUIView` handles the camera even on the pin-tap path
        // where the pane is already mounted (`showMap` stayed true across the
        // push/pop).
        //
        // A ZStack, not `.overlay` on the map: the map ignores the safe area
        // and an overlay on it inherits that frame, so the pill's offset was
        // measured from the screen edge — 96pt put it ABOVE the 56pt FABs
        // rather than beside them, hovering mid-chart (#43). The ZStack keeps
        // its safe area, so the pill takes the same `fabBarBottomPadding` the
        // FAB row does and lands on that row, clear of the home indicator.
        ZStack(alignment: .bottom) {
            MapViewRepresentable(
                center: mapCenterOverride
                    ?? mapFocus.map { CLLocationCoordinate2D(latitude: $0.item.latitude, longitude: $0.item.longitude) }
                    ?? fix.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    ?? RecentsStore.shared.lastOpened.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                    // SALISH_CENTER only survives to here on a genuine first
                    // run: no fix, nothing ever opened.
                    ?? SALISH_CENTER,
                zoom: mapFocus?.zoom ?? discoveryZoom
            ) { item in
                if regular { showMap = false }  // the detail pane shows the pick
                open(item)
            }
            .id("\(mapFocusToken)-\(normalizedSlackThresholdKn(slackWindowSpeed))")
            .accessibilityIdentifier("map-canvas")
            // Consumed once: the next appearance of this pane (fab toggle, a
            // fresh pick) starts from the fix/discovery camera again, not a
            // stale focus from a station visited an hour ago.
            .onAppear { mapFocus = nil }
            .ignoresSafeArea()

            // Satellite imagery shows no depths, so there is no chart-datum
            // claim to disclaim. The navigation half is not decoration:
            // the App Store review notes (private planning repo) tell the reviewer this app marks
            // "not for navigation" on every detail footer AND the map, and
            // that claim has to remain true on this surface.
            Text("Not for navigation.")
                .font(.caption2)
                .foregroundStyle(SN.foam.opacity(0.85))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(SN.canvas.opacity(0.82), in: Capsule())
                .accessibilityIdentifier("map-disclaimer")
                .padding(.bottom, Self.fabBarBottomPadding)   // the FAB row's own baseline
        }
        .background(SN.canvas.ignoresSafeArea())
    }

    /// The app's URL scheme (project.yml CFBundleURLTypes). Widgets emit
    /// both routes: locked accessory widgets → premium, home widgets
    /// and the free ones' deepLink → station/<id> (HomeWidgets.swift). Named
    /// rather than inline because RootView's pre-gate handoff replays the URL
    /// through it on first appear.
    private func handleDeepLink(_ url: URL) {
        // A universal link arrives here too, not through a separate callback.
        if let link = stationLink(from: url) {
            // A slug this build doesn't know — an older build, or a station
            // that has since left the bundle — opens nothing. It can never open
            // something else: a slug is allocated once and never reused.
            if let item = stationItem(for: link) { open(item, at: link.instant) }
            return
        }
        guard url.scheme == "slackwater" else { return }
        switch url.host {
        case "premium": showWidgetsGallery = true
        // `stationID(from:)`, never `pathComponents` — see DeepLink.swift.
        case "station":
            if let item = StationItem.byId[stationID(from: url)] { open(item) }
        default: break
        }
    }

    /// Show a station picked anywhere (row tap in regular, map pin tap in
    /// both). Resets the path first: in the split layout this replaces the
    /// shown detail; in the stack the path is empty here anyway.
    ///
    /// `at` is the moment a shared link carried; the pushed detail scrubs to
    /// it (ScrubDetailScaffold). Nil — every other caller — means "now".
    private func open(_ item: StationItem, at instant: Date? = nil) {
        pendingScrubInstant = instant
        // Regular width: the sidebar (and its focused search field) stays on
        // screen when a detail opens, so the keyboard would sit over the new
        // detail — drop it. On iPhone the push dismisses it anyway.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        path = NavigationPath()
        switch item {
        case .tide(let s): path.append(NoaaRoute.tide(s))
        case .current(let s): path.append(NoaaRoute.current(s))
        // Every CHS station routes the same way, fitted or not: ChsDetailView
        // shows the real detail when the model is there and the ⚠️ download
        // explanation when it isn't. A tap is never a dead tap.
        case .chs(let info): path.append(ChsRoute.port(info))
        case .chsGate(let gate): path.append(ChsRoute.derivedGate(gate))
        case .chsCurrent(let gate): path.append(ChsRoute.currentGate(gate))
        }
    }

    // The list: My Location → Favorites → Near Me → Recents, nothing else —
    // search is the discovery path for the rest of the catalog. Without a fix
    // the ranking anchors on the Victoria fallback, and the My Location slot
    // holds the amber denied card when location is off. Dedupe: ListGroups —
    // each station renders once, My Location > Favorites > Near Me > Recents.
    @ViewBuilder private var locatedSections: some View {
        let anchor = anchor
        // Ranked once per fix, not once per render (RankedStations).
        // Same-named stations collapse to their nearest in Near Me only;
        // Recents are uncollapsed (explicit picks stay exact). The rest are behind
        // the chooser.
        let (ranked, places) = RankedStations.near(lat: anchor.lat, lon: anchor.lon)
        // Both series under My Location: the nearest station plus the nearest
        // of the other series inside the nearby radius — "closest" must not
        // mean tide or current by accident of geography.
        let heroItems = fix == nil ? []
            : StationItem.heroItems(ranked: ranked, lat: anchor.lat, lon: anchor.lon)
        // The filter narrows Near Me only. The hero cards stay unfiltered
        // (they answer "where am I", not "what am I looking for"), and
        // Favorites/Recents are explicit picks a filter must not hide.
        let nearIds = seriesFilter.map { series in
            places.shownIds.filter { StationItem.byId[$0]?.series == series }
        } ?? places.shownIds
        let groups = ListGroups(heroIds: heroItems.map(\.id), favoriteIds: favorites.ids,
                                // Uncollapsed on purpose: a station opened via the chooser is an explicit
                                // pick, same principle StationGroups grants Favorites — collapsing it
                                // would let Recents silently show and reopen the nearest namesake
                                // instead. Near Me stays collapsed: distance ranking is not user choice.
                                recentIds: recents.ids,
                                rankedIds: nearIds,
                                // With hero cards the nearest is already on screen — 4 more; without, 5.
                                nearCount: fix == nil ? 5 : 4)

        // My Location slot: the hero tile, its locating state, the amber
        // denied card, or — past the gate, with the choice never made — the ask
        // card. Keep the slot mounted while Core Location finds a fix.
        Group {
            if let fix, !heroItems.isEmpty {
                MyLocationTile(items: heroItems, fix: fix, imperial: imperial) { item in
                    VStack(spacing: 0) {
                        itemCard(item, km: item.km(fromLat: fix.lat, lon: fix.lon))
                        matchingButton(item, places)
                    }
                }
                    .transition(.opacity)
            } else if loc.authorized {
                MyLocationLoadingTile()
                    .transition(.opacity)
            } else if loc.denied {
                unavailableCard.padding(.top, 14)  // ChsAmberCard brings its own horizontal inset
            } else {
                // .notDetermined past the gate. Two ways in, and NEITHER is a
                // first run: the gate's "or search" bypass sets seenGate
                // without ever asking, and iOS's "Ask Next Time Or When I
                // Share" (or an expired "Allow Once") resets an answered app
                // back to undecided. seenGate is one-way, so the gate — the
                // only caller of `request()` — never comes back, and this slot
                // used to render nothing at all: the whole My Location group
                // silently vanished with no prompt and no explanation.
                askCard.padding(.top, 14)  // ChsAmberCard brings its own horizontal inset
            }
        }
        .animation(.easeInOut(duration: 0.25),
                   value: fix.map { formatCoord(lat: $0.lat, lon: $0.lon) })

        // Favorites: starred stations, insertion order, managed by swipe.
        // Iterated by ID, not by resolved item: a favorite whose station has
        // left the bundle still gets a row (issue #91). Everywhere else a
        // resolve miss can only be a station the ranking itself produced, so
        // there is nothing to miss.
        if !groups.favorites.isEmpty {
            sectionLabel("Favorites")
            ForEach(groups.favorites, id: \.self) { id in
                if let item = StationItem.byId[id] {
                    itemCard(item)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        // Remove re-files to Recents — neutral tint, no
                        // destructive full-swipe.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { favorites.toggle(id) } label: {
                                Label("Unfavorite", systemImage: "star.slash")
                            }
                            .tint(SN.steel)
                        }
                } else {
                    removedCard(id)  // ChsAmberCard brings its own horizontal inset
                        .padding(.bottom, 12)
                        // Red destructive, unlike a live favorite's neutral
                        // unfavorite: there is no Recents to re-file to, so
                        // this really is deletion and says so.
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { favorites.forget(id) } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
        }

        HStack(alignment: .firstTextBaseline) {
            MonoLabel(text: "Near Me")
            Spacer(minLength: 8)
            SeriesFilterChips()
        }
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .padding(.bottom, 4)
        ForEach(items(groups.nearMe)) { item in
            VStack(spacing: 0) {
                itemCard(item, km: item.km(fromLat: anchor.lat, lon: anchor.lon))
                matchingButton(item, places)
            }
                .padding(.horizontal, 16)
                // 8 + 4 = the 12pt gap Favorites gets from its single
                // `.padding(.bottom, 12)`. Split across the two edges because a
                // Near Me row is a card *plus* its matching-stations link, and
                // the link needs the slack under it, not over it.
                .padding(.top, 8)
                .padding(.bottom, 4)
                .swipeActions(edge: .leading) {
                    Button { favorites.toggle(item.id) } label: {
                        Label("Favorite", systemImage: "star.fill")
                    }
                    .tint(SN.sun)
                }
        }

        // Recents at the very bottom: recently viewed, most recent
        // first, minus everything already shown above. Same cards as Near Me;
        // no distance — a recent is an explicit pick, not a ranked one.
        let recentItems = items(groups.recents)
        if !recentItems.isEmpty {
            sectionLabel("Recents")
            ForEach(recentItems) { item in
                VStack(spacing: 0) {
                    itemCard(item)
                    matchingButton(item, places)
                }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .swipeActions(edge: .trailing) {
                        // True deletion — red destructive full-swipe.
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
        ids.compactMap { StationItem.byId[$0] }
    }

    private func sectionLabel(_ text: String) -> some View {
        MonoLabel(text: text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    /// The matching-station chooser's entry point: a quiet link-styled line
    /// under an entry whose name several stations share (the web chooser's
    /// toggle — "not right?"). Renders nothing when the name is unique, since
    /// an affordance offering one option is noise (web StationChooser).
    @ViewBuilder private func matchingButton(_ item: StationItem, _ places: StationGroups) -> some View {
        let matches = places.matches(item)
        if matches.count > 1 {
            BranchLink(text: "\(matches.count) matching stations",
                       id: "matching-stations", chevron: false) {
                chooser = StationMatches(place: item.name, matches: matches)
            }
            .padding(.horizontal, 18)
            .padding(.top, 7)
        }
    }

    /// Row activation in both layouts: the tap drives the path directly, never
    /// a hidden NavigationLink behind the card. The My Location tile is ONE
    /// List row holding two cards, and a row activates every link inside it —
    /// one tap there pushes both stations (#359). Same
    /// closure-not-NavigationLink rule the detail-to-detail environment keys
    /// follow (Theme.swift), and what the search results and map pins do.
    @ViewBuilder private func activatable<V: View>(_ view: V, _ item: StationItem) -> some View {
        view.contentShape(Rectangle()).onTapGesture { open(item) }
    }

    @ViewBuilder private func itemCard(_ item: StationItem, km: Double? = nil) -> some View {
        switch item {
        case .tide(let info):
            activatable(StationCardView(info: info, imperial: imperial, km: km), item)
        case .current(let info):
            activatable(CurrentCardView(info: info, km: km), item)
        case .chs(let info):
            activatable(ChsCardView(info: info, imperial: imperial, km: km), item)
        case .chsGate(let gate):
            activatable(ChsGateCardView(gate: gate, km: km), item)
        case .chsCurrent(let gate):
            activatable(ChsCurrentGateCardView(gate: gate, km: km), item)
        }
    }

    /// A favorite whose station has left the bundle (issue #91). Stations come
    /// and go — CHS withdrew 28 in one release — and a starred one that simply
    /// stopped appearing is the worst of the options: no crash, no row, no
    /// explanation, and a dead id sitting in UserDefaults forever. So the row
    /// stays, says what happened, and offers the nearest stations to where that
    /// station used to be.
    ///
    /// The tombstone list is what makes the name renderable at all; without one
    /// (a favorite from a bundle older than tombstones, say) the card is
    /// nameless and the replacements come from where the user is instead.
    @ViewBuilder private func removedCard(_ id: String) -> some View {
        let gone = StationTombstone.byId[id]
        let origin = gone.map { (lat: $0.latitude, lon: $0.longitude) } ?? anchor
        ChsAmberCard(title: gone?.name ?? "Station removed",
                     headline: gone.map { "\($0.region) — no longer published." }
                        ?? "This station is no longer published.",
                     expectation: "It has been withdrawn from the hydrographic "
                        + "service, so it has no readings to show. Swipe to remove it.",
                     action: "Pick a replacement",
                     identifier: "removed-station-card",
                     icon: "mappin.slash") {
            chooser = StationMatches(place: gone?.name ?? "Removed station",
                                     matches: nearest(to: origin),
                                     replacing: .init(id: id, lat: origin.lat, lon: origin.lon))
        }
    }

    /// The five stations nearest a point, for the replacement chooser.
    /// Deliberately not `RankedStations.near`: that memoises exactly one fix,
    /// and asking it about a removed station's position would evict the user's
    /// own ranking and re-sort the whole catalog on the next render. This runs
    /// once, on a tap.
    private func nearest(to origin: (lat: Double, lon: Double)) -> [StationItem] {
        Array(StationItem.rankedByDistance(StationItem.all, lat: origin.lat, lon: origin.lon)
            .prefix(5))
    }

    /// Location never answered — same card shape as `unavailableCard`, but the
    /// action is the ask itself, not a trip to Settings: `.notDetermined` is
    /// the one state iOS still lets the app prompt from.
    private var askCard: some View {
        ChsAmberCard(title: "See stations near you",
                     headline: "Turn on location to find the nearest tide & current stations.",
                     action: "Use My Location",
                     identifier: "location-ask-card",
                     icon: "location.fill",
                     accent: SN.leaf) {
            loc.request()
        }
    }

    /// Location denied — the app's one amber card (ChsAmberCard carries the
    /// contrast story), deep linking to the app's iOS Settings.
    private var unavailableCard: some View {
        ChsAmberCard(title: "Location unavailable",
                     headline: "Turn on location for Slackwater to see stations near you.",
                     action: "Go to Settings",
                     identifier: "location-denied-card",
                     icon: "location.slash") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text("Slackwater")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(SN.paper)
                // The wordmark never wraps: in the 320pt iPad sidebar it shares
                // the row with two 34pt buttons and would break as "Slackwat/er".
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
            Spacer(minLength: 8)
            // Offline / online / downloading, beside the gear — and the way in
            // to the downloads manager (web OfflineStatus).
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

    // MARK: - Floating toolbar (search bottom-left, list ⇄ map bottom-right,
    // both persistent over list AND map)

    private var fabBar: some View {
        HStack {
            fab("magnifyingglass", label: "Search") { openSearch() }
            Spacer()
            fab(showMap ? "list.bullet" : "map", label: showMap ? "List" : "Map") {
                showMap.toggle()
                // Regular width: opening the map replaces the shown detail;
                // toggling back lands on the placeholder (the toggle is a
                // full surface swap, not a stack push).
                if regular && showMap { path = NavigationPath() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, Self.fabBarBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// The toolbar button: 56pt glass circle.
    private func fab(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(SN.foam)
                .frame(width: Self.fabSize, height: Self.fabSize)
                .glassEffect(.regular.interactive(), in: Circle())
                .shadow(color: SN.shadow.opacity(0.4), radius: 10, y: 6)
        }
        .accessibilityLabel(label)
    }

    // MARK: - Search (bottom input above the keyboard, results above —
    // the Weather-app pattern)

    private func openSearch() {
        query = ""       // a new search never inherits the last query
        searching = true
    }

    private var searchOverlay: some View {
        // Results scroll UNDER the chips and the input, dissolving toward
        // the bottom edge (the Weather-app search treatment): the scroll
        // surface fills the overlay and the controls float over its faded
        // tail, rather than owning their own slice of the screen.
        ZStack(alignment: .bottom) {
            CanvasBackground()
            ScrollView {
                    let results = StationItem.search(query, near: anchor, series: seriesFilter)
                    VStack(spacing: 12) {
                        // Nationally a two-letter query matches a thousand
                        // stations. Showing the nearest 60 is the useful
                        // answer; saying so is the honest one — and it says so
                        // ABOVE the results, where it is read, not 60 cards
                        // down where nobody scrolls.
                        if results.count == StationItem.searchLimit {
                            MonoLabel(text: "Nearest \(StationItem.searchLimit) — keep typing to narrow",
                                      color: SN.foam.opacity(0.5), tracking: 1.2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.bottom, 2)
                                .accessibilityIdentifier("search-truncated")
                        }
                        // The overlay covers the whole screen, sidebar and
                        // detail pane alike, so on iPad one column stretched
                        // a card built for 320–400pt across 1,300pt. Adaptive
                        // columns cap a card below twice the minimum: one
                        // column on iPhone, two in iPad portrait, three in
                        // landscape, with no size-class branch.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 12)],
                                  spacing: 12) {
                            ForEach(results) { item in
                                resultCard(item)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    // Room to scroll the last card clear of the floating
                    // controls and the fade under them.
                    .padding(.bottom, 190)
            }
            // The dissolve runs from just above the floating controls to the
            // overlay's very bottom edge. A mask changes rendering only —
            // rows inside the fade still scroll and hit-test.
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 170)
                }
            }
            VStack(spacing: 0) {
                // The same chips as the Near Me header — one filter, both
                // surfaces — sitting above the input, thumb-reachable.
                SeriesFilterChips()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                searchBar
            }
            // The controls float over tappable results, and glass (unlike
            // the flat background it replaced) is not a hit-test barrier — an
            // unguarded tap on the input's padding would open the faded card
            // BEHIND the field. The whole control region claims its taps and
            // spends them on focus; the chips and the X, being buttons, still
            // win their own.
            .contentShape(Rectangle())
            .onTapGesture { searchFocused = true }
        }
        .onAppear { searchFocused = true }  // keyboard up immediately
    }

    /// A search result: the ordinary card, tapping opens the detail and
    /// closes search (the overlay sits outside the nav stacks, so results
    /// drive `open` directly rather than riding hidden links).
    @ViewBuilder private func resultCard(_ item: StationItem) -> some View {
        Group {
            switch item {
            case .tide(let s): StationCardView(info: s, imperial: imperial)
            case .current(let s): CurrentCardView(info: s)
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

    /// The bottom bar: input pill + the X glass circle beside it —
    /// one tap exits search and drops the keyboard.
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SN.foam.opacity(0.7))
                TextField("Harbor, bay, or channel", text: $query)
                    .font(.body)
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
            // Same fix as the gate button: content sizes the pill, `minHeight`
            // keeps the 48pt look at default sizes. A fixed `.frame(height: 48)`
            // left the field's text hanging out of its own capsule at
            // accessibility sizes. `TextField` fails the way an `Image` does,
            // NOT the way a `Text` does: it reports its intrinsic line height
            // (65pt at AX5) and draws past a smaller frame, where a `Text`
            // would have quietly truncated instead. Visible either way here,
            // since the capsule is a background, not a clip.
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .glassEffect(.regular.interactive(), in: Capsule())

            Button {
                searching = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SN.foam)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// The My Location hero: MY LOCATION eyebrow with the location arrow and,
/// opposite it, the fix coordinates in mono (3 decimal places), over the
/// nearest stations' ordinary cards (distance rendered in each card's own
/// identity column — same as every other card). Usually two cards — the
/// nearest tide and the nearest current station (StationItem.heroItems) —
/// one where the other series has no nearby coverage.
///
/// The coordinates share the eyebrow's row (#42): on their own line under the
/// card they buy a full row of tile height for one short mono string, and
/// leave the eyebrow row half-empty above it — the card ends up sandwiched in
/// padding that encodes nothing.
struct MyLocationTile<Card: View>: View {
    let items: [StationItem]
    let fix: (lat: Double, lon: Double)
    let imperial: Bool
    @ViewBuilder let card: (StationItem) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "location.north.fill")
                    .font(.caption2)
                    .rotationEffect(.degrees(45))
                MonoLabel(text: "My Location", color: SN.foam.opacity(0.9))
                Spacer(minLength: 8)
                Text(formatCoord(lat: fix.lat, lon: fix.lon))
                    .font(.caption2.monospaced())
                    .foregroundStyle(SN.foam.opacity(0.55))
                    // Deliberately neither shrunk to fit nor line-limited: the
                    // wordmark is the only text in the app allowed to scale
                    // down (TypeScaleTests `testOnlyTheWordmarkShrinks` — a
                    // line scan, so naming the modifier here would fail it),
                    // and a truncated position is worse than a wrapped one.
                    // At the largest accessibility sizes this wraps and the
                    // row grows.
            }
            .foregroundStyle(SN.foam.opacity(0.9))
            // sectionLabel's three paddings (private to this file) — a header
            // over a plain card, not a box (#253).
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 4)
            VStack(spacing: 12) {
                ForEach(items) { item in
                    card(item)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct MyLocationLoadingTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "location.north.fill")
                    .font(.caption2)
                    .rotationEffect(.degrees(45))
                MonoLabel(text: "My Location", color: SN.foam.opacity(0.9))
            }
            // sectionLabel's three paddings (private to this file) — a header
            // over a plain card, not a box (#253).
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 4)

            HStack(spacing: 12) {
                ProgressView().tint(SN.leaf)
                Text("Finding your location…")
                    .font(.callout)
                    .foregroundStyle(SN.foam.opacity(0.7))
                Spacer()
            }
            .frame(minHeight: 96)
            .padding(.horizontal, 20)
            .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}
