// Slackwater — GPL v3. Purchases have their own sheet, shared by every upgrade entry point.
import SwiftUI

struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PremiumStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Slackwater Premium", systemImage: "sparkles")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(SN.leaf)
                        Text("Support Slackwater's development.")
                            .font(.body)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        if SettingsPlatform.current == .mobile {
                            benefit("Lock screen — Premium", symbol: "lock.iphone",
                                    detail: "Tides and currents at a glance on your lock screen.")
                        }
                        benefit("Favourites calendars", symbol: "calendar",
                                detail: "See tides and slack windows alongside your plans.")
                        benefit("Alerts", symbol: "bell",
                                detail: "Get notified before the tides and currents you care about.")
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18))
                    #if PREMIUM_ENABLED
                        PremiumPurchaseControls()
                    #endif
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .background(CanvasBackground())
            .foregroundStyle(SN.foam)
            .navigationTitle(store.isPremium
                             ? String(localized: "Slackwater supporter")
                             : String(localized: "Support Slackwater"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SN.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(SN.leaf)
                        .accessibilityIdentifier("premium-done")
                }
            }
        }
    }

    private func benefit(_ title: LocalizedStringKey, symbol: String,
                         detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(SN.leaf)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(SN.foam.opacity(0.7))
            }
        }
    }
}
