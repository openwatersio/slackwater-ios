// Slackwater — GPL v3. App entry: one-time migration and widget-reload hookup,
// then the root switch between the first-run gate and the station list.
import SwiftUI
import UserNotifications
import WidgetKit

@main
struct SlackwaterApp: App {
    init() {
        // Must run BEFORE anything touches FavoritesStore/RecentsStore/
        // ChsFitService: AppGroup.defaults itself never migrates on first
        // touch — an appex process can be the very first reader of the
        // shared suite on a fresh install, and migrating on that read would
        // burn the app's own standard-defaults history the appex never had.
        AppGroup.migrateIfNeeded(into: AppGroup.defaults, from: .standard)
        // The widget-reload hook (ChsStation.swift's `WidgetReload`): a no-op
        // until the app assigns it, so the widget extension — which also
        // compiles ChsModelStore.save — never triggers its own reload.
        // Every CHS model save funnels through this hook, and a newly fitted station can
        // make a waiting alert schedulable (notifications spec §6).
        WidgetReload.trigger = {
            WidgetCenter.shared.reloadAllTimelines()
            AlertScheduler.requestReschedule()
        }
        AlertRuleStore.shared.onChange = { AlertScheduler.requestReschedule() }
        // Before launch finishes, so a tap that cold-launches the app is delivered.
        UNUserNotificationCenter.current().delegate = AlertNotificationDelegate.shared
        // Chart packs download whether or not the map is ever opened.
        DispatchQueue.main.async { ChartPackManager.shared.start(styleURL: BASEMAP_STYLE_URL) }
        #if DEBUG
        applySeedHooksIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Gate until a choice is made; list ever after.
struct RootView: View {
    @AppStorage(seenGateKey) private var seenGate = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if seenGate {
                StationListView()
            } else {
                GateView()
            }
        }
        // The refresh that survives a flight. `.onAppear` fires once per view
        // lifetime, and re-activating a backgrounded scene does not re-appear
        // a view that is already on screen, so the list's own `.onAppear` only
        // covers a cold launch — a phone carried to another city needs this to
        // stop ranking Near Me around where it took off from. It sits here
        // rather than on the list so the gate gets it too, and does not replace
        // that `.onAppear`: `.onChange` is not guaranteed to observe the launch
        // transition into `.active`. `refreshIfAuthorized` never prompts and
        // no-ops when unauthorized, so the overlap costs one coalesced
        // `requestLocation`.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                LocationService.shared.refreshIfAuthorized()
                // Tops up the notification horizon and picks up permission changes made in Settings.
                AlertScheduler.requestReschedule()
            }
        }
        // `.onChange` is not guaranteed to see the launch transition into `.active`.
        .task { AlertScheduler.requestReschedule() }
        // A widget can be added from the gallery before the app is ever
        // opened, so a station link can arrive while the gate is still up —
        // and the handler that acts on it lives in the list, which does not
        // exist yet, so the URL would land on nothing. A link IS a station
        // chosen, which is the only thing the gate asks: resolve it and hand
        // the URL to the list's first appear, the handoff `gateSearchHandoff`
        // already rides. Past the gate this does nothing and the list's own
        // handler takes the URL directly.
        .onOpenURL { url in
            guard !seenGate else { return }
            // A universal link can arrive on a device that has never opened the
            // app - that is the ordinary case for a link someone was sent, not
            // an edge one - so it needs the same pre-gate handoff the widget's
            // scheme already gets. Both are a station chosen, which is the only
            // thing the gate asks.
            let isStationLink = stationLink(from: url) != nil
            guard isStationLink || (url.scheme == "slackwater" && url.host == "station") else { return }
            pendingDeepLink = url
            seenGate = true
        }
    }
}
