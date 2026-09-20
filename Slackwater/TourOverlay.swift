// Slackwater — GPL v3. The first-run tour's coach marks: one preference-fed
// overlay over the real detail, so nothing here is a second copy of the UI.
import SwiftUI

struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourCoach.Step: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [TourCoach.Step: Anchor<CGRect>],
                       nextValue: () -> [TourCoach.Step: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's bounds as the anchor for one tour step.
    func tourAnchor(_ step: TourCoach.Step) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [step: $0] }
    }
}

/// What each mark says. The copy is deliberately about what the thing IS, not
/// about the app: the backdrop being the real sky is the fact nobody guesses.
func tourCopy(_ step: TourCoach.Step, station: String, arrived: Bool) -> String {
    switch step {
    case .read:
        return "The reading is whatever sits on the centre line."
    case .stars:
        return arrived
            ? "Those are the actual stars over \(station) right now."
            : "Swipe the curve to move through time."
    case .moon:
        return "And that is the real moon, at tonight's phase."
    case .moonCard:
        return "Tap the moon for its rise, set and phase."
    case .star:
        return "Star a station to keep it at the top of your list."
    }
}

/// The mark itself: a ring around the thing, and a glass capsule beside it.
struct TourMarkLayer: View {
    let anchors: [TourCoach.Step: Anchor<CGRect>]
    let proxy: GeometryProxy
    let stationName: String
    /// True once the glide for this step has settled, which swaps the stars
    /// copy from the instruction to the payoff.
    let arrived: Bool
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var coach = TourCoach.shared

    var body: some View {
        if let step = coach.step, let anchor = anchors[step] {
            let rect = proxy[anchor]
            let below = rect.midY < proxy.size.height / 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SN.leaf, lineWidth: 2)
                    .frame(width: rect.width + 8, height: rect.height + 8)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)

                capsule(step: step)
                    .frame(maxWidth: 320)
                    .position(x: proxy.size.width / 2,
                              y: below ? rect.maxY + 56 : max(rect.minY - 56, 60))
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: step)
        }
    }

    private func capsule(step: TourCoach.Step) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if step == .stars {
                    // The platform's own swipe glyph. `.symbolEffect` stills
                    // itself under Reduce Motion without being asked.
                    Image(systemName: "hand.draw.fill")
                        .symbolEffect(.wiggle.left)
                }
                Text(tourCopy(step, station: stationName, arrived: arrived))
                    .font(.callout)
                    .foregroundStyle(SN.paper)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 16) {
                Button("Skip", action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(SN.foam.opacity(0.8))
                    .accessibilityIdentifier("tour-skip")
                Spacer()
                Button(step == .star ? "Done" : "Next", action: onNext)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SN.paper)
                    .accessibilityIdentifier("tour-next")
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("tour-mark")
    }
}
