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

    /// The watch's geometry: a short sky and plot, so the card fits below.
    /// ponytail: tuned on the 46mm simulator; retune on the wrist.
    static let padTop: CGFloat = 26
    static let plotDepth: CGFloat = 52
    /// The strip ends under its row of hours: the phone's day and sun rows
    /// below that have no room on a wrist, so they are clipped off.
    static func height(_ geo: TimelineGeo) -> CGFloat { geo.timeY + 10 }
    /// Where the sky's horizon sits: the bottom of the plot.
    static var skyHeight: CGFloat { padTop + 10 + plotDepth }
    /// How far a turn of the Crown carries the strip: the feel knob.
    /// ponytail: one number; tune on a real Crown.
    static let crownSensitivity: DigitalCrownRotationalSensitivity = .medium

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var crownX: Double = 0
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
        .digitalCrownRotation($crownX, from: 0, through: Double(data.totalWidth),
                              sensitivity: Self.crownSensitivity, isContinuous: false,
                              isHapticFeedbackEnabled: false,
                              onChange: { event in scrubTime = data.time(atX: CGFloat(event.offset)) },
                              onIdle: settle)
        .onAppear { crownX = Double(data.x(scrubTime)) }
        // A jump from outside (return to now, a re-anchored store) moves the Crown's origin too.
        .onChange(of: scrubTime) { _, t in
            let x = Double(data.x(t))
            if abs(x - crownX) > 1 { crownX = x }
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

    private func settle() {
        guard let target = data.magnetTarget(nearX: CGFloat(crownX)) else { return }
        let move = { scrubTime = target; crownX = Double(data.x(target)) }
        if reduceMotion { move() } else { withAnimation(.snappy) { move() } }
        landed += 1
    }
}
