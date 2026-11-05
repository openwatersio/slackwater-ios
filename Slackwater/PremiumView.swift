// Slackwater — GPL v3. The Premium sheet, shared by every upgrade entry point: each feature
// with a live example, what stays free, the plans, and the month's free day.
import SwiftUI

struct PremiumView: View {
    /// The card the carousel opens on; nil opens on the first.
    var opening: PremiumFeature? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PremiumStore.shared
    @StateObject private var purchase = PremiumPurchase()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    PremiumCarousel(opening: opening)
                    VStack(alignment: .leading, spacing: 24) {
                        PremiumComparison()
                        #if PREMIUM_ENABLED
                            if store.hasPurchased {
                                Label("You have Premium — thank you.", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundStyle(SN.leaf)
                                    .frame(maxWidth: .infinity)
                            } else {
                                PremiumPlanPicker(purchase: purchase)
                                FreeDayButton()
                            }
                        #endif
                        Text("Slackwater is independent and open source. Premium is how it keeps going.")
                            .font(.footnote)
                            .foregroundStyle(SN.foam.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        #if PREMIUM_ENABLED
                            if !store.hasPurchased { PremiumPolicyLinks(purchase: purchase) }
                        #endif
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                #if PREMIUM_ENABLED
                    if !store.hasPurchased { PremiumBuyButton(purchase: purchase) }
                #endif
            }
            .background(CanvasBackground())
            .foregroundStyle(SN.foam)
            .navigationTitle("Slackwater Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SN.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label("Slackwater Premium", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                        .foregroundStyle(SN.leaf)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("premium-close")
                }
            }
            .task { await purchase.load() }
        }
    }
}

/// One page per feature, swiped sideways, opening on the tapped one.
private struct PremiumCarousel: View {
    private let features = PremiumFeature.carousel(for: .current)
    @State private var selection: PremiumFeature

    init(opening: PremiumFeature?) {
        let features = PremiumFeature.carousel(for: .current)
        _selection = State(initialValue: opening.flatMap { features.contains($0) ? $0 : nil } ?? features[0])
    }

    var body: some View {
        VStack(spacing: 4) {
            // A paged TabView takes no height from its pages: the hidden stack gives it the tallest.
            ZStack {
                ForEach(features) { page($0) }
            }
            .hidden()
            .overlay {
                TabView(selection: $selection) {
                    ForEach(features) { page($0).tag($0) }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            dots
        }
    }

    private func page(_ feature: PremiumFeature) -> some View {
        VStack(spacing: 12) {
            PremiumFeaturePreview(feature: feature)
            Label(feature.title, systemImage: feature.symbol)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(feature.detail)
                .font(.subheadline)
                .foregroundStyle(SN.foam.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("premium-card-\(feature.rawValue)")
    }

    private var index: Int { features.firstIndex(of: selection) ?? 0 }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(features) { feature in
                Capsule()
                    .fill(feature == selection ? SN.leaf : SN.foam.opacity(0.3))
                    .frame(width: feature == selection ? 18 : 6, height: 6)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(Text("Premium features"))
        .accessibilityValue(Text("\(index + 1) of \(features.count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selection = features[min(index + 1, features.count - 1)]
            case .decrement: selection = features[max(index - 1, 0)]
            @unknown default: break
            }
        }
    }
}
