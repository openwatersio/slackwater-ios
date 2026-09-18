// Slackwater — GPL v3. Slackwater Premium (spec §3): one tier, two SKUs —
// yearly + lifetime. StoreKit 2. The verified entitlement is cached into the
// App Group so the widget process can gate without touching StoreKit.
import Foundation
import StoreKit
import WidgetKit

/// Thrown by `purchase(_:)` when StoreKit hands back a transaction it could
/// not verify (T6) — everything else `product.purchase()` can return
/// (`.userCancelled`, `.pending`) is an ordinary non-error outcome and stays
/// silent; only an unverified transaction is worth telling the user about.
enum PremiumError: LocalizedError {
    case unverified
    var errorDescription: String? { "Purchase couldn't be verified — try again." }
}

@MainActor
final class PremiumStore: ObservableObject {
    static let shared = PremiumStore()
    nonisolated static let yearlyID = "io.openwaters.slackwater.premium.yearly"
    nonisolated static let lifetimeID = "io.openwaters.slackwater.premium.lifetime"
    private nonisolated static let ids = [yearlyID, lifetimeID]

    @Published private(set) var isPremium: Bool
    @Published private(set) var products: [Product] = []

    private var updatesTask: Task<Void, Never>?

    private init() {
        isPremium = AppGroup.defaults.bool(forKey: AppGroup.premiumKey)
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
        let premium = Self.isPremium(owned: owned)
        guard premium != isPremium || AppGroup.defaults.object(forKey: AppGroup.premiumKey) == nil
        else { return }
        isPremium = premium
        Self.cache(premium, into: AppGroup.defaults)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
