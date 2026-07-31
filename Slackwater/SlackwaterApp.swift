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

struct StationListView: View {
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var showSettings = false
    // -openMap: launch straight into the map (manual offline verification hook).
    @State private var showMap = CommandLine.arguments.contains("-openMap")
    @AppStorage(unitsKey) private var units = "imperial"
    @ObservedObject private var loc = LocationService.shared
    @ObservedObject private var recents = RecentsStore.shared

    private var imperial: Bool { units == "imperial" }
    /// The fix the list ranks by — only while authorized.
    private var fix: (lat: Double, lon: Double)? {
        guard loc.authorized, let l = loc.location else { return nil }
        return (l.coordinate.latitude, l.coordinate.longitude)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                RadialGradient(colors: [SN.canvasGlow, SN.canvas], center: .top,
                               startRadius: 0, endRadius: 500)
                    .ignoresSafeArea()
                ScrollView {
                    header
                    searchField
                    if query.isEmpty {
                        locatedSections
                    } else {
                        MonoLabel(text: "Results")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 26)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        LazyVStack(spacing: 12) {
                            ForEach(StationItem.search(query)) { item in
                                itemCard(item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 44)
                    }
                }
                mapButton
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TideStationRecord.self) { TideDetailView(record: $0) }
            .navigationDestination(for: CurrentStationRecord.self) { CurrentDetailView(record: $0) }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showMap) {
            MapScreen { item in
                showMap = false
                open(item)
            }
        }
        .onAppear { loc.refreshIfAuthorized() }
        // First connected launch: the Canadian Salish ports auto-fit in the
        // background (M3 — no region UX). Partial failure retries next launch.
        .task { ChsFitService.shared.fitPendingIfNeeded() }
    }

    /// Push a station picked outside the list (map pin tap).
    private func open(_ item: StationItem) {
        switch item {
        case .tide(let s): path.append(s)
        case .current(let s): path.append(s)
        case .chs(let info):
            if case .fitted(let record) = ChsFitService.shared.state(info.id) {
                path.append(record)
            }
        }
    }

    // The list (Bryan's regrouping of the prototype READY·LIST): My Location →
    // Recents → Near Me, nothing else — search is the discovery path for the
    // rest of the catalog. Without a fix the ranking anchors on the Victoria
    // fallback (prototype FALLBACK), and the My Location slot holds the amber
    // denied card when location is off.
    @ViewBuilder private var locatedSections: some View {
        let anchor = fix ?? fallbackFix
        let ranked = StationItem.all.sorted {
            $0.km(fromLat: anchor.lat, lon: anchor.lon) < $1.km(fromLat: anchor.lat, lon: anchor.lon)
        }

        // My Location slot: the hero tile, or the amber card in its place.
        if let fix, let nearest = ranked.first {
            MyLocationTile(item: nearest, fix: fix, imperial: imperial) { itemCard($0) }
                .padding(.horizontal, 16)
                .padding(.top, 14)
        } else if loc.denied {
            unavailableCard.padding(.horizontal, 16).padding(.top, 14)
        }

        // Recents: persisted recently-viewed stations, most recent first.
        let recentItems = recents.items
        if !recentItems.isEmpty {
            MonoLabel(text: "Recents")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(recentItems) { item in
                    recentRow(item)
                    if item.id != recentItems.last?.id {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
            }
            .background(Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(SN.leaf.opacity(0.2), lineWidth: 0.5))
            .padding(.horizontal, 16)
        }

        MonoLabel(text: "Near Me")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 4)
        // With a hero the nearest is already on screen — 4 more; without, 5.
        let nearMe = fix == nil ? Array(ranked.prefix(5)) : Array(ranked.dropFirst().prefix(4))
        LazyVStack(spacing: 12) {
            ForEach(nearMe) { item in
                itemCard(item)
                    .overlay(alignment: .topTrailing) {
                        DistancePill(km: item.km(fromLat: anchor.lat, lon: anchor.lon))
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 44)
    }

    /// A compact recently-viewed row (prototype recent rows: gradient chip,
    /// name over region), navigating like the full cards.
    @ViewBuilder private func recentRow(_ item: StationItem) -> some View {
        switch item {
        case .tide(let station):
            NavigationLink(value: station) { RecentRowLabel(item: item, imperial: imperial) }
                .buttonStyle(.plain)
        case .current(let station):
            NavigationLink(value: station) { RecentRowLabel(item: item, imperial: imperial) }
                .buttonStyle(.plain)
        case .chs(let info):
            if case .fitted(let record) = ChsFitService.shared.state(info.id) {
                NavigationLink(value: record) { RecentRowLabel(item: item, imperial: imperial) }
                    .buttonStyle(.plain)
            } else {
                RecentRowLabel(item: item, imperial: imperial)
            }
        }
    }

    @ViewBuilder private func itemCard(_ item: StationItem) -> some View {
        switch item {
        case .tide(let station):
            NavigationLink(value: station) {
                StationCardView(record: station, imperial: imperial)
            }
            .buttonStyle(.plain)
        case .current(let station):
            NavigationLink(value: station) {
                CurrentCardView(record: station)
            }
            .buttonStyle(.plain)
        case .chs(let info):
            ChsCardView(info: info, imperial: imperial)
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
        HStack(alignment: .bottom, spacing: 10) {
            Text("Slackwater")
                .font(.fraunces(36, .semibold))
                .foregroundStyle(SN.paper)
            Spacer()
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
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    /// List ⇄ map switch: bottom-right floating button (detail-view spec
    /// backlog #6; prototype toolbar).
    private var mapButton: some View {
        Button {
            showMap = true
        } label: {
            Image(systemName: "map")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(SN.foam)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: Circle())
                .background(Color(hex: 0x184870, opacity: 0.55), in: Circle())
                .overlay(Circle().strokeBorder(SN.leaf.opacity(0.3), lineWidth: 0.5))
                .shadow(color: Color(hex: 0x000C1E, opacity: 0.4), radius: 10, y: 6)
        }
        .accessibilityLabel("Map")
        .padding(.trailing, 16)
        .padding(.bottom, 24)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SN.foam.opacity(0.7))
            TextField("Harbor, bay, or channel", text: $query)
                .font(.geist(17))
                .foregroundStyle(SN.paper)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SN.foam.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(SN.leaf.opacity(0.25), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.top, 16)
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
    @State private var reading = ""

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
        .task { if reading.isEmpty { reading = currentReading() } }
    }

    private var rawId: String {
        if case .current(let s) = item { return s.id }
        return item.id
    }

    private func currentReading() -> String {
        switch item {
        case .tide(let s):
            let state = s.cardState(at: appNow())
            return "\(formatHeight(state.height, imperial: imperial)) \(heightUnit(imperial: imperial))"
        case .current(let s):
            let state = s.cardState(at: appNow())
            return currentPhase(signed: state.signed) == .slack
                ? "slack" : "\(formatSpeed(abs(state.signed))) kn"
        case .chs(let info):
            guard case .fitted(let record) = ChsFitService.shared.state(info.id) else { return "" }
            let state = record.cardState(at: appNow())
            return "\(formatHeight(state.height, imperial: imperial)) \(heightUnit(imperial: imperial))"
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

    var body: some View {
        switch service.state(info.id) {
        case .fitted(let record):
            NavigationLink(value: record) {
                StationCardView(record: record, imperial: imperial)
            }
            .buttonStyle(.plain)
        case .fitting:
            pendingCard("Fitting on this device from CHS predictions…")
        case .pending:
            pendingCard("Needs a moment of signal — Canadian stations fit once on this device, then work offline.")
        }
    }

    private func pendingCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)
                        .font(.fraunces(23, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(info.region)
                        .font(.geist(13))
                        .foregroundStyle(SN.foam.opacity(0.78))
                }
                Spacer(minLength: 8)
                MonoLabel(text: "CHS", size: 10, color: SN.foam.opacity(0.7))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            Text(message)
                .font(.geist(12))
                .foregroundStyle(SN.foam.opacity(0.85))
                .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(stationGradient(id: info.id))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: 0x001432, opacity: 0.24), radius: 12, y: 10)
        .opacity(0.82)  // visibly quieter than a station with numbers
    }
}

/// The current-station card: same 1a gradient shell, but the reading is signed
/// velocity — speed + set arrow + Flooding/Ebbing, a Slack pill at slack, and
/// the next slack/max as the detail line (web StationCard's current layout).
struct CurrentCardView: View {
    let record: CurrentStationRecord
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
                            (Text(formatSpeed(abs(state.signed)))
                                .font(.fraunces(42))
                             + Text(" kn")
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
            : "\(next.turnLabel) \(formatSpeed(abs(next.speed))) kn · \(when)"
    }
}
