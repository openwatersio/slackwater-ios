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

    /// How much an online gate fetches in one go. Four times the strip it
    /// needs, so ordinary paging lands in cache instead of on the network —
    /// the gates people plan a passage around are exactly the ones that must
    /// not need a signal to look at next month.
    static let onlineFetchDays = 30.0

    /// The "weak current" convention: under half a knot a small boat transits.
    /// A constant, not a setting, until someone asks (split-scrubbers spec §2).
    static let slackThresholdKn = 0.5

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
    /// The back-pad is the whole reason this takes two dates: it answers a
    /// question about NOW, so it exists only when the anchor IS now.
    static func window(anchor: Date, today: Date) -> (start: Date, end: Date) {
        let back = anchor == today ? backHours : 0
        return (anchor.addingTimeInterval(-back * 3600),
                anchor.addingTimeInterval(forwardHours * 3600))
    }
}

/// Is the strip parked somewhere other than now? The one definition, shared by
/// all three scrubable details.
func scrubbedAway(_ scrubTime: Date, from live: Date) -> Bool {
    abs(scrubTime.timeIntervalSince(live)) > Timeline.scrubbedSeconds
}

/// The workable window around a slack: where |v| stays under `threshold`,
/// linearly interpolated at the crossings from the drawn 10-min samples —
/// the same series the strip renders, so the window can never disagree with
/// the curve. Clamped to the series; nil when no sub-threshold sample
/// brackets the slack.
func slackWindow(_ points: [CurrentPoint], around slack: Date,
                 threshold: Double) -> (start: Date, end: Date)? {
    // A slack outside the sampled series has no measurable window. Events are
    // scanned with a ±6h pad beyond the strip while `currentPoints` is clipped
    // to it, so a padded slack can otherwise walk the series' trailing
    // sub-threshold run and return a window that lies entirely before itself.
    guard let first = points.first, let last = points.last,
          slack >= first.time, slack <= last.time else { return nil }
    let i = points.lastIndex(where: { $0.time <= slack }) ?? 0
    let k: Int
    if abs(points[i].speed) < threshold { k = i }
    else if i + 1 < points.count, abs(points[i + 1].speed) < threshold { k = i + 1 }
    else { return nil }
    func cross(_ a: CurrentPoint, _ b: CurrentPoint) -> Date {
        let va = abs(a.speed), vb = abs(b.speed)
        let f = (threshold - va) / (vb - va)
        return a.time.addingTimeInterval(b.time.timeIntervalSince(a.time) * f)
    }
    var start = points[0].time
    var a = k
    while a > 0 {
        if abs(points[a - 1].speed) >= threshold { start = cross(points[a - 1], points[a]); break }
        a -= 1
    }
    var end = points[points.count - 1].time
    var b = k
    while b < points.count - 1 {
        if abs(points[b + 1].speed) >= threshold { end = cross(points[b], points[b + 1]); break }
        b += 1
    }
    return (start, end)
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

/// Slack/max events scanned from a sampled signed-velocity series — the
/// online-gate path draws fetched official points, so events come from the
/// samples, not a harmonic engine. Slacks interpolate the zero crossing or
/// land exactly on a zero sample; each run between crossings contributes its
/// largest |sample| as a signed maximum. 15-min official samples make
/// interpolated slacks exact to a few minutes — the same series CHS's own
/// tables are printed from.
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
    let start: Date          // today - 48h
    let end: Date            // today + 132h
    let days: [TimelineDay]  // offsets -2…8 (8 exists for the last night's moon)
    let tidePoints: [TidePoint]        // empty when current-only
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

    var hasTide: Bool { !tidePoints.isEmpty }
    var hasCurrent: Bool { !currentPoints.isEmpty }
    var totalWidth: CGFloat { x(end) }

    /// The list's window: the anchor's own midnight → +7d. Deliberately
    /// NARROWER than `start…end` — the strip carries `Timeline.centerPad` more
    /// so the last listed event can still park under the centerline.
    ///
    /// This lives here rather than in the four detail views because all four
    /// were computing it identically off `today`, and the anchor change would
    /// otherwise have to land correctly in four places.
    var scheduleRange: ClosedRange<Date> {
        anchor...anchor.addingTimeInterval(Timeline.scheduleHours * 3600)
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
        let w = Timeline.window(anchor: anchor, today: today)
        // -2 covers the back-pad on the current week; 8 exists so the last
        // visible night (offset 7) can find the following sunrise for its moon.
        let days: [TimelineDay] = (-2...8).map { off in
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
                      now: Date, anchor: Date) -> TimelineData {
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
                        threshold: Timeline.slackThresholdKn)
                .map { (slack: e.time, start: $0.start, end: $0.end) }
        }

        let sunTimes = chrome.days.filter { $0.offset <= 7 }
            .flatMap { [$0.sunrise, $0.sunset].compactMap { $0 } }
        let snaps = (currentEvents.map(\.time) + sunTimes)
            .filter { $0 >= start && $0 <= end }
            .sorted()

        return TimelineData(tz: chrome.tz, anchor: chrome.anchor, today: chrome.today,
                            start: start, end: end, days: chrome.days,
                            tidePoints: [], tideExtremes: [],
                            currentPoints: currentPoints, currentEvents: currentEvents,
                            snapTimes: snaps, slackWindows: windows)
    }

    static func build(tide: TideStationRecord?, current: CurrentStationRecord?,
                      now: Date, anchor: Date, gate: DerivedGateRecord? = nil) -> TimelineData {
        // The primary station names the timezone and the sky position.
        let tz = gate?.gate.tz ?? current?.tz ?? tide?.tz ?? .current
        let lat = gate?.gate.latitude ?? current?.latitude ?? tide?.latitude ?? 48.5
        let lon = gate?.gate.longitude ?? current?.longitude ?? tide?.longitude ?? -123.0
        let chrome = dayChrome(tz: tz, lat: lat, lon: lon, anchor: anchor, now: now)
        let today = chrome.today, start = chrome.start, end = chrome.end, days = chrome.days

        let pad = eventPad
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
                            threshold: Timeline.slackThresholdKn)
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
        let snaps = (tideExtremes.map(\.time) + currentEvents.map(\.time) + sunTimes)
            .filter { $0 >= start && $0 <= end }
            .sorted()

        return TimelineData(tz: tz, anchor: chrome.anchor, today: today, start: start, end: end, days: days,
                            tidePoints: tidePoints, tideExtremes: tideExtremes,
                            currentPoints: currentPoints, currentEvents: currentEvents,
                            snapTimes: snaps, slackWindows: windows)
    }
}

