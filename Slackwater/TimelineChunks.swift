// Slackwater — GPL v3. The infinite strip's data layer. The timeline is built
// in week-sized chunks keyed to a fixed origin midnight and merged into one
// `TimelineData` covering a sliding span around the scrub position, so the
// strip can extend in either direction forever while holding a bounded number
// of chunks in memory. The expensive work — engine sampling, Almanac sun/moon
// chrome, eclipse search — happens once per chunk, off the main actor; a merge
// is array concatenation and runs on every chunk arrival.
//
// Seam rules, all here so they cannot drift:
// - Samples: the engine grid is epoch-aligned (`makeTimeline` floors `from` to
//   the step), so per-chunk sampling over [start, end) reproduces the
//   monolithic grid exactly. Each chunk drops samples at or past its `end`;
//   the next chunk supplies them.
// - Events: root-finding scans are seeded from `from` and filter close pairs
//   against their neighbours, so each chunk scans with `TimelineData.eventPad`
//   of context and keeps only events inside its own half-open span. Bisection
//   roots carry ~1s of jitter between differently-seeded scans, so the merge
//   drops a same-kind event within 2s of the one before it.
// - Day chrome: a night band needs the NEXT day's sunrise and the previous
//   day's sunset, so a chunk carries one day of chrome beyond each end and the
//   merge dedupes by day start.
import Almanac
import Foundation
import SwiftUI
import TideEngine

// MARK: - What a chunk is built from

/// The three constituent-backed station kinds. The online gate stays on the
/// fetched-block builder (`TimelineData.build(onlinePoints:)`) — its data is
/// bounded by what was downloaded, not by what can be computed.
enum TimelineSource {
    case tide(TideStationRecord)
    case current(CurrentStationRecord, threshold: Double)
    case gate(DerivedGateRecord)

    var tz: TimeZone {
        switch self {
        case .tide(let r): r.tz
        case .current(let r, _): r.tz
        case .gate(let r): r.gate.tz
        }
    }
    var latitude: Double {
        switch self {
        case .tide(let r): r.latitude
        case .current(let r, _): r.latitude
        case .gate(let r): r.gate.latitude
        }
    }
    var longitude: Double {
        switch self {
        case .tide(let r): r.longitude
        case .current(let r, _): r.longitude
        case .gate(let r): r.gate.longitude
        }
    }
    var threshold: Double {
        if case .current(_, let t) = self { return t }
        return defaultSlackThresholdKn
    }
    var isSchematic: Bool {
        if case .gate = self { return true }
        return false
    }
}

// MARK: - One week of strip data

struct TimelineChunk {
    let index: Int
    let start: Date          // local midnight
    let end: Date            // the next chunk's start — 7 calendar days on
    /// Day chrome for start−1d through end, inclusive: one day beyond each
    /// edge so night bands that straddle the seam have both their sunset and
    /// the closing sunrise. Offsets here are chunk-relative and meaningless;
    /// the merge rewrites them against the current anchor.
    let days: [TimelineDay]
    let tidePoints: [TidePoint]
    let tideRates: [TideRatePoint]
    let tideExtremes: [TideExtreme]
    let currentPoints: [CurrentPoint]
    let currentEvents: [CurrentEvent]
    let slackWindows: [(slack: Date, start: Date, end: Date)]
    let eclipses: [WindowEclipse]

    /// A derived gate's schematic shape needs the slack before and after every
    /// sample, and slacks run ~6h apart — a wider net than the event pad.
    static let gateSlackPad = 24.0 * 3600

