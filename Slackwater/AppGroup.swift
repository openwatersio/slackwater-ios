// Slackwater — GPL v3. The App Group shared by the app and the widget
// extension: shared UserDefaults (favorites, recents, premium flag) and the
// shared container (CHS fitted models). One-time migration from the
// pre-widget standard-defaults/App-Support locations.
import Foundation

enum AppGroup {
    static let id = "group.io.openwaters.slackwater"

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
    static let premiumKey = "slackwater.premium"
    static let slackWindowSpeedKey = "slackwater.slackWindowSpeedKn"

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
