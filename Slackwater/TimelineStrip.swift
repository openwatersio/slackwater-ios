// Slackwater — GPL v3. The continuous pan-under-centerline scrubber, the iOS
// model from prototype/TidesApp.dc.html (DCLogic innerChart / chartEl /
// onTideScroll / magnet / tableEl). The reading line is FIXED at the viewport
// center; dragging pans a fixed multi-day timeline strip (-48h on the current
// week only, always +180h, 18pt per hour) underneath it, so nights bleed across
// day boundaries. Native UIScrollView supplies the momentum; a "magnet" pass
// after the scroll settles snaps a nearby stop (tide turn, slack/max, sun
// event) under the centerline when it's within 46pt. One implementation for
// the tide-only and current-only details.
import Almanac
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
    /// The one-shot loading affordance: show two hours of tide/current and sky
    /// motion, then settle on the live reading before the page feels delayed.
    static let introDuration: TimeInterval = 0.65
    static func introStart(for now: Date) -> Date { now.addingTimeInterval(-2 * 3600) }
    static func introTime(from start: Date, to now: Date, elapsed: TimeInterval) -> Date {
        let progress = max(0, min(1, elapsed / introDuration))
        return start.addingTimeInterval(now.timeIntervalSince(start) * progress)
    }

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
        Slackwater.rampT(rate, anchors: tideRateRampAnchorsMHr)
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

/// The times the axis row has room to print, earliest first. Two events close
/// together — a low an hour after a shallow high — would print on top of each
/// other, so a time within `minGap` of the last one kept is dropped; the
/// schedule below still lists it. Order-independent: the input is sorted by
/// time first, so the EARLIER of a crowded pair is always the survivor.
///
/// ponytail: drops the later label. Stagger onto a second row if a station
/// ever hides something worth reading.
func thinnedAxisTimes(_ times: [Date], x: (Date) -> CGFloat, minGap: CGFloat) -> [Date] {
    var kept: [Date] = []
    var lastX = -CGFloat.greatestFiniteMagnitude
    for t in times.sorted() where x(t) - lastX >= minGap {
        lastX = x(t)
        kept.append(t)
    }
    return kept
}

// MARK: - Data: everything the strip draws, computed once per station

struct TimelineDay {
    let offset: Int          // days from the anchor (which is today only on return-to-now)
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
    let days: [TimelineDay]  // offsets -3…8 (the ends cover DST and adjoining nights)
    let tidePoints: [TidePoint]        // empty when current-only
    let tideRates: [TideRatePoint]     // index-aligned with tidePoints (#95)
    let tideExtremes: [TideExtreme]
    let currentPoints: [CurrentPoint]  // empty when tide-only
    let currentEvents: [CurrentEvent]
    let snapTimes: [Date]    // prototype stops(): turns + slacks/maxes + sun events + eclipse contacts

    /// Lunar eclipses with a peak inside the window and at least one contact
    /// above this station's horizon. Built ONCE, in the builders below —
    /// `SkyState.init` runs on every scrub frame and must never search — and
    /// read by the dome's moon, the schedule row and the strip's mark.
    var eclipses: [WindowEclipse] = []

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

    /// Half-open: the end is a snap target, and parked there the water is
    /// already leaving slack — the reading should say so, not "Slack · 0m".
    func containingSlackWindow(at time: Date) -> (slack: Date, start: Date, end: Date)? {
        slackWindows.first { $0.start <= time && time < $0.end }
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
    /// and it is visible whether its own midnight is or not. `days` runs to
    /// offset 8, which is never visible: it supplies the sunrise that closes
    /// the last visible night band.
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
    /// Metres per hour under the centerline, signed like `tideRates`.
    func rateAt(_ t: Date) -> Double { interp(tideRates.map { ($0.time, $0.rate) }, t) }
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
        // the other end: never visible, it supplies the sunrise that closes
        // the last visible night band (offset 7).
        let observer = try? Observer(latitudeDeg: lat, longitudeDeg: lon)
        let days: [TimelineDay] = (-3...8).map { off in
            let d0 = cal.date(byAdding: .day, value: off, to: anchor)!
            // The civil day is bounded HERE because Almanac takes a half-open
            // UTC window and knows nothing of time zones; the widen-±1-day
            // filtering the old suncalc port needed goes away with it.
            // Calendar bounds, not +86_400: a DST-transition day is 23 or 25
            // hours, and the duration bound drops or admits events in the
            // skewed hour.
            let dayStart = cal.startOfDay(for: d0)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            let sun = observer.flatMap { try? sunEvents(from: dayStart, to: dayEnd, observer: $0) } ?? []
            return TimelineDay(offset: off, start: d0,
                               sunrise: sun.first { $0.kind == .rise }?.time,
                               sunset: sun.first { $0.kind == .set }?.time)
        }
        return DayChrome(tz: tz, anchor: anchor, today: today,
                         start: w.start, end: w.end, days: days)
    }

