// Slackwater — GPL v3. The continuous pan-under-centerline scrubber, the iOS
// model from prototype/TidesApp.dc.html (DCLogic innerChart / chartEl /
// onTideScroll / magnet / tableEl). The reading line is FIXED at the viewport
// center; dragging pans a fixed multi-day timeline strip (-48h…+132h around
// today's local midnight, 12pt per hour) underneath it, so nights bleed across
// day boundaries. Native UIScrollView supplies the momentum; a "magnet" pass
// after the scroll settles snaps a nearby stop (tide turn, slack/max, sun
// event) under the centerline when it's within 46pt. One implementation for
// tide-only, current-only, and tide+current (gate + paired port) details.
import SwiftUI
import UIKit
import TideEngine

// MARK: - Fixed window + scale (prototype TMIN / TMAX / PPH)

enum Timeline {
    static let pph: CGFloat = 12          // points per hour
    static let backHours = 48.0           // TMIN
    static let forwardHours = 132.0       // TMAX
    static let scheduleHours = 54.0       // tableEl TOP: list runs today 00:00 → +54h
    static let magnetPts: CGFloat = 46    // snap radius around the centerline

    /// One point of strip = 5 minutes, and UIScrollView snaps `contentOffset`
    /// to the pixel grid — so the centered-on-now strip round-trips through
    /// `scrubTime` up to ~2.5 min off before anyone has touched it. That was
    /// over the old 60 s "scrubbed away from now" threshold, which is why
    /// return-to-now could be there on arrival at some pane widths (iPad, M52).
    /// A whole point is the smallest honest answer: below it, the centerline
    /// has not visibly moved.
    static let scrubbedSeconds = 3600.0 / Double(pph)
}

/// Is the strip parked somewhere other than now? The one definition, shared by
/// all three scrubable details.
func scrubbedAway(_ scrubTime: Date, from live: Date) -> Bool {
    abs(scrubTime.timeIntervalSince(live)) > Timeline.scrubbedSeconds
}

// MARK: - Data: everything the strip draws, computed once per station

struct TimelineDay {
    let offset: Int          // days from today
    let start: Date          // local midnight
    let sunrise: Date?
    let sunset: Date?
}

struct TimelineData {
    let tz: TimeZone
    let today: Date          // today's local midnight
    let start: Date          // today - 48h
    let end: Date            // today + 132h
    let days: [TimelineDay]  // offsets -2…6 (6 exists for the last night's moon)
    let tidePoints: [TidePoint]        // empty when current-only
    let tideExtremes: [TideExtreme]
    let currentPoints: [CurrentPoint]  // empty when tide-only
    let currentEvents: [CurrentEvent]
    let snapTimes: [Date]    // prototype stops(): turns + slacks/maxes + sun events

    var hasTide: Bool { !tidePoints.isEmpty }
    var hasCurrent: Bool { !currentPoints.isEmpty }
    var totalWidth: CGFloat { x(end) }

    func x(_ t: Date) -> CGFloat {
        CGFloat(t.timeIntervalSince(start) / 3600) * Timeline.pph
    }
    func time(atX x: CGFloat) -> Date {
        start.addingTimeInterval(Double(x / Timeline.pph) * 3600)
    }
    func day(of t: Date) -> TimelineDay? {
        days.last { $0.start <= t }
    }

    /// Linear interpolation over the drawn 10-min samples — the centerline dots
    /// must ride the curve as rendered (prototype _ser reads the same series).
    func heightAt(_ t: Date) -> Double { interp(tidePoints.map { ($0.time, $0.height) }, t) }
    func velocityAt(_ t: Date) -> Double { interp(currentPoints.map { ($0.time, $0.speed) }, t) }

    private func interp(_ pts: [(Date, Double)], _ t: Date) -> Double {
        guard let first = pts.first else { return 0 }
        var prev = first
        for p in pts {
            if t <= p.0 {
                let span = p.0.timeIntervalSince(prev.0)
                let frac = span > 0 ? t.timeIntervalSince(prev.0) / span : 0
                return prev.1 + (p.1 - prev.1) * frac
            }
            prev = p
        }
        return prev.1
    }

