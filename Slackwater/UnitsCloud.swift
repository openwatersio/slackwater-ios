import Foundation

final class UnitsCloud {
    static let shared = UnitsCloud()

    private static let allowed = [unitsKey: ["imperial", "metric"], speedUnitKey: ["kn", "kmh", "ms"]]
    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private let reload: () -> Void
    private var observer: NSObjectProtocol?
    private var retry: DispatchWorkItem?

    init(defaults: UserDefaults = AppGroup.defaults,
         cloud: NSUbiquitousKeyValueStore? = FavoritesCloud.store,
         reload: @escaping () -> Void = { WidgetReload.trigger() }) {
        self.defaults = defaults
        self.cloud = cloud
        self.reload = reload
        guard let cloud else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] note in
            guard let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
                  reason == NSUbiquitousKeyValueStoreServerChange
                    || reason == NSUbiquitousKeyValueStoreInitialSyncChange
                    || reason == NSUbiquitousKeyValueStoreAccountChange else { return }
            guard let self else { return }
            if reason == NSUbiquitousKeyValueStoreAccountChange {
                self.retry?.cancel()
                self.retry = nil
            }
            self.adopt(seedMissing: false)
            if reason != NSUbiquitousKeyValueStoreAccountChange {
                // Let cloud downloads settle, then recheck missing keys before seeding saved preferences.
                self.retry?.cancel()
                let retry = DispatchWorkItem { [weak self] in self?.adopt(seedMissing: true) }
                self.retry = retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: retry)
            }
        }
        cloud.synchronize()
        // synchronize() starts asynchronous work; an empty cache must not trigger uploads.
        adopt(seedMissing: false)
    }

    deinit {
        retry?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func set(_ value: String, forKey key: String) {
        guard Self.allowed[key]?.contains(value) == true else { return }
        if cloud?.object(forKey: key) as? String != value {
            cloud?.set(value, forKey: key)
        }
        guard defaults.string(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
        reload()
    }

    private func adopt(seedMissing: Bool) {
        guard let cloud else { return }
        var changed = false
        for (key, allowed) in Self.allowed {
            let remote = cloud.object(forKey: key)
            if let value = remote as? String, allowed.contains(value) {
                if defaults.string(forKey: key) != value {
                    defaults.set(value, forKey: key)
                    changed = true
                }
            } else if seedMissing, remote == nil,
                      let value = defaults.string(forKey: key), allowed.contains(value) {
                // Seed saved preferences only; a fresh device must not upload its fallback units.
                cloud.set(value, forKey: key)
            }
        }
        if changed { reload() }
    }
}
