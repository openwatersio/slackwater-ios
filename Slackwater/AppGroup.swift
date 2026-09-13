// Slackwater — GPL v3. The App Group shared by the app and the widget
// extension: shared UserDefaults (favorites, recents, premium flag) and the
// shared container (CHS fitted models). One-time migration from the
// pre-widget standard-defaults/App-Support locations.
import Foundation

enum AppGroup {
    static let id = "group.org.openwaters.slackwater"

    /// The shared suite, with NO migration side effect — touching this must
    /// be safe from either process regardless of which one runs first. A
    /// widget-extension process is not guaranteed to run after the app has
    /// ever launched (the appex can be the first process on a freshly
    /// installed device to read this), so migration is the caller's job:
    /// `SlackwaterApp.init()` runs `migrateIfNeeded` explicitly, first thing,
    /// before anything touches FavoritesStore/RecentsStore/ChsFitService.
    static let defaults: UserDefaults = {
        guard let d = UserDefaults(suiteName: id) else {
            #if DEBUG
            assertionFailure("App Group suite unavailable — widget will not see shared state")
            #endif
            return .standard
        }
        return d
    }()

    /// Shared container; falls back to App Support so unit tests (no
    /// provisioned group) still get a real directory.
    static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask)[0]
    }

    static let favoritesKey = "slackwater.favorites"
    static let recentsKey = "slackwater.recents"
    static let currentLocationStationKey = "slackwater.currentLocationStation"
    static let currentLocationStationID = "slackwater:current-location"
    // The series-narrowed siblings of Current Location: synthetic picker
    // entries that follow the fix but resolve to the nearest station OF THAT
    // SERIES. Cached alongside the any-series id on every fix
    // (LocationService.cacheNearestWidgetStation), resolved in
    // WidgetStationLoader.resolvedStationID.
    static let nearestTideStationKey = "slackwater.nearestTideStation"
    static let nearestTideStationID = "slackwater:nearest-tide"
    static let nearestCurrentStationKey = "slackwater.nearestCurrentStation"
    static let nearestCurrentStationID = "slackwater:nearest-current"
    static let premiumKey = "slackwater.premium"
    static let slackWindowSpeedKey = "slackwater.slackWindowSpeedKn"
    /// Alert rules (notifications spec §3): JSON, device-local — two devices holding one
    /// rule would each deliver it.
    static let alertRulesKey = "slackwater.alertRules"
    /// The identifier of the "Slackwater" calendar the app created (notifications spec §5.1).
    static let alertCalendarKey = "slackwater.alertCalendar"

    private static let migratedKey = "slackwater.appgroup.migrated"
    private static let arrayKeys = [favoritesKey, recentsKey]
    /// String-valued settings (Units.swift) that predate the App Group too —
    /// same migration, different UserDefaults accessor since they're not
    /// arrays.
    private static let stringKeys = [unitsKey, speedUnitKey]

    static func migrateIfNeeded(into d: UserDefaults, from standard: UserDefaults) {
        guard !d.bool(forKey: migratedKey) else { return }
        for key in arrayKeys {
            if d.object(forKey: key) == nil, let v = standard.stringArray(forKey: key) {
                d.set(v, forKey: key)
            }
        }
        for key in stringKeys {
            if d.object(forKey: key) == nil, let v = standard.object(forKey: key) {
                d.set(v, forKey: key)
            }
        }
        d.set(true, forKey: migratedKey)
    }
}
