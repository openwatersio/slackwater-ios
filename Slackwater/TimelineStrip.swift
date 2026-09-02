// Slackwater — GPL v3. The continuous pan-under-centerline scrubber, the iOS
// model from prototype/TidesApp.dc.html (DCLogic innerChart / chartEl /
// onTideScroll / magnet / tableEl). The reading line is FIXED at the viewport
// center; dragging pans a fixed multi-day timeline strip (-48h on the current
// week only, always +180h, 18pt per hour) underneath it, so nights bleed across
// day boundaries. Native UIScrollView supplies the momentum; a "magnet" pass
// after the scroll settles snaps a nearby stop (tide turn, slack/max, sun
// event) under the centerline when it's within 46pt. One implementation for
// the tide-only and current-only details.
import SwiftUI
import UIKit
import TideEngine

// MARK: - Fixed window + scale (prototype TMIN / TMAX / PPH)

enum Timeline {
    /// Points per hour. Widened from 12 in the NEAPS pass: the tide track's
    /// times and heights moved off the curve into fixed bands above and below
    /// it, and those labels only ever collide with the SAME kind — high with
    /// high, low with low. The tightest real pair in a mixed-semidiurnal cycle
    /// is ~4h, which is 72pt here against a ~45pt label; at 12 it was 48pt and
    /// overprinted. A phone still shows ~22h at a glance.
    static let pph: CGFloat = 18          // points per hour
    /// The look-back, and it applies ONLY to the current week — see `window`.
    static let backHours = 48.0
    /// A week in the list. The product decision this whole spec is about; the
    /// 54 it replaced was the HTML prototype's `tableEl` TOP, never a decision.
    static let scheduleDays = 7.0
    static let scheduleHours = scheduleDays * 24          // 168
    /// Half a viewport, so the LAST listed event can still sit under the
    /// centerline instead of jamming against UIScrollView's contentOffset
    /// clamp. Tapping a schedule row scrubs the strip, and a row exactly at
    /// the strip's edge would park the centerline short of the event it names
    /// — the readout disagreeing with the row you just tapped. The old
    /// 132-vs-54 mismatch kept this property by accident; this keeps it on
    /// purpose, at the smallest width that still clears half a phone.
    static let centerPad = 12.0
    static let forwardHours = scheduleHours + centerPad   // 180
    static let magnetPts: CGFloat = 46    // snap radius around the centerline
    /// The discoverability nudge (#58). The strip opens this far off-centre
    /// and animates in, so the first thing you see it do is move sideways —
    /// which is the whole affordance now that the `‹ swipe to scrub ›` label
    /// is gone. Well inside `magnetPts`, so the settle never lands somewhere
    /// the magnet would then drag it away from.
    static let nudgePts: CGFloat = 28

    /// How much an online gate fetches in one go. Four times the strip it
    /// needs, so ordinary paging lands in cache instead of on the network —
    /// the gates people plan a passage around are exactly the ones that must
    /// not need a signal to look at next month.
    static let onlineFetchDays = 30.0

    /// How far back fetched online blocks are kept (#67 item 6: bounded backward
    /// retention). A block ages out at the first save after it falls behind
    /// today − this; a save's own fetch is always protected (`saveOnline`'s min),
    /// so a deliberately-picked old week renders and only later saves collect it.
    static let onlineRetentionDays = 60.0

    /// The absolute domain of the speed ramp (#97), spaced equally across it.
    /// Anchored to **capability** rather than to quantiles — the move Beaufort
    /// makes, and the reason Windy's ramp reads well: the colour says what you
    /// can still do about the water, not what percentile the station is in.
    ///
    ///   0.5 kn — the fixed low end of this visual scale
    ///     3 kn — around where a paddled craft can no longer make way against it
    ///     8 kn — severe current
    ///    12 kn — red ceiling; faster water stays red
    ///
    /// Across the 842 bundled NOAA current stations that puts the median at
    /// 23% of the ramp and p90 at 56%. A linear 0→16 puts them at 14% and 31%,
    /// compressing ninety percent of stations into the bottom third — this
    /// issue's own defect, re-entering through the transfer function. A ceiling
    /// of 6 makes Sechelt and Seymour Narrows identical again, which is the
    /// failure PredictWind's 6-kt tidal layer ships today.
    ///
    /// **Hard-coded, and never derived from the stations on the device**: a
    /// runtime ceiling would make the same colour mean different speeds on
    /// different phones, which is the absolute scale gone.
    ///
    /// The middle two are estimates and want a source — Sailing Directions or
    /// small-craft guidance. They ship flagged because the ramp is an encoding
    /// rather than a computed hazard call: an anchor wrong by half a knot moves
    /// a colour, not a decision.
    ///
    static let speedRampAnchorsKn = currentSpeedRampAnchorsKn

    /// Position on the speed ramp for `kn`, piecewise-linear between the
    /// anchors and clamped at both ends. Above the ceiling everything is the
    /// top colour — "beyond the top of the scale" is not a distinction worth
    /// resolving.
    static func rampT(forSpeedKn kn: Double) -> Double { widgetSpeedRampT(kn) }

    /// Tide change is a separate measurement from current speed, but uses the
    /// same global warning palette. The red ceiling is 1.8 m/hr (about
    /// 6 ft/hr), so Fundy-scale movement reaches the warning colour.
    static let tideRateRampAnchorsMHr = tideMovementRampAnchorsMHr
    static func rampT(forTideRateMHr rate: Double) -> Double {
        rampT(rate, anchors: tideRateRampAnchorsMHr)
    }

    private static func rampT(_ v: Double, anchors a: [Double]) -> Double {
        let step = 1.0 / Double(a.count - 1)
        if v <= a[0] { return 0 }
        for i in 0..<(a.count - 1) where v <= a[i + 1] {
            return (Double(i) + (v - a[i]) / (a[i + 1] - a[i])) * step
        }
        return 1
    }

    /// One point of strip = 5 minutes, and UIScrollView snaps `contentOffset`
    /// to the pixel grid — so the centered-on-now strip round-trips through
    /// `scrubTime` up to ~2.5 min off before anyone has touched it. That was
    /// over the old 60 s "scrubbed away from now" threshold, which is why
    /// return-to-now could be there on arrival at some pane widths (iPad, M52).
    /// A whole point is the smallest honest answer: below it, the centerline
    /// has not visibly moved.
    static let scrubbedSeconds = 3600.0 / Double(pph)

    /// THE window definition. Four sites used to re-derive `today ± hours`
    /// independently — day chrome, the online-gate coverage check, the
    /// UI-test seed, and the online fetch — and with a conditional back-pad
    /// they would drift. The failure mode is a coverage check that passes on
    /// a window with a hole in it, which renders as a strip with a dead zone.
    ///
    /// The 48h back-pad is UNCONDITIONAL (#67 item 1). It used to exist only when
    /// `anchor == today`, which (a) left the noon park with dead space to its left
    /// on panes wider than 432pt — the centering target is `x(t) − width/2`, and
    /// UIScrollView clamps the negative result to 0 — and (b) made the window's
    /// shape depend on exact Date equality between two `todayLocal` calls, a
    /// documented class of "two clocks answering one question" defects.
    static func window(anchor: Date) -> (start: Date, end: Date) {
        (anchor.addingTimeInterval(-backHours * 3600),
         anchor.addingTimeInterval(forwardHours * 3600))
    }
}

/// Is the strip parked somewhere other than now? The one definition, shared by
/// all three scrubable details.
func scrubbedAway(_ scrubTime: Date, from live: Date) -> Bool {
    abs(scrubTime.timeIntervalSince(live)) > Timeline.scrubbedSeconds
}

/// Places the scrub card on the open side of the curve with one half-card of
/// breathing room from the reading point. The card rides the fixed centerline,
/// not the scrolling canvas.
func floatingReadoutY(pointY: CGFloat, geo: TimelineGeo) -> CGFloat {
    let halfCard: CGFloat = 30
    let clearance = halfCard
    let midpoint = (geo.bodyTop + geo.bodyBottom) / 2
    let proposed = pointY < midpoint ? pointY + halfCard + clearance
                                     : pointY - halfCard - clearance
    return min(max(proposed, geo.bodyTop + halfCard), geo.bodyBottom - halfCard)
}

/// Round tick values for the tide track's fixed left axis, in DISPLAY units
/// (feet when imperial, metres otherwise) — the NEAPS "4 m / 3 m / 2 m" column.
/// `lo`/`hi` come in as metres, the units the geometry works in.
///
/// The step is the first candidate that keeps the column under seven labels, so
/// a 1.5 m creek and a 6 m Salish spring both get a readable axis instead of one
/// hardcoded interval that's too coarse for one and too fine for the other.
func axisTicks(lo: Double, hi: Double, imperial: Bool) -> [Double] {
    let l = imperial ? toFeet(lo) : lo
    let h = imperial ? toFeet(hi) : hi
    guard h > l else { return [] }
    let steps: [Double] = imperial ? [1, 2, 5, 10, 20] : [0.5, 1, 2, 5]
    let step = steps.first { (h - l) / $0 <= 6 } ?? steps[steps.count - 1]
    var out: [Double] = []
    var v = (l / step).rounded(.up) * step
    while v <= h { out.append(v); v += step }
    return out
}

