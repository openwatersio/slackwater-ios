import Foundation

/// Display preferences that follow the person between devices: units and the
/// comfort current. The App Group copy is what every reader uses.
@MainActor final class UnitsCloud {
    static let shared = UnitsCloud()

    private static let allowed: [String: (Any) -> Bool] = [
        unitsKey: { ["imperial", "metric"].contains($0 as? String) },
        speedUnitKey: { ["kn", "kmh", "ms"].contains($0 as? String) },
        AppGroup.slackWindowSpeedKey: { ($0 as? Double).map(slackThresholdRange.contains) == true },
    ]
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
            MainActor.assumeIsolated {
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
        }
        cloud.synchronize()
        // synchronize() starts asynchronous work; an empty cache must not trigger uploads.
        adopt(seedMissing: false)
    }

    isolated deinit {
        retry?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// `reloading: false` leaves the reload to a caller that debounces it.
    func set(_ value: Any, forKey key: String, reloading: Bool = true) {
        guard Self.allowed[key]?(value) == true else { return }
        if !same(cloud?.object(forKey: key), value) {
            cloud?.set(value as Any?, forKey: key)
        }
        guard !same(defaults.object(forKey: key), value) else { return }
        defaults.set(value, forKey: key)
        if reloading { reload() }
    }

    /// Strings and numbers both bridge to `NSObject`, whose `isEqual` compares values.
    private func same(_ a: Any?, _ b: Any) -> Bool {
        (a as? NSObject)?.isEqual(b) == true
    }

    private func adopt(seedMissing: Bool) {
        guard let cloud else { return }
        var changed = false
        for (key, allowed) in Self.allowed {
            let remote = cloud.object(forKey: key)
            if let value = remote, allowed(value) {
                if !same(defaults.object(forKey: key), value) {
                    defaults.set(value, forKey: key)
                    changed = true
                }
            } else if seedMissing, remote == nil,
                      let value = defaults.object(forKey: key), allowed(value) {
                // Seed saved preferences only; a fresh device must not upload its fallback units.
                cloud.set(value, forKey: key)
            }
        }
        if changed { reload() }
    }
}
