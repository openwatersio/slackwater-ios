// Slackwater — GPL v3. The Slackwater Premium sheet (spec §3). Quiet by
// design: the free core is stated first, the ask is support, and there is no
// trial, discount, or countdown anywhere.
import StoreKit
import SwiftUI

struct PremiumView: View {
    @ObservedObject private var store = PremiumStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false
    @State private var purchaseError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Everything you use today stays free, forever. Premium adds the lock screen — and it's how Slackwater's development gets funded. Buy it because you want it, or because you want to say thanks.")
                        .font(.callout)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Lock screen widgets — next slack, next turn, the workable window", systemImage: "lock.iphone")
                        Label("Coming to the same tier: the live slack tile, alerts, go-windows for your boat", systemImage: "arrow.forward.circle")
                    }
                    .font(.footnote)

                    if store.isPremium {
                        Label("You have Premium — thank you.", systemImage: "checkmark.seal")
                            .font(.callout.weight(.semibold))
                    } else {
                        // ponytail: products is empty whenever StoreKit has nothing to
                        // sell — no SKUs on App Store Connect yet (build 28), or a
                        // failed load. Without this the sheet is a pitch and a lone
                        // Restore button, which reads as broken.
                        if store.products.isEmpty {
                            Text("Premium isn't on sale yet — these widgets are still being finished. Everything you use today stays free either way.")
                                .font(.footnote)
                                .foregroundStyle(SN.foam.opacity(0.7))
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
                                        purchaseError = "Purchase didn't go through — try again."
                                    }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.displayName).fontWeight(.semibold)
                                        if product.id == PremiumStore.lifetimeID {
                                            Text("Pay once, never again.").font(.caption2)
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
                        Button("Restore purchase") { Task { await store.restore() } }
                            .font(.footnote)
                            .disabled(purchasing)
                    }
                }
                .padding(20)
            }
            .background(SN.page.ignoresSafeArea())
            .navigationTitle("Slackwater Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SN.page, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .foregroundStyle(SN.leaf)
            } }
            .task { await store.loadProducts() }
        }
        .preferredColorScheme(.dark)
    }
}
