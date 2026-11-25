// Slackwater — GPL v3. Online gates: fetched, never fitted. The one-per-gate
// window fetch, its on-disk store, and the readings a card and a strip take
// off a fetched window.
import Foundation
import SlackwaterKit

extension ChsFitService {
    /// The span one fetch covers: `Timeline.window`'s start for the anchor —
    /// back-padded like every window (#67 item 1), never re-derived here — and
    /// `Timeline.onlineFetchDays` forward of it, four strips' worth, so ordinary
    /// paging lands in cache instead of on the network.
    ///
    /// Split out of `fetchOnlineWindow` only so it can be tested: everything
    /// around it in that function needs IWLS, which would leave the anchored
    /// branch — the one a date picker will use — shipping unexercised.
    nonisolated static func onlineFetchSpan(anchor: Date?, today: Date) -> (start: Date, end: Date) {
        let from = anchor ?? today
        return (Timeline.window(anchor: from).start,
                from.addingTimeInterval(Timeline.onlineFetchDays * 86_400))
    }

    /// Pair the original IWLS vectors with the signed projection at each timestamp.
    nonisolated static func onlineVectors(speeds: [ChsSample], dirs: [ChsSample], flood: Double)
        -> (projected: [ChsSample], magnitudes: [Double], directions: [Double])? {
        let valid: (ChsSample) -> Bool = { $0.t.isFinite && abs($0.t) < Double(Int64.max) && $0.v.isFinite }
        let validDirections = dirs.filter(valid)
        let speedByTime = Dictionary(speeds.filter { valid($0) && $0.v >= 0 }.map { (Int64($0.t.rounded()), $0.v) }, uniquingKeysWith: { a, _ in a })
        let uniqueSpeeds = speedByTime.map { ChsSample(t: Double($0.key), v: $0.value) }.sorted { $0.t < $1.t }
        let directionByTime = Dictionary(validDirections.map { (Int64($0.t.rounded()), $0.v) }, uniquingKeysWith: { a, _ in a })
        let uniqueDirections = directionByTime.map { ChsSample(t: Double($0.key), v: $0.value) }.sorted { $0.t < $1.t }
        let projected = project(speeds: uniqueSpeeds, dirs: uniqueDirections, floodDirection: flood)
        guard !projected.isEmpty else { return nil }
        let magnitudes = projected.compactMap { speedByTime[Int64($0.t.rounded())] }
        let directions = projected.compactMap { directionByTime[Int64($0.t.rounded())] }
        guard magnitudes.count == projected.count, directions.count == projected.count,
              magnitudes.allSatisfy({ $0.isFinite && $0 >= 0 }), directions.allSatisfy(\.isFinite) else { return nil }
        return (projected, magnitudes, directions)
    }

    /// Fill a single missing direction only when its speed was measured.
    nonisolated static func fillSingleOnlineGaps(
        projected: [ChsSample], magnitudes: [Double], directions: [Double],
        measuredSpeeds: [ChsSample], flood: Double
    ) -> (projected: [ChsSample], magnitudes: [Double], directions: [Double?]) {
        guard projected.count == magnitudes.count, projected.count == directions.count else {
            return (projected, magnitudes, directions.map { Optional($0) })
        }
        let validSpeeds = measuredSpeeds.filter { $0.t.isFinite && abs($0.t) < Double(Int64.max) && $0.v.isFinite && $0.v >= 0 }
        let byTime = Dictionary(validSpeeds.map { (Int64($0.t.rounded()), $0.v) }, uniquingKeysWith: { first, _ in first })
        var samples: [ChsSample] = [], speeds: [Double] = [], bearings: [Double?] = []
        for i in projected.indices {
            if i > 0, projected[i].t - projected[i - 1].t == 2 * ChsOnlineWindow.sampleInterval * 1000 {
                let midpoint = (projected[i - 1].t + projected[i].t) / 2
                if let magnitude = byTime[Int64(midpoint.rounded())] {
                    let a = directions[i - 1] * .pi / 180, b = directions[i] * .pi / 180
                    let east = (magnitudes[i - 1] * sin(a) + magnitudes[i] * sin(b)) / 2
                    let north = (magnitudes[i - 1] * cos(a) + magnitudes[i] * cos(b)) / 2
                    let bearing: Double? = cos(a - b) > 0 && hypot(east, north) > 1e-9
                        ? (atan2(east, north) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) : nil
                    let estimate = (projected[i - 1].v + projected[i].v) / 2
                    let signed = bearing.map { magnitude * cos(($0 - flood) * .pi / 180) }
                        ?? max(-magnitude, min(magnitude, estimate))
                    samples.append(ChsSample(t: midpoint, v: signed))
                    speeds.append(magnitude)
                    bearings.append(bearing)
                }
            }
            samples.append(projected[i]); speeds.append(magnitudes[i]); bearings.append(directions[i])
        }
        return (samples, speeds, bearings)
    }

