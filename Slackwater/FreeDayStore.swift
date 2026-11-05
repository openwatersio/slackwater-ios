// Slackwater — GPL v3. The month's free day of Premium, shared across devices
// through iCloud's key-value store and copied into the App Group for widgets.
import Foundation

/// The slice of `NSUbiquitousKeyValueStore` the free day uses, so tests can
/// stand in for iCloud.
protocol FreeDayCloud: AnyObject {
    func date(forKey key: String) -> Date?
    func set(_ date: Date, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: FreeDayCloud {
    func date(forKey key: String) -> Date? { object(forKey: key) as? Date }
    func set(_ date: Date, forKey key: String) { set(date as Any?, forKey: key) }
}

@MainActor final class FreeDayStore: ObservableObject {
    static let shared = FreeDayStore()
    private static let key = AppGroup.freeDayStartKey

    @Published private(set) var lastStart: Date?

    /// The latest free day, running or ended. `freeDayRunning` says which.
    var current: FreeDay? { lastStart.map(FreeDay.init(start:)) }

    private let cloud: FreeDayCloud?
    private let defaults: UserDefaults
    // A closure rather than `PremiumStore.shared` read at init: PremiumStore's
    // own init reads `FreeDayStore.shared`.
    private let purchased: @MainActor () -> Bool
    private var observer: NSObjectProtocol?

    init(cloud: FreeDayCloud? = FavoritesCloud.store,
         defaults: UserDefaults = AppGroup.defaults,
         purchased: @escaping @MainActor () -> Bool = { PremiumStore.shared.hasPurchased }) {
        self.cloud = cloud
        self.defaults = defaults
        self.purchased = purchased
        lastStart = defaults.object(forKey: Self.key) as? Date
        guard let cloud else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.adoptCloud() }
        }
        cloud.synchronize()
        adoptCloud()
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func start(now: Date = appNow()) {
        guard !purchased(),
              freeDayAvailable(lastStart: lastStart, now: now, calendar: .current) else { return }
        cloud?.set(now, forKey: Self.key)
        record(now)
    }

    /// Takes the cloud's start only when it is newer, so an account change to
    /// an empty or older store never forgets this month's free day.
    func adoptCloud() {
        guard let remote = cloud?.date(forKey: Self.key) else { return }
        if let lastStart, lastStart >= remote { return }
        record(remote)
    }

    #if DEBUG
    /// UI-test seeds only: a start `start(now:)` would refuse.
    func seed(lastStart: Date) { record(lastStart) }
    #endif

    private func record(_ start: Date) {
        lastStart = start
        defaults.set(start, forKey: Self.key)
    }
}