    /// A derived gate's strip: the reference port's tide above, the schematic
    /// current below. The current track is a magnitude-less half-sine shape
    /// (±1, NOT a speed — web chs/current.ts schematicSignedAt) with slack
    /// events only: no peaks, so no speed labels and no FLOOD/EBB lines.
    static func build(gate: DerivedGateRecord, now: Date) -> TimelineData {
        build(tide: gate.port, current: nil, now: now, gate: gate)
    }

    static func build(tide: TideStationRecord?, current: CurrentStationRecord?,
                      now: Date, gate: DerivedGateRecord? = nil) -> TimelineData {
        // The primary station names the timezone and the sky position.
        let tz = gate?.gate.tz ?? current?.tz ?? tide?.tz ?? .current
        let lat = gate?.gate.latitude ?? current?.latitude ?? tide?.latitude ?? 48.5
        let lon = gate?.gate.longitude ?? current?.longitude ?? tide?.longitude ?? -123.0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: now)
        let start = today.addingTimeInterval(-Timeline.backHours * 3600)
        let end = today.addingTimeInterval(Timeline.forwardHours * 3600)

        let days: [TimelineDay] = (-2...6).map { off in
            let d0 = cal.date(byAdding: .day, value: off, to: today)!
            let sun = SunMoon.sunEvents(lat: lat, lon: lon, tz: tz, day: d0)
            return TimelineDay(offset: off, start: d0,
                               sunrise: sun.first { $0.kind == .sunrise }?.time,
                               sunset: sun.first { $0.kind == .sunset }?.time)
        }

        // Widen the event scans a touch so nothing at the edges is clipped.
        let pad = 6.0 * 3600
        var tidePoints: [TidePoint] = []
        var tideExtremes: [TideExtreme] = []
        if let tide {
            let s = tide.engineStation
            tidePoints = s.heights(from: start, to: end, step: 600)
            tideExtremes = s.extremes(from: start.addingTimeInterval(-pad),
                                      to: end.addingTimeInterval(pad))
        }
        var currentPoints: [CurrentPoint] = []
        var currentEvents: [CurrentEvent] = []
        if let current {
            let s = current.engineStation
            currentPoints = s.speeds(from: start, to: end, step: 600)
            currentEvents = s.events(from: start.addingTimeInterval(-pad),
                                     to: end.addingTimeInterval(pad))
        }
        if let gate {
            let g = gate.engineGate
            let slacks = g.slacks(from: start.addingTimeInterval(-pad),
                                  to: end.addingTimeInterval(pad))
            currentEvents = slacks.map { CurrentEvent(time: $0.time, speed: 0, kind: .slack) }
            var t = start
            while t <= end {
                currentPoints.append(CurrentPoint(time: t, speed: g.schematicSigned(at: t, slacks: slacks)))
                t = t.addingTimeInterval(600)
            }
        }

        let sunTimes = days.filter { $0.offset <= 5 }
            .flatMap { [$0.sunrise, $0.sunset].compactMap { $0 } }
        let snaps = (tideExtremes.map(\.time) + currentEvents.map(\.time) + sunTimes)
            .filter { $0 >= start && $0 <= end }
            .sorted()

        return TimelineData(tz: tz, today: today, start: start, end: end, days: days,
                            tidePoints: tidePoints, tideExtremes: tideExtremes,
                            currentPoints: currentPoints, currentEvents: currentEvents,
                            snapTimes: snaps)
    }
}

// MARK: - Vertical geometry (prototype geo())

struct TimelineGeo {
    let hasTide: Bool
    let hasCurrent: Bool
    let height: CGFloat
    let dayY: CGFloat = 20
    let sunY: CGFloat = 34
    let moonY: CGFloat = 34
    let tideTop: CGFloat = 48
    let tideBottom: CGFloat
    let sepY: CGFloat
    let curTop: CGFloat
    let curBottom: CGFloat
    let bodyBottom: CGFloat
    let tideMid: Double
    let tideSpan: Double     // half-range, padded (prototype amp*1.18)
    let maxAbsCur: Double    // prototype mxv = cur.mx*1.05