// MARK: - Vertical geometry (prototype geo())

/// Every number in here is a literal point, and that is why the chart's own
/// labels are the one place in this branch that keeps a fixed `.system(size:)`.
///
/// The slots are hand-packed: `dayY` 20, `sunY` 34 — 14pt between the day
/// label's centre and the sun dot's — then one track box at 106…256 inside a
/// canvas 328 tall, whichever track fills it.
///
/// Every event's reading lives in a fixed band on one side of that box —
/// `topTimeY`/`topValueY`/`topGlyphY` above, the mirror below — leaving only a
/// coloured dot on the curve. Tide sends highs up and lows down; current sends
/// flood up and ebb down; slack takes both ends, start above and end below.
/// That is what retired the three-row gutter on both tracks: the rows existed
/// to arbitrate labels that can no longer reach each other.
///
/// Nothing here reflows, and `tideY`/`curY` map data onto these constants.
///
/// Task 1 mapped the labels to `.caption2`, which does respond to Dynamic Type
/// — and at AX5 `.caption2` is ~26pt, so the day label overprints the sun dot
/// and reaches `tideTop`, while "Current" centred at `x: 42` runs off the left
/// edge. Scaling text inside fixed-point geometry does not degrade by wrapping;
/// it degrades by overprinting the chart.
///
/// Same rule this branch already applies to `MapHeader`'s 44pt buttons,
/// `OfflineStatusButton`'s 34pt circle and the FABs: chrome in a fixed-size
/// slot does not scale. Making these labels scale means making this geometry
/// scale with them — a real chart-layout change, not a font swap. Until then
/// the labels stay fixed; don't "finish the job" here.
struct TimelineGeo {
    let hasTide: Bool
    let hasCurrent: Bool
    let height: CGFloat
    let dayY: CGFloat = 20
    let sunY: CGFloat = 34
    let moonY: CGFloat = 34
    let tideTop: CGFloat
    let tideBottom: CGFloat
    let bodyTop: CGFloat
    let curTop: CGFloat
    let curBottom: CGFloat
    let bodyBottom: CGFloat
    let tideMid: Double
    let tideSpan: Double     // half-range, padded (prototype amp*1.18)
    let maxAbsCur: Double    // prototype mxv = cur.mx*1.05

