// Slackwater — GPL v3. The workable sub-threshold window around a slack — shared by the timeline strip and the widget extension.
// Scrubber behavior here is specified in docs/scrubber.md: update the spec in the same change as any visible change.
import Foundation
import SlackwaterKit

/// The boat-specific speed that defines a usable slack window. It is shared
/// with the widget and map, and falls back safely when a stored value is bad.
/// Zero turns the window off: only slack itself is drawn and named (#821).
let defaultSlackThresholdKn = 0.5
let slackThresholdRange = 0.0...10.0
let currentSpeedRampAnchorsKn: [Double] = [0.5, 3, 8, 12]

/// Position on a ramp for `v`: piecewise-linear between `anchors`, which
/// are spaced equally across 0...1, and clamped at both ends. Above the
/// ceiling everything is the top colour — "beyond the top of the scale" is
/// not a distinction worth resolving.
func rampT(_ v: Double, anchors a: [Double]) -> Double {
    let step = 1.0 / Double(a.count - 1)
    if v <= a[0] { return 0 }
    for i in 0..<(a.count - 1) where v <= a[i + 1] {
        return (Double(i) + (v - a[i]) / (a[i + 1] - a[i])) * step
    }
    return 1
}

/// Absolute capability scale shared by the full scrubber and its widget.
/// The same speed must never change colour with station or day.
func widgetSpeedRampT(_ speedKn: Double) -> Double {
    rampT(speedKn, anchors: currentSpeedRampAnchorsKn)
}

/// Rounded to the stepper's tenth first, so 0.3 stepped down three times is off,
/// not −3e-17 kn and the default.
func normalizedSlackThresholdKn(_ value: Double) -> Double {
    let tenth = (value * 10).rounded() / 10
    return slackThresholdRange.contains(tenth) ? tenth : defaultSlackThresholdKn
}

/// The person has turned the slack window off.
func slackWindowIsOff(_ threshold: Double) -> Bool { threshold <= 0 }

var slackThresholdKn: Double {
    normalizedSlackThresholdKn(AppGroup.defaults.object(forKey: AppGroup.slackWindowSpeedKey) as? Double
                               ?? defaultSlackThresholdKn)
}

/// Slack is the zero instant. The comfort current defines only the window.
func slackCoreThresholdKn(_ windowThreshold: Double) -> Double {
    0
}

/// The workable window around a slack: where |v| stays under `threshold`,
/// linearly interpolated at the crossings from the drawn 10-min samples —
/// the same series the strip renders, so the window can never disagree with
/// the curve. Clamped to the series and widened to hold the slack itself; nil
/// for a slack outside it, between two above-threshold samples of one sign,
/// or with the window off.
func slackWindow(_ points: [CurrentPoint], around slack: Date,
                 threshold: Double) -> (start: Date, end: Date)? {
    guard !slackWindowIsOff(threshold) else { return nil }
    // A slack outside the sampled series has no measurable window. Events are
    // scanned with a ±6h pad beyond the strip while `currentPoints` is clipped
    // to it, so a padded slack can otherwise walk the series' trailing
    // sub-threshold run and return a window that lies entirely before itself.
    guard let first = points.first, let last = points.last,
          slack >= first.time, slack <= last.time else { return nil }
    let i = points.lastIndex(where: { $0.time <= slack }) ?? 0
    let k: Int
    if abs(points[i].speed) <= threshold { k = i }
    else if i + 1 < points.count, abs(points[i + 1].speed) <= threshold { k = i + 1 }
    else if i + 1 < points.count, (points[i].speed > 0) != (points[i + 1].speed > 0) {
        // Both samples sit outside the band but the reversal between them crosses it.
        let a = points[i], b = points[i + 1]
        let span = abs(a.speed) + abs(b.speed), dt = b.time.timeIntervalSince(a.time)
        // Keep the window connected to the engine's slack when it differs from the sampled crossing.
        return (min(a.time.addingTimeInterval(dt * (abs(a.speed) - threshold) / span), slack),
                max(a.time.addingTimeInterval(dt * (abs(a.speed) + threshold) / span), slack))
    }
    else { return nil }
    func cross(_ a: CurrentPoint, _ b: CurrentPoint) -> Date { bandCrossing(a, b, threshold: threshold) }
    var start = points[0].time
    var a = k
    while a > 0 {
        if abs(points[a - 1].speed) > threshold { start = cross(points[a - 1], points[a]); break }
        a -= 1
    }
    var end = points[points.count - 1].time
    var b = k
    while b < points.count - 1 {
        if abs(points[b + 1].speed) > threshold { end = cross(points[b], points[b + 1]); break }
        b += 1
    }
    return (min(start, slack), max(end, slack))
}