    init(data: TimelineData) {
        hasTide = data.hasTide
        hasCurrent = data.hasCurrent
        switch (hasTide, hasCurrent) {
        case (true, true):
            height = 362; tideBottom = 170; sepY = 192; curTop = 216; curBottom = 342
        case (true, false):
            height = 258; tideBottom = 226; sepY = 0; curTop = 0; curBottom = 0
        default:
            height = 286; tideBottom = 0; sepY = 0; curTop = 68; curBottom = 270
        }
        bodyBottom = hasCurrent ? curBottom : tideBottom
        let heights = data.tidePoints.map(\.height)
        let mn = heights.min() ?? 0, mx = heights.max() ?? 1
        tideMid = (mn + mx) / 2
        tideSpan = max((mx - mn) / 2, 0.01) * 1.18
        maxAbsCur = max(data.currentPoints.map { abs($0.speed) }.max() ?? 1, 0.01) * 1.05
    }

    var zeroY: CGFloat { (curTop + curBottom) / 2 }
    var curHalf: CGFloat { (curBottom - curTop) / 2 - 3 }

    func tideY(_ h: Double) -> CGFloat {
        tideTop + (1 - CGFloat((h - (tideMid - tideSpan)) / (2 * tideSpan))) * (tideBottom - tideTop)
    }
    func curY(_ v: Double) -> CGFloat {
        zeroY - CGFloat(max(-1, min(1, v / maxAbsCur))) * curHalf
    }
}

// MARK: - The strip content (drawn once; pans under the fixed centerline)

struct TimelineCanvas: View {
    let data: TimelineData
    let geo: TimelineGeo
    let imperial: Bool
    let speedUnit: String
    let now: Date

