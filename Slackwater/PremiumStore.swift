// Slackwater — GPL v3. Slackwater Premium (spec §3): one tier, two SKUs —
// yearly + lifetime. StoreKit 2. The verified entitlement is cached into the
// App Group so the widget process can gate without touching StoreKit.
// Premium is that purchase or the month's free day while it runs.
import Combine
import Foundation
import StoreKit
import WidgetKit

/// Thrown by `purchase(_:)` when StoreKit hands back a transaction it could
/// not verify (T6) — everything else `product.purchase()` can return
/// (`.userCancelled`, `.pending`) is an ordinary non-error outcome and stays
/// silent; only an unverified transaction is worth telling the user about.
enum PremiumError: LocalizedError {
    case unverified
    var errorDescription: String? {
        String(localized: "Purchase couldn't be verified — try again.", comment: "Premium purchase verification error.")
    }
}

@MainActor
final class PremiumStore: ObservableObject {
    static let shared = PremiumStore()
    nonisolated static let yearlyID = "io.openwaters.slackwater.premium.yearly"
    nonisolated static let lifetimeID = "io.openwaters.slackwater.premium.lifetime.v2"
    private nonisolated static let ids = [yearlyID, lifetimeID]

    /// What StoreKit says. The sheet needs it apart from `isPremium`.
    @Published private(set) var hasPurchased: Bool
    @Published private(set) var isPremium: Bool
    @Published private(set) var products: [Product] = []

    private var updatesTask: Task<Void, Never>?
    private var freeDayWatch: AnyCancellable?
    private var freeDay: FreeDay?
    private var freeDayEnd: Task<Void, Never>?

    private init() {
        let purchased = AppGroup.defaults.bool(forKey: AppGroup.premiumKey)
        hasPurchased = purchased
        isPremium = purchased
        #if DEBUG
        // UI-test hook, like TestSeeds' -seed* arguments: -seedPremium holds the tier on for
        // the run. Without the early return, refreshEntitlement would set it back to what the
        // simulator's empty StoreKit account owns.
        if CommandLine.arguments.contains("-seedPremium") {
            hasPurchased = true
            isPremium = true
            return
        }
        #endif
        freeDay = FreeDayStore.shared.current
        isPremium = premiumActive(purchased: hasPurchased, freeDay: freeDay, at: appNow())
        scheduleFreeDayEnd()
        // @Published emits before the property changes, so take the value it hands over.
        freeDayWatch = FreeDayStore.shared.$lastStart.dropFirst().sink { [weak self] start in
            guard let self else { return }
            self.freeDay = start.map(FreeDay.init(start:))
            self.update(purchasedChanged: false)
        }
        updatesTask = Task { [weak self] in
            for await _ in Transaction.updates { await self?.refreshEntitlement() }
        }
        Task { await refreshEntitlement() }
    }

    // Pure and side-effect-free (beyond the passed-in defaults) — nonisolated
    // so the test target can call them synchronously, off the main actor.
    nonisolated static func isPremium(owned: Set<String>) -> Bool {
        !owned.isDisjoint(with: ids)
    }

    nonisolated static func cache(_ premium: Bool, into defaults: UserDefaults) {
        defaults.set(premium, forKey: AppGroup.premiumKey)
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        products = ((try? await Product.products(for: Self.ids)) ?? [])
            .sorted { $0.price < $1.price }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                await refreshEntitlement()
            case .unverified:
                throw PremiumError.unverified
            }
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var owned = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil {
                owned.insert(t.productID)
            }
        }
        let purchased = Self.isPremium(owned: owned)
        guard purchased != hasPurchased || AppGroup.defaults.object(forKey: AppGroup.premiumKey) == nil
        else { return }
        hasPurchased = purchased
        Self.cache(purchased, into: AppGroup.defaults)
        update(purchasedChanged: true)
    }

    /// A purchase change reloads even when `isPremium` holds, as buying during a free day
    /// does: the alert horizon and widgets stop ending with the free day.
    private func update(purchasedChanged: Bool) {
        let premium = premiumActive(purchased: hasPurchased, freeDay: freeDay, at: appNow())
        let flipped = premium != isPremium
        if flipped { isPremium = premium }
        scheduleFreeDayEnd()
        guard flipped || purchasedChanged else { return }
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        // Notifications are what the tier decides: gaining Premium schedules them, losing it
        // clears them. Station calendars keep publishing after a lapse (docs/alerts.md §6),
        // except a free day's, which stop with it unless a purchase claims them. The watch has
        // no alerts.
        if purchasedChanged && hasPurchased { StationCalendarStore.shared.clearFreeDayMarks() }
        AlertScheduler.requestReschedule()
        #endif
    }

    /// Ends the free day on time while the app runs. The continuous clock counts time the
    /// app spends suspended, so a wake after the end updates at once.
    private func scheduleFreeDayEnd() {
        freeDayEnd?.cancel()
        freeDayEnd = nil
        guard !hasPurchased, let freeDay, freeDayRunning(freeDay, at: appNow()) else { return }
        let wait = freeDay.end.timeIntervalSince(appNow())
        freeDayEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.update(purchasedChanged: false)
        }
    }
}