    // Widen the event scans a touch so nothing at the edges is clipped.
    // Not private: `DerivedGateDetailView` derives its phase slacks over the
    // same padded span, and must use the same number.
    static let eventPad = 6.0 * 3600

    /// The window's eclipses, or nothing — the shared tail of both builders.
    ///
    /// The full-moon gate is the whole performance story: `nextLunarEclipse`
    /// scans lunation by lunation and will happily walk months past the window
    /// before it finds one, on every rebuild. An eclipse IS a full moon, so a
    /// window without one cannot hold an eclipse, and `searchMoonPhases`
    /// answers that far more cheaply than the eclipse scan does.
    private static func windowEclipses(lat: Double, lon: Double,
                                       start: Date, end: Date) -> [WindowEclipse] {
        guard let observer = try? Observer(latitudeDeg: lat, longitudeDeg: lon),
              let phases = try? searchMoonPhases(from: start, to: end),
              phases.contains(where: { $0.phase == .full })
        else { return [] }
        return lunarEclipses(from: start, to: end, observer: observer)
    }

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
        let eclipses = windowEclipses(lat: lat, lon: lon, start: start, end: end)
        let snaps = Array(Set(currentEvents.map(\.time) + sunTimes
                              + eclipses.flatMap(\.contacts)
                              + windows.flatMap { [$0.start, $0.end] }))
            .filter { $0 >= start && $0 <= end }.sorted()

        return TimelineData(tz: chrome.tz, anchor: chrome.anchor, today: chrome.today,
                            start: start, end: end, days: chrome.days,
                            tidePoints: [], tideRates: [], tideExtremes: [],
                            currentPoints: currentPoints, currentEvents: currentEvents,
                            snapTimes: snaps, eclipses: eclipses,
                            slackWindows: windows, slackThreshold: threshold)
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
        // The fastest-rate moments stay magnetic: the chevrons that marked
        // them are gone, but each is now the most saturated point of the
        // rate-coloured line, and the readout's rate warning fires exactly
        // there.
        let eclipses = windowEclipses(lat: lat, lon: lon, start: start, end: end)
        let snaps = Array(Set(tideExtremes.map(\.time) + tideFlowArrows(tideRates).map(\.time)
                              + currentEvents.map(\.time) + sunTimes
                              + eclipses.flatMap(\.contacts)
                              + windows.flatMap { [$0.start, $0.end] }))
            .filter { $0 >= start && $0 <= end }.sorted()

        return TimelineData(tz: tz, anchor: chrome.anchor, today: today, start: start, end: end, days: days,
                            tidePoints: tidePoints, tideRates: tideRates, tideExtremes: tideExtremes,
                            currentPoints: currentPoints, currentEvents: currentEvents,
                            snapTimes: snaps, eclipses: eclipses, slackWindows: windows,
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
    /// The strip's height follows its last row of sun-event dots plus a margin.
    var height: CGFloat { sunY + 18 }
    let tideTop: CGFloat
    let tideBottom: CGFloat
    let bodyTop: CGFloat
    let curTop: CGFloat
    let curBottom: CGFloat
    let bodyBottom: CGFloat
    let tideMid: Double
    let tideSpan: Double     // half-range, padded (prototype amp*1.18)
    let maxAbsCur: Double    // prototype mxv = cur.mx*1.05

    /// The lead reading and, under it, the row of glass pills sit over this
    /// zone at the top of the strip, so the night and day bands can rise
    /// behind them and fade out — no hard edge where the page meets the
    /// chart, and nothing floating over the curve.
    let padTop: CGFloat = 160
    /// The pill row's top. The pills are caption-height glass, about 30pt,
    /// so the row ends 6pt above the pad and never reaches the plot. The
    /// commentary is centred on the reading line; return-to-now sits at the
    /// edge on the side now is.
    var chromeY: CGFloat { padTop - 36 }
    /// The plot box. 10 past the pad clears a turn dot's halo. Below it come
    /// the time row, then the day row (day label and sun times) — the card
    /// graph's order, chrome under the curve rather than over it.
    private static let plotTop: CGFloat = 170
    private static let plotBottom: CGFloat = 320

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
        // Both edges resolve tide-first, like the switch above: a both-tracks
        // input that took its top from the tide box and its bottom from the
        // empty current box would collapse the plot to nothing and drag the
        // chrome rows and the canvas height up with it.
        bodyTop = hasTide ? tideTop : curTop
        bodyBottom = hasTide ? tideBottom : curBottom
        let heights = data.tidePoints.map(\.height)
        let mn = heights.min() ?? 0, mx = heights.max() ?? 1
        tideMid = (mn + mx) / 2
        // 1.06: the readings hang INWARD from each turn (CurveStyle.hangOffset
        // toward the plot middle), so the padding only has to clear the
        // turn's dot and its halo.
        tideSpan = max((mx - mn) / 2, 0.01) * 1.06
        maxAbsCur = max(data.currentPoints.map { abs($0.speed) }.max() ?? 1, 0.01) * 1.05
    }