    var body: some View {
        Canvas { ctx, _ in
            drawDayChrome(ctx)
            if geo.hasTide { drawTide(ctx) }
            if geo.hasCurrent { drawCurrent(ctx) }
            // Real-now faint marker rides the timeline (prototype 'nowt').
            var nowLine = Path()
            nowLine.move(to: CGPoint(x: data.x(now), y: geo.hasTide ? geo.tideTop : geo.curTop))
            nowLine.addLine(to: CGPoint(x: data.x(now), y: geo.bodyBottom))
            ctx.stroke(nowLine, with: .color(SN.leaf.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        .frame(width: data.totalWidth, height: geo.height)
    }

    // Night bands, day tint, day labels, sun markers, per-night moons —
    // continuous across midnight (prototype's per-day rects abut exactly).
    private func drawDayChrome(_ ctx: GraphicsContext) {
        let visible = data.days.filter { $0.offset <= 5 }
        for day in visible {
            let ds = data.x(day.start), de = data.x(day.start.addingTimeInterval(86_400))
            let top = geo.dayY + 4
            if let rise = day.sunrise {
                ctx.fill(Path(CGRect(x: ds, y: top, width: data.x(rise) - ds,
                                     height: geo.bodyBottom - top)),
                         with: .color(SN.night.opacity(0.52)))
            }
            if let set = day.sunset {
                ctx.fill(Path(CGRect(x: data.x(set), y: top, width: de - data.x(set),
                                     height: geo.bodyBottom - top)),
                         with: .color(SN.night.opacity(0.52)))
            }
            if let rise = day.sunrise, let set = day.sunset {
                ctx.fill(Path(CGRect(x: data.x(rise), y: geo.hasTide ? geo.tideTop : geo.curTop,
                                     width: data.x(set) - data.x(rise),
                                     height: geo.bodyBottom - (geo.hasTide ? geo.tideTop : geo.curTop))),
                         with: .color(Color(hex: 0xA8CAE0).opacity(0.07)))
            }
        }
        for day in visible {
            // The night's moon sits mid-night — between this sunset and the
            // NEXT day's sunrise, straddling midnight (prototype moon loop).
            if let set = day.sunset,
               let nextRise = data.days.first(where: { $0.offset == day.offset + 1 })?.sunrise {
                let mid = set.addingTimeInterval(nextRise.timeIntervalSince(set) / 2)
                let moon = SunMoon.moonIllumination(date: mid)
                let cx = data.x(mid)
                let glowR = 28 + CGFloat(moon.fraction) * 84
                ctx.fill(Path(ellipseIn: CGRect(x: cx - glowR, y: geo.moonY - glowR,
                                                width: glowR * 2, height: glowR * 2)),
                         with: .radialGradient(
                            Gradient(stops: [
                                .init(color: Color(hex: 0xE6EEFF, opacity: 0.95 * (0.1 + moon.fraction * 0.66)), location: 0),
                                .init(color: Color(hex: 0xCFE0FF, opacity: 0.28 * (0.1 + moon.fraction * 0.66)), location: 0.45),
                                .init(color: Color(hex: 0xCFE0FF, opacity: 0), location: 1)]),
                            center: CGPoint(x: cx, y: geo.moonY), startRadius: 0, endRadius: glowR))
                let r: CGFloat = 8
                let disc = CGRect(x: cx - r, y: geo.moonY - r, width: 2 * r, height: 2 * r)
                // Corrected limb shift (see MoonGlyph): clear at full, covering at new.
                let shift = (moon.waxing ? -1 : 1) * CGFloat(moon.fraction) * 2 * r
                ctx.drawLayer { l in
                    l.clip(to: Path(ellipseIn: disc))
                    l.fill(Path(ellipseIn: disc), with: .color(Color(hex: 0xEEF4FF)))
                    l.fill(Path(ellipseIn: disc.offsetBy(dx: shift, dy: 0)),
                           with: .color(Color(hex: 0x000E22, opacity: 0.94)))
                }
                ctx.stroke(Path(ellipseIn: disc), with: .color(.white.opacity(0.3)), lineWidth: 0.6)
            }
            // Day label at local noon.
            ctx.draw(Text(relativeDayLabel(day.offset, day.start, data.tz))
                        .font(.fraunces(11, .semibold))
                        .foregroundStyle(SN.foam.opacity(0.85)),
                     at: CGPoint(x: data.x(day.start.addingTimeInterval(12 * 3600)), y: geo.dayY),
                     anchor: .center)
            // Sun rise/set dots + "↑5:24AM" labels.
            for (t, arrow) in [(day.sunrise, "↑"), (day.sunset, "↓")] {
                guard let t else { continue }
                let x = data.x(t)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: geo.sunY - 3.5, width: 7, height: 7)),
                         with: .color(SN.sun))
                ctx.draw(Text("\(arrow)\(cardTime(t, data.tz).replacingOccurrences(of: " ", with: ""))")
                            .font(.geistMono(10, .medium))
                            .foregroundStyle(SN.sunrise),
                         at: CGPoint(x: x, y: geo.dayY), anchor: .center)
            }
        }
        if geo.hasTide && geo.hasCurrent {
            var sep = Path()
            sep.move(to: CGPoint(x: 0, y: geo.sepY))
            sep.addLine(to: CGPoint(x: data.totalWidth, y: geo.sepY))
            ctx.stroke(sep, with: .color(.white.opacity(0.16)), lineWidth: 1)
        }
    }

    private func drawTide(_ ctx: GraphicsContext) {
        var line = Path()
        for (i, p) in data.tidePoints.enumerated() {
            let pt = CGPoint(x: data.x(p.time), y: geo.tideY(p.height))
            i == 0 ? line.move(to: pt) : line.addLine(to: pt)
        }
        var area = line
        area.addLine(to: CGPoint(x: data.totalWidth, y: geo.tideBottom))
        area.addLine(to: CGPoint(x: 0, y: geo.tideBottom))
        area.closeSubpath()
        ctx.fill(area, with: .linearGradient(
            Gradient(stops: [.init(color: Color(hex: 0x9CC0DC, opacity: 0.7), location: 0),
                             .init(color: Color(hex: 0x0D3A5C, opacity: 0.12), location: 1)]),
            startPoint: CGPoint(x: 0, y: geo.tideTop),
            endPoint: CGPoint(x: 0, y: geo.tideBottom)))
        ctx.stroke(line, with: .color(Color(hex: 0xEEF4EE)),
                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        // Extreme dots + height labels (prototype fmtH at each turn).
        let margin = 0.3 * 3600
        for e in data.tideExtremes
        where e.time >= data.start.addingTimeInterval(margin)
            && e.time <= data.end.addingTimeInterval(-margin) {
            let x = data.x(e.time), y = geo.tideY(e.height)
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                     with: .color(.white))
            ctx.draw(Text(formatHeight(e.height, imperial: imperial))
                        .font(.fraunces(10, .semibold)).foregroundStyle(.white),
                     at: CGPoint(x: x, y: e.kind == .high ? y - 11 : y + 11), anchor: .center)
        }
    }