    init(data: TimelineData) {
        hasTide = data.hasTide
        hasCurrent = data.hasCurrent
        // ONE track box, whichever track fills it. NEAPS-style bands replaced
        // the gutter on both tracks, and a band's rows are the same rows
        // whether the thing in them is a tide height or a current speed — so
        // the two cases no longer differ by a single number, and the strips are
        // now the same size and the same shape as each other. (They diverged
        // before because the current track needed extra room for speed labels
        // drawn ON the curve and for the FLOOD/EBB reference lines; both are
        // gone.) The switch survives its own collapse on purpose: it is what
        // makes a hypothetical both-tracks input resolve tide-first instead of
        // drawing two curves through each other.
        switch (hasTide, hasCurrent) {
        case (true, _):
            tideTop = 106; tideBottom = 256; height = 328
            curTop = 0; curBottom = 0
        default:
            // The current track's layout diverged from tide's here, and the
            // reason is what each answer is FOR. A tide turn's height is the
            // reading; a current's peak speed is something you steer around,
            // while the slack window is what you plan the day around. So the
            // current strip spends its rows differently: ONE green range above,
            // ONE small time below, and the speeds annotate the curve itself.
            // That is two rows instead of six, which is why this box is taller
            // and the canvas shorter than the tide case.
            tideTop = 0; tideBottom = 0
            curTop = 80; curBottom = 280; height = 312
        }
        bodyTop = hasTide ? tideTop : curTop
        bodyBottom = hasCurrent ? curBottom : tideBottom
        let heights = data.tidePoints.map(\.height)
        let mn = heights.min() ?? 0, mx = heights.max() ?? 1
        tideMid = (mn + mx) / 2
        // 1.06, down from 1.18: the padding existed to keep a turn's stacked
        // height label off the top and bottom edges, and those labels have left
        // the curve. What's left only has to clear a 4pt dot.
        tideSpan = max((mx - mn) / 2, 0.01) * 1.06
        maxAbsCur = max(data.currentPoints.map { abs($0.speed) }.max() ?? 1, 0.01) * 1.05
    }

    var zeroY: CGFloat { (curTop + curBottom) / 2 }
    var curHalf: CGFloat { (curBottom - curTop) / 2 - 3 }

    // MARK: The event bands (NEAPS model), shared by both tracks
    //
    // Above the track, reading down toward it: time, value, glyph, then the
    // event's own dot on the curve. Below the track, the mirror. `height` is
    // the last row plus a margin.
    //
    // Which events take which side is the track's business, not the geometry's:
    // tide puts highs on top and lows underneath; current puts flood on top and
    // ebb underneath, matching the side of the zero line each already lives on.
    // Slack has no side — it takes BOTH, its window's start time on top and its
    // end time below, which is what stops a short window from printing
    // "8:17AM–8:33AM" as one unreadable run.
    // Current-only rows. Deliberately NOT the shared band slots above: the
    // current track prints one thing over the curve and one under it, so
    // borrowing tide's three-row grid would leave four empty rows of dead
    // height on every gate.
    var slackRangeY: CGFloat { curTop - 18 }
    var maxTimeY: CGFloat { curBottom + 18 }