    static func build(_ source: TimelineSource, index: Int, start: Date, end: Date) -> TimelineChunk {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = source.tz
        let observer = try? Observer(latitudeDeg: source.latitude, longitudeDeg: source.longitude)

        var days: [TimelineDay] = []
        var dayStart = cal.date(byAdding: .day, value: -1, to: start)!
        var off = -1
        while dayStart <= end {
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            let sun = observer.flatMap { try? sunEvents(from: dayStart, to: dayEnd, observer: $0) } ?? []
            let moon = observer.flatMap { try? moonEvents(from: dayStart, to: dayEnd, observer: $0) } ?? []
            days.append(TimelineDay(offset: off, start: dayStart,
                                    sunrise: sun.first { $0.kind == .rise }?.time,
                                    sunset: sun.first { $0.kind == .set }?.time,
                                    moonrise: moon.first { $0.kind == .rise }?.time,
                                    moonset: moon.first { $0.kind == .set }?.time))
            dayStart = dayEnd
            off += 1
        }

        let pad = TimelineData.eventPad
        let inSpan = { (t: Date) in t >= start && t < end }

        var tidePoints: [TidePoint] = []
        var tideRates: [TideRatePoint] = []
        var tideExtremes: [TideExtreme] = []
        var currentPoints: [CurrentPoint] = []
        var currentEvents: [CurrentEvent] = []
        var windows: [(slack: Date, start: Date, end: Date)] = []

        switch source {
        case .tide(let record):
            let s = record.engineStation
            tidePoints = s.heights(from: start, to: end, step: 600).filter { $0.time < end }
            tideRates = s.rates(from: start, to: end, step: 600).filter { $0.time < end }
            tideExtremes = s.extremes(from: start.addingTimeInterval(-pad),
                                      to: end.addingTimeInterval(pad)).filter { inSpan($0.time) }
        case .current(let record, let threshold):
            let s = record.engineStation
            // Padded samples feed the slack-window measurement so a window
            // whose slack sits near the seam still sees its far shoulder;
            // only the in-span samples are drawn.
            let padded = s.speeds(from: start.addingTimeInterval(-pad),
                                  to: end.addingTimeInterval(pad), step: 600)
            currentPoints = padded.filter { inSpan($0.time) }
            currentEvents = s.events(from: start.addingTimeInterval(-pad),
                                     to: end.addingTimeInterval(pad)).filter { inSpan($0.time) }
            windows = currentEvents.filter { $0.kind == .slack }.compactMap { e in
                slackWindow(padded, around: e.time, threshold: threshold)
                    .map { (slack: e.time, start: $0.start, end: $0.end) }
            }
        case .gate(let record):
            let g = record.engineGate
            let slacks = g.slacks(from: start.addingTimeInterval(-Self.gateSlackPad),
                                  to: end.addingTimeInterval(Self.gateSlackPad))
            currentEvents = slacks.filter { inSpan($0.time) }
                .map { CurrentEvent(time: $0.time, speed: 0, kind: .slack) }
            var t = start
            while t < end {
                currentPoints.append(CurrentPoint(time: t, speed: g.schematicSigned(at: t, slacks: slacks)))
                t = t.addingTimeInterval(600)
            }
        }

        let eclipses = (observer.map { visibleEclipses(from: start, to: end, observer: $0) } ?? [])
            .filter { inSpan($0.peak) }

        return TimelineChunk(index: index, start: start, end: end, days: days,
                             tidePoints: tidePoints, tideRates: tideRates, tideExtremes: tideExtremes,
                             currentPoints: currentPoints, currentEvents: currentEvents,
                             slackWindows: windows, eclipses: eclipses)
    }
}

// MARK: - Merging chunks into the one TimelineData the strip draws

