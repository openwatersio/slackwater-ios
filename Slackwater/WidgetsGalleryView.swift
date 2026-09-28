// Slackwater — GPL v3. The in-app Widgets page (spec §5): every widget, free
// and Premium side by side, with add instructions. Doubles as the free
// widgets' discoverability surface; the only other pitch is the Settings row.
import SwiftUI

struct WidgetsGalleryView: View {
    #if PREMIUM_ENABLED
    @ObservedObject private var store = PremiumStore.shared
    @State private var showPremium = false
    #endif
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    group(String(localized: "Home screen — free", comment: "Widget gallery section title."),
                          note: String(localized: "Long-press your home screen → + → Slackwater.", comment: "Instructions for adding a home-screen widget."),
                          rows: [(String(localized: "Next Event", comment: "Widget name."), "square.grid.2x2",
                                  String(localized: "Now, which way it's going, and the next turn.", comment: "Next Event widget description.")),
                                 (String(localized: "Today's Curve", comment: "Widget name."), "waveform.path.ecg",
                                  String(localized: "Today's curve with the next event.", comment: "Today's Curve widget description."))])
                    #if PREMIUM_ENABLED
                    group(String(localized: "Lock screen — Premium", comment: "Widget gallery section title."),
                          note: String(localized: "Long-press your lock screen → Customize → add Slackwater above or below the clock.", comment: "Instructions for adding a lock-screen widget."),
                          rows: [(String(localized: "Next Slack (inline)", comment: "Widget name and family."), "lock.iphone",
                                  String(localized: "Above the clock: the next event and time.", comment: "Inline widget description.")),
                                 (String(localized: "Next Event (circular)", comment: "Widget name and family."), "circle.dashed",
                                  String(localized: "A glance: arrow and time.", comment: "Circular widget description.")),
                                 (String(localized: "Slack Window (rectangular)", comment: "Widget name and family."), "rectangle.dashed",
                                  String(localized: "Next event plus the workable window.", comment: "Rectangular widget description."))])
                    if !store.isPremium {
                        Button { showPremium = true } label: {
                            Text("About Slackwater Premium")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(SN.leaf)
                    }
                    #endif
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .background(CanvasBackground())
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SN.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(SN.leaf)
                }
            }
            #if PREMIUM_ENABLED
            .sheet(isPresented: $showPremium) { PremiumView() }
            #endif
        }
    }

    @ViewBuilder private func group(_ title: String, note: String,
                                    rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: title)
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.1).frame(width: 24).foregroundStyle(SN.leaf)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.0).font(.footnote.weight(.medium)).foregroundStyle(SN.foam.opacity(0.85))
                        Text(row.2).font(.caption).foregroundStyle(SN.foam.opacity(0.62))
                    }
                }
            }
            Text(note).font(.caption2).foregroundStyle(SN.foam.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
    }
}
