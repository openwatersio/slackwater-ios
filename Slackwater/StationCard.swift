import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 12) {
                StationGlyph(kind: glyphKind, tone: glyphTone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 7) {
                        badge()
                        Text(region)
                            .font(.footnote)
                            .foregroundStyle(SN.foam.opacity(0.78))
                    }
                    if let km {
                        Text(formatNm(km))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SN.foam.opacity(0.7))
                    }
                    if let detail {
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
