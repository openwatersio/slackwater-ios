// Slackwater — GPL v3. The workable sub-threshold window around a slack — shared by the timeline strip and the widget extension.
import Foundation
import TideEngine

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
