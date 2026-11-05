// Slackwater — GPL v3. The Premium sheet's free vs Premium table: what stays free comes first.
import SwiftUI

struct PremiumComparison: View {
    @ScaledMetric(relativeTo: .caption) private var column: CGFloat = 76
    private let free: [LocalizedStringKey] = [
        "Every tide and current, every date, offline", "Home screen widgets", "The watch app",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Free vs Premium")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Group {
                    Text("Free").frame(width: column)
                    HStack(spacing: 2) {
                        Image(systemName: "sparkles")
                        Text("Premium")
                    }
                    .foregroundStyle(SN.leaf)
                        .frame(width: column)
                }
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // Every row says which columns it is in.
                .accessibilityHidden(true)
            }
            .padding(.bottom, 8)
            ForEach(free.indices, id: \.self) { row(free[$0], free: true) }
            ForEach(PremiumFeature.carousel(for: .current)) { row($0.tableLabel, free: false) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("premium-table")
    }

    private func row(_ label: LocalizedStringKey, free: Bool) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: free ? "checkmark" : "minus")
                .foregroundStyle(free ? SN.foam : SN.foam.opacity(0.3))
                .frame(width: column)
            Image(systemName: "checkmark")
                .foregroundStyle(SN.leaf)
                .frame(width: column)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(SN.foam.opacity(0.08)).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(free ? Text("Free and Premium") : Text("Premium"))
    }
}