extension TimelineData {
    /// Contiguous, index-ordered chunks → the same struct the monolithic
    /// builders produce, spanning first.start … last.end.
    static func merged(_ chunks: [TimelineChunk], source: TimelineSource,
                       anchor: Date, today: Date) -> TimelineData {
        let tz = source.tz
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let start = chunks.first?.start ?? anchor
        let end = chunks.last?.end ?? anchor

        // Day chrome: dedupe the one-day overlaps, re-key offsets on the
        // anchor — `MultiDaySchedule` groups and the accessibility ids read
        // days-from-anchor, exactly as the monolithic `dayChrome` built them.
        var seen = Set<Date>()
        let days: [TimelineDay] = chunks.flatMap(\.days)
            .sorted { $0.start < $1.start }
            .filter { seen.insert($0.start).inserted }
            .map { d in
                TimelineDay(offset: cal.dateComponents([.day], from: anchor, to: d.start).day ?? 0,
                            start: d.start, sunrise: d.sunrise, sunset: d.sunset,
                            moonrise: d.moonrise, moonset: d.moonset)
            }

        // Bisection roots jitter ~1s between differently-seeded scans; a
        // boundary event caught by both neighbouring chunks would otherwise
        // print twice.
        func dedupeExtremes(_ events: [TideExtreme]) -> [TideExtreme] {
            var out: [TideExtreme] = []
            for e in events where !(out.last.map { $0.kind == e.kind && e.time.timeIntervalSince($0.time) < 2 } ?? false) {
                out.append(e)
            }
            return out
        }
        func dedupeEvents(_ events: [CurrentEvent]) -> [CurrentEvent] {
            var out: [CurrentEvent] = []
            for e in events where !(out.last.map { $0.kind == e.kind && e.time.timeIntervalSince($0.time) < 2 } ?? false) {
                out.append(e)
            }
            return out
        }

        let tidePoints = chunks.flatMap(\.tidePoints)
        let tideRates = chunks.flatMap(\.tideRates)
        let tideExtremes = dedupeExtremes(chunks.flatMap(\.tideExtremes))
        let currentPoints = chunks.flatMap(\.currentPoints)
        let currentEvents = dedupeEvents(chunks.flatMap(\.currentEvents))
        var windows = chunks.flatMap(\.slackWindows)
        windows = windows.enumerated().filter { i, w in
            i == 0 || w.slack.timeIntervalSince(windows[i - 1].slack) >= 2
        }.map(\.element)
        var eclipseSeen = Set<Date>()
        let eclipses = chunks.flatMap(\.eclipses).filter { eclipseSeen.insert($0.peak).inserted }

        // The magnet's stops, assembled the way both monolithic builders do it.
        let sunTimes = days.flatMap { [$0.sunrise, $0.sunset].compactMap { $0 } }
        let snaps = Array(Set(tideExtremes.map(\.time) + tideFlowArrows(tideRates).map(\.time)
                              + currentEvents.map(\.time) + sunTimes
                              + eclipses.flatMap(\.contacts)
                              + windows.flatMap { [$0.start, $0.end] }))
            .filter { $0 >= start && $0 <= end }.sorted()

        return TimelineData(tz: tz, anchor: anchor, today: today, start: start, end: end, days: days,
                            tidePoints: tidePoints, tideRates: tideRates, tideExtremes: tideExtremes,
                            currentPoints: currentPoints, currentEvents: currentEvents,
                            snapTimes: snaps, eclipses: eclipses, slackWindows: windows,
                            slackThreshold: source.threshold,
                            speedsAreSchematic: source.isSchematic)
    }
}

// MARK: - Vertical scale: viewport-fit with hysteresis

/// The plot box's y-mapping inputs, decoupled from "everything loaded": with
/// a sliding window the data span changes on every chunk swap, and a scale
/// derived from it would visibly re-stretch the curve on chunk churn.
struct TimelineScale: Equatable {
    var tideMid: Double
    var tideSpan: Double
    var maxAbsCur: Double

    /// The exact padding formulas `TimelineGeo` has always applied, shared so
    /// the governor's targets and the geometry can never disagree.
    static func fitting(tideMin: Double, tideMax: Double, maxSpeed: Double) -> TimelineScale {
        TimelineScale(tideMid: (tideMin + tideMax) / 2,
                      tideSpan: max((tideMax - tideMin) / 2, 0.01) * 1.06,
                      maxAbsCur: max(maxSpeed, 0.01) * 1.05)
    }

    static func fitting(_ data: TimelineData) -> TimelineScale {
        let heights = data.tidePoints.map(\.height)
        return fitting(tideMin: heights.min() ?? 0, tideMax: heights.max() ?? 1,
                       maxSpeed: data.currentPoints.map { abs($0.speed) }.max() ?? 1)
    }
}

/// When the y-scale may move (Swift Charts' behaviour, held by a deadband):
/// expand just before the visible curve would clip, contract only when the
/// box has gone mostly empty. Between the two thresholds a pan never
/// rescales. After adopting a fit the data reaches 1/1.06 ≈ 0.94 of the span,
/// inside both thresholds, so an adoption is always a fixed point.
///
/// ponytail: a rescale lands as a snap. The upgrade path is animating
/// `TimelineScale` toward the governor's target over a few frames before it
/// reaches TimelineGeo; nothing else changes.
enum ScaleGovernor {
    static let expandAt = 0.97
    static let contractAt = 0.65