/// A tick back to metres, the geometry's unit — the inverse of `toFeet`.
func axisTickMetres(_ tick: Double, imperial: Bool) -> Double {
    imperial ? tick / 3.28084 : tick
}

/// "4", "0.5", "-1" — trailing zeros are noise in an axis column.
func axisTickLabel(_ tick: Double) -> String {
    String(format: "%g", tick == 0 ? 0 : tick)   // strip a negative zero
}

/// Symmetric, display-unit ticks for the signed current chart. The curve keeps
/// its physics in knots; the fixed legend speaks the unit the boater selected.
func currentAxisTicks(maxAbsKn: Double, unit: String) -> [Double] {
    let scale = unit == "kmh" ? 1.852 : unit == "ms" ? 0.514444 : 1
    let maxValue = maxAbsKn * scale
    let steps = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20]
    let step = steps.first { maxValue / $0 <= 2 } ?? steps.last!
    return [-2, -1, 0, 1, 2].map { Double($0) * step }
        .filter { abs($0) <= maxValue * 1.01 }
}

func currentAxisKnots(_ tick: Double, unit: String) -> Double {
    tick / (unit == "kmh" ? 1.852 : unit == "ms" ? 0.514444 : 1)
}

/// Slack/max events scanned from a sampled signed-velocity series — the
/// online-gate path draws fetched official points, so events come from the
/// samples, not a harmonic engine. Slacks interpolate the zero crossing or
/// land exactly on a zero sample; each run between crossings contributes its
/// largest |sample| as a signed maximum. 15-min official samples make
/// interpolated slacks exact to a few minutes — the same series CHS's own
/// tables are printed from.
/// The current track's area fill, as one gradient stop per sample coloured by
/// the ABSOLUTE speed there (#97).
///
/// Pure and separate from the drawing, because the property that matters —
/// two gates of different speed cannot come out looking the same — is a
/// property of these stops and of nothing else. Drawing it is a detail; this
/// is the encoding.
///
/// `x` is the caller's strip-coordinate mapping and `width` the whole strip,
/// so the locations stay put under `TimelineCanvas`'s per-tile translate:
/// every tile draws the entire strip clipped to its own span.
///
/// `schematic` is the derived-gate case, and it takes the ramp OFF. Those
/// speeds are a ±1 shape meaning "flood, then ebb" — running them through an
/// absolute scale would render a one-knot gate, which is a number nobody
/// measured. It fills `SN.steel` instead: colour is state, and the state of
/// this curve's magnitude is *unknown*.
func currentFillStops(_ points: [CurrentPoint], x: (Date) -> CGFloat,
                      width: CGFloat, schematic: Bool = false) -> [Gradient.Stop] {
    guard width > 0, !points.isEmpty else { return [] }
    if schematic {
        return [Gradient.Stop(color: SN.steel.opacity(0.32), location: 0),
                Gradient.Stop(color: SN.steel.opacity(0.32), location: 1)]
    }
    // Not opaque: the night bands under the track keep a little of their
    // reading through the fill. Not the old 0.32 either — below about 0.8 the
    // top of the ramp stops arriving as bright, and a scale whose bright end
    // is not bright is not a scale.
    let alpha = 0.9
    let stops = points.map { p in
        Gradient.Stop(
            color: SN.speedColour(Timeline.rampT(forSpeedKn: abs(p.speed))).opacity(alpha),
            location: min(max(x(p.time) / width, 0), 1))
    }
    // A one-sample series is still a gradient, not a crash.
    return stops.count == 1
        ? [stops[0], Gradient.Stop(color: stops[0].color, location: 1)]
        : stops
}

/// Stroke stops for the tide line (card-look spec §4). Under the ramp floor
/// the line is the base colour; from the floor up it takes the absolute
/// tide-rate ramp, so a fast run climbs yellow to red toward its fastest
/// point and back. Locations are strip fractions, so the gradient stays put
/// under `TimelineCanvas`'s per-tile translate.
func tideRateStops(_ rates: [(time: Date, rate: Double)], x: (Date) -> CGFloat, width: CGFloat) -> [Gradient.Stop] {
    guard width > 0, !rates.isEmpty else { return [] }
    let stops = rates.map { p -> Gradient.Stop in
        let r = abs(p.rate)
        let colour = r < tideMovementRampAnchorsMHr[0]
            ? SN.graphLine
            : SN.speedColour(Timeline.rampT(forTideRateMHr: r))
        return Gradient.Stop(color: colour, location: min(max(x(p.time) / width, 0), 1))
    }
    return stops.count == 1 ? [stops[0], Gradient.Stop(color: stops[0].color, location: 1)] : stops
}

/// The fast portions of a current curve, clipped to the configured threshold.
/// These are the only paths allowed to carry the yellow→red speed fill.
func currentExcessSegments(_ points: [CurrentPoint], threshold: Double) -> [[CurrentPoint]] {
    guard points.count > 1 else { return [] }
    var segments: [[CurrentPoint]] = []
    var segment: [CurrentPoint] = []

    func append(_ point: CurrentPoint) {
        if segment.last?.time == point.time { return }
        segment.append(point)
    }
    func finish() {
        if segment.count > 1 { segments.append(segment) }
        segment = []
    }

    for (a, b) in zip(points, points.dropFirst()) {
        var cuts = [a]
        for limit in [-threshold, threshold] where (a.speed - limit) * (b.speed - limit) < 0 {
            let f = (limit - a.speed) / (b.speed - a.speed)
            cuts.append(CurrentPoint(time: a.time.addingTimeInterval(b.time.timeIntervalSince(a.time) * f),
                                     speed: limit))
        }
        cuts.append(b)
        cuts.sort { $0.time < $1.time }

        for (start, end) in zip(cuts, cuts.dropFirst()) {
            if abs((start.speed + end.speed) / 2) > threshold {
                append(start)
                append(end)
            } else {
                finish()
            }
        }
    }
    finish()
    return segments
}

func sampleEvents(_ points: [CurrentPoint]) -> [CurrentEvent] {
    guard points.count > 1 else { return [] }
    var events: [CurrentEvent] = []
    var runStart = 0
    var lastNonzeroSign: Int = 0    // +1, -1, or 0 (no nonzero yet)
    var lastWasZero = false         // true if the previous sample was exactly zero

    func closeRun(_ end: Int) {     // [runStart, end] inclusive
        guard runStart <= end else { return }  // no-op when run is empty
        // Collect only nonzero speeds; filter excludes exact-zero samples.
        let nonzeroInRun = points[runStart...end].filter { $0.speed != 0 }
        guard !nonzeroInRun.isEmpty else { return }
        let peak = nonzeroInRun.max { abs($0.speed) < abs($1.speed) }!
        events.append(CurrentEvent(time: peak.time, speed: peak.speed,
                                   kind: peak.speed > 0 ? .maxFlood : .maxEbb))
    }

    for i in 0..<points.count {
        let current = points[i]
        let sign = current.speed > 0 ? 1 : (current.speed < 0 ? -1 : 0)

        if sign == 0 {
            // Exact-zero sample: if preceded by nonzero and not consecutive zeros,
            // this zero IS the slack.
            if lastNonzeroSign != 0 && !lastWasZero {
                closeRun(i - 1)
                events.append(CurrentEvent(time: current.time, speed: 0, kind: .slack))
                runStart = i + 1
            }
            lastWasZero = true
        } else {
            // Nonzero sample
            if lastNonzeroSign != 0 && lastNonzeroSign != sign && !lastWasZero {
                // Sign opposes last nonzero, no zero between: interpolate crossing.
                let prev = points[i - 1]
                let f = abs(prev.speed) / (abs(prev.speed) + abs(current.speed))
                closeRun(i - 1)
                events.append(CurrentEvent(
                    time: prev.time.addingTimeInterval(current.time.timeIntervalSince(prev.time) * f),
                    speed: 0, kind: .slack))
                runStart = i
            }
            lastNonzeroSign = sign
            lastWasZero = false
        }
    }
    closeRun(points.count - 1)
    return events.sorted { $0.time < $1.time }
}

