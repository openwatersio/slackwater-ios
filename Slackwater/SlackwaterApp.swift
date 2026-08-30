// Slackwater — GPL v3. App entry: one-time migration and widget-reload hookup,
// then the root switch between the first-run gate and the station list.
import SwiftUI
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
        WidgetReload.trigger = { WidgetCenter.shared.reloadAllTimelines() }
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

    var body: some View {
        Group {
            if seenGate {
                StationListView()
            } else {
                GateView()
            }
        }
        // A widget can be added from the gallery before the app is ever
        // opened, so a station link can arrive while the gate is still up —
        // and the handler that acts on it lives in the list, which does not
        // exist yet, so the URL would land on nothing. A link IS a station
        // chosen, which is the only thing the gate asks: resolve it and hand
        // the URL to the list's first appear, the handoff `gateSearchHandoff`
        // already rides. Past the gate this does nothing and the list's own
        // handler takes the URL directly.
        .onOpenURL { url in
            guard !seenGate, url.scheme == "slackwater", url.host == "station" else { return }
            pendingDeepLink = url
            seenGate = true
        }
    }
}
