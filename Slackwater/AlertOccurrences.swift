// Slackwater — GPL v3. Alert rules → dated occurrences, read from the producers the strip already draws (notifications spec §4).
import Almanac
import Foundation
import TideEngine

/// Sample series start on a fixed 10-minute grid, so every reschedule interpolates the same
/// instants and a calendar event keeps its identity from one run to the next.
private func alertSampleGrid(_ t: Date) -> Date {
    Date(timeIntervalSince1970: (t.timeIntervalSince1970 / 600).rounded(.down) * 600)
}

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
    let start = alertSampleGrid(from).addingTimeInterval(-21_600), stop = to.addingTimeInterval(21_600)
    let points = station.speeds(from: start, to: stop, step: 600)
    let slacks = station.events(from: start, to: stop).filter { $0.kind == .slack }.map(\.time)
    let runs = mergeWindows(slacks.compactMap { slackWindow(points, around: $0, threshold: threshold) })
    let opened: [(event: Date, end: Date?)] = runs.map { ($0.start, $0.end) }
    let hairline: [(event: Date, end: Date?)] = slacks
        .filter { t in !runs.contains { $0.contains(t) } }
        .map { ($0, nil) }
    return (opened + hairline).sorted { $0.event < $1.event }
}

/// One dated event a rule found (notifications spec §4).
struct AlertOccurrence: Equatable, Sendable {
    let ruleID: UUID
    /// The water event itself.
    let event: Date
    /// When a notification fires: `event − lead`.
    let fire: Date
    /// A window's close.
    var end: Date? = nil
    /// A slack no run under the threshold covers.
    var noWindow = false
    /// Tide triggers: the height at the event, metres.
    var heightM: Double? = nil

    var key: String { "\(ruleID.uuidString).\(Int(event.timeIntervalSince1970))" }
}

/// What copy names: the station and the zone its times read in.
struct AlertPlace: Equatable, Sendable {
    let name: String
    let tz: TimeZone
}

extension WidgetRecord {
    /// Where the sky is read from. A derived gate uses its own position, not its reference port's.
    var alertPosition: (lat: Double, lon: Double) {
        switch self {
        case .tide(let r, _): (r.latitude, r.longitude)
        case .current(let r, _): (r.latitude, r.longitude)
        case .derived(let r): (r.gate.latitude, r.gate.longitude)
        }
    }

    var alertPlace: AlertPlace {
        switch self {
        case .tide(let r, _): AlertPlace(name: r.name, tz: r.tz)
        case .current(let r, _): AlertPlace(name: r.name, tz: r.tz)
        case .derived(let r): AlertPlace(name: r.gate.name, tz: r.gate.tz)
        }
    }
}

/// Every occurrence of `rule` at `station` with its event inside `[from, to]`. Pure: the
/// scheduler and the tests are its only callers.
func alertOccurrences(_ rule: AlertRule, station: WidgetStation, position: (lat: Double, lon: Double),
                      from: Date, to: Date, threshold: Double) -> [AlertOccurrence] {
    var found: [(event: Date, end: Date?, noWindow: Bool, heightM: Double?)]

    switch (rule.trigger, station) {
    case (.slackWindowOpens, .current(let s, _, _)):
        found = slackWindowOpenings(s, from: from, to: to, threshold: threshold)
            .map { (event: $0.event, end: $0.end, noWindow: $0.end == nil, heightM: nil) }
    case (.currentPeak(let flood), .current(let s, _, _)):
        found = s.events(from: from, to: to)
            .filter { $0.kind == (flood ? .maxFlood : .maxEbb) }
            .map { (event: $0.time, end: nil, noWindow: false, heightM: nil) }
    case (.slack, .derived(let g, _, _)):
        found = g.slacks(from: from, to: to)
            .map { (event: $0.time, end: nil, noWindow: false, heightM: nil) }
    case (.tideExtreme(let high), .tide(let s, _, _)):
        found = s.extremes(from: from, to: to)
            .filter { $0.kind == (high ? .high : .low) }
            .map { (event: $0.time, end: nil, noWindow: false, heightM: $0.height) }
    case (.tideCrossing(let level, let rising), .tide(let s, _, _)):
        let samples = s.heights(from: alertSampleGrid(from), to: to, step: 600).map { (time: $0.time, height: $0.height) }
        found = tideCrossings(samples, level: level, rising: rising)
            .map { (event: $0, end: nil, noWindow: false, heightM: level) }
    case (.eclipse, _):
        guard let observer = try? Observer(latitudeDeg: position.lat, longitudeDeg: position.lon) else { return [] }
        found = visibleEclipses(from: from, to: to, observer: observer)
            .map { (event: $0.start, end: nil, noWindow: false, heightM: nil) }
    default:
        // The trigger doesn't apply to this kind of station (spec §8).
        return []
    }

    found = found.filter { $0.event >= from && $0.event <= to }
    if rule.daylightOnly {
        let spans = daylightSpans(from: from, to: to, lat: position.lat, lon: position.lon)
        found = found.filter { f in spans.contains { $0.contains(f.event) } }
    }
    return found.map {
        AlertOccurrence(ruleID: rule.id, event: $0.event, fire: $0.event.addingTimeInterval(-rule.lead),
                        end: $0.end, noWindow: $0.noWindow, heightM: $0.heightM)
    }
}
