// Slackwater — GPL v3. M4: first-run location gate (prototype NearMe.dc.html),
// located list (My Location tile + Near Me by distance), settings, pin map.
// M1's list underneath; M53 gave the cards layout A — kind glyph, flat fill.
import CoreLocation
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
            // The gate is one screenful of fixed copy, and since the type
            // scales (Task 1) that screenful stops fitting at the top
            // accessibility sizes. Task 6 measured it at AX5 on both devices:
            // "See tides near you" came out "See tides nea…" and the subtitle
            // "Turn on location and…", because SwiftUI resolves a too-short
            // VStack by TRUNCATING its Texts, silently. A ScrollView gives the
            // copy the height it needs; `minHeight: geo.size.height` keeps the
            // Spacers' centred layout for every size that still fits, so
            // nothing moves below AX5.
            GeometryReader { geo in
              ScrollView {
                VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    Text("Slackwater")
                        .font(.largeTitle.weight(.semibold))
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
                        .font(.callout)
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
                        .font(.title.weight(.semibold))
                        .foregroundStyle(SN.paper)
                        .padding(.top, 26)
                    Text("Turn on location to find the \nnearest tide & current stations.")
                        .font(.subheadline)
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
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SN.navyDeep)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        // Content sizes the capsule; `minHeight` keeps the 54pt
                        // look at default sizes without capping growth. A fixed
                        // `.frame(height: 54)` here silently truncated the label
                        // at accessibility sizes ("Use My…"), because a `Text`
                        // given too little height degrades by DROPPING CONTENT,
                        // not by overflowing — the opposite of an `Image`, which
                        // ignores the proposal and draws past its frame. Text
                        // fails silently; images fail visibly. Never pin a
                        // height around text you need read.
                        .padding(.vertical, 12)
                        .frame(minHeight: 54)
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
                            .font(.caption)
                            .foregroundStyle(SN.foam.opacity(0.4))
                    }
                    .padding(.top, 16)
                }

                Spacer()
                Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
              }
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
    /// requirement, despite what an earlier version of this comment (and spec
    /// §4) claimed: `fab()` is `.font(.system(size: 21))` inside a fixed 56pt
    /// frame plus `fabBar`'s 24pt bottom padding, so the footprint this has to
    /// clear is CONSTANT at every content-size category. A flat
    /// `fabClearanceBase` would already clear the FABs everywhere — the last
    /// card is not going to end up under them.
    ///
    /// What `@ScaledMetric` buys is proportion: at large sizes the gap grows
    /// with the rows around it instead of reading as a hairline (+210pt at
    /// AX5, per the Task 6 verification table). What it costs is that
    /// `@ScaledMetric` scales in BOTH directions, so below the default
    /// category it would shrink the gap below the intended margin — which is
    /// the only thing the `max(...)` clamp at the call site undoes. Kept
    /// because it is harmless and the measured behaviour is good; if it ever
    /// needs to go, the honest replacement is the flat base, not a rewrite.
    @ScaledMetric(relativeTo: .body) private var fabClearance: CGFloat = Self.fabClearanceBase
    /// `unavailableCard`'s icon tile — tracks the `.title3` icon it holds
    /// (sweep finding, same failure shape as `ProvisionalBadge`/`ChsAmberCard`).
    @ScaledMetric(relativeTo: .title3) private var deniedIconTileSize: CGFloat = 46

    private var regular: Bool { hSize == .regular }
    private var imperial: Bool { units == "imperial" }
    /// The fix the list ranks by — only while authorized.
    private var fix: (lat: Double, lon: Double)? {
        guard loc.authorized, let l = loc.location else { return nil }
        return (l.coordinate.latitude, l.coordinate.longitude)
    }
    /// What distances are measured from: the fix, or the Victoria fallback.
    private var anchor: (lat: Double, lon: Double) { fix ?? fallbackFix }

    var body: some View {
        Group {
            if regular {
                splitLayout
            } else {
                stackLayout
            }
        }
        // Fifth-pass evidence (task-9): a pushed destination doesn't reliably
        // inherit environment attached to the NavigationStack itself when that
        // stack is NavigationSplitView's `detail:` column — attaching there
        // left `TideAtPortLink`'s `openTide` reading the default no-op on
        // iPad, tap included, in a live-logged repro. Attached here instead,
        // above BOTH layouts, delivery rides ordinary ancestor inheritance —
        // and there's exactly one attachment, so the two layouts can't drift.
        .environment(\.openTideDetail) { path.append($0) }
        // Search is modal: hide the base surface from accessibility while the
        // overlay is up (VoiceOver correctness, and hit-tests resolve to the
        // overlay's cards, not identically-named cards underneath).
        .accessibilityHidden(searching)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showDownloads) { OfflineManagerView() }
        .sheet(item: $chooser) { place in
            StationChooserSheet(place: place, anchor: anchor) { open($0) }
        }
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
            .navigationDestination(for: TideStationRecord.self) { TideDetailView(record: $0).id($0.id) }
            .navigationDestination(for: CurrentStationRecord.self) { CurrentDetailView(record: $0).id($0.id) }
            .navigationDestination(for: DerivedGateRecord.self) { DerivedGateDetailView(record: $0).id($0.gate.id) }
            .navigationDestination(for: ChsRoute.self) { ChsDetailView(route: $0).id($0.stationID) }
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
                .navigationDestination(for: DerivedGateRecord.self) { DerivedGateDetailView(record: $0).id($0.gate.id) }
                .navigationDestination(for: ChsRoute.self) { ChsDetailView(route: $0).id($0.stationID) }
                .toolbar(.hidden, for: .navigationBar)
            }
            // A regular-width launch opens on the first row rather than the
            // "Pick a station" placeholder (M52): the My Location station when
            // there is a fix, else the first row the list renders. Once only,
            // and only into an empty pane — coming back from a detail leaves
            // the placeholder alone, and an existing pick is never overridden.
            .onAppear {
                guard !didAutoSelect else { return }
                didAutoSelect = true
                guard path.isEmpty, !showMap, let first = firstListItem else { return }
                RecentsStore.shared.skipNextRecord = true
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
            RadialGradient(colors: [SN.canvasGlow, SN.canvas], center: .top,
                           startRadius: 0, endRadius: 500)
                .ignoresSafeArea()
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
                // detail pane is a scroll view too, and since it now opens on a
                // station (M52) "the first scroll view" is ambiguous.
                .accessibilityIdentifier("station-list")
            }
            .toolbar(.hidden, for: .navigationBar)
    }

    /// The in-place map surface (prototype READY·MAP): no header, no close —
    /// the toggle FAB is the only way back.
    private var mapPane: some View {
        MapViewRepresentable(center: fix.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        } ?? SALISH_CENTER) { item in
            if regular { showMap = false }  // the detail pane shows the pick
            open(item)
        }
        .accessibilityIdentifier("map-canvas")
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            // Was "Depths not reduced to chart datum — not for navigation."
            // The depths half stopped being true: the offline chart carries no
            // bathymetry at all (Seascape's depth shading is a `color-relief`
            // layer MapLibre Native rejects, and its contours and soundings are
            // separate online-only sources), so the map was disclaiming a
            // reading it never shows. The navigation half stays — it is not
            // decoration here, `docs/appstore-metadata.md` tells the reviewer
            // this app marks "not for navigation" on every detail footer AND
            // the map, and that claim has to remain true on this surface.
            Text("Not for navigation.")
                .font(.caption2)
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
        let anchor = anchor
        // Ranked once per fix, not once per render (M53 — RankedStations).
        // Same-named stations collapse to their nearest (M50) in Near Me only;
        // Recents are uncollapsed (explicit picks stay exact). The rest are behind
        // the chooser.
        let (ranked, places) = RankedStations.near(lat: anchor.lat, lon: anchor.lon)
        let heroItem = fix == nil ? nil : ranked.first
        let groups = ListGroups(heroId: heroItem?.id, favoriteIds: favorites.ids,
                                // Uncollapsed on purpose: a station opened via the chooser is an explicit
                                // pick, same principle StationGroups grants Favorites — collapsing it made
                                // Recents silently show and reopen the nearest namesake instead
                                // (split-scrubbers spec §6). Near Me stays collapsed: distance ranking is
                                // not user choice.
                                recentIds: recents.ids,
                                rankedIds: places.collapse(ranked.map(\.id)),
                                // With a hero the nearest is already on screen — 4 more; without, 5.
                                nearCount: fix == nil ? 5 : 4)

        // My Location slot: the hero tile, or the amber card in its place.
        if let fix, let nearest = heroItem {
            VStack(spacing: 0) {
                MyLocationTile(item: nearest, fix: fix, imperial: imperial) {
                    itemCard($0, km: $0.km(fromLat: fix.lat, lon: fix.lon))
                }
                matchingButton(nearest, places)
            }
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
            VStack(spacing: 0) {
                itemCard(item, km: item.km(fromLat: anchor.lat, lon: anchor.lon))
                matchingButton(item, places)
            }
                .padding(.horizontal, 16)
                // 8 + 4 = the 12pt gap Favorites gets from its single
                // `.padding(.bottom, 12)`. Split across the two edges because a
                // Near Me row is a card *plus* its matching-stations link, and
                // the link needs the slack under it, not over it. (The original
                // reason — clearance for a straddling nm pill — went with the
                // pill; this is the reason the number has now.)
                .padding(.top, 8)
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
                recentRow(item, places: places, isFirst: item.id == recentItems.first?.id,
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
        ids.compactMap { StationItem.byId[$0] }
    }

    private func sectionLabel(_ text: String) -> some View {
        MonoLabel(text: text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    /// A compact recently-viewed row (prototype recent rows: kind glyph, name
    /// over region), navigating like the full cards. First/last rows
    /// round the group's outer corners — the grouped-card look, but one List
    /// row per station so each carries its own swipe actions.
    @ViewBuilder private func recentRow(_ item: StationItem, places: StationGroups,
                                        isFirst: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            activatable(RecentRowLabel(item: item, imperial: imperial), item)
            // Nothing at all unless the name is shared — the common row is
            // exactly what it was.
            matchingButton(item, places).padding(.bottom, 10)
        }
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

    /// The matching-station chooser's entry point: a quiet link-styled line
    /// under an entry whose name several stations share (the web chooser's
    /// toggle — "not right?"). Renders nothing when the name is unique, since
    /// an affordance offering one option is noise (web StationChooser).
    @ViewBuilder private func matchingButton(_ item: StationItem, _ places: StationGroups) -> some View {
        let matches = places.matches(item)
        if matches.count > 1 {
            Button {
                chooser = StationMatches(place: item.name, matches: matches)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2.weight(.semibold))
                    Text("\(matches.count) matching stations")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(SN.leaf)
                .padding(.horizontal, 18)
                .padding(.top, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("matching-stations")
        }
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

    @ViewBuilder private func itemCard(_ item: StationItem, km: Double? = nil) -> some View {
        switch item {
        case .tide(let station):
            activatable(StationCardView(record: station, imperial: imperial, km: km), item)
        case .current(let station):
            activatable(CurrentCardView(record: station, km: km), item)
        case .chs(let info):
            activatable(ChsCardView(info: info, imperial: imperial, km: km), item)
        case .chsGate(let gate):
            activatable(ChsGateCardView(gate: gate, km: km), item)
        case .chsCurrent(let gate):
            activatable(ChsCurrentGateCardView(gate: gate, km: km), item)
        }
    }

    /// Location denied — `SN.amber` card, deep link to the app's iOS Settings.
    /// The token, not a literal: this card renders in the My Location slot
    /// directly above Near Me cards whose glyphs draw ebb, and the retired
    /// golden amber it used to hardcode is the value amber moved away from
    /// precisely because it read as ebb at that adjacency.
    private var unavailableCard: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 13) {
                    Image(systemName: "location.slash")
                        .font(.title3)
                        .foregroundStyle(SN.amber)
                        .frame(width: deniedIconTileSize, height: deniedIconTileSize)
                        .background(SN.amber.opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location unavailable")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(SN.paper)
                        Text("Turn on location for Slackwater to see stations near you.")
                            .font(.footnote)
                            .foregroundStyle(SN.foam.opacity(0.62))
                    }
                }
                HStack(spacing: 4) {
                    Spacer()
                    Text("Go to Settings")
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SN.amber)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SN.amber.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(SN.amber.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
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
        .padding(.bottom, Self.fabBarBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// The prototype toolbar button: 56pt glass circle.
    private func fab(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(SN.foam)
                .frame(width: Self.fabSize, height: Self.fabSize)
                .glassEffect(.regular.interactive(), in: Circle())
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
                    let results = StationItem.search(query, near: anchor)
                    LazyVStack(spacing: 12) {
                        // Nationally a two-letter query matches a thousand
                        // stations. Showing the nearest 60 is the useful
                        // answer; saying so is the honest one — and it says so
                        // ABOVE the results, where it is read, not 60 cards
                        // down where nobody scrolls (M53).
                        if results.count == StationItem.searchLimit {
                            MonoLabel(text: "Nearest \(StationItem.searchLimit) — keep typing to narrow",
                                      color: SN.foam.opacity(0.5), tracking: 1.2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.bottom, 2)
                                .accessibilityIdentifier("search-truncated")
                        }
                        ForEach(results) { item in
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
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(SN.leaf.opacity(0.25), lineWidth: 0.5))

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

/// The prototype's My Location hero: MY LOCATION eyebrow with the location
/// arrow, the nearest station's ordinary card (distance rendered in its own
/// identity column, layout A — same as every other card), then the fix
/// coordinates in mono (NearMe.dc.html fmtCoord — 3 decimal places).
struct MyLocationTile<Card: View>: View {
    let item: StationItem
    let fix: (lat: Double, lon: Double)
    let imperial: Bool
    @ViewBuilder let card: (StationItem) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "location.north.fill")
                    .font(.caption2)
                    .rotationEffect(.degrees(45))
                MonoLabel(text: "My Location", color: SN.foam.opacity(0.9))
            }
            .foregroundStyle(SN.foam.opacity(0.9))
            .padding(.horizontal, 6)
            card(item)
            Text(formatCoord(lat: fix.lat, lon: fix.lon))
                .font(.caption2.monospaced())
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

/// One place and every station that answers for it (M50 chooser payload).
struct StationMatches: Identifiable, Hashable {
    let place: String
    /// Nearest first; always includes the entry that opened the chooser.
    let matches: [StationItem]
    var id: String { place }
}

/// The matching-station chooser (web `StationChooser.tsx`, list-side): where
/// several stations share a name, the list shows the nearest and this says so
/// rather than silently hiding the rest. Each row carries the two things that
/// aren't the name — what it measures (tide or current, NOAA or CHS) and how
/// far it is — so the pick is informed rather than a guess between identical
/// labels.
struct StationChooserSheet: View {
    let place: StationMatches
    let anchor: (lat: Double, lon: Double)
    let onPick: (StationItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            RadialGradient(colors: [SN.canvasGlow, SN.canvas], center: .top,
                           startRadius: 0, endRadius: 400)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.place)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(SN.paper)
                        Text("\(place.matches.count) stations answer for this place — pick the one you mean.")
                            .font(.footnote)
                            .foregroundStyle(SN.foam.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SN.foam.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(place.matches) { row($0) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("station-chooser")
    }

    private func row(_ item: StationItem) -> some View {
        Button {
            onPick(item)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(SN.cardFill)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    // The name is the same on every row — the qualifier is the
                    // whole point, so it leads.
                    Text(item.region.isEmpty ? item.name : item.region)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SN.paper)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    MonoLabel(text: item.kindLabel,
                              color: SN.foam.opacity(0.55), tracking: 1.1)
                }
                Spacer(minLength: 8)
                Text(formatNm(item.km(fromLat: anchor.lat, lon: anchor.lon)))
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(SN.foam.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SN.leaf.opacity(0.16), lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The compact recent-station row body: kind glyph, name over region, current
/// reading trailing in Fraunces. The prototype's 38pt gradient chip is gone
/// with the gradients (M53 layout A) — it had become a flat empty box sitting
/// inches below cards that draw a real glyph, so it takes the same
/// `StationGlyph` the cards do: wave or dome for kind, tone for state.
struct RecentRowLabel: View {
    let item: StationItem
    let imperial: Bool
    @AppStorage(speedUnitKey) private var speedUnit = "kn"
    // Cache the engine state, format in body — unit switches re-render live.
    // The whole card state, not just the number, because the glyph's tone
    // needs the direction/phase the reading alone doesn't carry.
    @State private var tide: CardState?
    @State private var current: CurrentCardState?
    @State private var gate: DerivedGateCardState?  // derived gate: phase word, never a speed
    @ScaledMetric(relativeTo: .callout) private var tileGlyphSize: CGFloat = 26
    /// The glyph's slot — tracks `tileGlyphSize` (sweep finding: `StationGlyph`
    /// sizes its own internal `Canvas` from `size`, but this outer frame was
    /// left at a literal 38, so once `tileGlyphSize` outgrew it the glyph
    /// overflowed the slot into the row's name/reading text beside it).
    @ScaledMetric(relativeTo: .callout) private var tileGlyphSlot: CGFloat = 38

    private var glyphKind: StationGlyph.GlyphKind {
        switch item {
        case .tide, .chs: .tide
        case .current, .chsGate, .chsCurrent: .current
        }
    }

    /// Reuses the cards' own bindings so a row and its card can never disagree.
    private var glyphTone: StationGlyph.Tone {
        switch item {
        case .tide, .chs: StationCardView.glyphTone(tide)
        case .current, .chsCurrent: CurrentCardView.glyphTone(current)
        case .chsGate: ChsGateCardView.glyphTone(gate?.phase)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            StationGlyph(kind: glyphKind, tone: glyphTone, size: tileGlyphSize)
                .frame(width: tileGlyphSlot, height: tileGlyphSlot)
            // The name owns the full row width (M50). It used to share the
            // line with the reading, which in the 320pt iPad sidebar left it
            // ~150pt — "Deception Pass State Park" came out "Deception Pas…",
            // and two different stations truncated to the same string. The
            // reading drops to the secondary line, where the region (the least
            // load-bearing text here) is what gives way instead.
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(SN.paper)
                HStack(spacing: 8) {
                    Text(item.region)
                        .font(.caption)
                        .foregroundStyle(SN.foam.opacity(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(reading)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(0.7))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .task { if tide == nil && current == nil && gate == nil { load() } }
    }

    private var rawId: String {
        if case .current(let s) = item { return s.id }
        return item.id
    }

    private var reading: String {
        if let gate { return phaseWord(gate.phase).lowercased() }
        if let current {
            return currentPhase(signed: current.signed) == .slack
                ? "slack" : "\(formatSpeed(abs(current.signed), unit: speedUnit)) \(speedUnitLabel(speedUnit))"
        }
        guard let tide else { return "" }
        return "\(formatHeight(tide.height, imperial: imperial)) \(heightUnit(imperial: imperial))"
    }

    private func load() {
        switch item {
        case .tide(let s):
            tide = s.cardState(at: appNow())
        case .current(let s):
            current = s.cardState(at: appNow())
        case .chs(let info):
            guard case .fitted(let record) = ChsFitService.shared.state(info.id) else { return }
            tide = record.cardState(at: appNow())
        case .chsGate(let info):
            guard case .fitted(let port) = ChsFitService.shared.state(info.reference) else { return }
            gate = DerivedGateRecord(gate: info, port: port).cardState(at: appNow())
        case .chsCurrent(let info):
            guard case .fitted(let record) = ChsFitService.shared.currentState(info.id) else { return }
            current = record.cardState(at: appNow())
        }
    }
}

/// Layout A: kind glyph left, identity (name/region/distance), state right.
/// Fraunces name, big height numeral.
struct StationCardView: View {
    let record: TideStationRecord
    let imperial: Bool
    var km: Double? = nil
    @State private var state: CardState?

    /// State → tone. `static`, like the detail views' `phaseColor`, so the
    /// binding can be asserted without building a view: an inverted binding
    /// here renders a perfectly valid flood blue on a falling tide and no
    /// token or colour test can see it (`ColourAndFormTests`
    /// `testCardGlyphToneBindings`).
    static func glyphTone(_ state: CardState?) -> StationGlyph.Tone {
        guard let state else { return .unknown }
        return state.rising ? .rising : .falling
    }

    var body: some View {
        StationCard(glyphKind: .tide, glyphTone: Self.glyphTone(state),
                    name: record.name, region: record.region, km: km,
                    detail: state?.next.map { next in
                        "\(next.kind == .high ? "High" : "Low") \(formatHeight(next.height, imperial: imperial)) \(heightUnit(imperial: imperial)) · \(cardTime(next.time, record.tz))"
                    }) {
            if let state {
                (Text(formatHeight(state.height, imperial: imperial))
                    .font(.largeTitle.monospacedDigit())
                 + Text(" \(heightUnit(imperial: imperial))")
                    .font(.body))
                    .foregroundStyle(.white)
                HStack(spacing: 4) {
                    Text(state.rising ? "▲" : "▼").font(.caption2)
                    Text(state.rising ? "Rising" : "Falling").font(.caption2)
                }
                .foregroundStyle(SN.foam.opacity(0.9))
            }
        }
        .task { if state == nil { state = record.cardState(at: appNow()) } }
    }
}

/// A Canadian (CHS) tide port. Fitted: the ordinary tide card, navigable.
/// Not yet fitted: the same card shell with identity and an honest message
/// (chs-online spec §7c — never an empty chart, never a spinner to nothing).
struct ChsCardView: View {
    let info: ChsStationInfo
    let imperial: Bool
    var km: Double? = nil
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared

    var body: some View {
        // Navigation comes from the enclosing row's hidden link (itemCard).
        switch service.state(info.id) {
        case .fitted(let record):
            StationCardView(record: record, imperial: imperial, km: km)
        case .fitting:
            ChsPendingCard(name: info.name, region: info.region, id: info.id, kind: .tide, km: km,
                           message: "Downloading Canadian tidal predictions…")
        case .pending:
            ChsPendingCard(name: info.name, region: info.region, id: info.id, kind: .tide, km: km,
                           message: chsPendingMessage("tidal", id: info.id))
        case .failed:
            ChsPendingCard(name: info.name, region: info.region, id: info.id, kind: .tide, km: km,
                           message: "Canadian tidal predictions didn't finish downloading — open it to retry.")
        }
    }
}

/// A station with no model yet. Three honest situations, not one:
///   - not in the download set at all (M53 — most of Canada): opening it is
///     what downloads it, so say that rather than implying a queue it isn't in.
///   - queued and connected: it is in line behind the nearer stations.
///   - no signal: nothing is moving at all. The established moment-of-signal
///     copy is kept verbatim.
@MainActor func chsPendingMessage(_ series: String, id: String) -> String {
    if !ChsFitService.shared.isQueued(id) {
        return "Open to download — Canadian \(series) predictions download once, then work offline."
    }
    return Connectivity.shared.online
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
    /// No reading has ever loaded here — there's nothing yet to fit, so the
    /// glyph's tone is `.unknown`, never a guess. Kind still comes from the
    /// caller: a pending tide port and a pending derived current gate look
    /// the same wave/dome distinction as their fitted counterparts.
    let kind: StationGlyph.GlyphKind
    var km: Double? = nil
    let message: String

    var body: some View {
        StationCard(glyphKind: kind, glyphTone: .unknown,
                    name: name, region: region, km: km,
                    message: message,
                    opacity: 0.82,  // visibly quieter than a station with numbers
                    trailing: { EmptyView() })
            // Named per station (M53). "Some card on screen says 'Canadian tidal
            // predictions'" was a unique locator at 21 Canadian stations and is
            // meaningless at 1,097 — every undownloaded station says it, so a test
            // waiting for THIS station's copy to go never sees it go.
            .accessibilityIdentifier("chs-pending-\(id)")
    }
}

/// A derived current gate's card (web StationCard's derived layout): identity,
/// "Slack · time" as the next line, and a compact phase pill — a derived gate
/// has no speed, so the reading is never a number (chs/current.ts). Pending
/// while the reference port is unfitted, in the same register as the ports.
struct ChsGateCardView: View {
    let gate: ChsGateInfo
    var km: Double? = nil
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared
    @State private var state: DerivedGateCardState?

    /// Phase → tone. `static` for the same reason as `StationCardView`'s.
    static func glyphTone(_ phase: DerivedPhase?) -> StationGlyph.Tone {
        switch phase {
        case .flood: .flood
        case .ebb: .ebb
        case .slack: .slack
        case nil: .unknown
        }
    }

    var body: some View {
        switch service.state(gate.reference) {
        case .fitted(let port):
            fittedCard(DerivedGateRecord(gate: gate, port: port))
        case .fitting:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, kind: .current, km: km,
                           message: "Downloading Canadian tidal predictions…")
        case .pending:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, kind: .current, km: km,
                           message: chsPendingMessage("tidal", id: gate.reference))
        case .failed:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, kind: .current, km: km,
                           message: "Canadian tidal predictions didn't finish downloading — open it to retry.")
        }
    }

    private func fittedCard(_ record: DerivedGateRecord) -> some View {
        StationCard(glyphKind: .current, glyphTone: Self.glyphTone(state?.phase),
                    name: gate.name, region: gate.region, km: km,
                    detail: state?.nextSlack.map { next in
                        "Slack · \(cardTime(next.time, gate.tz))"
                    }) {
            if let state {
                // The web's phase-pill words: flood / ebb / slack. Slack
                // takes SN.go, not the neutral chip flood/ebb still use —
                // otherwise the glyph beside it reads green while this
                // pill reads grey, the exact collision Task 2 fixed on
                // the detail views (testSlackIsGreenWhereverItAppears).
                Text(state.phase == .flood ? "FLOOD" : state.phase == .ebb ? "EBB" : "SLACK")
                    .font(.caption2.monospaced().weight(.medium)).tracking(1)
                    .foregroundStyle(state.phase == .slack ? SN.navyDeep : .white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(state.phase == .slack ? SN.go : Color.white.opacity(0.18), in: Capsule())
            }
        }
        .task { if state == nil { state = record.cardState(at: appNow()) } }
    }
}

/// A validated CHS current gate. Fitted: the ordinary current card — real
/// velocities, navigable. Not yet fitted: the pending shell in the established
/// register, naming currents (chs-online spec §7c — never an empty chart).
struct ChsCurrentGateCardView: View {
    let gate: ChsCurrentGateInfo
    var km: Double? = nil
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared

    var body: some View {
        // Navigation comes from the enclosing row's hidden link (itemCard).
        switch service.currentState(gate.id) {
        case .fitted(let record):
            CurrentCardView(record: record, km: km,
                            provisional: service.isProvisional(gate.id) ? gate : nil)
        case .fitting:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, kind: .current, km: km,
                           message: "Downloading Canadian current predictions…")
        case .pending:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, kind: .current, km: km,
                           message: chsPendingMessage("current", id: gate.id))
        case .failed:
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, kind: .current, km: km,
                           message: "Canadian current predictions didn't finish downloading — open it to retry.")
        }
    }
}

/// The current-station card: same layout-A shell, but the reading is signed
/// velocity — speed + set arrow + Flooding/Ebbing, a Slack pill at slack, and
/// the next slack/max as the detail line (web StationCard's current layout).
struct CurrentCardView: View {
    let record: CurrentStationRecord
    var km: Double? = nil
    /// Set while this gate is showing its 60-day fast answer. On the LIST card
    /// that is a ⚠️ badge and a `~` on the readings — nothing else (M52). The
    /// amber prose this replaced was unreadable on the per-station gradients of
    /// the day; those are gone and the numbers were redone against the flat
    /// card (see `ProvisionalBadge`, which carries the current contrast story).
    /// The full explanation, in the amber card that can afford the contrast,
    /// lives on the detail view and is unchanged.
    var provisional: ChsCurrentGateInfo? = nil
    @AppStorage(speedUnitKey) private var speedUnit = "kn"
    @State private var state: CurrentCardState?

    /// The tilde stays: at normal card contrast "~5.8" reads cleanly, and it is
    /// the one part of the old treatment that marked the NUMBER rather than
    /// shouting around it.
    private var tilde: String { provisional == nil ? "" : "~" }

    /// Signed velocity → tone. `static` for the same reason as
    /// `StationCardView`'s.
    static func glyphTone(_ state: CurrentCardState?) -> StationGlyph.Tone {
        guard let state else { return .unknown }
        switch currentPhase(signed: state.signed) {
        case .flood: return .flood
        case .ebb: return .ebb
        case .slack: return .slack
        }
    }

    var body: some View {
        StationCard(glyphKind: .current, glyphTone: Self.glyphTone(state),
                    name: record.name, region: record.region, km: km,
                    detail: state?.next.map { nextLine($0) },
                    badge: { if provisional != nil { ProvisionalBadge() } }) {
            if let state {
                let phase = currentPhase(signed: state.signed)
                if phase == .slack {
                    // SN.go, not a neutral chip — see the matching
                    // comment on ChsGateCardView's phase pill.
                    Text("SLACK")
                        .font(.caption2.monospaced().weight(.medium)).tracking(1)
                        .foregroundStyle(SN.navyDeep)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(SN.go, in: Capsule())
                } else {
                    (Text(tilde + formatSpeed(abs(state.signed), unit: speedUnit))
                        .font(.largeTitle.monospacedDigit())
                     + Text(" \(speedUnitLabel(speedUnit))")
                        .font(.body))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        CompassArrow(deg: record.setDegrees(signed: state.signed)).font(.caption2)
                        Text(phaseWord(phase)).font(.caption2)
                    }
                    .foregroundStyle(SN.foam.opacity(0.9))
                }
            }
        }
        .task { if state == nil { state = record.cardState(at: appNow()) } }
        // The refinement replaces the record under an open list: recompute.
        .onChange(of: record) { _, refined in state = refined.cardState(at: appNow()) }
    }

    private func nextLine(_ next: CurrentEvent) -> String {
        let when = cardTime(next.time, record.tz)
        return next.kind == .slack
            ? "\(tilde)Slack · \(when)"
            : "\(next.turnLabel) \(tilde)\(formatSpeed(abs(next.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit)) · \(when)"
    }
}