    nonisolated static func onlineRuns(_ projected: [ChsSample]) -> [Range<Int>] {
        guard !projected.isEmpty else { return [] }
        var runs: [Range<Int>] = []
        var start = 0
        for i in 1..<projected.count where projected[i].t - projected[i - 1].t > ChsOnlineWindow.sampleInterval * 1000 {
            if i - start > 1 { runs.append(start..<i) }
            start = i
        }
        if projected.count - start > 1 { runs.append(start..<projected.count) }
        return runs
    }

    nonisolated static func onlineCoveredWindow(_ blocks: [ChsOnlineWindow], anchor: Date, name: String) throws -> ChsOnlineWindow {
        guard let window = blocks.first(where: { $0.covers(anchor: anchor) }) else {
            throw ChsError.incomplete("\(name): IWLS returned incomplete current vectors")
        }
        return window
    }

    /// The fit-reject gates (`ChsCurrentGateInfo.isOnline`) get no on-device fit
    /// — only official wcsp1/wcdp1 predictions, `Timeline.onlineFetchDays` forward
    /// of `anchor` (today unless a caller says otherwise) and back-padded like
    /// the strip, resolved/projected exactly like `fitCurrent` but served as
    /// fetched samples rather than harmonic constituents. No queue, no yield
    /// point: these gates never join the fit queue, so there is nothing to
    /// step aside for — a throw here is the whole story, and
    /// `OnlineGateDetailView` shows the honesty card on it.
    ///
    /// Persists the window itself (never just returns it for the caller to
    /// save) and bumps `onlineFetchStamp` on a successful save — one seam,
    /// so every caller, today's and any future one, gets the same
    /// "the fetch landed" signal without re-deriving it.
    ///
    /// Returns the stored block this fetch merged into — never narrower than
    /// the disk's copy of this span. Only a failed disk write falls back to
    /// the bare fetched block.
    ///
    /// ONE fetch per gate at a time. The picker's speculative prefetch and the
    /// user's own fetch of the week they landed on are both fetches of the same
    /// file, and run concurrently they interleave a read-modify-write: disjoint
    /// blocks coexist on disk (#67 item 4), so the store keeps both, but two
    /// concurrent read-modify-writes of one file still lose ONE of the two
    /// fetches. A second caller joins the fetch already running instead of
    /// starting its own, which also spares the duplicate 30-day round trip —
    /// and is what the coalescing below is for.
    ///
    /// ponytail: coalescing is by gate, NOT by gate+span — a joiner gets the
    /// span the in-flight fetch asked for, which may not cover it. That path
    /// ends on the honesty card whose "Try again" fetches the parked anchor,
    /// so it is recoverable; key the span in too if that ever reads as a bug.
    ///
    /// Main-actor, like every caller, so the prefetch loop takes a gate off
    /// `onlinePending` and marks it `.fetching` without a suspension between.
    /// A hop there would leave it idle and unqueued for a turn, which reads as
    /// no work to the download counts and to the background task's completion
    /// poll. A tap starts its fetch a turn later, so it goes through
    /// `startOnlineWork`, which holds the gate across that turn.
    static func fetchOnlineWindow(for gate: ChsCurrentGateInfo,
                                  from anchor: Date?, automatic: Bool = false) async throws -> ChsOnlineWindow {
        try await fetchOnlineUpdate(for: gate, from: anchor ?? todayLocal(gate.tz)) { from in
            try await shared.onlineFetchTask(for: gate, from: from, automatic: automatic).value
        }
    }