    var zeroY: CGFloat { (curTop + curBottom) / 2 }
    var curHalf: CGFloat { (curBottom - curTop) / 2 - 3 }
    /// The one row of absolute times, under the plot (current spec §5.5:
    /// one home per surface).
    var timeY: CGFloat { bodyBottom + 18 }
    /// The day row under the axis: day label and sun times on `dayY`, the
    /// date 17 below it, with sun dots centred on `sunY`.
    var dayY: CGFloat { timeY + 26 }
    var sunY: CGFloat { dayY + 14 }

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
    var showsDayBands = true

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
    /// = 6480px had fit; the week widened it further. Metal refuses the texture
    /// silently and the SwiftUI overlays on top of the canvas keep drawing, so
    /// the failure looks like a layout bug rather than a texture limit.)
    ///
    /// Slicing the strip into tiles gives each its own layer, so the cap now
    /// applies per tile instead of to the whole timeline and `pph` is free to
    /// move again — five tiles at today's width. Every tile runs the same
    /// drawing code translated into strip coordinates and clipped to its own
    /// slice — the clip is what makes this safe, since the translucent night
    /// bands and area fills would otherwise stack on each other wherever two
    /// tiles overdrew.
    static let tileWidth: CGFloat = 900

    /// The twilight fade on each night band's edge: this many hours either
    /// side of sunset and sunrise. 0.75h ≈ civil twilight plus a shoulder;
    /// at 18pt/h the whole transition is 27pt.
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

    /// The past/future split for every stroke on the strip (`CurveDrawing`).
    private func strokeSplitAtNow(_ ctx: GraphicsContext, _ path: Path,
                                  with shading: GraphicsContext.Shading,
                                  lineWidth: CGFloat = CurveStyle.lineWidth) {
        CurveDrawing.strokeSplitAtNow(ctx, path, with: shading, nowX: nowX,
                                      width: data.totalWidth, height: geo.height, lineWidth: lineWidth)
    }

    /// The card's white now dot, riding the curve. Only when now is on the strip.
    private func drawNowDot(_ ctx: GraphicsContext, at p: CGPoint) {
        guard data.contains(now) else { return }
        CurveDrawing.nowDot(ctx, at: p)
    }