/// The useful current-cycle aggregate: the signed difference between the
/// adjoining flood and ebb maxima around a reading, expressed in knots.
func currentPeakToPeakRange(_ events: [CurrentEvent], around time: Date) -> Double? {
    let maxima = events.filter { $0.kind != .slack }.sorted { $0.time < $1.time }
    guard let before = maxima.last(where: { $0.time <= time }),
          let after = maxima.first(where: { $0.time > time }) else { return nil }
    return abs(after.speed - before.speed)
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
    /// The local midnight this window is built around. Geometry only.
    let anchor: Date
    /// The REAL local midnight. Language and liveness only — the
    /// Today/Tomorrow labels, the now-marker, return-to-now. Never geometry.
    let today: Date
    let start: Date          // anchor - 48h, and only when the anchor is today
    let end: Date            // anchor + 180h
    let days: [TimelineDay]  // offsets -3…8 (the ends are DST/moon slack, see dayChrome)
    let tidePoints: [TidePoint]        // empty when current-only
    let tideRates: [TideRatePoint]     // index-aligned with tidePoints (#95)
    let tideExtremes: [TideExtreme]
    let currentPoints: [CurrentPoint]  // empty when tide-only
    let currentEvents: [CurrentEvent]
    let snapTimes: [Date]    // prototype stops(): turns + slacks/maxes + sun events

    /// The workable sub-threshold window around each slack, computed ONCE here
    /// off the same `currentPoints` the strip draws (gutter spec §3). The green
    /// band on the strip and the duration in the readout are therefore the same
    /// numbers by construction, not by two call sites agreeing.
    ///
    /// Empty for a derived gate: `build(gate:)` synthesises a schematic ±1
    /// shape, and a 0.5 kn window measured off a shape would be fiction.
    let slackWindows: [(slack: Date, start: Date, end: Date)]
    /// The setting used to build `slackWindows`, retained so the chart cannot
    /// render a different threshold than the duration it reports.
    var slackThreshold: Double = defaultSlackThresholdKn

    /// True when `currentPoints` is that schematic ±1 shape rather than
    /// measured speed. Same fiction, one step further on: the shape says
    /// "flood, then ebb", it does not say *one knot*. Colouring it through
    /// the absolute ramp (#97) would print a speed the app has never been
    /// told — so the ramp is skipped and the fill goes to `SN.steel`, which
    /// is already this app's word for a state it does not know.
    var speedsAreSchematic = false

    var hasTide: Bool { !tidePoints.isEmpty }
    var hasCurrent: Bool { !currentPoints.isEmpty }
    var totalWidth: CGFloat { x(end) }

    func containingSlackWindow(at time: Date) -> (slack: Date, start: Date, end: Date)? {
        slackWindows.first { $0.start <= time && time <= $0.end }
    }

    /// The list's window: the anchor's own midnight → +7d. Deliberately
    /// NARROWER than `start…end` — the strip carries `Timeline.centerPad` more
    /// so the last listed event can still park under the centerline.
    ///
    /// This lives here rather than in the four detail views because all four
    /// were computing it identically off `today`, and the anchor change would
    /// otherwise have to land correctly in four places.
    var scheduleRange: ClosedRange<Date> {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return anchor...cal.date(byAdding: .day, value: Int(Timeline.scheduleDays), to: anchor)!
    }

    /// Is `t` inside the drawn window? The guard on anything positioned by
    /// absolute time rather than by the window itself.
    func contains(_ t: Date) -> Bool { t >= start && t <= end }

    /// The days with any part of them on the strip — the ONE definition of what
    /// day chrome draws, derived from the window so it can't drift again. It
    /// already did: a literal `offset <= 5`, correct for the 132h strip it was
    /// written against, outlived it and left days 6 and 7 with no night bands,
    /// no daylight tint, no label and no sun dots — while their sun events
    /// stayed in `snapTimes`, so the magnet parked the centerline on a sunrise
    /// that was drawn nowhere.
    ///
    /// An OVERLAP test, not `contains($0.start)`: on the fall-back DST day two
    /// calendar days back is 49 hours, so a back-padded `start` lands AFTER
    /// that day's midnight and a midnight-in-window test would drop 23 visible
    /// hours of chrome — the same bug, once a year. Don't "simplify" this back
    /// to a midnight test. `day(of: start)` is the day the window opens inside,
    /// and it is visible whether its own midnight is or not. `days` runs to offset 8, which is never visible: it exists so the
    /// last visible night can find the following sunrise for its moon.
    var visibleDays: [TimelineDay] {
        let firstStart = day(of: start)?.start ?? .distantPast
        return days.filter { $0.start >= firstStart && $0.start <= end }
    }

    func x(_ t: Date) -> CGFloat {
        CGFloat(t.timeIntervalSince(start) / 3600) * Timeline.pph
    }
    func time(atX x: CGFloat) -> Date {
        start.addingTimeInterval(Double(x / Timeline.pph) * 3600)
    }
    func day(of t: Date) -> TimelineDay? {
        days.last { $0.start <= t }
    }
    /// A day's real end — the next day's start. `days` is contiguous and built
    /// by calendar-day adds, so this is exact across DST, where a local day is
    /// 23 or 25 hours and `start + 86_400` misses midnight by an hour. The
    /// fallback only exists for the final offset-8 day, which is never visible.
    func dayEnd(_ day: TimelineDay) -> Date {
        if let next = days.first(where: { $0.start > day.start }) { return next.start }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(byAdding: .day, value: 1, to: day.start)!
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

    /// Everything both `build` overloads need before touching tide/current/
    /// gate data: the timezone-anchored window and the per-day sun chrome.
    /// Shared so the two builds can never drift on how "today" or the sun
    /// times are computed.
    private struct DayChrome {
        let tz: TimeZone
        let anchor: Date
        let today: Date
        let start: Date
        let end: Date
        let days: [TimelineDay]
    }

    private static func dayChrome(tz: TimeZone, lat: Double, lon: Double,
                                  anchor: Date, now: Date) -> DayChrome {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: now)   // the caller's clock, not the app's
        let w = Timeline.window(anchor: anchor)
        // -3, not the -2 the 48h back-pad suggests: the look-back spans THREE
        // calendar days whenever a spring-forward falls inside it. The day
        // after that transition is 23 hours long, so `anchor - 48h` lands an
        // hour BEFORE the second day back began — in Pacific, the two anchors
        // following each March change (e.g. 2026-03-09 and -10, start
        // 2026-03-06 23:00). A day the window reaches but `days` never built
        // draws no chrome at all, which is the 36-hour gap this branch already
        // fixed once, one hour wide and twice a year.
        //
        // Costs one `sunEvents` call per build; `visibleDays` picks -3 up only
        // when the window actually reaches it, so nothing else changes. 8 is
        // the other end: never visible, it exists so the last visible night
        // (offset 7) can find the following sunrise for its moon.
        let days: [TimelineDay] = (-3...8).map { off in
            let d0 = cal.date(byAdding: .day, value: off, to: anchor)!
            let sun = SunMoon.sunEvents(lat: lat, lon: lon, tz: tz, day: d0)
            return TimelineDay(offset: off, start: d0,
                               sunrise: sun.first { $0.kind == .sunrise }?.time,
                               sunset: sun.first { $0.kind == .sunset }?.time)
        }
        return DayChrome(tz: tz, anchor: anchor, today: today,
                         start: w.start, end: w.end, days: days)
    }

    // Widen the event scans a touch so nothing at the edges is clipped.
    private static let eventPad = 6.0 * 3600

    /// A derived gate's strip is single-track: the schematic ±1 half-sine with
    /// slack events only. The port is the SOURCE of the slack times (engineGate
    /// reads it), never a drawn track (split-scrubbers spec §3).
    static func build(gate: DerivedGateRecord, now: Date, anchor: Date) -> TimelineData {
        build(tide: nil, current: nil, now: now, anchor: anchor, gate: gate)
    }

    /// The online-gate path: current-only strip drawn from fetched CHS/NOAA
    /// samples rather than a harmonic engine. Events come from `sampleEvents`
    /// scanning the unclipped fetched series (mirrors the padded engine scan
    /// below) so a slack/max sitting just outside the strip window still
    /// counts if it lands within the pad; only `currentPoints`/`snapTimes`
    /// clip to the visible window.
    static func build(onlinePoints: [CurrentPoint], tz: TimeZone, lat: Double, lon: Double,
                      now: Date, anchor: Date, threshold: Double = slackThresholdKn) -> TimelineData {
        let chrome = dayChrome(tz: tz, lat: lat, lon: lon, anchor: anchor, now: now)
        let start = chrome.start, end = chrome.end

        let currentPoints = onlinePoints.filter { $0.time >= start && $0.time <= end }
        let currentEvents = sampleEvents(onlinePoints).filter {
            $0.time >= start.addingTimeInterval(-eventPad) && $0.time <= end.addingTimeInterval(eventPad)
        }

        // Online gates DO get slack windows, unlike derived gates. The reason
        // the derived path has none is that its curve is a schematic ±1 shape,
        // so a sub-threshold window measured off it would be fiction (gutter
        // spec §3). These are fetched OFFICIAL samples — real velocities, just
        // downloaded rather than computed — so the window means exactly what it
        // means at a harmonic station. Same computation, same series the strip
        // draws.
        let windows = currentEvents.filter { $0.kind == .slack }.compactMap { e in
            slackWindow(currentPoints, around: e.time,
                        threshold: threshold)
                .map { (slack: e.time, start: $0.start, end: $0.end) }
        }

        let sunTimes = chrome.days.filter { $0.offset <= 7 }
            .flatMap { [$0.sunrise, $0.sunset].compactMap { $0 } }
        let snaps = Array(Set(currentEvents.map(\.time) + sunTimes
                              + windows.flatMap { [$0.start, $0.end] }))
            .filter { $0 >= start && $0 <= end }.sorted()

        return TimelineData(tz: chrome.tz, anchor: chrome.anchor, today: chrome.today,
                            start: start, end: end, days: chrome.days,
                            tidePoints: [], tideRates: [], tideExtremes: [],
                            currentPoints: currentPoints, currentEvents: currentEvents,
                            snapTimes: snaps, slackWindows: windows, slackThreshold: threshold)
    }

    static func build(tide: TideStationRecord?, current: CurrentStationRecord?,
                      now: Date, anchor: Date, gate: DerivedGateRecord? = nil,
                      threshold: Double = slackThresholdKn) -> TimelineData {
        // The primary station names the timezone and the sky position.
        let tz = gate?.gate.tz ?? current?.tz ?? tide?.tz ?? .current
        let lat = gate?.gate.latitude ?? current?.latitude ?? tide?.latitude ?? 48.5
        let lon = gate?.gate.longitude ?? current?.longitude ?? tide?.longitude ?? -123.0
        let chrome = dayChrome(tz: tz, lat: lat, lon: lon, anchor: anchor, now: now)
        let today = chrome.today, start = chrome.start, end = chrome.end, days = chrome.days

        let pad = eventPad
        var tidePoints: [TidePoint] = []
        var tideRates: [TideRatePoint] = []
        var tideExtremes: [TideExtreme] = []
        if let tide {
            let s = tide.engineStation
            tidePoints = s.heights(from: start, to: end, step: 600)
            tideRates = s.rates(from: start, to: end, step: 600)
            tideExtremes = s.extremes(from: start.addingTimeInterval(-pad),
                                      to: end.addingTimeInterval(pad))
        }
        var currentPoints: [CurrentPoint] = []
        var currentEvents: [CurrentEvent] = []
        // Only a real current station gets windows — computed inside this
        // block (rather than behind a later `current != nil` guard) so the
        // gate branch below, which overwrites `currentPoints`/`currentEvents`
        // with schematic data, can never make windows out of that fiction.
        var windows: [(slack: Date, start: Date, end: Date)] = []
        if let current {
            let s = current.engineStation
            currentPoints = s.speeds(from: start, to: end, step: 600)
            currentEvents = s.events(from: start.addingTimeInterval(-pad),
                                     to: end.addingTimeInterval(pad))
            windows = currentEvents.filter { $0.kind == .slack }.compactMap { e in
                slackWindow(currentPoints, around: e.time,
                            threshold: threshold)
                    .map { (slack: e.time, start: $0.start, end: $0.end) }
            }
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

        let sunTimes = days.filter { $0.offset <= 7 }
            .flatMap { [$0.sunrise, $0.sunset].compactMap { $0 } }
        let snaps = Array(Set(tideExtremes.map(\.time) + tideFlowArrows(tideRates).map(\.time)
                              + currentEvents.map(\.time) + sunTimes
                              + windows.flatMap { [$0.start, $0.end] }))
            .filter { $0 >= start && $0 <= end }.sorted()

        return TimelineData(tz: tz, anchor: chrome.anchor, today: today, start: start, end: end, days: days,
                            tidePoints: tidePoints, tideRates: tideRates, tideExtremes: tideExtremes,
                            currentPoints: currentPoints, currentEvents: currentEvents,
                            snapTimes: snaps, slackWindows: windows,
                            slackThreshold: threshold,
                            speedsAreSchematic: gate != nil)
    }
}

// MARK: - Vertical geometry (prototype geo())

/// Every number in here is a literal point, and that is why the chart's own
/// labels are the one place in this branch that keeps a fixed `.system(size:)`
/// — text scaled inside fixed-point geometry degrades by OVERPRINTING the
/// chart, not by wrapping (measured at AX5). Making the labels scale means
/// making this geometry scale with them — a real chart-layout change, not a
/// font swap. Until then the labels stay fixed; don't "finish the job" here.
///
/// The card look (spec §2): day chrome on top, one plot box, one time row
/// under it. Readings annotate the curve itself, so both tracks share the
/// same box; `tideY`/`curY` map data onto it.
struct TimelineGeo {
    let hasTide: Bool
    let hasCurrent: Bool
    let height: CGFloat = 284
    let dayY: CGFloat = 20
    let sunY: CGFloat = 34   // also the night moons' centre line
    let tideTop: CGFloat
    let tideBottom: CGFloat
    let bodyTop: CGFloat
    let curTop: CGFloat
    let curBottom: CGFloat
    let bodyBottom: CGFloat
    let tideMid: Double
    let tideSpan: Double     // half-range, padded (prototype amp*1.18)
    let maxAbsCur: Double    // prototype mxv = cur.mx*1.05

    /// The plot box. 60 clears the moon disc (sunY 34 + radius 8) with room
    /// for a dot's halo; 250 leaves the time row and a margin under it.
    private static let plotTop: CGFloat = 60
    private static let plotBottom: CGFloat = 250

    init(data: TimelineData) {
        hasTide = data.hasTide
        hasCurrent = data.hasCurrent
        // ONE track box, whichever track fills it. The switch resolves a
        // hypothetical both-tracks input tide-first instead of drawing two
        // curves through each other.
        switch (hasTide, hasCurrent) {
        case (true, _):
            tideTop = Self.plotTop; tideBottom = Self.plotBottom
            curTop = 0; curBottom = 0
        default:
            tideTop = 0; tideBottom = 0
            curTop = Self.plotTop; curBottom = Self.plotBottom
        }
        bodyTop = hasTide ? tideTop : curTop
        bodyBottom = hasCurrent ? curBottom : tideBottom
        let heights = data.tidePoints.map(\.height)
        let mn = heights.min() ?? 0, mx = heights.max() ?? 1
        tideMid = (mn + mx) / 2
        // 1.06: the padding only has to clear a dot and its halo now that the
        // readings sit on a band across the middle rather than at the turns.
        tideSpan = max((mx - mn) / 2, 0.01) * 1.06
        maxAbsCur = max(data.currentPoints.map { abs($0.speed) }.max() ?? 1, 0.01) * 1.05
    }

    var zeroY: CGFloat { (curTop + curBottom) / 2 }
    var curHalf: CGFloat { (curBottom - curTop) / 2 - 3 }
    /// The one row of absolute times, under the plot (current spec §5.5:
    /// one home per surface).
    var timeY: CGFloat { bodyBottom + 18 }

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

    /// True set bearings for this station's flood and ebb, so a max's glyph on
    /// the chart is the compass arrow the schedule pill and the readout already
    /// show — "the stream runs THIS way" — rather than an up/down arrow that
    /// only restates which side of the zero line the peak sits on. Nil on a
    /// derived gate: it knows slack times and nothing about set, and inventing
    /// a bearing there would be the schematic-curve mistake in glyph form.
    var floodDeg: Double? = nil
    var ebbDeg: Double? = nil

    /// A `Canvas` renders into ONE backing texture and Metal caps that at
    /// 8192px on a side. The 228-hour strip is `228 * pph` = 4104pt wide,
    /// tripled on a 3× phone: 12312px, half again past the cap, and the entire
    /// chart would render EMPTY — no curve, no day chrome, no labels, and no
    /// error. (Caught on the NEAPS pass, at 180h × 18 = 9720px, when 180h × 12
    /// = 6480px had fit; the week widened it further. The left axis kept drawing,
    /// because it's a separate SwiftUI overlay, which is exactly what made the
    /// blank canvas look like a layout bug rather than a texture limit.)
    ///
    /// Slicing the strip into tiles gives each its own layer, so the cap now
    /// applies per tile instead of to the whole timeline and `pph` is free to
    /// move again — five tiles at today's width. Every tile runs the same
    /// drawing code translated into strip coordinates and clipped to its own
    /// slice — the clip is what makes this safe, since the translucent night
    /// bands and area fills would otherwise stack on each other wherever two
    /// tiles overdrew.
    static let tileWidth: CGFloat = 900

    /// Half-width of the twilight fade on each night band's edges, in hours
    /// each side of sunset and sunrise. 0.75h ≈ civil twilight plus a
    /// shoulder; at 18pt/h the whole transition is 27pt.
    static let twilightHours = 0.75

    var body: some View {
        let tiles = Array(0..<max(Int((data.totalWidth / Self.tileWidth).rounded(.up)), 1))
        HStack(spacing: 0) {
            ForEach(tiles, id: \.self) { i in
                let x0 = CGFloat(i) * Self.tileWidth
                let w = min(Self.tileWidth, data.totalWidth - x0)
                Canvas { ctx, _ in
                    ctx.translateBy(x: -x0, y: 0)
                    ctx.clip(to: Path(CGRect(x: x0, y: 0, width: w, height: geo.height)))
                    draw(ctx)
                }
                .frame(width: w, height: geo.height)
            }
        }
        .frame(width: data.totalWidth, height: geo.height)
    }

    private func draw(_ ctx: GraphicsContext) {
        drawDayChrome(ctx)
        if geo.hasTide { drawTide(ctx) }
        if geo.hasCurrent { drawCurrent(ctx) }
    }

    // MARK: Card-look primitives, shared by both tracks

    /// Where `now` falls on the strip: 0 when it is before the window (an
    /// anchored month out — everything is forecast), the full width when it
    /// is after it (everything is past).
    private var nowX: CGFloat {
        now <= data.start ? 0 : now >= data.end ? data.totalWidth : data.x(now)
    }

    /// A label or dot for a moment already passed fades like the past line.
    private func fade(_ t: Date) -> Double { t < now ? CurveStyle.pastLabelFade : 1 }

    /// The past is context, the future is the forecast: the same path drawn
    /// muted left of now and at full strength right of it, split by clip.
    private func strokeSplitAtNow(_ ctx: GraphicsContext, _ path: Path,
                                  with shading: GraphicsContext.Shading,
                                  lineWidth: CGFloat = CurveStyle.lineWidth) {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        var past = ctx
        past.opacity = CurveStyle.pastLineOpacity
        past.clip(to: Path(CGRect(x: 0, y: 0, width: nowX, height: geo.height)))
        past.stroke(path, with: shading, style: style)
        var future = ctx
        future.clip(to: Path(CGRect(x: nowX, y: 0, width: data.totalWidth - nowX, height: geo.height)))
        future.stroke(path, with: shading, style: style)
    }

    /// A halo that truly matches whatever is behind the canvas: erase a ring
    /// around the dot (destinationOut punches through the fill and the night
    /// bands alike) rather than paint a guess at the ground colour.
    private func punchHalo(_ ctx: GraphicsContext, at p: CGPoint, dotRadius: CGFloat) {
        let radius = dotRadius + CurveStyle.haloGap
        var eraser = ctx
        eraser.blendMode = .destinationOut
        eraser.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(.black))
    }

    private func dot(_ ctx: GraphicsContext, at p: CGPoint, color: Color) {
        punchHalo(ctx, at: p, dotRadius: CurveStyle.dotRadius)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - CurveStyle.dotRadius, y: p.y - CurveStyle.dotRadius,
                                        width: CurveStyle.dotRadius * 2, height: CurveStyle.dotRadius * 2)),
                 with: .color(color))
    }

    /// The card's white now dot, riding the curve. Only when now is on the strip.
    private func drawNowDot(_ ctx: GraphicsContext, at p: CGPoint) {
        guard data.contains(now) else { return }
        let r = CurveStyle.nowDotDiameter / 2
        punchHalo(ctx, at: p, dotRadius: r)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .color(SN.paper))
    }

    /// The dotted datum/zero reference line, full strip width.
    private func referenceLine(_ ctx: GraphicsContext, at lineY: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: lineY))
        path.addLine(to: CGPoint(x: data.totalWidth, y: lineY))
        ctx.stroke(path, with: .color(SN.foam.opacity(CurveStyle.referenceLineOpacity)),
                   style: StrokeStyle(lineWidth: 1, dash: CurveStyle.referenceLineDash))
    }

    /// One axis time on the bottom row, faded when passed.
    private func axisTime(_ ctx: GraphicsContext, _ t: Date) {
        ctx.draw(Text(chartTime(t, data.tz))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.7 * fade(t))),
                 at: CGPoint(x: data.x(t), y: geo.timeY), anchor: .center)
    }

    // Night bands, day tint, day labels, sun markers, per-night moons —
    // continuous across midnight (prototype's per-day rects abut exactly).
    private func drawDayChrome(_ ctx: GraphicsContext) {
        let visible = data.visibleDays
        // Night and day bands span the strip's full height (#246) and fade
        // into each other across twilight — a hard edge at sunset read as a
        // rectangle pasted onto the chart. One rect per NIGHT, sunset to the
        // next day's sunrise straddling midnight (the moon loop below pairs
        // days the same way), so the fades land on the sun events and
        // nothing abuts at midnight. `data.days` rather than `visible`: the
        // night before the first visible sunrise belongs to a day off the
        // strip, and the tile clip discards what is off-canvas.
        let fadeW = CGFloat(Self.twilightHours) * Timeline.pph
        func fadedBand(from a: CGFloat, to b: CGFloat, color: Color, opacity: Double) {
            guard b > a else { return }
            let rect = CGRect(x: a - fadeW, y: 0, width: (b - a) + 2 * fadeW, height: geo.bodyBottom)
            let ramp = min(2 * fadeW / rect.width, 0.5)
            ctx.fill(Path(rect), with: .linearGradient(
                Gradient(stops: [
                    .init(color: color.opacity(0), location: 0),
                    .init(color: color.opacity(opacity), location: ramp),
                    .init(color: color.opacity(opacity), location: 1 - ramp),
                    .init(color: color.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
        }
        for day in data.days {
            guard let set = day.sunset,
                  let nextRise = data.days.first(where: { $0.offset == day.offset + 1 })?.sunrise
            else { continue }
            fadedBand(from: data.x(set), to: data.x(nextRise), color: SN.night, opacity: 0.52)
        }
        for day in data.days {
            guard let rise = day.sunrise, let set = day.sunset else { continue }
            fadedBand(from: data.x(rise), to: data.x(set), color: Color(hex: 0xA8CAE0), opacity: 0.07)
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
                ctx.fill(Path(ellipseIn: CGRect(x: cx - glowR, y: geo.sunY - glowR,
                                                width: glowR * 2, height: glowR * 2)),
                         with: .radialGradient(
                            Gradient(stops: [
                                .init(color: Color(hex: 0xE6EEFF, opacity: 0.95 * (0.1 + moon.fraction * 0.66)), location: 0),
                                .init(color: Color(hex: 0xCFE0FF, opacity: 0.28 * (0.1 + moon.fraction * 0.66)), location: 0.45),
                                .init(color: Color(hex: 0xCFE0FF, opacity: 0), location: 1)]),
                            center: CGPoint(x: cx, y: geo.sunY), startRadius: 0, endRadius: glowR))
                let r: CGFloat = 8
                let disc = CGRect(x: cx - r, y: geo.sunY - r, width: 2 * r, height: 2 * r)
                let shift = moonLimbShift(fraction: moon.fraction, waxing: moon.waxing, radius: r)
                ctx.drawLayer { l in
                    l.clip(to: Path(ellipseIn: disc))
                    l.fill(Path(ellipseIn: disc), with: .color(Color(hex: 0xEEF4FF)))
                    l.fill(Path(ellipseIn: disc.offsetBy(dx: shift, dy: 0)),
                           with: .color(SN.moonLimb))
                }
                ctx.stroke(Path(ellipseIn: disc), with: .color(.white.opacity(0.3)), lineWidth: 0.6)
            }
            // Day label at local noon. Fixed size, not `.caption2` — see the
            // TimelineGeo doc comment: `dayY` is 20 and the sun dot is at 34.
            ctx.draw(Text(relativeDayLabel(day.start, data.tz, today: data.today))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SN.foam.opacity(0.85)),
                     at: CGPoint(x: data.x(day.start.addingTimeInterval(12 * 3600)), y: geo.dayY),
                     anchor: .center)
            ctx.draw(Text(monthDay(day.start, data.tz))
                        .font(.system(size: 10, weight: .medium).monospaced())
                        .foregroundStyle(SN.foam.opacity(0.48)),
                     at: CGPoint(x: data.x(day.start.addingTimeInterval(12 * 3600)), y: geo.dayY + 17),
                     anchor: .center)
            // Sun rise/set dots + "↑5:24AM" labels.
            for (t, arrow) in [(day.sunrise, "↑"), (day.sunset, "↓")] {
                guard let t else { continue }
                let x = data.x(t)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: geo.sunY - 3.5, width: 7, height: 7)),
                         with: .color(SN.sun))
                ctx.draw(Text("\(arrow)\(cardTime(t, data.tz).replacingOccurrences(of: " ", with: ""))")
                            .font(.system(size: 11, weight: .medium).monospaced())
                            .foregroundStyle(SN.sunrise),
                         at: CGPoint(x: x, y: geo.dayY), anchor: .center)
            }
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
        // A tide's intensity is the water level itself, so the fade is
        // vertical (the card, via Neaps): strongest at the surface, easing
        // toward the bottom of the box.
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [SN.graphLine.opacity(CurveStyle.fillOpacity),
                              SN.graphLine.opacity(CurveStyle.tideFillFloor)]),
            startPoint: CGPoint(x: 0, y: geo.tideTop),
            endPoint: CGPoint(x: 0, y: geo.tideBottom)))

        // Chart datum, the reference every printed height is quoted against.
        // Drawn only when datum is inside the plotted span; a week where the
        // tide never drops near it would otherwise get a rule pinned to an
        // edge it isn't at.
        if 0 > geo.tideMid - geo.tideSpan && 0 < geo.tideMid + geo.tideSpan {
            referenceLine(ctx, at: geo.tideY(0))
        }

        // Rate of rise as line colour (#95, card-look spec §4): base blue
        // under the ramp floor, the absolute tide-rate ramp above it. The
        // past fade applies on top.
        // ponytail: one stop per sample (~1,400 across the strip). Thin to
        // every Nth sample if the canvas ever stalls on an iPad.
        let stops = tideRateStops(data.tideRates.map { (time: $0.time, rate: $0.rate) },
                                  x: data.x, width: data.totalWidth)
        let shading: GraphicsContext.Shading = stops.isEmpty
            ? .color(SN.graphLine)
            : .linearGradient(Gradient(stops: stops),
                              startPoint: .zero, endPoint: CGPoint(x: data.totalWidth, y: 0))
        strokeSplitAtNow(ctx, line, with: shading)

        // Turns: a dot on the curve, the reading on a band across the middle
        // of the box with its pointer on the dot's side, the time on the
        // bottom row. Teal for a high and amber for a low, as on the card.
        let margin = 0.3 * 3600
        for e in data.tideExtremes where e.time >= data.start.addingTimeInterval(margin)
                                      && e.time <= data.end.addingTimeInterval(-margin) {
            let x = data.x(e.time), y = geo.tideY(e.height)
            let high = e.kind == .high
            let f = fade(e.time)
            let tint = (high ? SN.graphHigh : SN.graphLow).opacity(f)
            dot(ctx, at: CGPoint(x: x, y: y), color: tint)
            // The reading hangs off the turn toward the plot middle — down
            // from a high, up from a low — with the to-bar arrow under it:
            // the same rule the current track's peaks follow, and clear of
            // the axis column's tick labels. No unit: the fixed axis column
            // carries it once.
            let toward: CGFloat = high ? 1 : -1
            let cy = y + toward * 23
            ctx.draw(Text(formatHeight(e.height, imperial: imperial))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(f)),
                     at: CGPoint(x: x, y: cy - 7), anchor: .center)
            // ⤒ / ⤓ — arrow TO BAR: a plain ↑ says "rising", the one thing no
            // longer true at a high.
            ctx.draw(Text(high ? "⤒" : "⤓")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint),
                     at: CGPoint(x: x, y: cy + 8), anchor: .center)
            axisTime(ctx, e.time)
        }

        drawNowDot(ctx, at: CGPoint(x: data.x(now), y: geo.tideY(data.heightAt(now))))
    }

    /// This station's set for one direction, nil on a derived gate.
    private func deg(_ flood: Bool) -> Double? { flood ? floodDeg : ebbDeg }

    private func drawCurrent(_ ctx: GraphicsContext) {
        var line = Path()
        for (i, p) in data.currentPoints.enumerated() {
            let pt = CGPoint(x: data.x(p.time), y: geo.curY(p.speed))
            i == 0 ? line.move(to: pt) : line.addLine(to: pt)
        }
        let runs = mergeWindows(data.slackWindows.map { (start: $0.start, end: $0.end) })

        if !data.speedsAreSchematic {
            // Hot water starts at the comfort limit, never at zero: only the
            // excess above the threshold is inked, on the absolute ramp (#97).
            for segment in currentExcessSegments(data.currentPoints, threshold: data.slackThreshold) {
                let positive = segment[0].speed > 0
                let thresholdY = geo.curY(positive ? data.slackThreshold : -data.slackThreshold)
                var excess = Path()
                for (i, point) in segment.enumerated() {
                    let p = CGPoint(x: data.x(point.time), y: geo.curY(point.speed))
                    i == 0 ? excess.move(to: p) : excess.addLine(to: p)
                }
                excess.addLine(to: CGPoint(x: data.x(segment.last!.time), y: thresholdY))
                excess.addLine(to: CGPoint(x: data.x(segment[0].time), y: thresholdY))
                excess.closeSubpath()
                ctx.fill(excess, with: .linearGradient(
                    Gradient(colors: [SN.speedColour(0), SN.speedColour(0.5), SN.speedColour(1)]),
                    startPoint: CGPoint(x: 0, y: thresholdY),
                    endPoint: CGPoint(x: 0, y: positive ? geo.curTop : geo.curBottom)))
            }
            // The limit made visible everywhere at once (spec §5.2), quiet:
            // two hairlines, and no zero stroke while they are drawn (§7.4).
            for speed in [-data.slackThreshold, data.slackThreshold] {
                var threshold = Path()
                threshold.move(to: CGPoint(x: 0, y: geo.curY(speed)))
                threshold.addLine(to: CGPoint(x: data.totalWidth, y: geo.curY(speed)))
                ctx.stroke(threshold, with: .color(SN.go.opacity(0.35)), lineWidth: 1)
            }
        } else {
            var area = line
            area.addLine(to: CGPoint(x: data.totalWidth, y: geo.zeroY))
            area.addLine(to: CGPoint(x: 0, y: geo.zeroY))
            area.closeSubpath()
            let fillStops = currentFillStops(data.currentPoints, x: data.x,
                                             width: data.totalWidth, schematic: true)
            if !fillStops.isEmpty {
                ctx.fill(area, with: .linearGradient(
                    Gradient(stops: fillStops),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: data.totalWidth, y: 0)))
            }
            referenceLine(ctx, at: geo.zeroY)
        }

        strokeSplitAtNow(ctx, line, with: .color(SN.graphLine))

        // The run is the mark (spec §5.2): the line itself turns the go
        // colour between each run's interpolated edges, over a wider
        // round-capped eraser so the seam at both ends is a clear ring, not
        // a slanted cut. The run's opening gets the track's only dot; its
        // time goes on the bottom row.
        for run in runs {
            var seg = Path()
            seg.move(to: CGPoint(x: data.x(run.start), y: geo.curY(data.velocityAt(run.start))))
            for p in data.currentPoints where p.time > run.start && p.time < run.end {
                seg.addLine(to: CGPoint(x: data.x(p.time), y: geo.curY(p.speed)))
            }
            seg.addLine(to: CGPoint(x: data.x(run.end), y: geo.curY(data.velocityAt(run.end))))
            var eraser = ctx
            eraser.blendMode = .destinationOut
            eraser.stroke(seg, with: .color(.black),
                          style: StrokeStyle(lineWidth: CurveStyle.lineWidth + CurveStyle.haloGap * 2,
                                             lineCap: .round))
            strokeSplitAtNow(ctx, seg, with: .color(SN.go))
            dot(ctx, at: CGPoint(x: data.x(run.start), y: geo.curY(data.velocityAt(run.start))),
                color: SN.go.opacity(fade(run.start)))
        }

        let margin = 0.3 * 3600
        let onStrip = { (t: Date) in
            t >= data.start.addingTimeInterval(margin) && t <= data.end.addingTimeInterval(-margin)
        }
        let slacks = data.currentEvents.filter { $0.kind == .slack }.map(\.time)
        for t in currentAxisMoments(runs: runs, slacks: slacks) where onStrip(t) {
            axisTime(ctx, t)
        }

        for e in data.currentEvents where onStrip(e.time) {
            let x = data.x(e.time)
            switch e.kind {
            case .slack:
                // No window (a violent gate the sampling steps over, every
                // derived gate): a hairline rather than a run — a zero-width
                // window must not look like a window (§5.3). Where a run
                // exists, the run is the mark.
                if !runs.contains(where: { $0.contains(e.time) }) {
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: geo.curTop))
                    tick.addLine(to: CGPoint(x: x, y: geo.curBottom))
                    ctx.stroke(tick, with: .color(SN.go.opacity(0.35 * fade(e.time))), lineWidth: 1)
                }
            case .maxFlood, .maxEbb:
                // Context, not the event (§5.1): no dot. The speed hangs off
                // the peak inside its lobe, toward the zero line, with the set
                // arrow under it — off the threshold hairlines and the axis
                // column's ±threshold labels, which is where a zero-line band
                // collided. No unit: the fixed axis column carries it once.
                let flood = e.kind == .maxFlood
                let f = fade(e.time)
                let ink = SN.foam.opacity(f)
                let toward: CGFloat = flood ? 1 : -1      // toward the zero line
                let cy = geo.curY(e.speed) + toward * 23
                if !data.speedsAreSchematic {
                    ctx.draw(Text(formatSpeed(abs(e.speed), unit: speedUnit))
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .foregroundStyle(ink),
                             at: CGPoint(x: x, y: cy - 7), anchor: .center)
                }
                if let d = deg(flood) {
                    ctx.drawLayer { l in
                        l.translateBy(x: x, y: cy + 8)
                        l.rotate(by: .degrees(d))
                        l.draw(Text("↑").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ink),
                               at: .zero, anchor: .center)
                    }
                }
            }
        }

        drawNowDot(ctx, at: CGPoint(x: data.x(now), y: geo.curY(data.velocityAt(now))))
    }
}

