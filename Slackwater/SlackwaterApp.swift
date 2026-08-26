// Slackwater — GPL v3. M4: first-run location gate (prototype NearMe.dc.html),
// located list (My Location tile + Near Me by distance), settings, pin map.
// M1's list underneath; M53 gave the cards layout A — kind glyph, flat fill.
import CoreLocation
import SwiftUI
import TideEngine
import WidgetKit

@main
struct SlackwaterApp: App {
    init() {
        // Must run BEFORE anything touches FavoritesStore/RecentsStore/
        // ChsFitService: AppGroup.defaults itself no longer migrates on first
        // touch (B2) — an appex process can be the very first reader of the
        // shared suite on a fresh install, and migrating on that read would
        // burn the app's own standard-defaults history the appex never had.
        AppGroup.migrateIfNeeded(into: AppGroup.defaults, from: .standard)
        // The widget-reload hook (ChsStation.swift's `WidgetReload`): a no-op
        // until the app assigns it, so the widget extension — which also
        // compiles ChsModelStore.save — never triggers its own reload.
        WidgetReload.trigger = { WidgetCenter.shared.reloadAllTimelines() }
        // UI-test hooks, like -chsResetModels: -resetGate forces the first-run
        // gate; -seedGate skips it (arguments-domain values would mask the
        // in-app write, so tests set persisted state explicitly instead).
        if CommandLine.arguments.contains("-resetGate") {
            UserDefaults.standard.removeObject(forKey: seenGateKey)
        }
        if CommandLine.arguments.contains("-seedGate") {
            UserDefaults.standard.set(true, forKey: seenGateKey)
        }
        // -seedTideModel <id> (UserDefaults argument domain): writes a
        // synthetic fitted model for one bundled CHS tide port, so a derived
        // gate whose reference it is (Malibu Rapids ← Point Atkinson) renders
        // its detail offline in the fast plan. Opposite ordering trap to
        // -seedOnlineWindow below: ChsFitService.shared's init reads the model
        // directory ONCE into `tideRecords`, so this seed must be on disk
        // BEFORE anything touches `.shared` — and never combined with
        // -chsResetModels, whose wipe runs inside that same later init and
        // would delete the seed. The hook wipes the store itself instead.
        if let id = UserDefaults.standard.string(forKey: "seedTideModel") {
            seedTideModel(stationID: id)
        }
        // -seedOnlineWindow <id> (UserDefaults argument domain): writes a
        // fetched-looking ChsOnlineWindow for one of the 7 online (fit-reject)
        // gates, so a UI test can land on OnlineGateDetailView's fetched
        // single-track detail with no network.
        if let id = UserDefaults.standard.string(forKey: "seedOnlineWindow") {
            // Trap: ChsFitService.shared's own init calls
            // ChsModelStore.resetIfRequested(), which wipes ChsModelStore.dir
            // — the same directory the seed file below lands in. `shared` is a
            // lazy `static let`, so if nothing has touched it yet, its init
            // (and the wipe) fires the first time something does — e.g. the
            // list view's `.task` — which would run AFTER this seed write and
            // silently delete it. Touch `.shared` now so the one-time
            // init/reset happens before the write, never after.
            _ = ChsFitService.shared
            seedOnlineWindow(stationID: id)
        }
        // -seedOnlineFarWindow <id>: same trap, same fix — a second, DISJOINT
        // seeded block (#67 item 4) for the hermetic two-block UI proof.
        if let id = UserDefaults.standard.string(forKey: "seedOnlineFarWindow") {
            _ = ChsFitService.shared
            seedOnlineFarWindow(stationID: id)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// UI-test hook (SlackwaterApp.init's `-seedTideModel <id>`): a plausible
/// M2+K1 harmonic model for one bundled CHS tide port, stored as if fitted on
/// this device — the reference-port fit a derived gate's slacks derive from,
/// with no network (issue #38; the synthetic-constituents idea is PR #77's
/// `-seedGateModels`). Amplitudes/offset are Point-Atkinson-ish metres; any
/// plausible shape gives TideEngine real highs and lows to lag into slacks.
/// Wipes the model store AND the chunk store first, so the seed is the WHOLE
/// state `ChsFitService.init` finds — determinism without `-chsResetModels`,
/// which this hook must never be combined with (see the init comment). The
/// chunk store matters as much as the model one: a leftover chunk from a
/// full-plan run lets the derived gate render off cached CHS predictions
/// instead of this fit, and the test then passes without exercising what it
/// names.
private func seedTideModel(stationID: String) {
    guard ChsStationInfo.all.contains(where: { $0.id == stationID }) else { return }
    try? FileManager.default.removeItem(at: ChsModelStore.dir)
    try? FileManager.default.removeItem(at: ChsChunkStore.dir)
    let now = appNow()
    let model = ChsModel(
        stationID: stationID, iwlsID: "seeded", iwlsName: "\(stationID) (seeded)",
        fittedAt: now, fitStartMs: (now.timeIntervalSince1970 - 60 * 86_400) * 1000,
        fitEndMs: now.timeIntervalSince1970 * 1000,
        offset: 3.0, rms: 0.05,
        constituents: [Con(name: "M2", amplitude: 1.5, phase: 0),
                       Con(name: "K1", amplitude: 0.9, phase: 90)])
    try? ChsModelStore.save(model)
}

/// UI-test hook (SlackwaterApp.init's `-seedOnlineWindow <id>`): writes a
/// synthetic `ChsOnlineWindow` covering exactly `Timeline.window(anchor:)`'s
/// span for today — the same definition `ChsFitService.fetchOnlineWindow` uses
/// for a real fetch (`covers`'s neighborhood, ChsCurrentGate.swift) — so
/// `OnlineGateDetailView` reads it as
/// current and renders the fetched detail on first launch, no network
/// involved. An M2-ish sine (12.42h period, ~2 kn amplitude) at 15-min samples
/// gives the strip real slacks and maxima to assert against, not a flat line.
///
/// `-chsResetModels` (ChsStation.swift) already clears this file too: it
/// removes the whole `ChsModelStore.dir`, the same directory `-online.json`
/// files live in beside the fitted `.json`/`-current.json` ones
/// (`ChsModelStore.onlineUrl`) — nothing extra to wipe there.
private func seedOnlineWindow(stationID: String) {
    seedOnline(stationID: stationID, offsetDays: nil, spanDays: nil)
}

/// UI-test hook (SlackwaterApp.init's `-seedOnlineFarWindow <id>`): like
/// `seedOnlineWindow`, but a DISJOINT far block — [today+30d, today+85d],
/// wide enough that "two months out, cell 10" in the picker always lands a
/// whole strip inside it, and far enough that it can never merge with
/// today's block. Written through `saveOnline` so the test exercises the
/// real disjoint-save path (#67 item 4).
private func seedOnlineFarWindow(stationID: String) {
    seedOnline(stationID: stationID, offsetDays: 30, spanDays: 55)
}

/// nil offset = today's real window (`Timeline.window(anchor: today)`); an
/// offset seeds [today+offset, today+offset+span] instead.
private func seedOnline(stationID: String, offsetDays: Double?, spanDays: Double?) {
    guard let gate = ChsCurrentGateInfo.all.first(where: { $0.id == stationID }) else { return }
    let today = todayLocal(gate.tz)
    let start: Date, end: Date
    if let offsetDays, let spanDays {
        start = today.addingTimeInterval(offsetDays * 86_400)
        end = start.addingTimeInterval(spanDays * 86_400)
    } else {
        let w = Timeline.window(anchor: today)
        start = w.start; end = w.end
    }
    let period = 12.42 * 3600.0   // M2 tidal period, seconds
    let amplitude = 2.0           // kn
    var times: [Double] = []
    var speeds: [Double] = []
    var t = start
    while t <= end {
        times.append(t.timeIntervalSince1970)
        speeds.append(amplitude * sin(2 * .pi * t.timeIntervalSince(start) / period))
        t = t.addingTimeInterval(900)  // 15-min official-sample cadence
    }
    let window = ChsOnlineWindow(
        stationID: gate.id, iwlsName: "\(gate.name) (seeded)", timezone: gate.timezone,
        fetchedAt: appNow(), start: start, end: end,
        floodDirection: 0, ebbDirection: 180, times: times, speeds: speeds)
    // `_ =` because `try?` re-wraps the merged window `saveOnline` now returns,
    // and @discardableResult doesn't survive the Optional.
    _ = try? ChsModelStore.saveOnline(window)
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
            CanvasBackground()
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
                                colors: SN.gateTile,
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 96, height: 96)
                            .shadow(color: SN.shadow.opacity(0.4), radius: 20, y: 16)
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
    @State private var showWidgetsGallery = false
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    // -openMap: launch straight into the map (manual offline verification hook).
    @State private var showMap = CommandLine.arguments.contains("-openMap")
    /// One-shot: set by the map-header title tap (issue #32), read by
    /// `mapPane` as a camera override, then cleared by `.onAppear`. The next
    /// fix landing or user pan owns the camera after that.
    @State private var mapFocus: StationItem?
    /// Bumped on every focus tap and used as `mapPane`'s `.id`, so a focus
    /// always REMOUNTS the map — even on the pin-tap path where `showMap` is
    /// already true and the map instance would otherwise survive the
    /// push/pop. Distinct from the coordinate so re-focusing the SAME
    /// station twice still counts.
    @State private var mapFocusToken = 0
    /// The currents-fill map switch (graduation spec §2) — stored under the
    /// same key `currentFillEnabled` reads, so the style builders and this
    /// toggle can never disagree.
    @AppStorage(currentFillKey) private var showFill = true
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @AppStorage(AppGroup.slackWindowSpeedKey, store: AppGroup.defaults)
    private var slackWindowSpeed = defaultSlackThresholdKn
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
    private var openMapFocused: (StationItem) -> Void {
        { item in
            mapFocus = item
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
        // Fifth-pass evidence (task-9): a pushed destination doesn't reliably
        // inherit environment attached to the NavigationStack itself when that
        // stack is NavigationSplitView's `detail:` column — attaching there
        // left `TideAtPortLink`'s `openTide` reading the default no-op on
        // iPad, tap included, in a live-logged repro. Attached here instead,
        // above BOTH layouts, delivery rides ordinary ancestor inheritance —
        // and there's exactly one attachment, so the two layouts can't drift.
        .environment(\.openTideDetail) { path.append($0) }
        // Same reasoning, same attachment point — every CHS push (an online
        // gate's honesty card, a Downloads-sheet row) rides this one closure,
        // never a NavigationLink (OpenChsRouteKey doc comment, Theme.swift).
        // Dismiss-then-append (OfflineManagerView's row tap) still lands here:
        // this appends to the ROOT stack's path regardless of which presented
        // sheet or pushed screen the tap came from, so a detail that opened
        // the sheet stays under the newly pushed route on the back stack —
        // correct behavior, not a side effect to work around.
        .environment(\.openChsRoute, openChsRoute)
        // Same attachment point, same reasoning — the map-header title lives
        // inside a pushed detail in both layouts, so ordinary ancestor
        // inheritance from here is enough; no `.sheet` re-forward needed
        // because MapHeader never appears inside Settings or Downloads.
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
        // The app's first URL scheme (project.yml CFBundleURLTypes). Widgets
        // emit both routes: locked accessory widgets → premium (Task 6), home
        // widgets and the free ones' deepLink → station/<id> (HomeWidgets.swift).
        .onOpenURL { url in
            guard url.scheme == "slackwater" else { return }
            switch url.host {
            case "premium": showWidgetsGallery = true
            case "station":
                let id = url.pathComponents.dropFirst().first ?? ""
                if let item = StationItem.byId[id] { open(item) }
            default: break
            }
        }
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
        }
        // First connected launch: the auto-fit set around where this list is
        // ranked downloads in the background, nearest-first, and the nearby
        // online gates prefetch (M53 budget, `ChsFitService.autoFitSet` /
        // `autoPrefetchGates`). Partial failure retries from the manager or
        // the next launch.
        //
        // `anchor`, not `fix` (#178): the list ranks from `rankingAnchor` —
        // fix, then last-opened, then Victoria — but this used to adopt only
        // on a live fix, so a user who denied location, or whose fix had not
        // landed yet, got a Near Me list ranked around one place and a
        // download set built around another. Every row on the first screen
        // then read "Tap to download". `adopt` is accretive and `prioritize`
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
    /// moved to the floating button (M4.5) — no top bar.
    private var listPane: some View {
            ZStack {
                CanvasBackground()
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
        // `mapFocus` wins when set (header-title tap, issue #32): centers on
        // that station at its own detail zoom rather than the fix/discovery
        // camera. `.id(mapFocusToken)` forces a remount on every focus, so
        // `makeUIView` handles the camera even on the pin-tap path where the
        // pane is already mounted (`showMap` stayed true across the push/pop).
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
                    ?? mapFocus.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    ?? fix.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    ?? RecentsStore.shared.lastOpened.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                    // SALISH_CENTER only survives to here on a genuine first
                    // run: no fix, nothing ever opened.
                    ?? SALISH_CENTER,
                zoom: mapFocus == nil ? discoveryZoom : stationZoom
            ) { item in
                if regular { showMap = false }  // the detail pane shows the pick
                open(item)
            }
            // The fill toggle joins the remount key: flipping it rebuilds the
            // style, which is how the layer appears/disappears — rare, user
            // -initiated, and far simpler than mutating a live style.
            .id("\(mapFocusToken)-\(showFill)-\(slackWindowSpeed)")
            .accessibilityIdentifier("map-canvas")
            // Consumed once: the next appearance of this pane (fab toggle, a
            // fresh pick) starts from the fix/discovery camera again, not a
            // stale focus from a station visited an hour ago.
            .onAppear { mapFocus = nil }
            .ignoresSafeArea()

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
                .background(SN.canvas.opacity(0.82), in: Capsule())
                .accessibilityIdentifier("map-disclaimer")
                .padding(.bottom, Self.fabBarBottomPadding)   // the FAB row's own baseline
        }
        .background(SN.canvas.ignoresSafeArea())
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
            unavailableCard.padding(.top, 14)  // ChsAmberCard brings its own horizontal inset
        }

        // Favorites: starred stations, insertion order (spec §9 swipe-to-manage).
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
                        // Spec §9: remove re-files to Recents — neutral tint, no
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

        sectionLabel("Near Me")
        // The wedge is currents, and an empty currents list reads as "the
        // water is slack" unless it's stated otherwise (T6). A per-card check
        // (does a current item happen to rank into the visible top-4/5) would
        // still misfire inside real coverage: dense CHS tide-station clusters
        // alone (not the new worldwide stations — verified across 10 Salish
        // Sea anchors) crowd every slot in 2 of 10 cases, e.g. Sidney BC and
        // Desolation Sound. So this checks the current bundle directly against
        // the anchor, once, independent of what happened to rank into view.
        if !hasCurrentCoverage(latitude: anchor.lat, longitude: anchor.lon) {
            CardStatusStrip(status: .noCurrentCoverage)
                .padding(.horizontal, 26)
                .padding(.bottom, 8)
        }
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
            BranchLink(text: "\(matches.count) matching stations",
                       id: "matching-stations", chevron: false) {
                chooser = StationMatches(place: item.name, matches: matches)
            }
            .padding(.horizontal, 18)
            .padding(.top, 7)
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
        Array(StationItem.all
            .sorted { $0.km(fromLat: origin.lat, lon: origin.lon)
                    < $1.km(fromLat: origin.lat, lon: origin.lon) }
            .prefix(5))
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
            // Beside the list toggle, not centered — bottom-center belongs to
            // the "Not for navigation" pill.
            if showMap {
                fab(showFill ? "water.waves" : "water.waves.slash",
                    label: showFill ? "Hide currents" : "Show currents") { showFill.toggle() }
                    .accessibilityIdentifier("currents-toggle")
                    .padding(.trailing, 12)
            }
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
                .shadow(color: SN.shadow.opacity(0.4), radius: 10, y: 6)
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
            CanvasBackground()
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
/// arrow and, opposite it, the fix coordinates in mono (NearMe.dc.html
/// fmtCoord — 3 decimal places), over the nearest station's ordinary card
/// (distance rendered in its own identity column, layout A — same as every
/// other card).
///
/// The coordinates shared the eyebrow's row from #42. On their own line under
/// the card they bought a full row of tile height for one short mono string,
/// and left the eyebrow row half-empty above it — the card ended up sandwiched
/// in padding that encoded nothing.
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
            .padding(.horizontal, 6)
            card(item)
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
    /// Set when the chooser is offering a replacement for a favorite whose
    /// station left the bundle (issue #91): the dead id to swap out, and the
    /// position the distances are measured from — where that station *was*,
    /// not where the user is. A dead Haida Gwaii favorite offering Victoria
    /// stations because that is where the phone happens to be is not an offer.
    /// A struct rather than the tuple it wants to be: tuples aren't Hashable,
    /// and this type is.
    struct Removed: Hashable {
        let id: String
        let lat: Double
        let lon: Double
    }
    var replacing: Removed? = nil
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
    // Same glyph-in-slot sizing RecentRowLabel carries (issue #14): the glyph
    // scales with type, the slot scales with it so it can't overflow the row.

    var body: some View {
        ZStack {
            CanvasBackground()
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

/// The compact recent-station row body: name over region, current reading
/// trailing in Fraunces. No kind mark — it came off these rows with the cards',
/// for the same reason (the wave and the dome are not universal symbols), and
/// a row that kept one beside cards that dropped theirs would read as a
/// distinction that isn't there.
struct RecentRowLabel: View {
    let item: StationItem
    let imperial: Bool
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    // Cache the engine state, format in body — unit switches re-render live.
    // Still the whole card state and not just the number: `reading` needs the
    // slack test and the phase word, which the bare value doesn't carry.
    @State private var tide: CardState?
    @State private var current: CurrentCardState?
    @State private var gate: DerivedGateCardState?  // derived gate: phase word, never a speed
    var body: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        if let gate { return gate.phase.word.lowercased() }
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

    var body: some View {
        StationCard(name: record.name, region: record.region, km: km,
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
            pending(fitting: true)
        case .pending:
            pending()
        case .failed:
            pending(failed: true)
        }
    }

    private func pending(fitting: Bool = false, failed: Bool = false) -> ChsPendingCard {
        ChsPendingCard(name: info.name, region: info.region, id: info.id, km: km,
                       status: cardStatus(id: info.id, fitting: fitting, failed: failed))
    }
}

/// The not-yet-fitted CHS shell: identity + one status strip, no numbers
/// (chs-online spec §7c). Shared by the tide ports and the derived gates —
/// a gate is pending exactly while its reference port is.
struct ChsPendingCard: View {
    let name: String
    let region: String
    let id: String
    var km: Double? = nil
    let status: CardStatus

    var body: some View {
        StationCard(name: name, region: region, km: km,
                    status: status,
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
            pending(fitting: true)
        case .pending:
            pending()
        case .failed:
            pending(failed: true)
        }
    }

    /// A derived gate waits on its reference PORT's tidal download.
    private func pending(fitting: Bool = false, failed: Bool = false) -> ChsPendingCard {
        ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, km: km,
                       status: cardStatus(id: gate.reference, fitting: fitting, failed: failed))
    }

    private func fittedCard(_ record: DerivedGateRecord) -> some View {
        StationCard(name: gate.name, region: gate.region, km: km,
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
    /// Only ever read for an online gate — a fitted gate never touches this.
    @State private var onlineStore: ChsOnlineStore?

    var body: some View {
        // Navigation comes from the enclosing row's hidden link (itemCard).
        Group {
            if gate.isOnline {
                onlineCard
            } else {
                switch service.currentState(gate.id) {
                case .fitted(let record):
                    CurrentCardView(record: record, km: km,
                                    provisional: service.isProvisional(gate.id) ? gate : nil)
                case .fitting:
                    pending(fitting: true)
                case .pending:
                    pending()
                case .failed:
                    pending(failed: true)
                }
            }
        }
        .task { refreshOnlineWindow() }
        // The fitted path re-renders off `service.currentRecords` (the
        // `@ObservedObject` above) the moment a fit lands. An online gate's
        // data isn't in that dictionary — it's a disk read — so without this
        // the row stayed on its stale `.task`-time read: opening the gate's
        // detail (which fetches, saves, and pops back to this same
        // still-mounted row) never re-fired `.task`, and the card sat on
        // "fetched when connected" after the fetch had already landed.
        // `onlineFetchStamp` is the same "something changed, reload" signal
        // for the online-gate seam that `currentRecords` already is for the
        // fitted one.
        .onReceive(service.$onlineFetchStamp) { _ in refreshOnlineWindow() }
    }

    private func refreshOnlineWindow() {
        guard gate.isOnline else { return }
        onlineStore = ChsModelStore.loadOnline(gate.id)
    }

    private func pending(fitting: Bool = false, failed: Bool = false) -> ChsPendingCard {
        ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, km: km,
                       status: cardStatus(id: gate.id, fitting: fitting, failed: failed))
    }

    /// The 7 online gates (online-gates spec §4): a covering fetched window
    /// reads like any other current card; without one, the pending shell
    /// carries the strip `onlineGateStatus` picks — never a queue status this
    /// gate can't be in.
    @ViewBuilder private var onlineCard: some View {
        let today = todayLocal(gate.tz)
        if let block = onlineStore?.block(covering: today) {
            OnlineGateCardView(gate: gate, window: block, km: km)
        } else {
            // Never fetched and fetched-but-run-out are different states, and
            // this path used to print one string for both (#93):
            // `onlineGateStatus` only null-checks `blocks.last` — nil is the
            // former (.notDownloaded), non-nil is the latter (.expired); it
            // doesn't read the block's own covered-to date.
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, km: km,
                           status: onlineGateStatus(onlineStore?.blocks.last, online: net.online))
        }
    }
}

/// An online gate's list card with a covering fetched window: same shell and
/// reading treatment as `CurrentCardView`, off `ChsOnlineWindow.cardState`
/// instead of a `CurrentStationRecord` — this gate has no harmonic model to
/// build one from.
struct OnlineGateCardView: View {
    let gate: ChsCurrentGateInfo
    let window: ChsOnlineWindow
    var km: Double? = nil
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"

    private var state: CurrentCardState { window.cardState(at: appNow()) }

    var body: some View {
        let state = state
        StationCard(name: gate.name, region: gate.region, km: km,
                    detail: state.next.map { nextLine($0) }) {
            if currentPhase(signed: state.signed) == .slack {
                Text("SLACK")
                    .font(.caption2.monospaced().weight(.medium)).tracking(1)
                    .foregroundStyle(SN.navyDeep)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(SN.go, in: Capsule())
            } else {
                (Text(formatSpeed(abs(state.signed), unit: speedUnit))
                    .font(.largeTitle.monospacedDigit())
                 + Text(" \(speedUnitLabel(speedUnit))")
                    .font(.body))
                    .foregroundStyle(.white)
                // Direction-first (#59): a novice reads the arrow + cardinal;
                // the flood/ebb word demotes to a dimmer label. Kept as its
                // own Text — the screenshot tests match its exact label.
                let deg = state.signed >= 0 ? window.floodDirection : window.ebbDirection
                HStack(spacing: 4) {
                    CompassArrow(deg: deg).font(.caption2)
                    Text(compass16(deg)).font(.caption2)
                    Text(currentPhase(signed: state.signed).word).font(.caption2)
                        .foregroundStyle(SN.foam.opacity(0.6))
                }
                .foregroundStyle(SN.foam.opacity(0.9))
            }
        }
    }

    private func nextLine(_ next: CurrentEvent) -> String {
        let when = cardTime(next.time, gate.tz)
        return next.kind == .slack
            ? "Slack · \(when)"
            : "\(next.turnLabel) \(formatSpeed(abs(next.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit)) · \(when)"
    }
}

/// The current-station card: same layout-A shell, but the reading is signed
/// velocity — speed + set arrow + Flooding/Ebbing, a Slack pill at slack, and
/// the next slack/max as the detail line (web StationCard's current layout).
struct CurrentCardView: View {
    let record: CurrentStationRecord
    var km: Double? = nil
    /// Set while this gate is showing its 60-day fast answer. On the LIST card
    /// that is the amber "Refining" strip and a `~` on the readings — nothing
    /// else. The strip replaced M52's ⚠️ badge beside the region (#93): one
    /// marking per state, and this one can carry the gate's own tolerance,
    /// which the badge could only gesture at. The full explanation still lives
    /// on the detail view's amber card.
    var provisional: ChsCurrentGateInfo? = nil
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @State private var state: CurrentCardState?

    /// nil tolerance rather than the "±0 min" `provisionalTolerance` prints:
    /// a gate that never offered a fast answer has no measured number to show.
    private var status: CardStatus? {
        provisional.map {
            .refining(tolerance: $0.provisionalSlackMinutes == nil ? nil : $0.provisionalTolerance)
        }
    }

    /// The tilde stays: at normal card contrast "~5.8" reads cleanly, and it is
    /// the one part of the old treatment that marked the NUMBER rather than
    /// shouting around it.
    private var tilde: String { provisional == nil ? "" : "~" }

    var body: some View {
        StationCard(name: record.name, region: record.region, km: km,
                    detail: state?.next.map { nextLine($0) },
                    status: status) {
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
                    // Direction-first (#59) — same treatment as
                    // OnlineGateCardView's, see the comment there.
                    let deg = record.setDegrees(signed: state.signed)
                    HStack(spacing: 4) {
                        CompassArrow(deg: deg).font(.caption2)
                        Text(compass16(deg)).font(.caption2)
                        Text(phase.word).font(.caption2)
                            .foregroundStyle(SN.foam.opacity(0.6))
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