    /// Work that fetches `gate` in a new Task, for a tap or the detail view's
    /// own fetches. The Task runs a turn later, so the gate is held from this turn until the work ends
    /// (`onlineHolds`). Every path releases it: the release is the Task's own.
    static func startOnlineWork(for gate: ChsCurrentGateInfo,
                                _ work: @escaping @MainActor () async -> Void) {
        shared.holdOnline(gate)
        Task { @MainActor in
            defer { shared.releaseOnline(gate.id) }
            await work()
        }
    }

    /// A date-specific fetch must also replace any today refresh it displaced.
    /// `fetch` is main-actor so calling it is not a hop (`fetchOnlineWindow`).
    /// The gate is held for the whole update: the first fetch returns it to
    /// idle a turn before this resumes to start the one for today.
    static func fetchOnlineUpdate(for gate: ChsCurrentGateInfo, from anchor: Date,
                                  fetch: @MainActor (Date) async throws -> ChsOnlineWindow) async throws -> ChsOnlineWindow {
        shared.holdOnline(gate)
        defer { shared.releaseOnline(gate.id) }
        let result: Result<ChsOnlineWindow, Error>
        do {
            result = .success(try await fetch(anchor))
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            guard case .incomplete = error as? ChsError else { throw error }
            result = .failure(error)
        }
        let today = todayLocal(gate.tz)
        if anchor != today, (try? result.get().covers(anchor: today)) != true,
           ChsModelStore.loadOnline(gate.id)?.block(covering: today) == nil {
            _ = try? await fetch(today)
        }
        return try result.get()
    }

    /// The check-and-set, on the main actor so it is atomic: an existing handle
    /// is joined, otherwise one is registered before this returns. The task
    /// clears its own entry on the way out — success, failure or throw.
    @MainActor
    private func onlineFetchTask(for gate: ChsCurrentGateInfo,
                                 from anchor: Date?, automatic: Bool) throws -> Task<ChsOnlineWindow, Error> {
        guard !automatic || isFetchingOnline(gate.id) else { throw CancellationError() }
        if let existing = onlineFetch(for: gate.id) {
            if !automatic { retainOnline(gate) }
            return existing
        }
        beginOnlineFetch(gate)
        if !automatic { retainOnline(gate) }
        let task = Task { @MainActor in
            defer { ChsFitService.shared.setOnlineFetch(nil, for: gate.id) }
            do {
                let window = try await ChsFitService.runOnlineFetch(for: gate, from: anchor)
                finishOnlineFetch(gate.id)
                return window
            } catch {
                if Task.isCancelled {
                    onlineFetchCancelled(gate)
                } else if automatic,
                          ChsModelStore.loadOnline(gate.id)?.block(covering: todayLocal(gate.tz)) != nil {
                    noteOnlineRefreshFailure(gate.id)
                } else {
                    let incomplete: Bool
                    if case .incomplete = error as? ChsError { incomplete = true } else { incomplete = false }
                    noteOnlineFailure(gate.id, error: Self.reason(error),
                                      permanent: ChsError.isPermanent(error) && !incomplete,
                                      maxAttempts: incomplete ? 3 : nil)
                }
                throw error
            }
        }
        setOnlineFetch(task, for: gate.id)
        return task
    }

