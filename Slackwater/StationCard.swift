import SwiftUI

/// Only the fields a tier can actually shed. The glyph, name, region and
/// trailing reading used to be listed here too, and it was a lie the tests
/// then dressed up as a guard: `content(for:)` renders all four
/// unconditionally, so `.region` in `reduced.fields` had no authority over
/// anything. Deleting it failed a test and changed nothing on screen; putting
/// `if fields.contains(.region)` back passed the same test and restored the
/// exact bug it exists to prevent (see `CardTier` below). Two cases, both
/// consulted — a guard that can't fail is worse than no guard.
enum CardField: Equatable { case distance, detail }

/// Two tiers, one shed step: distance and detail go together; region, the
/// name, and the reading are load-bearing at every size, never shed.
/// Asserted in TypeScaleTests.
///
/// Distance and detail shed first because the list's own grouping already
/// answers "which of these is near me" (distance) and "when" is the detail
/// view's whole job, one tap away (detail). Region never sheds: it is the
/// only thing separating "Victoria" from "Victoria Harbour" from "Victoria
/// Inner Harbour" — a truncated ambiguous name is worse than a missing one.
///
/// A third, region-dropping "essential" tier shipped in the first cut of this
/// type and was wrong: its own doc comment already called region "load-bearing
/// at every size" while its `fields` array dropped `.region` anyway. Fix round
/// 1 (task-4-report.md) caught it two ways at once — `ProvisionalBadge` (paired
/// with region) silently disappeared at the largest accessibility sizes, and
/// `ScreenshotTests.testM50MatchingStationChooser` failed on the iPad Pro 11"
/// sidebar at DEFAULT text size, where the sidebar's width alone (not enlarged
/// type) was enough to pick that tier. The station in that test is a collided
/// name ("Discovery Island" ×2, NOAA current stations); its `region` field
/// happens to be formatted as a bearing ("3.0 nm NE" / "6.6 nm SSE" — that is
/// literally the `region` string in currents.json, not the live per-user
/// `.distance` reading, which for that test's fix coordinate would read "0.0
/// nm" with no compass suffix at all — `formatNm` never appends one). Dropping
/// region dropped the one thing disambiguating the two stations. Collapsing
/// to two tiers makes region unconditional again, matching what the doc
/// comment always said it should be, and needs no fourth tier: nothing above
/// this ever asks for a layout narrower than name + region + trailing.
///
/// Top-level, not nested in `StationCard`: nesting inside a generic would
/// force every assertion to spell `StationCard<EmptyView, EmptyView>.Tier`,
/// and the tiers have nothing to do with the shell's generic parameters.
enum CardTier: CaseIterable {
    case full, reduced

    /// What this tier keeps of the two sheddable fields. The glyph, name,
    /// region and reading are absent by design, not by omission: they are
    /// unconditional in `content(for:)` and enumerating them here would only
    /// invite a future edit to gate them again.
    var fields: [CardField] {
        switch self {
        case .full:    [.distance, .detail]
        case .reduced: []
        }
    }
}

/// The one card shell. Four variants used to hand-roll this chrome; they
/// drifted, and Task 4's ViewThatFits needs a single place to live.
///
/// Slots, not subclasses: `badge` is the optional ProvisionalBadge beside the
/// region, `trailing` is the reading block (a big value, a phase pill, or
/// nothing at all for a pending card).
struct StationCard<Trailing: View, Badge: View>: View {
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
    @ViewBuilder var badge: () -> Badge
    @ViewBuilder var trailing: () -> Trailing

    /// Grows with the text it sits beside. Frozen, a 24pt mark next to 40pt
    /// type reads as a bullet rather than a station kind.
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 24

    /// The identity row — the only thing a tier changes, and so the only thing
    /// `ViewThatFits` measures. `message` and the card chrome sit outside it in
    /// `body`; see the note there for why that matters.
    @ViewBuilder
    func content(for tier: CardTier) -> some View {
        let fields = tier.fields
        HStack(alignment: .top, spacing: 12) {
            StationGlyph(kind: glyphKind, tone: glyphTone, size: glyphSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    // Wrap, never truncate. Task 6 measured the iPad's 320pt
                    // sidebar at the accessibility sizes: the identity column
                    // narrows to ~50pt, and without this the name accepted the
                    // squeezed proposal and came out "Vi/ct/…" — three lines
                    // and an ellipsis on the one field that identifies the
                    // station — while `region` right below it wrapped to five
                    // lines untouched. A `Text` given too little room degrades
                    // by DROPPING CONTENT; `fixedSize(vertical:)` makes it take
                    // the height it actually needs instead.
                    .fixedSize(horizontal: false, vertical: true)
                // Unconditional, like name/glyph/trailing above and below —
                // region (and the badge beside it) never sheds. See the
                // CardTier doc comment: a gated version of this shipped
                // once and silently dropped both the badge and the
                // disambiguating field the M50 chooser depends on.
                HStack(spacing: 7) {
                    badge()
                    Text(region)
                        .font(.footnote)
                        .foregroundStyle(SN.foam.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if fields.contains(.distance), let km {
                    Text(formatNm(km))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(0.7))
                }
                if fields.contains(.detail), let detail {
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
            // unit test — ViewThatFits exposes no way to ask. The tiers'
            // CONTENTS are unit-tested in TypeScaleTests.
            ViewThatFits(in: .horizontal) {
                content(for: .full)
                content(for: .reduced)
            }
            // `message` has no `CardField` of its own and is not shed by tier:
            // it is prose standing in for the whole reading on a pending card
            // (glyph + name + an honest "why there's nothing yet" sentence,
            // `trailing` empty), and dropping it at a narrow width would leave
            // that card with no explanation at all.
            //
            // It sits OUTSIDE the ViewThatFits, and that placement is
            // load-bearing. `ViewThatFits` compares each candidate's IDEAL
            // width, and a `Text`'s ideal width is its unwrapped single line —
            // so while the message was inside the candidates, its ~470pt ideal
            // dominated both of them, no candidate ever "fit", and every card
            // carrying a long message fell through to `.reduced` regardless of
            // width or text size. Task 6 caught it as two adjacent Near Me
            // cards disagreeing about whether distance shows: "Victoria
            // Harbour" (short message) kept its 0.1 nm, "Selkirk Water" (long
            // one) lost it, at identical width. The message is identical in
            // both tiers, so it has no business being measured by the picker.
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

extension StationCard where Badge == EmptyView {
    init(glyphKind: StationGlyph.GlyphKind, glyphTone: StationGlyph.Tone,
         name: String, region: String, km: Double? = nil, detail: String? = nil,
         message: String? = nil, opacity: Double = 1,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(glyphKind: glyphKind, glyphTone: glyphTone, name: name, region: region,
                  km: km, detail: detail, message: message, opacity: opacity,
                  badge: { EmptyView() }, trailing: trailing)
    }
}