    private func drawCurrent(_ ctx: GraphicsContext) {
        var line = Path()
        for (i, p) in data.currentPoints.enumerated() {
            let pt = CGPoint(x: data.x(p.time), y: geo.curY(p.speed))
            i == 0 ? line.move(to: pt) : line.addLine(to: pt)
        }
        var area = line
        area.addLine(to: CGPoint(x: data.totalWidth, y: geo.zeroY))
        area.addLine(to: CGPoint(x: 0, y: geo.zeroY))
        area.closeSubpath()
        // Flood fill above the zero line, ebb fill below (prototype clip paths).
        // These were SN.leaf (the slack-only green) and a hardcoded blue —
        // leftover from before the rebrand, still speaking the retired
        // direction pair in the chart's most prominent area.
        ctx.drawLayer { l in
            l.clip(to: Path(CGRect(x: 0, y: geo.curTop - 10, width: data.totalWidth,
                                   height: geo.zeroY - (geo.curTop - 10))))
            l.fill(area, with: .color(SN.flood.opacity(0.32)))
        }
        ctx.drawLayer { l in
            l.clip(to: Path(CGRect(x: 0, y: geo.zeroY, width: data.totalWidth,
                                   height: geo.curBottom + 10 - geo.zeroY)))
            l.fill(area, with: .color(SN.ebb.opacity(0.32)))
        }
        var zero = Path()
        zero.move(to: CGPoint(x: 0, y: geo.zeroY))
        zero.addLine(to: CGPoint(x: data.totalWidth, y: geo.zeroY))
        ctx.stroke(zero, with: .color(.white.opacity(0.4)), lineWidth: 1)
        ctx.stroke(line, with: .color(Color(hex: 0xDFEEE0)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        let margin = 0.3 * 3600
        for e in data.currentEvents
        where e.time >= data.start.addingTimeInterval(margin)
            && e.time <= data.end.addingTimeInterval(-margin) {
            let x = data.x(e.time)
            switch e.kind {
            case .slack:
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2.6, y: geo.zeroY - 2.6,
                                                width: 5.2, height: 5.2)),
                         with: .color(.white.opacity(0.85)))
                // Slack is the app's "go" colour, not a neutral. It is the moment the
                // app is named for, and it must read the same on every surface.
                ctx.draw(Text("slack").font(.geistMono(8))
                            .foregroundStyle(SN.go),
                         at: CGPoint(x: x, y: geo.zeroY + 12), anchor: .center)
            case .maxFlood, .maxEbb:
                let y = geo.curY(e.speed)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                         with: .color(.white))
                ctx.draw(Text(formatSpeed(abs(e.speed), unit: speedUnit))
                            .font(.fraunces(10, .semibold))
                            .foregroundStyle(e.kind == .maxFlood ? SN.floodLabel : SN.ebbLabel),
                         at: CGPoint(x: x, y: e.kind == .maxFlood ? y - 10 : y + 12),
                         anchor: .center)
            }
        }
    }
}

/// "Today" / "Tomorrow" / "Yesterday", short weekday otherwise (prototype dayName).
func relativeDayLabel(_ offset: Int, _ date: Date, _ tz: TimeZone) -> String {
    switch offset {
    case 0: "Today"
    case 1: "Tomorrow"
    case -1: "Yesterday"
    default: formatterShortWeekday(date, tz)
    }
}

private func formatterShortWeekday(_ date: Date, _ tz: TimeZone) -> String {
    String(weekdayName(date, tz).prefix(3))
}

// MARK: - The scroll host: native pan + momentum, magnet on settle

