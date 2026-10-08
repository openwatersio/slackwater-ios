// Slackwater — GPL v3. Inline StoreKit purchase and restore controls.
import StoreKit
import SwiftUI

struct PremiumPurchaseControls: View {
    @ObservedObject private var store = PremiumStore.shared
    @State private var purchasing = false
    @State private var loading = true
    @State private var purchaseError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.isPremium {
                Label("You have Premium — thank you.", systemImage: "sparkles")
                    .font(.callout.weight(.semibold))
            } else {
                if loading {
                    ProgressView()
                } else if store.products.isEmpty {
                    Text("Purchases are temporarily unavailable.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") {
                        Task { await loadProducts() }
                    }
                    .disabled(purchasing)
                }
                ForEach(store.products, id: \.id) { product in
                    Button {
                        purchaseError = nil
                        purchasing = true
                        Task {
                            defer { purchasing = false }
                            do {
                                try await store.purchase(product)
                            } catch {
                                purchaseError = String(
                                    localized: "Purchase didn't go through — try again.",
                                    comment: "Premium purchase error.")
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            VStack(alignment: .leading) {
                                Text(product.displayName).fontWeight(.semibold)
                                if product.id == PremiumStore.lifetimeID {
                                    Text("Pay once, never again.").font(.caption2)
                                } else if product.id == PremiumStore.yearlyID {
                                    // App Review 3.1.2: a subscription states its length beside its price.
                                    Text("Renews every year until you cancel.").font(.caption2)
                                }
                            }
                            Spacer()
                            Text(product.displayPrice)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(purchasing)
                }
                if let purchaseError {
                    Text(purchaseError)
                        .font(.footnote)
                        .foregroundStyle(SN.foam.opacity(0.7))
                }
                Button("Restore purchase") {
                    // Shares `purchasing` with the buy buttons: AppStore.sync()
                    // raises a system prompt, and two are worse than one.
                    purchasing = true
                    Task {
                        defer { purchasing = false }
                        await store.restore()
                    }
                }
                .font(.footnote)
                .disabled(purchasing)
                // App Review 3.1.2: the purchase screen links both policies.
                VStack(alignment: .leading, spacing: 8) {
                    Link("Privacy Policy", destination: URL(string: "https://slackwater.xyz/privacy")!)
                    Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(SN.leaf)
        .foregroundStyle(SN.foam.opacity(0.85))
        .accessibilityIdentifier("premium-purchases")
        .task { await loadProducts() }
    }

    private func loadProducts() async {
        loading = true
        await store.loadProducts()
        loading = false
    }
}