    /// The axis times on the bottom row, faded when passed.
    private func axisTimes(_ ctx: GraphicsContext, _ times: [Date]) {
        for t in thinnedAxisTimes(times, x: data.x, minGap: 64) {
            ctx.draw(Text(chartTime(t, data.tz))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(0.7 * fade(t))),
                     at: CGPoint(x: data.x(t), y: geo.timeY), anchor: .center)
        }
    }

    // Night bands, day tint, day labels and sun markers — continuous across
    // midnight (prototype's per-day rects abut exactly).
    private func drawDayChrome(_ ctx: GraphicsContext) {
        let visible = data.visibleDays
        // Night and day bands span the strip's full height (#246) and fade
        // into each other across twilight — a hard edge at sunset read as a
        // rectangle pasted onto the chart. One rect per NIGHT, sunset to the
        // next day's sunrise straddling midnight, so the fades land on the
        // sun events and nothing abuts at midnight. `data.days` rather than
        // `visible`: the
        // night before the first visible sunrise belongs to a day off the
        // strip, and the tile clip discards what is off-canvas.
        if showsDayBands {
            let fadeW = CGFloat(Self.twilightHours) * Timeline.pph
            // The bands rise behind the lead and sink behind the axis rows, fading
            // to nothing at both ends: a soft alpha clip, so the page shows through
            // above and below the plot.
            var banded = ctx
            banded.clipToLayer { mask in
                mask.fill(Path(CGRect(x: -1e5, y: 0, width: 2e5, height: geo.height)),
                          with: .linearGradient(
                            Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                             .init(color: .white, location: geo.padTop / geo.height),
                                             .init(color: .white, location: geo.bodyBottom / geo.height),
                                             .init(color: .white.opacity(0), location: 1)]),
                            startPoint: .zero, endPoint: CGPoint(x: 0, y: geo.height)))
            }
            func fadedBand(from a: CGFloat, to b: CGFloat, color: Color, opacity: Double) {
                guard b > a else { return }
                let rect = CGRect(x: a - fadeW, y: 0, width: (b - a) + 2 * fadeW, height: geo.height)
                let ramp = min(2 * fadeW / rect.width, 0.5)
                banded.fill(Path(rect), with: .linearGradient(
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
        }
        for day in visible {
            // Day label at local noon. Fixed size, not `.caption2` — chart
            // labels do not scale (current spec §7.5).
            ctx.draw(Text(relativeDayLabel(day.start, data.tz, today: data.today))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SN.foam.opacity(0.85)),
                     at: CGPoint(x: data.x(noonLocal(day.start, data.tz)), y: geo.dayY),
                     anchor: .center)
            ctx.draw(Text(monthDay(day.start, data.tz))
                        .font(.system(size: 10, weight: .medium).monospaced())
                        .foregroundStyle(SN.foam.opacity(0.48)),
                     at: CGPoint(x: data.x(noonLocal(day.start, data.tz)), y: geo.dayY + 17),
                     anchor: .center)
            // Sun rise/set dots + "↑5:24AM" labels.
            for (t, arrow) in [(day.sunrise, "↑"), (day.sunset, "↓")] {
                guard let t else { continue }
                let x = data.x(t)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: geo.sunY - 3.5, width: 7, height: 7)),
                         with: .color(SN.sun))
                ctx.draw(Text("\(arrow)\(cardTime(t, data.tz))")
                            .font(.system(size: 11, weight: .medium).monospaced())
                            .foregroundStyle(SN.sunrise),
                         at: CGPoint(x: x, y: geo.dayY), anchor: .center)
            }
        }
        drawEclipses(ctx)
    }

    /// A moon at greatest eclipse, on the sun dots' row. That is the whole
    /// mark on the strip.
    ///
    /// No text, and no band. The text came first and could not fit: `dayY`
    /// holds the day name and sun times, `dayY + 17` the date, `sunY` the sun
    /// dots, `height` is `sunY + 18` — there is no free row, and an eclipse
    /// starts in the evening, so a time label lands an hour or two from sunset
    /// and prints through it. A copper band across P1–P4 replaced it and was
    /// worse in a different way: a coloured span over the curve reads as a
    /// measurement of something, and nobody could tell what.
    ///
    /// So: half-size glyph, small enough to sit between the sun dots without
    /// crowding them, and the times stay where they already were — the
    /// schedule row below, and the readout as you scrub. #304 is where a
    /// better answer goes; this one is deliberately quiet rather than wrong.
    private func drawEclipses(_ ctx: GraphicsContext) {
        for e in data.eclipses where data.contains(e.peak) {
            ctx.draw(Text("🌘").font(.system(size: 6.5)),
                     at: CGPoint(x: data.x(e.peak), y: geo.sunY), anchor: .center)
        }
    }

    private func drawTide(_ ctx: GraphicsContext) {
        var line = Path()
        for (i, p) in data.tidePoints.enumerated() {
            let pt = CGPoint(x: data.x(p.time), y: geo.tideY(p.height))
            i == 0 ? line.move(to: pt) : line.addLine(to: pt)
        }
        // The card's fill, anchored at chart datum (CurveDrawing.datumFill).
        let datumY = geo.tideY(0)
        var area = line
        area.addLine(to: CGPoint(x: data.totalWidth, y: datumY))
        area.addLine(to: CGPoint(x: 0, y: datumY))
        area.closeSubpath()
        let lowest = data.tidePoints.map(\.height).min() ?? 0
        CurveDrawing.datumFill(ctx, area, plotTop: geo.tideTop, plotBottom: geo.tideBottom,
                               width: data.totalWidth, datumY: datumY, lowestY: geo.tideY(lowest))

        // Chart datum, the reference every printed height is quoted against.
        // Drawn only when datum is inside the plotted span; a week where the
        // tide never drops near it would otherwise get a rule pinned to an
        // edge it isn't at.
        if 0 > geo.tideMid - geo.tideSpan && 0 < geo.tideMid + geo.tideSpan {
            CurveDrawing.referenceLine(ctx, at: datumY, width: data.totalWidth)
        }

        // Rate of rise as line colour (#95): the past fade applies on top.
        CurveDrawing.tideLine(ctx, line, rates: data.tideRates.map { (x: data.x($0.time), rate: $0.rate) },
                              nowX: nowX, width: data.totalWidth, height: geo.height)

        // Turns: a dot on the curve, the reading hanging off it toward the
        // plot middle with the to-bar arrow nearest the dot — the same rule
        // the current peaks follow — and the time on the bottom row. Teal
        // for a high and amber for a low, as on the card. No unit: the lead
        // reading carries it once.
        let margin = 0.3 * 3600
        for e in data.tideExtremes where e.time >= data.start.addingTimeInterval(margin)
                                      && e.time <= data.end.addingTimeInterval(-margin) {
            let p = CGPoint(x: data.x(e.time), y: geo.tideY(e.height))
            let high = e.kind == .high
            let f = fade(e.time)
            let tint = (high ? SN.graphHigh : SN.graphLow).opacity(f)
            CurveDrawing.dot(ctx, at: p, color: tint)
            CurveDrawing.hangLabel(ctx, at: p, toward: high ? 1 : -1,
                                   value: formatHeight(e.height, imperial: imperial),
                                   glyph: .toBar(high: high), tint: tint, ink: SN.foam.opacity(f),
                                   valueFontSize: CurveStyle.stripValueFontSize)
        }
        axisTimes(ctx, data.tideExtremes.map(\.time).filter { t in
            t >= data.start.addingTimeInterval(margin) && t <= data.end.addingTimeInterval(-margin)
        })

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

        // The card's fill, anchored at zero (CurveDrawing.zeroFill). A derived
        // gate is flat steel instead: the zero-anchored blue reads as a
        // magnitude, and a ±1 schematic shape has none to report. Colour is
        // state, and this curve's magnitude is unknown.
        var area = line
        area.addLine(to: CGPoint(x: data.totalWidth, y: geo.zeroY))
        area.addLine(to: CGPoint(x: 0, y: geo.zeroY))
        area.closeSubpath()
        if data.speedsAreSchematic {
            ctx.fill(area, with: .color(SN.steel.opacity(0.32)))
        } else {
            CurveDrawing.zeroFill(ctx, area, plotTop: geo.curTop, plotBottom: geo.curBottom, zeroY: geo.zeroY)
        }

        // Slack: the line every speed on this track is signed against, drawn
        // the way the tide track draws chart datum. Under the curve, so the
        // curve reads as sitting on it.
        CurveDrawing.referenceLine(ctx, at: geo.zeroY, width: data.totalWidth)

        // The card's line: blue with the speed thread (#97). A schematic
        // shape has no speed, so no thread.
        if data.speedsAreSchematic {
            strokeSplitAtNow(ctx, line, with: .color(SN.graphLine))
        } else {
            CurveDrawing.currentLine(ctx, line,
                                     samples: data.currentPoints.map { (x: data.x($0.time), speedKn: $0.speed) },
                                     nowX: nowX, width: data.totalWidth, height: geo.height)
        }

        // The run is the mark (spec §5.2): the line itself turns the go
        // colour between each run's interpolated edges (CurveDrawing.runs).
        let segs = runs.map { run -> Path in
            var seg = Path()
            seg.move(to: CGPoint(x: data.x(run.start), y: geo.curY(data.velocityAt(run.start))))
            for p in data.currentPoints where p.time > run.start && p.time < run.end {
                seg.addLine(to: CGPoint(x: data.x(p.time), y: geo.curY(p.speed)))
            }
            seg.addLine(to: CGPoint(x: data.x(run.end), y: geo.curY(data.velocityAt(run.end))))
            return seg
        }
        CurveDrawing.runs(ctx, segs, nowX: nowX, width: data.totalWidth, height: geo.height)

        let margin = 0.3 * 3600
        let onStrip = { (t: Date) in
            t >= data.start.addingTimeInterval(margin) && t <= data.end.addingTimeInterval(-margin)
        }
        let slacks = data.currentEvents.filter { $0.kind == .slack }.map(\.time)
        axisTimes(ctx, currentAxisMoments(runs: runs, slacks: slacks).filter(onStrip))

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
                // arrow nearest the peak, in the reading's own ink — the fill
                // and the line say nothing about direction, and neither does
                // the arrow's colour. No unit: the lead reading carries it
                // once; a schematic shape has none to print.
                let flood = e.kind == .maxFlood
                let ink = SN.foam.opacity(fade(e.time))
                CurveDrawing.hangLabel(ctx, at: CGPoint(x: x, y: geo.curY(e.speed)),
                                       toward: flood ? 1 : -1,     // toward the zero line
                                       value: data.speedsAreSchematic ? nil : formatSpeed(abs(e.speed), unit: speedUnit),
                                       glyph: deg(flood).map { .set(deg: $0) }, tint: ink, ink: ink,
                                       valueFontSize: CurveStyle.stripValueFontSize)
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
    var showsDayBands = true
    var floodDeg: Double? = nil
    var ebbDeg: Double? = nil
    @Binding var scrubTime: Date
    /// Bumped by a pill tap. A tap must win over whatever the strip is doing,
    /// so this bypasses the settle guard below.
    var jumpToken = 0

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
            coordinator.layoutDidRun(sv)
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
        // `!co.nudging` for the opening slide: scroll callbacks move
        // `scrubTime` with the animation, and this guard stops those updates
        // from making the representable snap its own offset mid-flight.
        //
        // NOT gated on `isDecelerating` or `magneting` (#237): while the strip
        // coasts, every frame writes `scrubTime` back from the offset, so a
        // request skipped here is overwritten before the glide ends — the Now
        // tap was simply swallowed. A finger still down (`isDragging`) keeps
        // its say; momentum does not. Setting the offset unanimated is how
        // UIKit stops a deceleration, and it cancels a magnet in flight too.
        let desired = data.x(scrubTime) - sv.bounds.width / 2
        if co.seenJump != jumpToken {
            // A tapped pill mid-fling: the guard below would drop the jump and
            // the next scroll callback would write the fling's time back over
            // the tap. Stop the fling and the magnet, then ride the magnet's
            // own animated path to the stop — the curve eases under the
            // centerline and the reading follows it, and
            // `didEndScrollingAnimation` parks exactly on the tapped time.
            // Reduce Motion, or nothing to travel, lands directly: a
            // zero-length animated scroll may never call back.
            co.seenJump = jumpToken
            co.stopIntro()
            sv.setContentOffset(sv.contentOffset, animated: false)
            if UIAccessibility.isReduceMotionEnabled || abs(desired - sv.contentOffset.x) < 0.5 {
                co.magneting = false
                sv.contentOffset = CGPoint(x: desired, y: 0)
            } else {
                co.magneting = true
                co.magnetTarget = scrubTime
                sv.setContentOffset(CGPoint(x: desired, y: 0), animated: true)
            }
            return
        }
        if abs(desired - sv.contentOffset.x) > 1, !sv.isDragging, !co.nudging {
            if sv.isDecelerating || co.magneting {
                sv.setContentOffset(sv.contentOffset, animated: false)
                co.cancelMagnet()
            }
            sv.contentOffset = CGPoint(x: desired, y: 0)
        }
    }

    private var canvas: TimelineCanvas {
        TimelineCanvas(data: data, geo: geo, imperial: imperial, speedUnit: speedUnit,
                       now: now, showsDayBands: showsDayBands,
                       floodDeg: floodDeg, ebbDeg: ebbDeg)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: TimelineScrubber
        var host: UIHostingController<TimelineCanvas>?
        var didInitialCenter = false
        var seenJump = 0
        var magneting = false
        /// The opening slide is animating. It keeps `updateUIView`'s external-
        /// scrub branch from snapping the offset back while scroll callbacks
        /// deliberately drive the reading and sky toward now.
        var nudging = false
        var introDisplayLink: CADisplayLink?
        var introStartedAt: CFTimeInterval?
        var introRange: (start: Date, destination: Date)?
        weak var introScrollView: UIScrollView?
        /// Where the animated scroll — the magnet's snap or a pill's jump — is
        /// headed; parked on exactly when the animation ends.
        var magnetTarget: Date?
        /// The viewport width the offset was last computed against (#280).
        var laidOutWidth: CGFloat = 0
        /// A width change is re-anchoring the offset to `scrubTime`; the
        /// scroll callback it fires must not write `scrubTime` back from
        /// layout.
        var reanchoring = false

        init(_ parent: TimelineScrubber) { self.parent = parent }

        /// Every `layoutSubviews`: the one-shot opening centre, then the
        /// width check that keeps the same time under the centerline.
        func layoutDidRun(_ sv: UIScrollView) {
            centerIfNeeded(sv)
            reanchorIfResized(sv)
            publishCenter(sv)
        }

        /// Rotation (iPad portrait ↔ landscape, Stage Manager) keeps
        /// `contentOffset.x` while `bounds.width` changes, so the time under
        /// the centerline — `contentOffset.x + width / 2` — drifts by half
        /// the width change and the curve disagrees with the readout until
        /// the next state change (#280). No scroll callback fires for a pure
        /// bounds change and SwiftUI does not re-run `updateUIView` for
        /// layout, so this is the only place that can notice. Re-anchor the
        /// offset to `scrubTime` unanimated, cancelling a magnet or fling in
        /// flight. The opening slide is left alone: it recomputes its offset
        /// from the live width every frame.
        func reanchorIfResized(_ sv: UIScrollView) {
            let width = sv.bounds.width
            defer { laidOutWidth = width }
            guard didInitialCenter, width > 0, abs(width - laidOutWidth) > 0.5, !nudging else { return }
            if sv.isDecelerating || magneting {
                sv.setContentOffset(sv.contentOffset, animated: false)
                cancelMagnet()
            }
            reanchoring = true
            sv.contentOffset = CGPoint(x: parent.data.x(parent.scrubTime) - width / 2, y: 0)
            reanchoring = false
        }

        /// The time actually under the centerline, as the strip's
        /// accessibility value. The lead readout carries `scrubTime`; this is
        /// the only signal a UI test has for whether the curve agrees with it.
        func publishCenter(_ sv: UIScrollView) {
            guard sv.bounds.width > 0 else { return }
            let t = parent.data.time(atX: sv.contentOffset.x + sv.bounds.width / 2)
            sv.accessibilityValue = chartTime(t, parent.data.tz)
        }

        /// One-shot initial centering, at the first layout with a real width
        /// (also reachable from updateUIView, whichever lands first). After
        /// this, scrollViewDidScroll drives scrubTime — including the very
        /// first drag.
        ///
        /// The four detail views initialize at `Timeline.introStart`; that
        /// exact opening state slides to now. Any other state (for example a
        /// picked week after an online timeline reload) centres without an
        /// intro. Reduce Motion likewise lands directly on now.
        func centerIfNeeded(_ sv: UIScrollView) {
            guard !didInitialCenter, sv.bounds.width > 0 else { return }
            let start = parent.scrubTime
            let isIntro = abs(start.timeIntervalSince(Timeline.introStart(for: parent.now))) < 2
            let destination = isIntro ? parent.now : start
            let startX = parent.data.x(start) - sv.bounds.width / 2
            let destinationX = parent.data.x(destination) - sv.bounds.width / 2

            // Offset assignment can call the delegate synchronously. Keep
            // `didInitialCenter` false until the opening position is in place,
            // so layout never mutates SwiftUI state.
            sv.contentOffset = CGPoint(x: isIntro ? startX : destinationX, y: 0)
            didInitialCenter = true
            laidOutWidth = sv.bounds.width
            guard isIntro else { return }
            guard !UIAccessibility.isReduceMotionEnabled else {
                sv.contentOffset = CGPoint(x: destinationX, y: 0)
                Task { @MainActor [weak self] in self?.parent.scrubTime = destination }
                return
            }

            nudging = true
            introScrollView = sv
            introRange = (start, destination)
            let link = CADisplayLink(target: self, selector: #selector(advanceIntro))
            introDisplayLink = link
            link.add(to: .main, forMode: .common)
        }

        @objc private func advanceIntro(_ link: CADisplayLink) {
            guard let sv = introScrollView, let range = introRange else {
                stopIntro()
                return
            }
            if introStartedAt == nil { introStartedAt = link.timestamp }
            let elapsed = link.timestamp - (introStartedAt ?? link.timestamp)
            let time = Timeline.introTime(from: range.start, to: range.destination,
                                          elapsed: elapsed)
            sv.contentOffset = CGPoint(x: parent.data.x(time) - sv.bounds.width / 2, y: 0)
            if elapsed >= Timeline.introDuration {
                parent.scrubTime = range.destination
                stopIntro()
            }
        }

        func stopIntro() {
            introDisplayLink?.invalidate()
            introDisplayLink = nil
            introStartedAt = nil
            introRange = nil
            introScrollView = nil
            nudging = false
        }

        func scrollViewDidScroll(_ sv: UIScrollView) {
            publishCenter(sv)
            guard sv.bounds.width > 0, didInitialCenter, !reanchoring else { return }
            parent.scrubTime = parent.data.time(atX: sv.contentOffset.x + sv.bounds.width / 2)
        }
        /// A touch during the opening slide leaves the scrubber exactly where
        /// the user grabbed it.
        func scrollViewWillBeginDragging(_ sv: UIScrollView) {
            stopIntro()
        }
        func scrollViewDidEndDragging(_ sv: UIScrollView, willDecelerate: Bool) {
            if !willDecelerate { magnet(sv) }
        }
        func scrollViewDidEndDecelerating(_ sv: UIScrollView) { magnet(sv) }
        /// An external scrub interrupted the animated settle; drop its
        /// target so a late `didEndScrollingAnimation` cannot park on it.
        func cancelMagnet() {
            magneting = false
            magnetTarget = nil
        }
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

/// Extends the sky's horizon colour down to the visible tide/current line. The path
/// stops on the line at every x, so sky never leaks into the water below it.
private struct SkyCurveFill: View {
    let data: TimelineData
    let geo: TimelineGeo
    let scrubTime: Date
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: geo.bodyTop))
            for x in stride(from: CGFloat(0), through: size.width, by: 2) {
                let seconds = Double(x - size.width / 2) / Double(Timeline.pph) * 3600
                let time = scrubTime.addingTimeInterval(seconds)
                let y = geo.hasTide ? geo.tideY(data.heightAt(time)) : geo.curY(data.velocityAt(time))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: geo.bodyTop))
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }
    }
}