/// "Today" / "Tomorrow" / "Yesterday", short weekday otherwise (prototype
/// dayName). Takes the day itself and the caller's today, never an offset: on an
/// anchored strip `TimelineDay.offset` is days-from-anchor, so feeding it here
/// would label the first day of a September window "Today".
func relativeDayLabel(_ dayStart: Date, _ tz: TimeZone, today: Date) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return switch cal.dateComponents([.day], from: today, to: dayStart).day ?? 0 {
    case 0: "Today"
    case 1: "Tomorrow"
    case -1: "Yesterday"
    default: shortWeekday(dayStart, tz)
    }
}

// MARK: - The scroll host: native pan + momentum, magnet on settle

struct TimelineScrubber: UIViewRepresentable {
    let data: TimelineData
    let geo: TimelineGeo
    let imperial: Bool
    let speedUnit: String
    let now: Date
    var floodDeg: Double? = nil
    var ebbDeg: Double? = nil
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
        // The window's width is a constant 228h for every anchor (the 48h
        // back-pad is unconditional, #67 item 1) — an anchor pick alone can no
        // longer change `totalWidth`. The guard below still earns its keep for
        // whatever DOES change it: the host frame and `contentSize` were set
        // once in `makeUIView` and never again, so a canvas that grew or
        // shrank without a resize here lays itself out CENTRED inside the
        // stale host view — off from where the offset arithmetic below assumes
        // the window starts — and the viewport can land on empty space. A
        // blank strip under a perfectly correct readout, which is exactly what
        // shipping this fix's first attempt produced (back when an anchor pick
        // was still the trigger).
        //
        // Resize BEFORE the offset: the offset is set against these bounds, and
        // shrinking `contentSize` afterwards lets UIKit clamp it out from under
        // us.
        if abs(sv.contentSize.width - data.totalWidth) > 0.5 {
            co.host?.view.frame = CGRect(x: 0, y: 0, width: data.totalWidth, height: geo.height)
            sv.contentSize = CGSize(width: data.totalWidth, height: geo.height)
        }
        if !co.didInitialCenter {
            co.centerIfNeeded(sv)
            return
        }
        // External scrub (event tap, return-to-now): jump the strip so the
        // requested time sits under the centerline (prototype scrubTo/centerNow
        // are instant). User-driven scrolling round-trips within a point.
        // `!co.nudging` for the opening slide: it suppresses scrubTime writes,
        // so `desired` sits at the nudge's destination while the offset is
        // still travelling — without the guard the first re-render jumps
        // straight there and the hint never plays.
        let desired = data.x(scrubTime) - sv.bounds.width / 2
        if abs(desired - sv.contentOffset.x) > 1,
           !sv.isDragging, !sv.isDecelerating, !co.magneting, !co.nudging {
            sv.contentOffset = CGPoint(x: desired, y: 0)
        }
    }

    private var canvas: TimelineCanvas {
        TimelineCanvas(data: data, geo: geo, imperial: imperial, speedUnit: speedUnit,
                       now: now, floodDeg: floodDeg, ebbDeg: ebbDeg)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: TimelineScrubber
        var host: UIHostingController<TimelineCanvas>?
        var didInitialCenter = false
        var magneting = false
        /// The opening nudge is animating. Suppresses the `scrubTime` writes
        /// `scrollViewDidScroll` would otherwise make from a scroll nobody
        /// asked for — a hint must not move the reading — and keeps
        /// `updateUIView`'s external-scrub branch from snapping the offset
        /// back mid-animation, which would cancel the nudge on its first
        /// re-render (#66: scroll-callback writes during a view update are
        /// the hazard zone here).
        var nudging = false
        private var magnetTarget: Date?

        init(_ parent: TimelineScrubber) { self.parent = parent }

        /// One-shot initial centering, at the first layout with a real width
        /// (also reachable from updateUIView, whichever lands first). After
        /// this, scrollViewDidScroll drives scrubTime — including the very
        /// first drag.
        ///
        /// It arrives from `Timeline.nudgePts` off-centre and animates into
        /// place: that sideways motion is the scrubber's affordance now that
        /// the label is gone (#58). Once per appearance — `didInitialCenter`
        /// already makes this one-shot — and never on a scrub. Under Reduce
        /// Motion it lands directly, with no static hint standing in: the
        /// label it replaced is gone for everyone.
        func centerIfNeeded(_ sv: UIScrollView) {
            guard !didInitialCenter, sv.bounds.width > 0 else { return }
            didInitialCenter = true
            let x = parent.data.x(parent.scrubTime) - sv.bounds.width / 2
            guard !UIAccessibility.isReduceMotionEnabled else {
                sv.contentOffset = CGPoint(x: x, y: 0)
                return
            }
            // Set true BEFORE the offset: assigning contentOffset calls
            // scrollViewDidScroll synchronously, and that off-centre offset
            // is not a reading.
            nudging = true
            sv.contentOffset = CGPoint(x: x + Timeline.nudgePts, y: 0)
            // UIKit clamps that to contentSize, so at the strip's right edge
            // the nudge has nowhere to go — and `setContentOffset(animated:)`
            // over a zero-length move is not guaranteed to call
            // `didEndScrollingAnimation`, which would latch `nudging` on and
            // leave the strip permanently unable to write `scrubTime`. Ask
            // the scroll view where it actually landed, not where we put it.
            guard abs(sv.contentOffset.x - x) > 0.5 else { nudging = false; return }
            sv.setContentOffset(CGPoint(x: x, y: 0), animated: true)
        }

        func scrollViewDidScroll(_ sv: UIScrollView) {
            guard sv.bounds.width > 0, didInitialCenter, !nudging else { return }
            parent.scrubTime = parent.data.time(atX: sv.contentOffset.x + sv.bounds.width / 2)
        }
        /// A touch during the opening nudge ends it — the user is scrubbing
        /// now, and their offset has to reach `scrubTime`. Needed on its own
        /// because a touch cancels the animation without
        /// `didEndScrollingAnimation` ever firing.
        func scrollViewWillBeginDragging(_ sv: UIScrollView) { nudging = false }
        func scrollViewDidEndDragging(_ sv: UIScrollView, willDecelerate: Bool) {
            if !willDecelerate { magnet(sv) }
        }
        func scrollViewDidEndDecelerating(_ sv: UIScrollView) { magnet(sv) }
        func scrollViewDidEndScrollingAnimation(_ sv: UIScrollView) {
            magneting = false
            nudging = false
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
    var imperial = true    // only read by the tide track; current-only strips omit it
    var speedUnit = "kn"   // tide-only strips draw no speed labels
    let now: Date
    var floodDeg: Double? = nil
    var ebbDeg: Double? = nil
    @Binding var scrubTime: Date
    var onReturn: (() -> Void)? = nil

    var body: some View {
        TimelineScrubber(data: data, geo: geo, imperial: imperial, speedUnit: speedUnit,
                         now: now, floodDeg: floodDeg, ebbDeg: ebbDeg, scrubTime: $scrubTime)
            .frame(height: geo.height)
            .overlay { overlay }
            .overlay { floatingReadout }
            .overlay { floatingNowButton }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("timeline-strip")
    }

    @ViewBuilder private var floatingNowButton: some View {
        if let onReturn, scrubbedAway(scrubTime, from: now) {
            GeometryReader { _ in
                Button(action: onReturn) {
                    Label("Now", systemImage: "arrow.left")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SN.foam.opacity(0.8))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(SN.canvas.opacity(0.68), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(SN.steel.opacity(0.35), lineWidth: 1))
                }
                .position(x: 52, y: geo.timeY)
                .accessibilityLabel("Return to now")
                .accessibilityIdentifier("detail-return-now")
            }
        }
    }

    private var floatingReadout: some View {
        GeometryReader { proxy in
            let pointY = geo.hasTide ? geo.tideY(data.heightAt(scrubTime))
                                      : geo.curY(data.velocityAt(scrubTime))
            VStack(spacing: 1) {
                Text(cardTime(scrubTime, data.tz))
                    .font(.system(size: 12, weight: .medium).monospaced())
                    .foregroundStyle(SN.foam.opacity(0.58))
                if data.speedsAreSchematic {
                    Text("Slack timing")
                        .font(.system(size: 18, weight: .semibold))
                } else if geo.hasTide {
                    Text("\(formatHeight(data.heightAt(scrubTime), imperial: imperial)) \(heightUnit(imperial: imperial))")
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                } else {
                    let v = data.velocityAt(scrubTime)
                    HStack(spacing: 5) {
                        Text("\(formatSpeed(abs(v), unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                            .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        // The set, so the reader sees which way the water is
                        // going as a window opens and closes. A fixed slot:
                        // at true slack a neutral mark keeps the card one size.
                        Group {
                            if abs(v) < 0.05 {
                                Text("•").foregroundStyle(SN.foam.opacity(0.4))
                            } else if let d = v >= 0 ? floodDeg : ebbDeg {
                                CompassArrow(deg: d)
                            }
                        }
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 22)
                    }
                }
            }
            .foregroundStyle(SN.foam)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(SN.canvas.opacity(0.92), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SN.steel.opacity(0.55), lineWidth: 1))
            .position(x: proxy.size.width / 2, y: floatingReadoutY(pointY: pointY, geo: geo))
            .allowsHitTesting(false)
        }
    }

    private var overlay: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .topLeading) {
                // The height axis belongs to the viewport, not the strip: it is
                // the one thing on this chart that never moves when you pan, and
                // it is what lets the turn labels drop their unit.
                if geo.hasTide { tideAxis }
                if geo.hasCurrent { currentAxis }
                // Fixed reading line + cap triangle (prototype chartEl overlay).
                LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.3)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 2, height: geo.bodyBottom - 8)
                    .position(x: w / 2, y: 8 + (geo.bodyBottom - 8) / 2)
                Image(systemName: "arrowtriangle.down.fill")
                    .resizable()
                    .foregroundStyle(.white)
                    .frame(width: 8, height: 6)
                    .position(x: w / 2, y: 5)
                if geo.hasTide {
                    // Neutral white, like the current dot below it — a green
                    // dot coloured the mark by SERIES IDENTITY inside a canvas
                    // where green means slack.
                    Circle().fill(.white)
                        .frame(width: 13, height: 13)
                        .shadow(color: .white.opacity(0.9), radius: 4)
                        .position(x: w / 2, y: geo.tideY(data.heightAt(scrubTime)))
                }
                if geo.hasCurrent {
                    Circle().fill(.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .white.opacity(0.9), radius: 3)
                        .position(x: w / 2, y: geo.curY(data.velocityAt(scrubTime)))
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// The fixed height axis down the left edge (NEAPS "4 m / 3 m / 2 m …").
    /// The scrim is doing real work: the strip is full-bleed and the tide fill
    /// is at its brightest exactly where this column sits, so without it the
    /// numbers wash out on a spring high.
    private var tideAxis: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [SN.canvas.opacity(0.9), SN.canvas.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 60)
            ForEach(axisTicks(lo: geo.tideMid - geo.tideSpan, hi: geo.tideMid + geo.tideSpan,
                              imperial: imperial), id: \.self) { tick in
                Text("\(axisTickLabel(tick)) \(heightUnit(imperial: imperial))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .position(x: 26, y: geo.tideY(axisTickMetres(tick, imperial: imperial)))
            }
        }
    }

    /// The current equivalent of the tide-height column. It stays signed so
    /// the zero line reads as the slack boundary, while its unit follows the
    /// user's current-speed setting.
    private var currentAxis: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [SN.canvas.opacity(0.9), SN.canvas.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 60)
            let threshold = data.slackThreshold
            ForEach(currentAxisTicks(maxAbsKn: geo.maxAbsCur, unit: speedUnit)
                .filter { abs(abs(currentAxisKnots($0, unit: speedUnit)) - threshold) > 0.01 }, id: \.self) { tick in
                Text("\(axisTickLabel(tick)) \(speedUnitLabel(speedUnit))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.5))
                    .position(x: 26, y: geo.curY(currentAxisKnots(tick, unit: speedUnit)))
            }
            ForEach([-threshold, threshold], id: \.self) { value in
                Text("\(value > 0 ? "+" : "−")\(formatSpeed(abs(value), unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(SN.go)
                    .position(x: 26, y: geo.curY(value))
            }
        }
    }

}

