// Slackwater — GPL v3. Siri's event details over the shared widget card.
import SwiftUI

struct TideShortcutSnippetView: View {
    let answer: String
    let detail: String?
    let card: WidgetCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: answer).font(.headline)
                if let detail {
                    Text(verbatim: detail).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if let card {
                DayCurveContentView(card: card)
                    .frame(height: 180)
                    .background(SN.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .environment(\.colorScheme, .dark)
                    // The scalable answer carries the full name above the fixed-height widget drawing.
                    .dynamicTypeSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
