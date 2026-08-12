import SwiftUI

/// The one card shell. Four variants used to hand-roll this chrome; they
/// drifted, and Task 4's ViewThatFits needs a single place to live.
///
/// `trailing` is the reading block (a big value, a phase pill, or nothing at
/// all for a pending card). `provisional` puts the ProvisionalBadge beside the
/// region.
///
/// Two layouts, one shed step: distance and detail drop together when the
/// width can't hold them (the list's grouping already answers "near me", and
/// "when" is the detail view's job one tap away). The glyph, name, region and
/// reading are load-bearing at every size and render unconditionally — a
/// region-shedding tier shipped once and silently dropped both the badge and
/// the one field disambiguating same-named stations (M50).
struct StationCard<Trailing: View>: View {
    let glyphKind: StationGlyph.GlyphKind
    let glyphTone: StationGlyph.Tone
    let name: String
    let region: String
    var km: Double? = nil
    /// A next-event reading (`High 3.2 m · 14:20`) — mono-digit, sits inside
    /// the identity column beside the glyph.
    var detail: String? = nil
    /// A status sentence ("Queued — Canadian tidal predictions download once,
    /// then work offline") — prose, not a reading. Sits below the whole row
    /// at full card width, dimmer than `detail`. Kept as its own slot rather
    /// than a flag on `detail`: the two differ in opacity, width, and font
    /// treatment, and conflating them regressed both (fix round 1, Task 3).
    var message: String? = nil
    var opacity: Double = 1
    /// Marks a 60-day fast answer: the ⚠️ badge beside the region.
    var provisional = false
    @ViewBuilder var trailing: () -> Trailing

    /// Grows with the text it sits beside. Frozen, a 24pt mark next to 40pt
    /// type reads as a bullet rather than a station kind.
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 24

    /// The identity row — the only thing `extras` changes, and so the only
    /// thing `ViewThatFits` measures. `message` and the card chrome sit
    /// outside it in `body`; see the note there for why that matters.
    @ViewBuilder
    func content(extras: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            StationGlyph(kind: glyphKind, tone: glyphTone, size: glyphSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    // Wrap, never truncate: a `Text` given too little room
                    // degrades by DROPPING CONTENT ("Vi/ct/…" in the 320pt
                    // iPad sidebar); `fixedSize(vertical:)` makes it take the
                    // height it actually needs instead.
                    .fixedSize(horizontal: false, vertical: true)
                // Unconditional — region (and the badge beside it) never
                // sheds: it is the only thing separating same-named stations.
                HStack(spacing: 7) {
                    if provisional { ProvisionalBadge() }
                    Text(region)
                        .font(.footnote)
                        .foregroundStyle(SN.foam.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if extras, let km {
                    Text(formatNm(km))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(0.7))
                }
                if extras, let detail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(0.92))
                        .padding(.top, 10)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) { trailing() }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Which candidate wins is verified by screenshot (Task 6), not by
            // unit test — ViewThatFits exposes no way to ask.
            ViewThatFits(in: .horizontal) {
                content(extras: true)
                content(extras: false)
            }
            // `message` sits OUTSIDE the ViewThatFits, and that placement is
            // load-bearing: `ViewThatFits` compares each candidate's IDEAL
            // width, and a `Text`'s ideal width is its unwrapped single line —
            // inside the candidates, a long message's ~470pt ideal dominated
            // both, no candidate ever "fit", and every card carrying one fell
            // through to the reduced layout regardless of width. The message
            // is identical in both candidates, so it has no business being
            // measured by the picker.
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(SN.foam.opacity(0.85))
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(SN.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: 0x001432, opacity: 0.24), radius: 12, y: 10)
        .opacity(opacity)
    }
}