    var topGlyphY: CGFloat { bodyTop - 14 }
    var topValueY: CGFloat { bodyTop - 32 }
    var topTimeY: CGFloat { bodyTop - 54 }
    var bottomGlyphY: CGFloat { bodyBottom + 16 }
    var bottomValueY: CGFloat { bodyBottom + 36 }
    var bottomTimeY: CGFloat { bodyBottom + 58 }

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
    /// 8192px on a side. The 180-hour strip is `180 * pph` points wide, tripled
    /// on a 3× phone: at 12pt/hour that was 6480px and fit, at 18 it is 9720px
    /// and the entire chart renders EMPTY — no curve, no day chrome, no labels,
    /// and no error. (Caught on the NEAPS pass: the left axis kept drawing,
    /// because it's a separate SwiftUI overlay, which is exactly what made the
    /// blank canvas look like a layout bug rather than a texture limit.)
    ///
    /// Slicing the strip into tiles gives each its own layer, so the cap now
    /// applies per tile instead of to the whole timeline and `pph` is free to
    /// move again. Every tile runs the same drawing code translated into strip
    /// coordinates and clipped to its own slice — the clip is what makes this
    /// safe, since the translucent night bands and area fills would otherwise
    /// stack on each other wherever two tiles overdrew.
    static let tileWidth: CGFloat = 900

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
        // Real-now faint marker rides the timeline (prototype 'nowt') — but
        // only when now is ON this timeline. An anchored strip a month out has
        // no "now" to mark, and drawing it anyway pins a dashed line to
        // whichever edge the clamp lands on, which reads as a real event.
        guard data.contains(now) else { return }
        var nowLine = Path()
        nowLine.move(to: CGPoint(x: data.x(now), y: geo.hasTide ? geo.tideTop : geo.curTop))
        nowLine.addLine(to: CGPoint(x: data.x(now), y: geo.bodyBottom))
        ctx.stroke(nowLine, with: .color(SN.leaf.opacity(0.55)),
                   style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
    }

