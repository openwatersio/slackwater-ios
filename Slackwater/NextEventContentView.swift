// Slackwater — GPL v3. The small widget's content: the station card's reading
// over its own curve (current-charts §15.5).
import SwiftUI

/// The small widget is the card one row shorter: the name, the compact
/// reading (`ConditionsItem`, one row), and the card curve below, whose own
/// labels name the next turn.
struct NextEventContentView: View {
    let card: WidgetCard
    /// Why this place is showing, in the corner: it stands in for a group
    /// heading where there is no room for one (the watch list, #521).
    var mark: PlaceMark? = nil
    /// Clears the name and hero rows above the curve, and scales with them.
    @ScaledMetric(relativeTo: .title3) private var graphInset: CGFloat = 58
    /// The medium card's own points, cropped to half a swing back and one
    /// and a half ahead; nothing is resampled.
    private var graph: StationCardGraph? {
        guard var g = card.graph else { return nil }
        g.back = 0.5 * StationCardGraph.swing
        g.forward = 1.5 * StationCardGraph.swing
        return g
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.name).font(.caption2).foregroundStyle(SN.foam).lineLimit(1)
                if let mark {
                    Spacer(minLength: 4)
                    Image(systemName: mark.symbol)
                        .font(.caption2)
                        .foregroundStyle(mark.color)
                        .accessibilityLabel(mark.label)
                }
            }
            ConditionsItem(reading: card.reading, compact: true)
            // A derived gate has no curve, so its next slack has no other
            // home than a line.
            if let next = card.nextSlack {
                Text("Slack · \(cardTime(next.time, next.tz))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.92))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                SN.cardFill
                // The horizontal bleed lets the line exit through the edge
                // on its own slope.
                if let graph { graph.padding(.top, graphInset).padding(.horizontal, -3) }
            }
        }
    }
}

/// The corner icons: the wearer's location in white, a nearby place in
/// steel, a favorite in the star's sun, a recent one as a clock.
enum PlaceMark: Hashable {
    case location, nearby, favorite, recent

    var symbol: String {
        switch self {
        case .location, .nearby: "location.fill"
        case .favorite: "star.fill"
        case .recent: "clock"
        }
    }

    var color: Color {
        switch self {
        case .location: SN.foam
        case .nearby: SN.steel
        case .favorite: SN.sun
        case .recent: SN.foam.opacity(0.6)
        }
    }

    var label: String {
        switch self {
        case .location: String(localized: "My Location", comment: "Current-location section heading.")
        case .nearby: String(localized: "Near Me", comment: "Nearby-stations section heading.")
        case .favorite: String(localized: "Favorites", comment: "Favorite-stations section heading.")
        case .recent: String(localized: "Recents", comment: "Recent-stations section heading.")
        }
    }
}