struct TimelineScrubber: UIViewRepresentable {
    let data: TimelineData
    let geo: TimelineGeo
    let imperial: Bool
    let speedUnit: String
    let now: Date
    @Binding var scrubTime: Date

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// The scroll view's bounds are zero in makeUIView and updateUIView is
    /// not re-invoked by layout, so "center now under the centerline" can't
    /// live there: it would wait for the next state change (the first magnet
    /// settle), leaving the first view uncentered and the first scrub's
    /// readout frozen (build-7 riding-dot bug). Centering runs at layout
    /// time instead — the first moment the real width exists.
    final class ScrubScrollView: UIScrollView {
        var onLayout: (() -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = ScrubScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.alwaysBounceVertical = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.delegate = context.coordinator
        let host = UIHostingController(rootView: canvas)
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: data.totalWidth, height: geo.height)
        sv.addSubview(host.view)
        sv.contentSize = CGSize(width: data.totalWidth, height: geo.height)
        context.coordinator.host = host
        sv.onLayout = { [weak sv, coordinator = context.coordinator] in
            guard let sv else { return }
            coordinator.centerIfNeeded(sv)
        }
        return sv
    }

    func updateUIView(_ sv: UIScrollView, context: Context) {
        let co = context.coordinator
        co.parent = self
        co.host?.rootView = canvas
        guard sv.bounds.width > 0 else { return }
        if !co.didInitialCenter {
            co.centerIfNeeded(sv)
            return
        }
        // External scrub (event tap, return-to-now): jump the strip so the
        // requested time sits under the centerline (prototype scrubTo/centerNow
        // are instant). User-driven scrolling round-trips within a point.
        let desired = data.x(scrubTime) - sv.bounds.width / 2
        if abs(desired - sv.contentOffset.x) > 1,
           !sv.isDragging, !sv.isDecelerating, !co.magneting {
            sv.contentOffset = CGPoint(x: desired, y: 0)
        }
    }

    private var canvas: TimelineCanvas {
        TimelineCanvas(data: data, geo: geo, imperial: imperial, speedUnit: speedUnit, now: now)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: TimelineScrubber
        var host: UIHostingController<TimelineCanvas>?
        var didInitialCenter = false
        var magneting = false
        private var magnetTarget: Date?

        init(_ parent: TimelineScrubber) { self.parent = parent }

        /// One-shot initial centering, at the first layout with a real width
        /// (also reachable from updateUIView, whichever lands first). After
        /// this, scrollViewDidScroll drives scrubTime — including the very
        /// first drag.
        func centerIfNeeded(_ sv: UIScrollView) {
            guard !didInitialCenter, sv.bounds.width > 0 else { return }
            didInitialCenter = true
            sv.contentOffset = CGPoint(x: parent.data.x(parent.scrubTime) - sv.bounds.width / 2, y: 0)
        }

        func scrollViewDidScroll(_ sv: UIScrollView) {
            guard sv.bounds.width > 0, didInitialCenter else { return }
            parent.scrubTime = parent.data.time(atX: sv.contentOffset.x + sv.bounds.width / 2)
        }
        func scrollViewDidEndDragging(_ sv: UIScrollView, willDecelerate: Bool) {
            if !willDecelerate { magnet(sv) }
        }
        func scrollViewDidEndDecelerating(_ sv: UIScrollView) { magnet(sv) }
        func scrollViewDidEndScrollingAnimation(_ sv: UIScrollView) {
            magneting = false
            // Park exactly on the stop, so readouts show the event's own time.
            if let t = magnetTarget { magnetTarget = nil; parent.scrubTime = t }
        }

        /// Prototype magnet(): after the scroll settles, the nearest stop
        /// within 46pt of the centerline pulls the strip onto itself.
        private func magnet(_ sv: UIScrollView) {
            guard !magneting else { return }
            let center = sv.contentOffset.x + sv.bounds.width / 2
            var best: Date?
            var bd = CGFloat.greatestFiniteMagnitude
            for t in parent.data.snapTimes {
                let d = abs(parent.data.x(t) - center)
                if d < bd { bd = d; best = t }
            }
            guard let best, bd < Timeline.magnetPts, bd > 0.5 else { return }
            magneting = true
            magnetTarget = best
            sv.setContentOffset(CGPoint(x: parent.data.x(best) - sv.bounds.width / 2, y: 0),
                                animated: true)
        }
    }
}