    /// One event's band: glyph, then a `primary` line and an optional
    /// `secondary` one, in the three fixed rows on one side of the track. Both
    /// tracks draw through here, which is what keeps a current's reading and a
    /// tide's reading the same object rendered twice rather than two label
    /// systems that drift apart.
    ///
    /// The rows are deliberately named by WEIGHT, not by content: `primary` is
    /// the big line and `secondary` is the small one, and which fact goes in
    /// which is the caller's judgement about what that event is for. A tide
    /// turn or a current max leads with its number and drops its time to the
    /// small row. Slack leads with the TIME and has no small row at all —
    /// slack timing is the whole answer at a gate, while the exact knots at
    /// peak ebb is trivia you steer around rather than plan by. Naming these
    /// `value`/`time` is what made the earlier version print the sub-threshold
    /// constant six times a screen: the grid demanded a number in the big row,
    /// so slack got handed the only number it had.
    private func drawBand(_ ctx: GraphicsContext, x: CGFloat, top: Bool,
                          glyph: String, primary: String, secondary: String?,
                          tint: Color, rotateDeg: Double? = nil) {
        let glyphAt = CGPoint(x: x, y: top ? geo.topGlyphY : geo.bottomGlyphY)
        let mark = Text(glyph).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
        if let rotateDeg {
            // Rotate about the glyph's own centre, not the canvas origin — a
            // bare ctx.rotate would swing the mark somewhere off in the strip.
            ctx.drawLayer { l in
                l.translateBy(x: glyphAt.x, y: glyphAt.y)
                l.rotate(by: .degrees(rotateDeg))
                l.draw(mark, at: .zero, anchor: .center)
            }
        } else {
            ctx.draw(mark, at: glyphAt, anchor: .center)
        }
        ctx.draw(Text(primary).font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint),
                 at: CGPoint(x: x, y: top ? geo.topValueY : geo.bottomValueY), anchor: .center)
        if let secondary {
            ctx.draw(Text(secondary).font(.system(size: 12).monospaced())
                        .foregroundStyle(.white.opacity(0.6)),
                     at: CGPoint(x: x, y: top ? geo.topTimeY : geo.bottomTimeY), anchor: .center)
        }
    }

    // Night bands, day tint, day labels, sun markers, per-night moons —
    // continuous across midnight (prototype's per-day rects abut exactly).
    private func drawDayChrome(_ ctx: GraphicsContext) {
        let visible = data.visibleDays
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
            // Day label at local noon. Fixed size, not `.caption2` — see the
            // TimelineGeo doc comment: `dayY` is 20 and the sun dot is at 34.
            ctx.draw(Text(relativeDayLabel(day.start, data.tz, today: data.today))
                        .font(.system(size: 13, weight: .semibold))
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
        ctx.fill(area, with: .linearGradient(
            Gradient(stops: [.init(color: Color(hex: 0x9CC0DC, opacity: 0.7), location: 0),
                             .init(color: Color(hex: 0x0D3A5C, opacity: 0.12), location: 1)]),
            startPoint: CGPoint(x: 0, y: geo.tideTop),
            endPoint: CGPoint(x: 0, y: geo.tideBottom)))
        ctx.stroke(line, with: .color(Color(hex: 0xEEF4EE)),
                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

        // Chart datum, the reference every printed height is quoted against —
        // the axis column names it "0" and this is the line it points at. Drawn
        // only when datum is actually inside the plotted span; a week where the
        // tide never drops near it would otherwise get a rule pinned to an edge
        // it isn't at.
        if 0 > geo.tideMid - geo.tideSpan && 0 < geo.tideMid + geo.tideSpan {
            var datum = Path()
            datum.move(to: CGPoint(x: 0, y: geo.tideY(0)))
            datum.addLine(to: CGPoint(x: data.totalWidth, y: geo.tideY(0)))
            ctx.stroke(datum, with: .color(.white.opacity(0.28)),
                       style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
        }

        // Turns, the NEAPS way: the curve carries a coloured DOT and nothing
        // else, and the reading — time, height, direction arrow — is pulled out
        // into a fixed band on the turn's own side of the track. That replaces
        // both the value-stacked-on-the-dot label and the three-row gutter
        // beneath it (Amendment A/C), because kind now does the separating that
        // rows used to: a high's label physically cannot land on a low's.
        //
        // Colour is the existing direction axis — high is the top of rising
        // (flood), low the bottom of falling (ebb) — not NEAPS' green/amber.
        // Green in this app means slack and only slack, and the same pair
        // already labels HIGH/LOW in the schedule directly below this strip.
        // The pale variants are the tokens meant for small text on near-black.
        let margin = 0.3 * 3600
        let filteredExtremes = data.tideExtremes.filter { e in
            e.time >= data.start.addingTimeInterval(margin)
                && e.time <= data.end.addingTimeInterval(-margin)
        }
        for e in filteredExtremes {
            let x = data.x(e.time), y = geo.tideY(e.height)
            let high = e.kind == .high
            let tint = high ? SN.floodLabel : SN.ebbLabel
            ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                     with: .color(tint))
            // ⤒ / ⤓ — arrow TO BAR, not a bare arrow. A turn is where the water
            // stops, and the bar is the stop; a plain ↑ says "rising", which is
            // the one thing that is no longer true at a high. (NEAPS uses the
            // same pair for the same reason. The current track keeps bare
            // arrows, because there flood/ebb really is a direction of travel.)
            //
            // No unit on the value — the fixed axis column carries it once, and
            // a shorter label is the difference between clearing a neighbour
            // and overprinting it.
            drawBand(ctx, x: x, top: high, glyph: high ? "⤒" : "⤓",
                     primary: formatHeight(e.height, imperial: imperial),
                     secondary: chartTime(e.time, data.tz), tint: tint)
        }
    }

    /// This station's set for one direction, nil on a derived gate.
    private func deg(_ flood: Bool) -> Double? { flood ? floodDeg : ebbDeg }

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
        let filteredEvents = data.currentEvents.filter { e in
            e.time >= data.start.addingTimeInterval(margin)
                && e.time <= data.end.addingTimeInterval(-margin)
        }

        // The workable slack column spans the WHOLE track, not zeroY-downward
        // as the old band did. Two things follow from that, and the second is
        // the point: the window reads as a column of time you can transit
        // rather than a patch hanging off the zero line, and its two edge times
        // get to live at opposite ends of the chart — start on top, end
        // underneath. A 16-minute window used to print "8:17AM–8:33AM" as one
        // merged run because two labels 5pt apart are unreadable; 150pt apart
        // vertically, they are just two labels.
        //
        // Drawn before the events so the dots and the curve stay on top of the
        // tint. 0.12 keeps it a highlight rather than an opaque patch.
        for w in data.slackWindows {
            let x0 = data.x(w.start), x1 = data.x(w.end)
            ctx.fill(Path(CGRect(x: x0, y: geo.curTop, width: x1 - x0,
                                 height: geo.curBottom - geo.curTop)),
                     with: .color(SN.go.opacity(0.12)))
        }

        for e in filteredEvents {
            let x = data.x(e.time)
            switch e.kind {
            case .slack:
                ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: geo.zeroY - 4,
                                                width: 8, height: 8)),
                         with: .color(SN.go))
                // ONE label, centred over the column, no glyph. The window's
                // two ends were living at opposite ends of the strip to keep
                // them from merging into an unreadable "8:17AM–8:33AM" run;
                // trimming the repeated hour does the same job in one place
                // and gives the whole top row back to slack. Nothing else is
                // up here now, which is the point — at a gate this row IS the
                // answer, and it can afford to be the widest thing on screen.
                // ONE time, and it is the SLACK ITSELF — not the window's
                // opening edge, which is what this printed first.
                //
                // The magnet snaps the strip to `snapTimes`, and a slack's entry
                // there is the zero crossing, the middle of the window. Labelling
                // the edge meant the number you read and the moment the scrubber
                // parked you on were minutes apart with nothing to explain the
                // gap — the chart contradicting itself at the one event this app
                // is named for. Print what the strip can actually stop on.
                //
                // The window is still DRAWN, as the green column: it is context
                // you look at, not a time you read off. Planning a transit
                // through it is later work, and it can bring its own readout.
                if data.slackWindows.first(where: { $0.slack == e.time }) == nil {
                    // No window (a violent gate the sampling steps over, every
                    // derived gate): a hairline rather than a column — a
                    // zero-width window must not look like a window.
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: geo.curTop))
                    tick.addLine(to: CGPoint(x: x, y: geo.curBottom))
                    ctx.stroke(tick, with: .color(SN.go.opacity(0.35)), lineWidth: 1)
                }
                ctx.draw(Text(chartTime(e.time, data.tz))
                            .font(.system(size: 18, weight: .semibold).monospacedDigit())
                            .foregroundStyle(SN.go),
                         at: CGPoint(x: x, y: geo.slackRangeY), anchor: .center)
            case .maxFlood, .maxEbb:
                let flood = e.kind == .maxFlood
                let tint = flood ? SN.floodLabel : SN.ebbLabel
                let y = geo.curY(e.speed)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                         with: .color(tint))

                // The speed annotates the CURVE, not a band: it is context you
                // read off the shape, not a number you plan by. It sits between
                // the peak and the zero line — inside the fill — whenever the
                // fill is deep enough to hold it, and inverts to white there
                // because it is then sitting on colour. A weak peak has no room
                // under it, so the label sits outside on the dark ground and
                // keeps its direction tint instead. That is the whole rule, and
                // it is why a big flood reads white while a small ebb doesn't.
                // No chip behind it. White on the flood fill carries itself, and
                // a box made the label an object sitting ON the chart instead of
                // an annotation belonging to it — which is the opposite of
                // "informal information you read off the shape".
                let toward: CGFloat = flood ? 1 : -1      // toward the zero line
                let labelH: CGFloat = 30
                let inside = abs(y - geo.zeroY) >= labelH + 12
                let cy = y + toward * (labelH / 2 + 8)
                let mark = inside ? Color.white : tint
                ctx.draw(Text(formatSpeed(abs(e.speed), unit: speedUnit))
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(mark),
                         at: CGPoint(x: x, y: cy - 7), anchor: .center)
                let arrow = Text(deg(flood) == nil ? (flood ? "↑" : "↓") : "↑")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(mark)
                if let d = deg(flood) {
                    ctx.drawLayer { l in
                        l.translateBy(x: x, y: cy + 8)
                        l.rotate(by: .degrees(d))
                        l.draw(arrow, at: .zero, anchor: .center)
                    }
                } else {
                    ctx.draw(arrow, at: CGPoint(x: x, y: cy + 8), anchor: .center)
                }

                // The time drops to the one small row under the track, in the
                // same weight it had as a band's secondary line.
                ctx.draw(Text(chartTime(e.time, data.tz))
                            .font(.system(size: 12).monospaced())
                            .foregroundStyle(.white.opacity(0.6)),
                         at: CGPoint(x: x, y: geo.maxTimeY), anchor: .center)
            }
        }
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
    default: formatterShortWeekday(dayStart, tz)
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
        TimelineCanvas(data: data, geo: geo, imperial: imperial, speedUnit: speedUnit,
                       now: now, floodDeg: floodDeg, ebbDeg: ebbDeg)
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
    var floodDeg: Double? = nil
    var ebbDeg: Double? = nil
    @Binding var scrubTime: Date

    var body: some View {
        TimelineScrubber(data: data, geo: geo, imperial: imperial, speedUnit: speedUnit,
                         now: now, floodDeg: floodDeg, ebbDeg: ebbDeg, scrubTime: $scrubTime)
            .frame(height: geo.height)
            .overlay { overlay }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("timeline-strip")
    }

    private var overlay: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .topLeading) {
                // The height axis belongs to the viewport, not the strip: it is
                // the one thing on this chart that never moves when you pan, and
                // it is what lets the turn labels drop their unit.
                if geo.hasTide { tideAxis }
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
                    // Neutral, like the current dot below it. This was green,
                    // which made it a mark coloured by SERIES IDENTITY — kind —
                    // inside a canvas where green means slack: on a paired
                    // current+tide detail the same chart carried a green dot
                    // meaning "tide curve" and green `slack` labels at every
                    // zero crossing. Both track lines are near-white anyway, so
                    // the green matched nothing it sat on.
                    // (The white ring it used to wear was there to lift green
                    // off the track; on a white dot it drew nothing.)
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
            LinearGradient(colors: [SN.page.opacity(0.9), SN.page.opacity(0)],
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

/// Day-grouped events list, today 00:00 → +54h (prototype tableEl TOP): day
/// name in a left column, rows scrub on tap, the row nearest the centerline
/// time is highlighted. The prototype dims nothing for the past — the nearest-
/// row highlight is the time cue.
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
            HStack(spacing: 3) {
                if let deg = e.arrowDeg { CompassArrow(deg: deg) }
                Text(e.pill == .flood ? "FLOOD" : "EBB")
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
