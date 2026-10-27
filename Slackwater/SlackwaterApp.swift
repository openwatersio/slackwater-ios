// Slackwater — GPL v3. App entry: one-time migration and widget-reload hookup,
// then the station list.
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
        // Loading the stores moves saved ids whose station left the bundle to
        // its successor (StationSuccessors), so the first frame and the
        // alert scheduler only ever see ids that ship.
        _ = FavoritesStore.shared
        _ = RecentsStore.shared
        Task.detached(priority: .utility) { SlackwaterShortcuts.updateAppShortcutParameters() }
        _ = ChsModelTransfer.shared
        // The widget-reload hook (ChsStation.swift's `WidgetReload`): a no-op
        // until the app assigns it, so the widget extension — which also
        // compiles ChsModelStore.save — never triggers its own reload.
        // Every CHS model save funnels through this hook, and a newly fitted station can
        // make a waiting alert schedulable (docs/alerts.md §6).
        WidgetReload.trigger = {
            WidgetCenter.shared.reloadAllTimelines()
            AlertScheduler.requestReschedule()
        }
        _ = UnitsCloud.shared
        AlertRuleStore.shared.onChange = { AlertScheduler.requestReschedule() }
        StationCalendarStore.shared.onChange = { AlertScheduler.requestReschedule() }
        // Before launch finishes, so a tap that cold-launches the app is delivered.
        UNUserNotificationCenter.current().delegate = AlertNotificationDelegate.shared
        // Chart packs download whether or not the map is ever opened.
        DispatchQueue.main.async { ChartPackManager.shared.start(styleURL: BASEMAP_STYLE_URL) }
        #if DEBUG
        applySeedHooksIfRequested()
        if uiTestQuiet { UIView.setAnimationsEnabled(false) }
        #endif
        // Must come after the seed hooks above: `-resetTour`/`-seedTour`
        // write `seenTourKey`, and `arm()` reads it.
        TourCoach.shared.arm()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                // The SwiftUI half of `-uiTestQuiet`: `setAnimationsEnabled`
                // above governs UIKit's own transitions, not SwiftUI's.
                .transaction { @Sendable in if uiTestQuiet { $0.disablesAnimations = true } }
        }
    }
}

/// `-uiTestQuiet`: the app under XCUITest runs with no animations at all.
///
/// XCUITest waits for the app to report its animations complete before every
/// synthesized event and every query, and gives up after 60 s. On hosted
/// runners that notification stopped arriving once a CHS download was in
/// flight, and the whole suite then measured the timeout instead of the app
/// (#556): six consecutive 60 s waits in one test, each ending in "App
/// animations complete notification not received", while finds and hierarchy
/// snapshots in between stayed at a tenth of a second and the screen recording
/// held a single unchanging frame. An app with no animations has none to
/// finish, which covers every animation the app grows later as well.
///
/// Debug builds only, and never on the screenshot walks, which shoot the app
/// as users see it.
let uiTestQuiet: Bool = {
#if DEBUG
    return CommandLine.arguments.contains("-uiTestQuiet")
#else
    return false
#endif
}()

/// The station list, and the scene-level refreshes that ride on it.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        StationListView()
        // The refresh that survives a flight. `.onAppear` fires once per view
        // lifetime, and re-activating a backgrounded scene does not re-appear
        // a view that is already on screen, so the list's own `.onAppear` only
        // covers a cold launch — a phone carried to another city needs this to
        // stop ranking Near Me around where it took off from. It does not
        // replace that `.onAppear`: `.onChange` is not guaranteed to observe
        // the launch transition into `.active`. `refreshIfAuthorized` never
        // prompts and no-ops when unauthorized, so the overlap costs one
        // coalesced `requestLocation`.
        .onChange(of: scenePhase) { _, phase in
            Task.detached(priority: .utility) { SlackwaterShortcuts.updateAppShortcutParameters() }
            if phase == .active {
                LocationService.shared.refreshIfAuthorized()
                ChsFitService.shared.resumeForForeground()
                // Tops up the notification horizon and picks up permission changes made in Settings.
                AlertScheduler.requestReschedule()
            }
        }
        // `.onChange` is not guaranteed to see the launch transition into `.active`.
        .task { AlertScheduler.requestReschedule() }
    }
}