struct TimelineScrubStrip: View {
    let data: TimelineData
    let geo: TimelineGeo
    var imperial = true    // only read by the tide track; current-only strips omit it
    var speedUnit = "kn"   // tide-only strips draw no speed labels
    let now: Date
    var showsDayBands = true
    var skyFill: Color? = nil
    var chromeInk: Color = SN.foam
    var floodDeg: Double? = nil
    var ebbDeg: Double? = nil
    @Binding var scrubTime: Date
    var onReturn: (() -> Void)? = nil
    /// The next significant event from the scrub, and the scrub to it.
    var commentary: String? = nil
    /// The commentary's ink when it is a warning rather than a next event.
    var commentaryTint: Color? = nil
    var onCommentary: () -> Void = {}
    @State private var jumpToken = 0

    var body: some View {
        TimelineScrubber(data: data, geo: geo, imperial: imperial, speedUnit: speedUnit,
                         now: now, showsDayBands: showsDayBands,
                         floodDeg: floodDeg, ebbDeg: ebbDeg, scrubTime: $scrubTime,
                         jumpToken: jumpToken)
            .frame(height: geo.height)
            .background {
                if let skyFill, geo.hasTide || geo.hasCurrent {
                    SkyCurveFill(data: data, geo: geo, scrubTime: scrubTime, color: skyFill)
                }
            }
            .overlay { overlay }
            .overlay(alignment: .top) { chromeRow }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("timeline-strip")
    }

