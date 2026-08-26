// Slackwater — GPL v3. The in-app Widgets page (spec §5): every widget, free
// and Premium side by side, with add instructions. Doubles as the free
// widgets' discoverability surface; the only other pitch is the Settings row.
import SwiftUI

struct WidgetsGalleryView: View {
    @ObservedObject private var store = PremiumStore.shared
    @State private var showPremium = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    group("Home screen — free",
                          note: "Long-press your home screen → + → Slackwater.",
                          rows: [("Next Event", "square.grid.2x2",
                                  "The next slack or tide turn at your station."),
                                 ("Today's Curve", "waveform.path.ecg",
                                  "Today's curve with the next event.")])
                    group("Lock screen — Premium",
                          note: "Long-press your lock screen → Customize → add Slackwater above or below the clock.",
                          rows: [("Next Slack (inline)", "lock.iphone",
                                  "Above the clock: the next event and time."),
                                 ("Next Event (circular)", "circle.dashed",
                                  "A glance: arrow and time."),
                                 ("Slack Window (rectangular)", "rectangle.dashed",
                                  "Next event plus the workable window.")])
                    if !store.isPremium {
                        Button { showPremium = true } label: {
                            Text("About Slackwater Premium")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(SN.leaf)
                    }
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
            .sheet(isPresented: $showPremium) { PremiumView() }
        }
        .preferredColorScheme(.dark)
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
