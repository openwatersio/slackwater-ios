import SwiftUI

enum CardField: Equatable { case glyph, name, region, distance, detail, trailing }

/// Shed order: distance, then detail, then nothing more — region and the
/// reading are load-bearing at every size. Asserted in TypeScaleTests.
///
/// Distance goes first because the list's own grouping already answers "which
/// of these is near me". The detail line goes second because "when" is the
/// detail view's whole job, one tap away. Region survives longest because it
/// is the only thing separating "Victoria" from "Victoria Harbour" from
/// "Victoria Inner Harbour" — a truncated ambiguous name is worse than a
/// missing one.
///
/// Top-level, not nested in `StationCard`: nesting inside a generic would
/// force every assertion to spell `StationCard<EmptyView, EmptyView>.Tier`,
/// and the tiers have nothing to do with the shell's generic parameters.
enum CardTier: CaseIterable {
    case full, reduced, essential

    var fields: [CardField] {
        switch self {
        case .full:      [.glyph, .name, .region, .distance, .detail, .trailing]
        case .reduced:   [.glyph, .name, .region, .trailing]
        case .essential: [.glyph, .name, .trailing]
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

    /// `message` has no `CardField` of its own and is not shed by tier: it is
    /// prose that stands in for the whole reading on a pending card (glyph +
    /// name + an honest "why there's nothing yet" sentence, `trailing` empty)
    /// and dropping it at a narrow width would leave that card with no
    /// explanation at all. It renders unconditionally, below the row, same as
    /// before Task 4.
    @ViewBuilder
    func content(for tier: CardTier) -> some View {
        let fields = tier.fields
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                StationGlyph(kind: glyphKind, tone: glyphTone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    if fields.contains(.region) {
                        HStack(spacing: 7) {
                            badge()
                            Text(region)
                                .font(.footnote)
                                .foregroundStyle(SN.foam.opacity(0.78))
                        }
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

    var body: some View {
        // Which candidate wins is verified by screenshot (Task 6), not by unit
        // test — ViewThatFits exposes no way to ask. The tiers' CONTENTS are
        // unit-tested in TypeScaleTests.
        ViewThatFits(in: .horizontal) {
            content(for: .full)
            content(for: .reduced)
            content(for: .essential)
        }
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
