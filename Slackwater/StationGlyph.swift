import SwiftUI

/// A station's kind, drawn — a wave for a current station, a dome over a datum
/// line for a tide station. The glyph's COLOUR is its live state and never its
/// kind: that separation is the whole point. A green wave is a current gate at
/// slack, which is the most useful thing to spot while scanning a mixed list.
///
/// The map deliberately does NOT use these. Tried there and rejected: thin
/// curved strokes over bathymetry contours make a dense chart denser. The map
/// takes plain circle and square markers instead. A list row is roomy enough to
/// earn an expressive glyph; a chart at zoom 12 is not.
struct StationGlyph: View {
    enum GlyphKind { case tide, current }
    enum Tone { case rising, falling, flood, ebb, slack, unknown }

    let kind: GlyphKind
    let tone: Tone
    var size: CGFloat = 24

    static func colour(for tone: Tone) -> Color {
        switch tone {
        case .rising, .flood: SN.flood
        case .falling, .ebb: SN.ebb
        case .slack: SN.go
        case .unknown: SN.steel
        }
    }

    /// One wave for a current station; a dome over a datum line for a tide one.
    static func path(for kind: GlyphKind, in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        switch kind {
        case .current:
            p.move(to: CGPoint(x: 0.08 * w, y: 0.5 * h))
            p.addCurve(to: CGPoint(x: 0.5 * w, y: 0.5 * h),
                       control1: CGPoint(x: 0.22 * w, y: 0.12 * h),
                       control2: CGPoint(x: 0.36 * w, y: 0.88 * h))
            p.addCurve(to: CGPoint(x: 0.92 * w, y: 0.5 * h),
                       control1: CGPoint(x: 0.64 * w, y: 0.12 * h),
                       control2: CGPoint(x: 0.78 * w, y: 0.88 * h))
        case .tide:
            p.move(to: CGPoint(x: 0.10 * w, y: 0.66 * h))
            p.addQuadCurve(to: CGPoint(x: 0.90 * w, y: 0.66 * h),
                           control: CGPoint(x: 0.5 * w, y: 0.08 * h))
            p.move(to: CGPoint(x: 0.14 * w, y: 0.84 * h))
            p.addLine(to: CGPoint(x: 0.86 * w, y: 0.84 * h))
        }
        return p
    }

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            context.stroke(Self.path(for: kind, in: rect),
                           with: .color(Self.colour(for: tone)),
                           style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(kind == .current ? "Current station" : "Tide station")
    }
}