    static func update(_ current: TimelineScale,
                       tideMin: Double?, tideMax: Double?, maxSpeed: Double?) -> TimelineScale {
        var out = current
        if let mn = tideMin, let mx = tideMax, mx >= mn {
            let reach = max(mx - current.tideMid, current.tideMid - mn) / current.tideSpan
            let target = TimelineScale.fitting(tideMin: mn, tideMax: mx, maxSpeed: 0)
            if reach > expandAt || target.tideSpan < contractAt * current.tideSpan {
                out.tideMid = target.tideMid
                out.tideSpan = target.tideSpan
            }
        }
        if let mv = maxSpeed {
            let fitted = max(mv, 0.01) * 1.05
            if mv > expandAt * current.maxAbsCur || fitted < contractAt * current.maxAbsCur {
                out.maxAbsCur = fitted
            }
        }
        return out
    }
}

// MARK: - Scroll gate

/// The one fact the store needs from the scroll view: is it safe to move the
/// coordinate origin? Prepending or left-evicting chunks shifts `data.start`,
/// which shifts every x and forces a contentOffset write — and an offset
/// write is how UIKit CANCELS a deceleration (TimelineScrubber's own settle
/// logic relies on that). Appends are offset-neutral and never wait.
///
/// Main-thread only by convention, not annotation: the writer is a scroll-view
/// delegate (always main) and a `@MainActor` type here would force the whole
/// non-isolated Coordinator onto the actor.
final class ScrollGate {
    var isQuiet = true {
        didSet { if isQuiet, !oldValue { onQuiet?() } }
    }
    var onQuiet: (() -> Void)?
}

// MARK: - The store

/// One per detail view: owns the chunk cache, builds off-main around the
/// scrub position, evicts by distance, and publishes the merged TimelineData
/// plus the governed vertical scale.
@MainActor @Observable final class TimelineWindowStore {
    private let source: TimelineSource
    private let tz: TimeZone

    private(set) var timeline: TimelineData?
    private(set) var scale: TimelineScale?
    let gate = ScrollGate()

    /// Chunk 0's local midnight — the first anchor. Never moves; chunk
    /// indices are stable for the life of the store.
    private var origin = Date.distantPast
    private var anchor = Date.distantPast
    private var chunks: [Int: TimelineChunk] = [:]
    private var building: Set<Int> = []
    private var published: ClosedRange<Int>?
    private var lastFocus = 0
    /// A publish that would move the left edge, parked until the scroll rests.
    private var pendingPublish = false
    private var viewportHours = 24.0

    /// Chunks kept built each side of the focus. Two weeks of margin outruns
    /// a maximal fling (~10 days at 18pt/h) with room to spare, so the left
    /// edge never needs to move mid-deceleration; a chain of maximal flings
    /// with no rest between them can still reach the loaded edge, where the
    /// strip clamps until the next quiet moment extends it.
    static let ensureRadius = 2
    /// Chunks kept in the published window each side of the focus: ±3 weeks
    /// on screen, everything further evicted at the next quiet moment.
    static let evictRadius = 3
    static let chunkDays = 7

