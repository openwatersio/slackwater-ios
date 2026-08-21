// Slackwater — GPL v3. The App Group shared by the app and the widget
// extension: shared UserDefaults (favorites, recents, premium flag) and the
// shared container (CHS fitted models). One-time migration from the
// pre-widget standard-defaults/App-Support locations.
import Foundation

enum AppGroup {
    static let id = "group.org.openwaters.slackwater"

    static let defaults: UserDefaults = {
        let d = UserDefaults(suiteName: id) ?? .standard
        migrateIfNeeded(into: d, from: .standard)
        return d
    }()

    /// Shared container; falls back to App Support so unit tests (no
    /// provisioned group) still get a real directory.
    static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask)[0]
    }

    private static let migratedKey = "slackwater.appgroup.migrated"

    static func migrateIfNeeded(into d: UserDefaults, from standard: UserDefaults) {
        guard !d.bool(forKey: migratedKey) else { return }
        for key in ["slackwater.favorites", "slackwater.recents"] {
            if d.object(forKey: key) == nil, let v = standard.stringArray(forKey: key) {
                d.set(v, forKey: key)
            }
        }
        d.set(true, forKey: migratedKey)
    }
}