/// Where the straight line between one sample inside the ±`threshold` band and
/// one outside it crosses the band's edge. Signed, so a pair either side of a
/// reversal crosses on the outside sample's side rather than at a mirrored speed.
func bandCrossing(_ a: CurrentPoint, _ b: CurrentPoint, threshold: Double) -> Date {
    let outside = abs(a.speed) > threshold ? a.speed : b.speed
    let edge = outside > 0 ? threshold : -threshold
    let f = (edge - a.speed) / (b.speed - a.speed)
    return a.time.addingTimeInterval(b.time.timeIntervalSince(a.time) * f)
}

/// Each slack's window at `threshold` and its slack core, measured on the same
/// samples. A core lies inside its window; a slack outside the samples has neither.
func measureSlacks(_ points: [CurrentPoint], slacks: [Date], threshold: Double)
    -> (windows: [(slack: Date, start: Date, end: Date)], cores: [(slack: Date, start: Date, end: Date)]) {
    let core = slackCoreThresholdKn(threshold)
    func measure(_ at: Double) -> [(slack: Date, start: Date, end: Date)] {
        slacks.compactMap { t in slackWindow(points, around: t, threshold: at).map { (slack: t, start: $0.start, end: $0.end) } }
    }
    return (measure(threshold), measure(core))
}

/// One usable run of slack water. Touching or overlapping windows merge into
/// one run and carry one label (current-charts spec §4 rule 3); the predicate that
/// produced each window is unchanged, only the drawing joins them.
struct WindowRun: Equatable {
    let start: Date
    let end: Date
    func contains(_ t: Date) -> Bool { start <= t && t <= end }
    /// Half-open: parked on the closing, the water is already leaving slack (scrubber §9.2).
    func holdsSlack(at t: Date) -> Bool { start <= t && t < end }
}

/// Windows in chronological order → runs. Two windows join when the later
/// one starts at or before the earlier one ends.
func mergeWindows(_ windows: [(start: Date, end: Date)]) -> [WindowRun] {
    var runs: [WindowRun] = []
    for w in windows {
        if let last = runs.last, w.start <= last.end {
            runs[runs.count - 1] = WindowRun(start: last.start, end: max(last.end, w.end))
        } else {
            runs.append(WindowRun(start: w.start, end: w.end))
        }
    }
    return runs
}

extension WindowRun {
    var centre: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    /// From the duration at a surface's scale, so data code agrees with that surface's drawing without a Path.
    func drawsAsDot(pointsPerHour: CGFloat) -> Bool {
        CurveStyle.runDrawsAsDot(width: CGFloat(end.timeIntervalSince(start) / 3600) * pointsPerHour)
    }
    /// The axis prints where the run's mark is: a dot's centre, a stroke's opening (spec §4 rule 7).
    func axisMoment(pointsPerHour: CGFloat) -> Date {
        drawsAsDot(pointsPerHour: pointsPerHour) ? centre : start
    }
}

/// The green a strip or card draws: each slack run, stretched around its
/// centre to `CurveStyle.shortestSlackStroke` when it is shorter, and a run
/// that long at each slack in `bare`. Slack is all lines, never a dot, so it
/// joins its window's blue the way a long run does (#821).
func slackStrokes(cores: [WindowRun], bare: [Date], pointsPerHour: CGFloat) -> [WindowRun] {
    let half = TimeInterval(CurveStyle.shortestSlackStroke / pointsPerHour) * 3600 / 2
    func around(_ t: Date) -> WindowRun { WindowRun(start: t.addingTimeInterval(-half), end: t.addingTimeInterval(half)) }
    return (cores.map { $0.drawsAsDot(pointsPerHour: pointsPerHour) ? around($0.centre) : $0 } + bare.map(around))
        .sorted { $0.start < $1.start }
}

/// The slacks no run covers. Each keeps one mark, a dot at its own instant, so every slack the alerts and the magnet know is drawn and timed.
func bareSlacks(_ slacks: [Date], runs: [WindowRun]) -> [Date] {
    slacks.filter { t in !runs.contains { $0.holdsSlack(at: t) } }
}

/// The reading says Slack inside a slack core, or within a second of a slack no core holds, where the magnet parks on its dot (scrubber §9.2).
func readsSlack(at t: Date, runs cores: [WindowRun], slacks: [Date]) -> Bool {
    cores.contains { $0.holdsSlack(at: t) }
        || bareSlacks(slacks, runs: cores).contains { abs($0.timeIntervalSince(t)) < 1 }
}

/// One time per mark at a surface's scale: each drawn window's opening, and
/// each slack mark outside every drawn window — a core at its axis moment, a
/// slack no core holds at its instant. A window too short to draw gives way to
/// the slack mark inside it.
func slackAxisMoments(windows: [WindowRun], cores: [WindowRun], slacks: [Date],
                      pointsPerHour: CGFloat) -> [Date] {
    let drawn = windows.filter { !$0.drawsAsDot(pointsPerHour: pointsPerHour) }
    let marks = cores.map { $0.axisMoment(pointsPerHour: pointsPerHour) } + bareSlacks(slacks, runs: cores)
    return (drawn.map(\.start) + marks.filter { t in !drawn.contains { $0.contains(t) } }).sorted()
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