    /// The fetch itself. Private: everything goes through `fetchOnlineWindow`,
    /// which is where the one-per-gate rule lives.
    private nonisolated static func runOnlineFetch(for gate: ChsCurrentGateInfo,
                                                  from anchor: Date?) async throws -> ChsOnlineWindow {
        let fetcher = IwlsFetcher()
        let list = try await fetcher.stationList()
        let station = try Self.resolve(name: gate.name, latitude: gate.latitude, longitude: gate.longitude,
                                       series: "wcsp1", in: list)
        let meta = try await fetcher.metadata(stationID: station.id)
        guard let flood = meta.floodDirection, let ebb = meta.ebbDirection else {
            throw ChsError.permanent("\(gate.name): IWLS metadata has no flood axis")
        }
        let (start, end) = Self.onlineFetchSpan(anchor: anchor, today: todayLocal(gate.tz))
        // Same absolute 7-day grid `chunkPlan` uses for the fit path — the
        // fetched span in days, ending at its own end, gives exactly the chunk
        // set covering start…end (up to 7 days of slop at the grid boundary,
        // same tradeoff the fit path already makes).
        let plan = Self.chunkPlan(days: end.timeIntervalSince(start) / 86_400, end: end)
        let total = plan.count * 2 + 1
        await MainActor.run { shared.setOnlineProgress(gate.id, done: 1, total: total) }
        var speeds: [ChsSample] = [], dirs: [ChsSample] = []
        for (index, chunk) in plan.enumerated() {
            speeds += try await fetcher.series("wcsp1", stationID: station.id, chunk: chunk, cacheEmpty: false)
            await MainActor.run { shared.setOnlineProgress(gate.id, done: index * 2 + 2, total: total) }
            dirs += try await fetcher.series("wcdp1", stationID: station.id, chunk: chunk, cacheEmpty: false)
            await MainActor.run { shared.setOnlineProgress(gate.id, done: index * 2 + 3, total: total) }
        }
        try Task.checkCancellation()
        // Empty or unmatched IWLS series cannot establish coverage or a current vector.
        guard let rawVectors = Self.onlineVectors(speeds: speeds, dirs: dirs, flood: flood) else {
            IwlsFetcher.chunkCache.purge(station.id)
            throw ChsError.incomplete("\(gate.name): IWLS returned incomplete current vectors")
        }
        let vectors = Self.fillSingleOnlineGaps(projected: rawVectors.projected, magnitudes: rawVectors.magnitudes, directions: rawVectors.directions, measuredSpeeds: speeds, flood: flood)
        let projected = vectors.projected
        // A chunk IWLS truncates mid-series (a short response, a gap at one
        // edge) must not be saved under the full requested start/end — that
        // would make `covers` pass on a window with a hole in it and
        // render a strip with a dead zone. Clamp to what actually came back,
        // symmetrically, so a truncated fetch honestly fails coverage instead.
        let windows = Self.onlineRuns(projected).compactMap { range -> ChsOnlineWindow? in
            let first = Date(timeIntervalSince1970: projected[range.lowerBound].t / 1000)
            let last = Date(timeIntervalSince1970: projected[range.upperBound - 1].t / 1000)
            guard first <= end, last >= start else { return nil }
            return ChsOnlineWindow(stationID: gate.id, iwlsName: station.officialName, timezone: gate.timezone,
                                   fetchedAt: .now, start: max(start, first), end: min(end, last),
                                   floodDirection: flood, ebbDirection: ebb,
                                   times: range.map { projected[$0].t / 1000 }, speeds: range.map { projected[$0].v },
                                   magnitudes: range.map { vectors.magnitudes[$0] }, directions: range.map { vectors.directions[$0] })
        }
        guard !windows.isEmpty else {
            IwlsFetcher.chunkCache.purge(station.id)
            throw ChsError.incomplete("\(gate.name): IWLS returned incomplete current vectors")
        }
        var saved: [ChsOnlineWindow] = []
        for window in windows {
            try Task.checkCancellation()
            if let merged = try? ChsModelStore.saveOnline(window, retainingFrom: windows[0].start) {
                saved.append(merged)
                await MainActor.run { shared.bumpOnlineFetchStamp() }
            } else {
                saved.append(window)
            }
        }
        try Task.checkCancellation()
        let desired = anchor ?? todayLocal(gate.tz)
        let blocks = (ChsModelStore.loadOnline(gate.id)?.blocks ?? []) + saved
        do {
            return try Self.onlineCoveredWindow(blocks, anchor: desired, name: gate.name)
        } catch {
            IwlsFetcher.chunkCache.purge(station.id)
            throw error
        }
    }
}

