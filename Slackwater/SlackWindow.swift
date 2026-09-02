// Slackwater — GPL v3. The workable sub-threshold window around a slack — shared by the timeline strip and the widget extension.
import Foundation
import TideEngine

/// The boat-specific speed that defines a usable slack window. It is shared
/// with the widget and map, and falls back safely when a stored value is bad.
let defaultSlackThresholdKn = 0.5
let slackThresholdRange = 0.1...10.0
let currentSpeedRampAnchorsKn: [Double] = [0.5, 3, 8, 12]

/// Absolute capability scale shared by the full scrubber and its widget.
/// The same speed must never change colour with station or day.
func widgetSpeedRampT(_ speedKn: Double) -> Double {
    let step = 1.0 / Double(currentSpeedRampAnchorsKn.count - 1)
    if speedKn <= currentSpeedRampAnchorsKn[0] { return 0 }
    for i in 0..<(currentSpeedRampAnchorsKn.count - 1)
        where speedKn <= currentSpeedRampAnchorsKn[i + 1] {
        return (Double(i) + (speedKn - currentSpeedRampAnchorsKn[i])
                / (currentSpeedRampAnchorsKn[i + 1] - currentSpeedRampAnchorsKn[i])) * step
    }
    return 1
}

func normalizedSlackThresholdKn(_ value: Double) -> Double {
    slackThresholdRange.contains(value) ? value : defaultSlackThresholdKn
}

var slackThresholdKn: Double {
    normalizedSlackThresholdKn(AppGroup.defaults.object(forKey: AppGroup.slackWindowSpeedKey) as? Double
                               ?? defaultSlackThresholdKn)
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
    if abs(points[i].speed) <= threshold { k = i }
    else if i + 1 < points.count, abs(points[i + 1].speed) <= threshold { k = i + 1 }
    else { return nil }
    func cross(_ a: CurrentPoint, _ b: CurrentPoint) -> Date {
        let va = abs(a.speed), vb = abs(b.speed)
        let f = (threshold - va) / (vb - va)
        return a.time.addingTimeInterval(b.time.timeIntervalSince(a.time) * f)
    }
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
    return (start, end)
}

/// One usable run of slack water. Touching or overlapping windows merge into
/// one run and carry one label (current-charts spec §4 rule 3); the predicate that
/// produced each window is unchanged, only the drawing joins them.
struct WindowRun: Equatable {
    let start: Date
    let end: Date
    func contains(_ t: Date) -> Bool { start <= t && t <= end }
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

/// The moments a current axis prints: each run's opening (the time a planner
/// is aiming at — spec §4 rule 7), plus the bare instant of any slack no run
/// covers, which is the hairline case (§5.3). Sorted.
func currentAxisMoments(runs: [WindowRun], slacks: [Date]) -> [Date] {
    let bare = slacks.filter { t in !runs.contains { $0.contains(t) } }
    return (runs.map(\.start) + bare).sorted()
}