    init(source: TimelineSource) {
        self.source = source
        tz = source.tz
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        calendar = cal
        // The gate flips from a scroll delegate — main thread, but not a
        // MainActor context the compiler can see.
        //
        // The publish is DEFERRED to the next turn of the run loop. The gate
        // is also synced from inside `updateUIView`, so a strip that comes to
        // rest during a SwiftUI update would otherwise publish a new timeline
        // in the middle of the pass that is reading it — "Modifying state
        // during view update", which SwiftUI calls undefined behavior and
        // which showed up as a strip that never appeared. The centering code
        // in `TimelineScrubber` avoids the same trap the same way.
        gate.onQuiet = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingPublish else { return }
                self.pendingPublish = false
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    publishAround(lastFocus)
                }
            }
        }
    }

    /// First build, synchronous — the opening view needs its own chunks the
    /// same way it used to need the monolithic build, and nothing else.
    /// Neighbours arrive in the background. `focus` nil opens around `now`
    /// (the intro slide); a replacement store for a page already parked
    /// elsewhere passes the parked scrub instead.
    func start(anchor: Date, now: Date, focus: Date? = nil) {
        guard origin == .distantPast else { return }
        origin = anchor
        self.anchor = anchor
        // Cover the intro slide's look-back and half a viewport either side.
        let reach = 15.0 * 3600
        let center = focus ?? now
        syncBuild(covering: center.addingTimeInterval(-reach)...center.addingTimeInterval(reach))
        lastFocus = chunkIndex(containing: center)
        publishAround(lastFocus)
        scale = timeline.map(TimelineScale.fitting)
        ensureBuilt((lastFocus - Self.ensureRadius)...(lastFocus + Self.ensureRadius))
    }

    /// Every scrub frame. Cheap when nothing is missing.
    func focus(_ t: Date, viewportPts: CGFloat) {
        guard timeline != nil else { return }
        if viewportPts > 0 { viewportHours = max(Double(viewportPts / Timeline.pph), 6) }
        let k = chunkIndex(containing: t)
        lastFocus = k
        ensureBuilt((k - Self.ensureRadius)...(k + Self.ensureRadius))
        publishAround(k)
        updateScale(around: t)
    }

    /// The week bar's job follows the scrub: re-key the schedule without
    /// touching geometry. Same chunks, same start — safe at any moment.
    func setAnchor(_ a: Date) {
        guard a != anchor else { return }
        anchor = a
        if let published { apply(published) }
    }

    /// A picker jump, a shared link, or a far return-to-now: land on `t`
    /// immediately, building its chunk synchronously when it isn't cached —
    /// the same beat the old monolithic rebuild had.
    func jump(to t: Date, anchor a: Date) {
        anchor = a
        let half = viewportHours / 2 * 3600
        syncBuild(covering: t.addingTimeInterval(-half)...t.addingTimeInterval(half))
        lastFocus = chunkIndex(containing: t)
        pendingPublish = false
        publishAround(lastFocus, force: true)
        ensureBuilt((lastFocus - Self.ensureRadius)...(lastFocus + Self.ensureRadius))
        updateScale(around: t)
    }

    // MARK: chunk arithmetic

    private let calendar: Calendar

    /// Exact across DST: both `origin` and `startOfDay(t)` are local
    /// midnights, so the day count is whole and floor-division buckets it.
    private func chunkIndex(containing t: Date) -> Int {
        let d = calendar.dateComponents([.day], from: origin, to: calendar.startOfDay(for: t)).day ?? 0
        return Int((Double(d) / Double(Self.chunkDays)).rounded(.down))
    }

    private func chunkStart(_ i: Int) -> Date {
        calendar.date(byAdding: .day, value: i * Self.chunkDays, to: origin)!
    }

    // MARK: building

    private func syncBuild(covering span: ClosedRange<Date>) {
        let lo = chunkIndex(containing: span.lowerBound)
        let hi = chunkIndex(containing: span.upperBound)
        for i in lo...hi where chunks[i] == nil {
            chunks[i] = TimelineChunk.build(source, index: i,
                                            start: chunkStart(i), end: chunkStart(i + 1))
        }
    }

    private func ensureBuilt(_ range: ClosedRange<Int>) {
        for i in range where chunks[i] == nil && !building.contains(i) {
            building.insert(i)
            let source = source, start = chunkStart(i), end = chunkStart(i + 1)
            Task.detached(priority: .userInitiated) {
                let chunk = TimelineChunk.build(source, index: i, start: start, end: end)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    building.remove(i)
                    chunks[i] = chunk
                    publishAround(lastFocus)
                }
            }
        }
    }

    // MARK: publishing

    private func contiguousRun(around k: Int) -> ClosedRange<Int>? {
        guard chunks[k] != nil else { return published }
        var lo = k, hi = k
        while chunks[lo - 1] != nil, k - lo < Self.evictRadius { lo -= 1 }
        while chunks[hi + 1] != nil, hi - k < Self.evictRadius { hi += 1 }
        return lo...hi
    }

    private func publishAround(_ k: Int, force: Bool = false) {
        guard var target = contiguousRun(around: k) else { return }
        // A moving left edge has to wait for the scroll to rest. Growing to
        // the RIGHT does not: appended width leaves every existing x alone,
        // so it needs no offset write and cannot cancel the fling. Keeping
        // the old left edge while extending forward is what lets a chain of
        // flings run on without ever reaching the drawn edge.
        if !force, !gate.isQuiet, let published, target.lowerBound != published.lowerBound {
            pendingPublish = true
            target = published.lowerBound...max(target.upperBound, published.upperBound)
        }
        guard target != published else { return }
        apply(target)
    }

    private func apply(_ range: ClosedRange<Int>) {
        // Never merge across a hole: a gap would render as a strip whose
        // `start…end` claims hours it holds no samples for — a dead zone
        // under a perfectly confident readout. Short is honest; holed is not.
        guard chunks[range.lowerBound] != nil else { return }
        var hi = range.lowerBound
        while hi + 1 <= range.upperBound, chunks[hi + 1] != nil { hi += 1 }
        let solid = range.lowerBound...hi
        published = solid
        timeline = TimelineData.merged(solid.compactMap { chunks[$0] }, source: source,
                                       anchor: anchor, today: todayLocal(tz))
        // Drop chunks the window has left behind; a step back rebuilds them.
        // Keys collected before removing: mutating inside `for i in chunks.keys`
        // is well-defined in Swift (the iterator holds the original storage and
        // the removal copies), but leaving that for the next reader to work out
        // is not worth the allocation this saves on a path that runs only when
        // the window actually moves.
        let stale = chunks.keys.filter { $0 < solid.lowerBound - 1 || $0 > solid.upperBound + 1 }
        for i in stale { chunks.removeValue(forKey: i) }
        if scale == nil { scale = timeline.map(TimelineScale.fitting) }
    }

    // MARK: scale

    private func updateScale(around t: Date) {
        guard let tl = timeline, let current = scale else { return }
        let half = viewportHours / 2 * 3600 + 3600
        let from = t.addingTimeInterval(-half), to = t.addingTimeInterval(half)
        // One pass, no intermediate array. This runs on every scrub frame, and
        // `map` then `min` then `max` is an allocation and three walks of the
        // visible samples to answer what one walk answers.
        var tideMin: Double?, tideMax: Double?
        if tl.hasTide {
            var mn = Double.greatestFiniteMagnitude, mx = -Double.greatestFiniteMagnitude
            for p in slice(tl.tidePoints, \.time, from, to) {
                if p.height < mn { mn = p.height }
                if p.height > mx { mx = p.height }
            }
            if mn <= mx { tideMin = mn; tideMax = mx }
        }
        var maxSpeed: Double?
        if tl.hasCurrent, !tl.speedsAreSchematic {
            var mx = -Double.greatestFiniteMagnitude
            for p in slice(tl.currentPoints, \.time, from, to) where abs(p.speed) > mx {
                mx = abs(p.speed)
            }
            if mx >= 0 { maxSpeed = mx }
        }
        let next = ScaleGovernor.update(current, tideMin: tideMin, tideMax: tideMax, maxSpeed: maxSpeed)
        if next != current { scale = next }
    }

    /// Contiguous sub-array with `keyPath` in [from, to], by binary search —
    /// this runs on every scrub frame and must not scan five weeks of samples.
    private func slice<T>(_ sorted: [T], _ keyPath: KeyPath<T, Date>, _ from: Date, _ to: Date) -> ArraySlice<T> {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid][keyPath: keyPath] < from { lo = mid + 1 } else { hi = mid }
        }
        var lo2 = lo, hi2 = sorted.count
        while lo2 < hi2 {
            let mid = (lo2 + hi2) / 2
            if sorted[mid][keyPath: keyPath] <= to { lo2 = mid + 1 } else { hi2 = mid }
        }
        return sorted[lo..<lo2]
    }
}
