// Slackwater — GPL v3. The first-run tour's coach marks: one preference-fed
// overlay over the real detail, so nothing here is a second copy of the UI.
import SwiftUI

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

/// One short line per mark, set bold above the copy.
func tourTitle(_ step: TourCoach.Step, arrived: Bool) -> String {
    switch step {
    case .read: return "Reading the strip"
    case .stars: return arrived ? "The real sky" : "Swipe to see more"
    case .moon: return "The moon"
    case .moonCard: return "Moon details"
    case .star: return "Favourites"
    }
}

func tourSymbol(_ step: TourCoach.Step) -> String {
    switch step {
    case .read: return "chart.xyaxis.line"
    case .stars: return "hand.draw.fill"
    case .moon: return "moon.stars"
    case .moonCard: return "moon"
    case .star: return "star"
    }
}

/// The card's pointer: a small triangle on the edge facing the target.
private struct TourPointer: Shape {
    /// True when the card sits below its target, so the point faces up.
    let up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        }
        p.closeSubpath()
        return p
    }
}

private let tourCardFill = Color.black.opacity(0.92)
private let tourPointerHeight: CGFloat = 10

/// The mark itself: a dark card that points at the thing, in the shape of
/// the system Weather app's tips — no ring around the target.
struct TourMarkLayer: View {
    let anchors: [TourCoach.Step: Anchor<CGRect>]
    let proxy: GeometryProxy
    let stationName: String
    /// True once the glide for this step has settled, which swaps the stars
    /// copy from the instruction to the payoff.
    let arrived: Bool
    let onNext: () -> Void
    let onSkip: () -> Void

    @ViewBuilder private var mark: some View {
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
            // Below a target in the upper half, above one in the lower half,
            // so the card always has room on screen.
            let below = rect.midY < proxy.size.height / 2
            let cardWidth = min(proxy.size.width - 32, 360)
            let cardMinX = (proxy.size.width - cardWidth) / 2
            // Where the pointer sits along the card's edge: under the
            // target's centre, kept clear of the card's rounded corners.
            let pointerX = min(max(rect.midX - cardMinX, 24), cardWidth - 24)

            card(step: step)
                .frame(width: cardWidth)
                .overlay(alignment: below ? .top : .bottom) {
                    TourPointer(up: below)
                        .fill(tourCardFill)
                        .frame(width: 18, height: tourPointerHeight)
                        .offset(x: pointerX - cardWidth / 2,
                                y: below ? -tourPointerHeight : tourPointerHeight)
                }
                .padding(.top, below ? rect.maxY + tourPointerHeight + 2 : 0)
                .padding(.bottom, below ? 0 : proxy.size.height - rect.minY + tourPointerHeight + 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: below ? .top : .bottom)
                .transition(.opacity)
                // A fresh view per step: a crossfade between marks, not a
                // card sliding across the screen with its text re-wrapping.
                .id(step)
        }
    }

    var body: some View {
        ZStack { mark }
            // On the parent so it animates the swap, not the swapped view.
            .animation(.easeInOut(duration: 0.2), value: TourCoach.shared.step)
    }

    private func card(step: TourCoach.Step) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // The platform's own swipe glyph for `.stars`. `.symbolEffect`
            // stills itself under Reduce Motion without being asked.
            Image(systemName: tourSymbol(step))
                .font(.title2)
                .foregroundStyle(SN.foam.opacity(0.7))
                .symbolEffect(.wiggle.left, isActive: step == .stars)
                .frame(width: 32)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(tourTitle(step, arrived: arrived))
                    .font(.headline)
                    .foregroundStyle(SN.paper)
                Text(tourCopy(step, stationName: stationName, arrived: arrived))
                    .font(.subheadline)
                    .foregroundStyle(SN.foam.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                Button(step == .star ? "Done" : "Next ›", action: onNext)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SN.paper)
                    .padding(.top, 6)
                    .accessibilityIdentifier("tour-next")
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Button(action: onSkip) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SN.foam.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(SN.foam.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("Skip")
            .accessibilityIdentifier("tour-skip")
        }
        .padding(16)
        .background(tourCardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // .contain (not the default .combine) keeps this container itself
        // addressable as "tour-mark" while letting the Skip/Next buttons
        // keep their own identifiers — see TimelineStrip.swift's
        // "timeline-strip" for the same shape. Without it, an identifier on
        // a container overrides its descendants' in SwiftUI.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour-mark")
    }
}