// MARK: - Strip + fixed overlay (centerline, riding dots, track labels)

struct TimelineScrubStrip: View {
    let data: TimelineData
    let geo: TimelineGeo
    let imperial: Bool
    var speedUnit = "kn"   // tide-only strips draw no speed labels
    let now: Date
    @Binding var scrubTime: Date

    var body: some View {
        TimelineScrubber(data: data, geo: geo, imperial: imperial, speedUnit: speedUnit,
                         now: now, scrubTime: $scrubTime)
            .frame(height: geo.height)
            .overlay { overlay }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("timeline-strip")
    }

    private var overlay: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .topLeading) {
                // Fixed reading line + cap triangle (prototype chartEl overlay).
                LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.3)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 2, height: geo.bodyBottom - 8)
                    .position(x: w / 2, y: 8 + (geo.bodyBottom - 8) / 2)
                Triangle()
                    .fill(.white)
                    .frame(width: 8, height: 6)
                    .position(x: w / 2, y: 5)
                if geo.hasTide {
                    Circle().fill(SN.leaf)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: SN.leaf.opacity(0.9), radius: 4)
                        .position(x: w / 2, y: geo.tideY(data.heightAt(scrubTime)))
                    MonoLabel(text: "Tide", size: 9, color: SN.leaf.opacity(0.9), tracking: 1.4)
                        .padding(.horizontal, 4)
                        .background(Color(hex: 0x001020, opacity: 0.5))
                        .position(x: 30, y: geo.tideTop - 3)
                }
                if geo.hasCurrent {
                    Circle().fill(.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .white.opacity(0.9), radius: 3)
                        .position(x: w / 2, y: geo.curY(data.velocityAt(scrubTime)))
                    MonoLabel(text: "Current", size: 9, color: SN.leaf.opacity(0.9), tracking: 1.4)
                        .padding(.horizontal, 4)
                        .background(Color(hex: 0x001020, opacity: 0.5))
                        .position(x: 42, y: (geo.hasTide ? geo.sepY : geo.curTop) - 8)
                    visibleMaxLines(width: w)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// FLOOD / EBB reference lines at the strongest peaks visible in the
    /// window around the centerline (prototype chartEl mf/me).
    @ViewBuilder
    private func visibleMaxLines(width w: CGFloat) -> some View {
        let half = Double(w / 2 / Timeline.pph) * 3600
        let lo = scrubTime.addingTimeInterval(-half), hi = scrubTime.addingTimeInterval(half)
        let vis = data.currentEvents.filter { $0.time >= lo && $0.time <= hi }
        let mf = vis.filter { $0.kind == .maxFlood }.map(\.speed).max() ?? 0
        let me = vis.filter { $0.kind == .maxEbb }.map(\.speed).min() ?? 0
        if mf > 0 {
            Rectangle().fill(SN.floodLabel.opacity(0.5)).frame(width: w, height: 1)
                .position(x: w / 2, y: geo.curY(mf))
            Text("FLOOD").font(.geistMono(9, .medium)).foregroundStyle(SN.floodLabel)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color(hex: 0x001020, opacity: 0.55))
                .position(x: w - 30, y: geo.curY(mf) - 10)
        }
        if me < 0 {
            Rectangle().fill(SN.ebbLabel.opacity(0.5)).frame(width: w, height: 1)
                .position(x: w / 2, y: geo.curY(me))
            Text("EBB").font(.geistMono(9, .medium)).foregroundStyle(SN.ebbLabel)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color(hex: 0x001020, opacity: 0.55))
                .position(x: w - 24, y: geo.curY(me) + 10)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Rolling multi-day schedule (prototype tableEl)

enum SchedulePill {
    case high, low, flood, ebb, slack, sunrise, sunset
}

struct ScheduleEntry: Identifiable {
    let time: Date
    let pill: SchedulePill
    let value: String?       // "6.2 ft" / "3.1 kn"; nil renders as "—"
    let arrowDeg: Double?    // flood/ebb set bearing
    var id: String { "\(time.timeIntervalSince1970)-\(pill)" }

    init(time: Date, pill: SchedulePill, value: String? = nil, arrowDeg: Double? = nil) {
        self.time = time
        self.pill = pill
        self.value = value
        self.arrowDeg = arrowDeg
    }
}

/// Day-grouped events list, today 00:00 → +54h (prototype tableEl TOP): day
/// name in a left column, rows scrub on tap, the row nearest the centerline
/// time is highlighted. The prototype dims nothing for the past — the nearest-
/// row highlight is the time cue.
struct MultiDaySchedule: View {
    let entries: [ScheduleEntry]  // pre-sorted, pre-filtered to the window
    let tz: TimeZone
    let today: Date               // local midnight
    let scrubTime: Date
    let onTap: (Date) -> Void

    private var groups: [(offset: Int, start: Date, items: [ScheduleEntry])] {
        var out: [(Int, Date, [ScheduleEntry])] = []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        for e in entries {
            let d0 = cal.startOfDay(for: e.time)
            let off = cal.dateComponents([.day], from: today, to: d0).day ?? 0
            if out.last?.1 == d0 { out[out.count - 1].2.append(e) }
            else { out.append((off, d0, [e])) }
        }
        return out
    }

    private var nearestID: String? {
        entries.min { abs($0.time.timeIntervalSince(scrubTime)) < abs($1.time.timeIntervalSince(scrubTime)) }?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.start) { group in
                if group.start != groups.first?.start {
                    Divider().overlay(Color.white.opacity(0.08))
                }
                HStack(alignment: .top, spacing: 0) {
                    Text(relativeDayLabel(group.offset, group.start, tz))
                        .font(.geist(12, .semibold))
                        .foregroundStyle(SN.foam.opacity(0.9))
                        .frame(width: 74, alignment: .leading)
                        .padding(.leading, 14)
                        .padding(.top, 12)
                    VStack(spacing: 0) {
                        ForEach(group.items) { e in
                            let on = e.id == nearestID
                            // A tap gesture, not a Button: Button press tracking
                            // goes dead in the iPad split layout's detail column
                            // (regular width, below the strip) while gesture
                            // recognizers keep working — same tap for the user.
                            HStack(spacing: 8) {
                                Text(clockTime(e.time, tz))
                                    .font(.geistMono(14))
                                    .foregroundStyle(on ? .white : SN.foam.opacity(0.85))
                                Spacer()
                                Text(e.value ?? "—")
                                    .font(.fraunces(15, .semibold))
                                    .foregroundStyle(e.value == nil ? SN.foam.opacity(0.5) : .white)
                                pillView(e)
                                    .frame(width: 84, alignment: .trailing)
                            }
                            .padding(.vertical, 9)
                            .padding(.trailing, 14)
                            .background(on ? SN.leaf.opacity(0.13) : .clear)
                            .overlay(alignment: .leading) {
                                if on { Rectangle().fill(SN.leaf).frame(width: 2) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onTap(e.time) }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("schedule-row-d\(group.offset)")
                            if e.id != group.items.last?.id {
                                Divider().overlay(Color.white.opacity(0.055))
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func pillView(_ e: ScheduleEntry) -> some View {
        switch e.pill {
        case .high:
            Text("↑ HIGH")
                .font(.geistMono(10, .medium)).tracking(0.5)
                .foregroundStyle(SN.navyDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.rising, in: Capsule())
        case .low:
            Text("↓ LOW")
                .font(.geistMono(10, .medium)).tracking(0.5)
                .foregroundStyle(SN.navyDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.falling, in: Capsule())
        case .flood, .ebb:
            HStack(spacing: 3) {
                if let deg = e.arrowDeg { CompassArrow(deg: deg) }
                Text(e.pill == .flood ? "FLOOD" : "EBB")
            }
            .font(.geistMono(10, .medium)).tracking(0.5)
            .foregroundStyle(SN.navyDeep)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(e.pill == .flood ? SN.rising : SN.falling, in: Capsule())
        case .slack:
            Text("● SLACK")
                .font(.geistMono(10, .medium)).tracking(0.5)
                .foregroundStyle(SN.navyDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.go, in: Capsule())
        case .sunrise:
            SunPill(kind: .sunrise)
        case .sunset:
            SunPill(kind: .sunset)
        }
    }
}
