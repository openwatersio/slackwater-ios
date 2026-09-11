// Slackwater — GPL v3. The Moon sheet's drawings: the moon at the horizon, and
// the orbit it rides.
//
// Neither of these computes a fact. Every number they draw is one the sheet
// already printed beside them — `MoonFacts` does the astronomy, these turn it
// into something you can look at instead of read.
import SwiftUI

/// The moon at the horizon, rising or setting.
///
/// The two marks put the moon in the SAME place, because that is where it is at
/// both events: half a disc on the line. Only the trail and the arrow differ,
/// and that is the whole distinction — rise and set are one position and two
/// directions.
struct MoonHorizonMark: View {
    let fraction: Double
    let waxing: Bool
    let rising: Bool
    var width: CGFloat = 78
    var height: CGFloat = 44

    var body: some View {
        // The ground sits low enough to leave the trail somewhere to go, and
        // the disc is large enough that the phase still reads at half a moon.
        let ground = height - 11
        let disc: CGFloat = 26
        ZStack {
            // Where it is headed, or where it came from. Dashed because it is
            // a path through time, not anything in the sky.
            Path { p in
                p.move(to: CGPoint(x: width / 2, y: ground - 2))
                p.addQuadCurve(to: CGPoint(x: rising ? width - 7 : 7, y: 5),
                               control: CGPoint(x: rising ? width - 13 : 13, y: ground - 7))
            }
            .stroke(SN.foam.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            // Masked at the horizon: the lower limb is already below it, which
            // is what "at moonrise" means and what a tangent circle would not say.
            MoonGlyph(fraction: fraction, waxing: waxing, size: disc)
                .position(x: width / 2, y: ground)
                .mask(alignment: .top) { Rectangle().frame(height: ground) }

            Path { p in
                p.move(to: CGPoint(x: 0, y: ground))
                p.addLine(to: CGPoint(x: width, y: ground))
            }
            .stroke(SN.foam.opacity(0.4), lineWidth: 1)
            // The rule fades out at both ends rather than stopping: a horizon
            // with two hard endpoints reads as a drawn object in its own right.
            .mask(LinearGradient(colors: [.clear, .white, .white, .clear],
                                 startPoint: .leading, endPoint: .trailing))

            Image(systemName: rising ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(SN.foam.opacity(0.55))
                .position(x: width / 2 + disc / 2 + 9, y: ground - 9)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// Where the moon sits on the drawn orbit at `t` — the angle from perigee, in
/// radians, running the way the moon does.
///
/// ponytail: this is the MEAN anomaly used where the drawing wants the true
/// one. They differ by up to 2e radians, which at the real eccentricity is
/// about 6° — a couple of degrees of arc on a 130-point ellipse, under a
/// point of travel. The drawing is schematic in the eccentricity itself
/// (see `MoonOrbitMark`), so solving Kepler's equation to place the dot would
/// be precision spent inside an approximation. Upgrade path if the mark ever
/// carries a readable angle: Newton on E − e·sin E = M, then the standard
/// half-angle step to v.
func moonOrbitAngle(at t: Date, perigee: Date) -> Double {
    // The anomalistic month — perigee to perigee — not the synodic one. The
    // moon's distance cycles against its own orbit, not against the sun.
    let anomalisticMonth = 27.554_549 * 86_400.0
    let turns = t.timeIntervalSince(perigee) / anomalisticMonth
    return 2 * .pi * (turns - turns.rounded(.down))
}

/// A point on an orbit with its focus at the origin: the polar equation of an
/// ellipse, `a` the semi-major axis and `e` the eccentricity. Angle 0 is
/// perigee, where the radius is smallest.
func orbitPoint(trueAnomaly v: Double, a: CGFloat, e: Double) -> CGPoint {
    let r = Double(a) * (1 - e * e) / (1 + e * cos(v))
    return CGPoint(x: r * cos(v), y: r * sin(v))
}

/// The moon's orbit around the earth, with the moon on it and the two ends of
/// the month marked.
///
/// ponytail: the eccentricity here is DRAWN, not real. The moon's orbit is
/// e = 0.055 — at this size that is a circle to the eye, and a circle cannot
/// show why one date is closest and another farthest, which is the only thing
/// this mark exists to say. So it is drawn at 0.35 and squashed vertically as
/// if seen at an angle. The kilometres printed above it are exact; the shape
/// is a diagram. Upgrade path if this ever needs to be dimensionally honest:
/// keep the true ellipse and carry the range in a scale bar instead.
struct MoonOrbitMark: View {
    let at: Date
    let perigee: Date?
    let apogee: Date?
    let tz: TimeZone
    let onJump: (Date) -> Void

    var height: CGFloat = 156

    private let e = 0.35
    /// The viewing angle, as a vertical scale. Applied to the path and to
    /// every point on it alike, so the moon never leaves the line it rides.
    private let squash: CGFloat = 0.42

    var body: some View {
        GeometryReader { geo in orbit(width: geo.size.width) }
            .frame(height: height)
    }

    private func orbit(width: CGFloat) -> some View {
        // Two bounds on the drawing's size, and it takes the tighter. Width:
        // both vertices have to fit, and the pad is set by the date labels
        // rather than by the path. Height: the labels sit BELOW the ellipse
        // rather than beside the vertices, because the moon reaches a vertex
        // every time the scrub time is near perigee or apogee — which is
        // exactly when someone is reading this — and it would land on top of
        // the words.
        let a = min(max((width - 96) / 2, 40), (height - 56) / (2 * squash) * 0.937)
        let b = a * CGFloat((1 - e * e).squareRoot())
        let cy = 12 + b * squash
        let focusX = 48 + a * CGFloat(1 + e)
        let place = { (p: CGPoint) in CGPoint(x: focusX + p.x, y: cy + p.y * squash) }
        let near = place(orbitPoint(trueAnomaly: 0, a: a, e: e))
        let far = place(orbitPoint(trueAnomaly: .pi, a: a, e: e))
        let moon = place(orbitPoint(
            trueAnomaly: perigee.map { moonOrbitAngle(at: at, perigee: $0) } ?? 0,
            a: a, e: e))

        return ZStack {
            Path { p in
                for step in 0...180 {
                    let pt = place(orbitPoint(trueAnomaly: Double(step) * .pi / 90, a: a, e: e))
                    step == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                p.closeSubpath()
            }
            .stroke(SN.foam.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

            // The distance itself, drawn: the label says "from Earth", and
            // this is the segment it names.
            Path { p in
                p.move(to: CGPoint(x: focusX, y: cy))
                p.addLine(to: moon)
            }
            .stroke(SN.steel.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))

            Circle().fill(SN.flood)
                .frame(width: 13, height: 13)
                .overlay(Circle().strokeBorder(SN.foam.opacity(0.3), lineWidth: 0.75))
                .position(x: focusX, y: cy)

            // A plain dot, not the phase glyph: this drawing is about
            // distance, the phase is already stated twice above it, and a
            // crescent a few percent lit is invisible at this size — which is
            // the one night the moon must not vanish off its own orbit.
            Circle().fill(SN.foam.opacity(0.9)).frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(SN.canvas.opacity(0.6), lineWidth: 1))
                .position(moon)

            if let perigee { vertex("CLOSEST", perigee, at: near, floor: cy + b * squash) }
            if let apogee { vertex("FARTHEST", apogee, at: far, floor: cy + b * squash) }
        }
    }

    /// One end of the month: a tick on the path, and the date below the orbit
    /// under it. Tappable on the same terms as everything else in this sheet
    /// that names a time.
    private func vertex(_ label: String, _ date: Date, at p: CGPoint,
                        floor: CGFloat) -> some View {
        ZStack {
            Circle().fill(SN.foam.opacity(0.75)).frame(width: 5, height: 5)
                .position(p)
                .accessibilityHidden(true)
            // The tap target is the LABEL, never the enclosing stack: two
            // vertices share this drawing, and a `contentShape` on the stack
            // would give each of them the whole orbit to swallow taps with —
            // whichever drew last would answer for both.
            VStack(spacing: 2) {
                MonoLabel(text: label, color: SN.foam.opacity(0.5), tracking: 1)
                Text(monthDay(date, tz)).font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 92)
            .contentShape(Rectangle())
            .onTapGesture { onJump(date) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label.lowercased()) \(monthDay(date, tz))")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(label == "CLOSEST" ? "moon-perigee" : "moon-apogee")
            .position(x: p.x, y: floor + 24)
        }
    }
}
