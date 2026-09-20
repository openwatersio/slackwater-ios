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
func tourCopy(_ step: TourCoach.Step, stationName: String, arrived: Bool) -> String {
    switch step {
    case .read:
        // True on all four detail views, including a derived gate, whose
        // `LeadCard` has no numeric value at all (shape/speed only) — this
        // says what the line marks, not what value it holds.
        return "The center line marks the moment shown below."
    case .stars:
        return arrived
            // The glide already moved the strip to sunset + 1h, so by the
            // time this shows the moment on screen is tonight, not now.
            ? "Those are the actual stars over \(stationName) tonight."
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

    var body: some View {
        // `.stars` and `.moon` both point at the strip; only the copy and
        // the glide target differ, so `.moon` falls back to the `.stars`
        // anchor rather than publishing a second one.
        //
        // A step with no anchor at all draws nothing here — no capsule, so
        // no Skip, which would strand the tour (`seenTour` never written).
        // That is only safe because no reachable case currently drops an
        // anchor: `.read`/`.stars` require a timeline, which `begin` already
        // requires; all four detail views pass a moon tile, so `tile-moon`
        // (the `.moonCard` anchor) always exists; `.star` is only absent on
        // a non-scaffold view, which never runs the tour. A future change
        // that removes an anchor conditionally must keep that true.
        if let step = TourCoach.shared.step,
           let anchor = anchors[step] ?? (step == .moon ? anchors[.stars] : nil) {
            let rect = proxy[anchor]
            let capsuleBelow = rect.midY < proxy.size.height / 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SN.leaf, lineWidth: 2)
                    .frame(width: rect.width + 8, height: rect.height + 8)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)

                capsule(step: step)
                    .frame(maxWidth: 320)
                    .position(x: proxy.size.width / 2,
                              y: capsuleBelow ? rect.maxY + 56 : max(rect.minY - 56, 60))
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
                Text(tourCopy(step, stationName: stationName, arrived: arrived))
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
        // .contain (not the default .combine) keeps this container itself
        // addressable as "tour-mark" while letting the Skip/Next buttons
        // keep their own identifiers — see TimelineStrip.swift's
        // "timeline-strip" for the same shape. Without it, an identifier on
        // a container overrides its descendants' in SwiftUI.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour-mark")
    }
}