extension ChsModelStore {
    /// The prune cut is bounded backward retention (#67 item 6): blocks age out
    /// at the first save after they fall behind today − onlineRetentionDays. The
    /// min(_, window.start) guard is what keeps the cut from discarding data the
    /// incoming fetch itself covers, or a picked old week would be deleted by
    /// its own save and refetch forever.
    ///
    // ponytail: no forward cap. A 30-day block is ~2880 samples (~90KB JSON);
    // someone who pages a year out accumulates ~1MB on a gate they evidently
    // care about, and -chsResetModels already clears it. Add a cap when a real
    // file gets big.
    @discardableResult
    static func saveOnline(_ window: ChsOnlineWindow, retainingFrom: Date? = nil) throws -> ChsOnlineWindow {
        let tz = TimeZone(identifier: window.timezone) ?? .current
        let cut = min(todayLocal(tz).addingTimeInterval(-Timeline.onlineRetentionDays * 86_400),
                      retainingFrom ?? window.start)
        let store = (loadOnline(window.stationID)
                     ?? ChsOnlineStore(stationID: window.stationID, blocks: []))
            .inserting(window, prunedBefore: cut)
        try Task.checkCancellation()
        let url = onlineUrl(window.stationID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(store).write(to: url, options: .atomic)
        WidgetReload.trigger()
        return store.block(spanning: window) ?? window
    }
}

extension ChsOnlineWindow {
    /// Does the stored window cover the FULL strip `Timeline` would build for
    /// `anchor`? The window is computed by `Timeline.window`, never re-derived
    /// here — a second derivation drifts, and the failure mode is this
    /// returning true for a window with a hole in it, which renders as a
    /// strip with a dead zone.
    func covers(anchor: Date) -> Bool {
        let need = Timeline.window(anchor: anchor)
        return start <= need.start && end >= need.end
    }

    /// The list/search card's reading: nearest official sample to `now` (a card
    /// tolerates half a sample interval of slop; `OnlineGateDetailView`'s scrub is where
    /// interpolating the drawn curve earns its keep), and the next event from
    /// the same fetched series `sampleEvents` scans — the same shape
    /// `CurrentStationRecord.cardState(at:)` returns for a fitted gate, so the
    /// card rendering doesn't need to know which kind of gate it's reading.
    func cardState(at now: Date) -> CurrentCardState {
        let point = points.min { abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now)) }
            ?? CurrentPoint(time: now, speed: 0)
        let next = sampleEvents(points).lazy.filter { $0.time > now }.first { event in
            !currentEventsMatchingWater(self, events: [event]).isEmpty
        }
        return CurrentCardState(point: point, flood: floodDirection, ebb: ebbDirection, next: next)
    }
}

extension ChsOnlineStore {
    /// The one block covering `anchor`'s whole strip, or nil — never a stitch
    /// across a gap.
    func block(covering anchor: Date) -> ChsOnlineWindow? {
        blocks.first { $0.covers(anchor: anchor) }
    }

    /// A coverage question, like `covers`: the block covering `today` should
    /// reach a full fetch ahead, so the stored month never runs down while the
    /// app has signal. Half a day of slack absorbs a fetch clamped to its last
    /// sample; yesterday's fetch falls a whole day short. Low Data Mode
    /// fetches only a station missing today.
    func needsRefresh(today: Date, lowData: Bool = false) -> Bool {
        guard let block = block(covering: today) else { return true }
        let reach = today.addingTimeInterval((Timeline.onlineFetchDays - 0.5) * 86_400)
        return !lowData && block.end < reach
    }

    /// The block whose reach the person cares about: the one covering today,
    /// else the latest that began by today, which reads as expired. A later
    /// block would name a date past a gap, so with only those it is nil and
    /// reads as not downloaded.
    func reachBlock(today: Date) -> ChsOnlineWindow? {
        block(covering: today) ?? blocks.last { $0.start <= today }
    }
}