    /// The row of glass pills between the lead and the plot: the commentary
    /// centred on the reading line, return-to-now at the edge on the side now
    /// is (scrubbed into history, now is to the right and the arrow points
    /// there; into the future, the left).
    private var chromeRow: some View {
        let past = scrubTime < now
        let showNow = onReturn != nil && scrubbedAway(scrubTime, from: now)
        return ZStack {
            Commentary(text: commentary, tint: commentaryTint,
                       scrubTime: scrubTime, ink: chromeInk) {
                jumpToken += 1
                onCommentary()
            }
            if showNow {
                HStack {
                    if past { Spacer(minLength: 0) }
                    nowPill(past: past)
                    if !past { Spacer(minLength: 0) }
                }
            }
        }
        .padding(.top, geo.chromeY)
        .padding(.horizontal, 16)
    }

    private func nowPill(past: Bool) -> some View {
        Button(action: { jumpToken += 1; onReturn?() }) {
            HStack(spacing: 4) {
                if !past { Image(systemName: "arrow.left") }
                Text("Now")
                if past { Image(systemName: "arrow.right") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(chromeInk)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Return to now")
        .accessibilityIdentifier("detail-return-now")
    }

    private var overlay: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .topLeading) {
                // No y-axis column: the lead reading above the strip carries
                // the unit and the turn labels carry the values. A faint
                // reading line runs from the pill row to the plot's foot —
                // the riding dot marks the scrub, the line only ties it to
                // the lead above.
                Rectangle().fill(.white.opacity(0.18))
                    .frame(width: 1, height: geo.bodyBottom - geo.padTop)
                    .position(x: w / 2, y: geo.padTop + (geo.bodyBottom - geo.padTop) / 2)
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
}

// MARK: - Rolling multi-day schedule (prototype tableEl)

enum SchedulePill {
    case high, low, flood, ebb, slack, eclipse
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

/// The window's eclipses as schedule rows: one row each, at the first bite,
/// with the peak in the value column.
///
/// Built here and merged by `ScrubDetailScaffold` rather than by the four
/// detail views: an eclipse is the sky's event, not the station's, so all four
/// kinds of detail get the same row from the one place.
func eclipseEntries(_ tl: TimelineData) -> [ScheduleEntry] {
    tl.eclipses
        .filter { tl.scheduleRange.contains($0.start) }
        .map { ScheduleEntry(time: $0.start, pill: .eclipse, value: chartTime($0.peak, tl.tz)) }
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
                                    Text("↑\(chartTime(rise, tz))").foregroundStyle(SN.sunrise)
                                }
                                if let set = day.sunset {
                                    Text("↓\(chartTime(set, tz))").foregroundStyle(SN.sunset)
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
                                Text(chartTime(e.time, tz))
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(on ? .white : SN.foam.opacity(0.85))
                                    // "7:03am" is a character shorter than
                                    // "12:53pm": the floor keeps the values
                                    // beside it in a column down the list.
                                    .frame(minWidth: 58, alignment: .leading)
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
            // detail, so they have to speak the same glyph — and the same
            // colour: teal for a high, amber for a low, the chart's turn dots.
            // A row and the dot it scrubs to are one event. Flood and ebb below
            // stay on the direction axis, which is a different question.
            Text("⤒ HIGH")
                .font(.caption2.monospaced().weight(.medium)).tracking(0.5)
                .foregroundStyle(SN.navyDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.graphHigh, in: Capsule())
        case .low:
            Text("⤓ LOW")
                .font(.caption2.monospaced().weight(.medium)).tracking(0.5)
                .foregroundStyle(SN.navyDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.graphLow, in: Capsule())
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
        case .eclipse:
            // Copper, and light text on it rather than navy: this is the one
            // row in the list that is not about water. The KIND (partial,
            // total, penumbral) is deliberately absent — the column caps at
            // 100pt for "WSW FLOOD" and "🌘 PENUMBRAL ECLIPSE" does not fit.
            // The kind belongs to the Moon sheet, which has room for it.
            Text("🌘 ECLIPSE")
                .font(.caption2.monospaced().weight(.medium)).tracking(0.5)
                .foregroundStyle(SN.foam)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.umbra, in: Capsule())
        }
    }
}
