// Slackwater — GPL v3. Alert rules → dated occurrences, read from the producers the strip already draws (notifications spec §4).
import Almanac
import Foundation
import TideEngine

/// Each time a sampled height series passes `level` in the given direction, linearly
/// interpolated between the two samples that bracket it. A sample exactly on the level
/// counts once, on the pair that arrives at it.
func tideCrossings(_ samples: [(time: Date, height: Double)], level: Double, rising: Bool) -> [Date] {
    guard samples.count > 1 else { return [] }
    var found: [Date] = []
    for i in 0..<(samples.count - 1) {
        let a = samples[i], b = samples[i + 1]
        let crosses = rising ? (a.height < level && b.height >= level)
                             : (a.height > level && b.height <= level)
        guard crosses else { continue }
        let f = (level - a.height) / (b.height - a.height)
        found.append(a.time.addingTimeInterval(b.time.timeIntervalSince(a.time) * f))
    }
    return found
}

/// Sunrise → sunset spans at a position, padded a day either side of the range so an
/// event near either end still finds its day. One Almanac search for the whole range.
/// ponytail: a polar day with no rise or set has no span, so it reads as night.
func daylightSpans(from: Date, to: Date, lat: Double, lon: Double) -> [ClosedRange<Date>] {
    guard let observer = try? Observer(latitudeDeg: lat, longitudeDeg: lon),
          let events = try? sunEvents(from: from.addingTimeInterval(-86_400),
                                      to: to.addingTimeInterval(86_400), observer: observer)
    else { return [] }
    var spans: [ClosedRange<Date>] = []
    var rise: Date?
    for event in events {
        switch event.kind {
        case .rise: rise = event.time
        case .set:
            if let r = rise { spans.append(r...event.time) }
            rise = nil
        default: break
        }
    }
    return spans
}

/// The opening of every merged slack run, with its close, plus the bare instant of any
/// slack no run covers (`end == nil`) — the moments `currentAxisMoments` prints. Series
/// and events are padded 6 h beyond the range so a window straddling either end is whole;
/// the caller clips to the range.
func slackWindowOpenings(_ station: any CurrentPredicting, from: Date, to: Date,
                         threshold: Double) -> [(event: Date, end: Date?)] {
    let start = from.addingTimeInterval(-21_600), stop = to.addingTimeInterval(21_600)
    let points = station.speeds(from: start, to: stop, step: 600)
    let slacks = station.events(from: start, to: stop).filter { $0.kind == .slack }.map(\.time)
    let runs = mergeWindows(slacks.compactMap { slackWindow(points, around: $0, threshold: threshold) })
    let opened: [(event: Date, end: Date?)] = runs.map { ($0.start, $0.end) }
    let hairline: [(event: Date, end: Date?)] = slacks
        .filter { t in !runs.contains { $0.contains(t) } }
        .map { ($0, nil) }
    return (opened + hairline).sorted { $0.event < $1.event }
}