// MARK: - Rolling multi-day schedule (prototype tableEl)

enum SchedulePill {
    case high, low, flood, ebb, slack
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

/// Day-grouped events list over `Timeline.scheduleRange` — the week hanging off
/// `anchor`, which is why this takes the anchor and `today` separately: day
/// groups key on the first, labels read the second. Day name in a left column,
/// rows scrub on tap, the row nearest the centerline time is highlighted. The
/// prototype dims nothing for the past — the nearest-row highlight is the time
/// cue. (The prototype's `tableEl` TOP, a flat today+54h, is what
/// `scheduleRange` replaced.)
struct MultiDaySchedule: View {
    let entries: [ScheduleEntry]  // pre-sorted, pre-filtered to the window
    let tz: TimeZone
    /// The window's anchor — day-group offsets are anchor-relative, matching
    /// `TimelineDay.offset`, because that is what `days` is keyed on below.
    let anchor: Date
    /// The caller's today, for the Today/Tomorrow labels only.
    let today: Date
    let days: [TimelineDay]
    let scrubTime: Date
    let onTap: (Date) -> Void

    private var groups: [(offset: Int, start: Date, items: [ScheduleEntry])] {
        var out: [(Int, Date, [ScheduleEntry])] = []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        for e in entries {
            let d0 = cal.startOfDay(for: e.time)
            let off = cal.dateComponents([.day], from: anchor, to: d0).day ?? 0
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(relativeDayLabel(group.start, tz, today: today))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SN.foam.opacity(0.9))
                        if let day = days.first(where: { $0.offset == group.offset }) {
                            VStack(alignment: .leading, spacing: 1) {
                                if let rise = day.sunrise {
                                    Text("↑\(clockTime(rise, tz))").foregroundStyle(SN.sunrise)
                                }
                                if let set = day.sunset {
                                    Text("↓\(clockTime(set, tz))").foregroundStyle(SN.sunset)
                                }
                            }
                            .font(.caption2.monospaced())
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("day-sun-d\(group.offset)")
                        }
                    }
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
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(on ? .white : SN.foam.opacity(0.85))
                                Spacer()
                                Text(e.value ?? "—")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(e.value == nil ? SN.foam.opacity(0.5) : .white)
                                pillView(e)
                                    // 100, not 84: room for the widest
                                    // direction-first pill ("WSW FLOOD").
                                    .frame(width: 100, alignment: .trailing)
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
            // ⤒ / ⤓, the strip's turn glyph — arrow to bar, "arrives and stops".
            // A bare ↑ here said "rising" next to a row that means the rising is
            // over. The two surfaces sit one above the other on every tide
            // detail, so they have to speak the same glyph.
            Text("⤒ HIGH")
                .font(.caption2.monospaced().weight(.medium)).tracking(0.5)
                .foregroundStyle(SN.navyDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.rising, in: Capsule())
        case .low:
            Text("⤓ LOW")
                .font(.caption2.monospaced().weight(.medium)).tracking(0.5)
                .foregroundStyle(SN.navyDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.falling, in: Capsule())
        case .flood, .ebb:
            // Direction-first (#59): arrow + cardinal lead, the flood/ebb
            // word demotes to a dimmer label for those who want it.
            HStack(spacing: 3) {
                if let deg = e.arrowDeg {
                    CompassArrow(deg: deg)
                    Text(compass16(deg))
                }
                Text(e.pill == .flood ? "FLOOD" : "EBB")
                    .opacity(0.7)
            }
            .font(.caption2.monospaced().weight(.medium)).tracking(0.5)
            .foregroundStyle(SN.navyDeep)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(e.pill == .flood ? SN.rising : SN.falling, in: Capsule())
        case .slack:
            Text("● SLACK")
                .font(.caption2.monospaced().weight(.medium)).tracking(0.5)
                .foregroundStyle(SN.navyDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.go, in: Capsule())
        }
    }
}
