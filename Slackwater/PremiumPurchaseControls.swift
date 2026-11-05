// Slackwater — GPL v3. The Premium sheet's StoreKit controls: plans, the pinned purchase
// button, restore and the policy links.
import StoreKit
import SwiftUI

/// What the plan rows, the pinned button and restore share.
@MainActor final class PremiumPurchase: ObservableObject {
    @Published var plan = PremiumStore.yearlyID
    @Published private(set) var loading = true
    @Published private(set) var purchasing = false
    @Published private(set) var error: String?
    private let store = PremiumStore.shared

    var product: Product? { store.products.first { $0.id == plan } }

    /// The selected plan can't be bought: StoreKit didn't return it, even when the other loaded.
    var unavailable: Bool {
        Self.unavailable(loading: loading, plan: plan, loaded: Set(store.products.map(\.id)))
    }

    nonisolated static func unavailable(loading: Bool, plan: String, loaded: Set<String>) -> Bool {
        !loading && !loaded.contains(plan)
    }

    func load() async {
        loading = true
        await store.loadProducts()
        loading = false
    }

    func buy() {
        guard let product, !purchasing else { return }
        error = nil
        purchasing = true
        Task {
            defer { purchasing = false }
            do {
                try await store.purchase(product)
            } catch {
                self.error = String(localized: "Purchase didn't go through — try again.",
                                    comment: "Premium purchase error.")
            }
        }
    }

    /// Shares `purchasing` with buying: AppStore.sync() raises a system prompt, and two are
    /// worse than one.
    func restore() {
        guard !purchasing else { return }
        purchasing = true
        Task {
            defer { purchasing = false }
            await store.restore()
        }
    }
}

struct PremiumPlanPicker: View {
    @ObservedObject var purchase: PremiumPurchase
    @ObservedObject private var store = PremiumStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // App Review 3.1.2: a subscription states its term beside its price.
            plan(PremiumStore.yearlyID, "Yearly", detail: "Renews every year until you cancel.",
                 identifier: "premium-plan-yearly")
            plan(PremiumStore.lifetimeID, "Lifetime", detail: "Pay once, never again.",
                 identifier: "premium-plan-lifetime")
            if purchase.unavailable {
                Text("Purchases are temporarily unavailable.")
                    .font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await purchase.load() }
                } label: {
                    Text("Try again").frame(minHeight: 44)
                }
                .font(.footnote)
                .disabled(purchase.purchasing)
            }
        }
        .tint(SN.leaf)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("premium-purchases")
    }

    private func plan(_ id: String, _ name: LocalizedStringKey, detail: LocalizedStringKey,
                      identifier: String) -> some View {
        let selected = purchase.plan == id
        let shape = RoundedRectangle(cornerRadius: 14)
        return Button { purchase.plan = id } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(SN.leaf)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(SN.foam.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let product = store.products.first(where: { $0.id == id }) {
                    Text(product.displayPrice).font(.headline.monospacedDigit())
                } else if purchase.loading {
                    ProgressView()
                }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? SN.leaf : SN.foam.opacity(0.4))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(SN.foam)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? SN.leaf.opacity(0.12) : SN.cardFill, in: shape)
            .overlay(shape.strokeBorder(selected ? SN.leaf : SN.foam.opacity(0.25), lineWidth: selected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(purchase.purchasing)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Pinned below the scroll, so the price and the button stay in reach while the features scroll.
struct PremiumBuyButton: View {
    @ObservedObject var purchase: PremiumPurchase
    @ObservedObject private var store = PremiumStore.shared

    var body: some View {
        VStack(spacing: 8) {
            if let error = purchase.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { purchase.buy() } label: {
                VStack(spacing: 2) {
                    Label("Get Premium", systemImage: "sparkles")
                        .font(.headline)
                    if let product = purchase.product {
                        Group {
                            if product.id == PremiumStore.yearlyID {
                                Text("\(product.displayPrice) per year")
                            } else {
                                Text(product.displayPrice)
                            }
                        }
                        .font(.footnote.monospacedDigit())
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(SN.leaf)
            // Canvas ink on the leaf fill measures 8.1:1; foam would ride it at 2.0:1
            // (slackwater-feedback#23).
            .foregroundStyle(SN.canvas)
            .disabled(purchase.purchasing || purchase.product == nil)
            .accessibilityIdentifier("premium-buy")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            SN.canvas
                .overlay(alignment: .top) { Rectangle().fill(SN.foam.opacity(0.12)).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// App Review 3.1.2: the purchase screen offers restore and links both policies.
struct PremiumPolicyLinks: View {
    @ObservedObject var purchase: PremiumPurchase

    var body: some View {
        VStack(spacing: 4) {
            Button { purchase.restore() } label: {
                Text("Restore purchase").frame(minHeight: 44)
            }
            .disabled(purchase.purchasing)
            ViewThatFits {
                HStack(spacing: 24) { links }
                VStack(spacing: 4) { links }
            }
        }
        .font(.footnote)
        .tint(SN.leaf)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var links: some View {
        Link(destination: URL(string: "https://slackwater.xyz/privacy")!) {
            Text("Privacy Policy").frame(minHeight: 44)
        }
        Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
            Text("Terms of Use").frame(minHeight: 44)
        }
    }
}
