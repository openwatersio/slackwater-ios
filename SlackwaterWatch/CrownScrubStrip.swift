// Slackwater — GPL v3. The phone's timeline canvas, scrubbed by the Digital
// Crown (#522). No momentum code: the Crown brings its own, and a settle
// snaps by the phone's rule.
import SwiftUI

struct CrownScrubStrip: View {
    let data: TimelineData
    let scale: TimelineScale?
    let now: Date
    let imperial: Bool
    let speedUnit: String
    var floodDeg: Double? = nil
    var ebbDeg: Double? = nil
    @Binding var scrubTime: Date

    /// The watch's geometry: a short plot under the card. The sky shows
    /// behind the card, so the strip keeps only room for a high's dot.
    /// ponytail: tuned on the 46mm simulator; retune on the wrist.
    static let padTop: CGFloat = 8
    static let plotDepth: CGFloat = 52
    /// The strip ends under its row of hours: the phone's day and sun rows
    /// below that have no room on a wrist, so they are clipped off.
    static func height(_ geo: TimelineGeo) -> CGFloat { geo.timeY + 10 }
    /// The row of hours under the plot's floor, which the sky stops above:
    /// `timeY` is 18 below the floor, and the strip ends 10 below that.
    static let belowHorizon: CGFloat = 28
    /// How far a turn of the Crown carries the strip: the feel knob.
    /// ponytail: one number; tune on a real Crown.
    static let crownSensitivity: DigitalCrownRotationalSensitivity = .medium

    init(data: TimelineData, scale: TimelineScale?, now: Date, imperial: Bool, speedUnit: String,
         floodDeg: Double? = nil, ebbDeg: Double? = nil, scrubTime: Binding<Date>) {
        self.data = data
        self.scale = scale
        self.now = now
        self.imperial = imperial
        self.speedUnit = speedUnit
        self.floodDeg = floodDeg
        self.ebbDeg = ebbDeg
        _scrubTime = scrubTime
        // Seeded here, not on appear: a Crown whose value starts outside its
        // range may clamp it to the strip's start on the first frame.
        _crown = State(initialValue: Self.crown(scrubTime.wrappedValue))
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The Crown's position in strip points from a fixed origin, not from
    /// `data.start`: the store prepends and evicts chunks, which moves
    /// `data.start`, and a position measured from it would then name another
    /// moment. Same points per hour as the strip, so the feel is the strip's.
    @State private var crown: Double = 0
    @State private var landed = 0

    var body: some View {
        let geo = TimelineGeo(data: data, scale: scale, padTop: Self.padTop, plotDepth: Self.plotDepth)
        GeometryReader { proxy in
            let width = proxy.size.width
            let center = data.x(scrubTime)
            let firstTile = max(Int((center - width) / TimelineCanvas.tileWidth), 0)
            ZStack(alignment: .topLeading) {
                TimelineCanvas(data: data, geo: geo, imperial: imperial, speedUnit: speedUnit, now: now,
                               floodDeg: floodDeg, ebbDeg: ebbDeg, tileRange: firstTile..<(firstTile + 2))
                    .offset(x: width / 2 - center)
                ring(geo: geo, width: width)
            }
            .frame(width: width, height: Self.height(geo), alignment: .topLeading)
            .clipped()
        }
        .frame(height: Self.height(geo))
        .focusable()
        .digitalCrownRotation($crown, from: Self.crown(data.start), through: Self.crown(data.end),
                              sensitivity: Self.crownSensitivity, isContinuous: false,
                              isHapticFeedbackEnabled: false,
                              onChange: { event in scrubTime = Self.time(atCrown: event.offset) },
                              onIdle: settle)
        // A move from outside (return to now, the snap) carries the Crown with it.
        .onChange(of: scrubTime) { _, t in
            let c = Self.crown(t)
            if abs(c - crown) > 1 { crown = c }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: landed)
    }

    /// The scrub point on the curve: the phone's white ring.
    private func ring(geo: TimelineGeo, width: CGFloat) -> some View {
        let y = data.hasTide ? geo.tideY(data.heightAt(scrubTime)) : geo.curY(data.velocityAt(scrubTime))
        return Circle()
            .strokeBorder(.white, lineWidth: 3)
            .background(Circle().fill(SN.canvas))
            .frame(width: 14, height: 14)
            .position(x: width / 2, y: y)
    }

    private static func crown(_ t: Date) -> Double {
        t.timeIntervalSinceReferenceDate / 3600 * Double(Timeline.pph)
    }

    private static func time(atCrown c: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: c / Double(Timeline.pph) * 3600)
    }

    private func settle() {
        guard let target = data.magnetTarget(nearX: data.x(Self.time(atCrown: crown))) else { return }
        let move = { scrubTime = target; crown = Self.crown(target) }
        if reduceMotion { move() } else { withAnimation(.snappy) { move() } }
        landed += 1
    }
}
