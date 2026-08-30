// Slackwater — GPL v3. Online gates: fetched, never fitted. The one-per-gate
// window fetch, its on-disk store, and the readings a card and a strip take
// off a fetched window.
import Foundation

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
    nonisolated static func fetchOnlineWindow(for gate: ChsCurrentGateInfo,
                                             from anchor: Date?) async throws -> ChsOnlineWindow {
        try await MainActor.run { shared.onlineFetchTask(for: gate, from: anchor) }.value
    }

    /// The check-and-set, on the main actor so it is atomic: an existing handle
    /// is joined, otherwise one is registered before this returns. The task
    /// clears its own entry on the way out — success, failure or throw.
    @MainActor
    private func onlineFetchTask(for gate: ChsCurrentGateInfo,
                                 from anchor: Date?) -> Task<ChsOnlineWindow, Error> {
        if let existing = onlineFetch(for: gate.id) { return existing }
        let task = Task { @MainActor in
            defer { ChsFitService.shared.setOnlineFetch(nil, for: gate.id) }
            return try await ChsFitService.runOnlineFetch(for: gate, from: anchor)
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
            throw ChsError.failed("\(gate.name): IWLS metadata has no flood axis")
        }
        let (start, end) = Self.onlineFetchSpan(anchor: anchor, today: todayLocal(gate.tz))
        // Same absolute 7-day grid `chunkPlan` uses for the fit path — the
        // fetched span in days, ending at its own end, gives exactly the chunk
        // set covering start…end (up to 7 days of slop at the grid boundary,
        // same tradeoff the fit path already makes).
        let plan = Self.chunkPlan(days: end.timeIntervalSince(start) / 86_400, end: end)
        var speeds: [ChsSample] = [], dirs: [ChsSample] = []
        for chunk in plan {
            speeds += try await fetcher.series("wcsp1", stationID: station.id, chunk: chunk)
            dirs += try await fetcher.series("wcdp1", stationID: station.id, chunk: chunk)
        }
        let projected = Self.project(speeds: speeds.sorted { $0.t < $1.t }, dirs: dirs, floodDirection: flood)
        // IWLS can 200 with an empty series (a quiet chunk boundary, no error
        // to catch). Saving anyway would fall through to the requested
        // start/end below and stick forever — a zero-sample window that
        // still reads as "covers the strip". Fail the fetch instead: the
        // caller already turns any thrown error into the honesty card + retry.
        guard !projected.isEmpty else { throw ChsError.failed("\(gate.name): IWLS returned an empty series") }
        // A chunk IWLS truncates mid-series (a short response, a gap at one
        // edge) must not be saved under the full requested start/end — that
        // would make `covers` pass on a window with a hole in it and
        // render a strip with a dead zone. Clamp to what actually came back,
        // symmetrically, so a truncated fetch honestly fails coverage instead.
        let sampleStart = projected.first.map { Date(timeIntervalSince1970: $0.t / 1000) } ?? start
        let sampleEnd = projected.last.map { Date(timeIntervalSince1970: $0.t / 1000) } ?? end
        let window = ChsOnlineWindow(
            stationID: gate.id, iwlsName: station.officialName, timezone: gate.timezone,
            fetchedAt: .now, start: max(start, sampleStart), end: min(end, sampleEnd),
            floodDirection: flood, ebbDirection: ebb,
            times: projected.map { $0.t / 1000 }, speeds: projected.map { $0.v })
        do {
            // The MERGED window goes back to the caller, not `window`: the
            // fetched block is only the part that was missing, and a caller
            // rendering it alone would have less on screen than it has on disk
            // (`saveOnline`'s doc comment).
            let merged = try ChsModelStore.saveOnline(window)
            await MainActor.run { shared.bumpOnlineFetchStamp() }
            return merged
        } catch {
            // ponytail: a local disk-write failure on an already-fetched
            // window isn't worth failing the whole fetch over — the caller
            // still gets `window` to render; only the reload-elsewhere signal
            // (the stamp) and next launch's offline copy are what's lost.
        }
        return window
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
    static func saveOnline(_ window: ChsOnlineWindow) throws -> ChsOnlineWindow {
        let tz = TimeZone(identifier: window.timezone) ?? .current
        let cut = min(todayLocal(tz).addingTimeInterval(-Timeline.onlineRetentionDays * 86_400),
                      window.start)
        let store = (loadOnline(window.stationID)
                     ?? ChsOnlineStore(stationID: window.stationID, blocks: []))
            .inserting(window, prunedBefore: cut)
        try save(store, id: window.stationID, suffix: "-online")
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

    /// The list/search card's reading: nearest 15-min sample to `now` (a card
    /// tolerates the ≤7.5 min slop; `OnlineGateDetailView`'s scrub is where
    /// interpolating the drawn curve earns its keep), and the next event from
    /// the same fetched series `sampleEvents` scans — the same shape
    /// `CurrentStationRecord.cardState(at:)` returns for a fitted gate, so the
    /// card rendering doesn't need to know which kind of gate it's reading.
    func cardState(at now: Date) -> CurrentCardState {
        let signed = points.min { abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now)) }?.speed ?? 0
        let next = sampleEvents(points).first { $0.time > now }
        return CurrentCardState(signed: signed, next: next)
    }
}

extension ChsOnlineStore {
    /// The one block covering `anchor`'s whole strip, or nil — never a stitch
    /// across a gap.
    func block(covering anchor: Date) -> ChsOnlineWindow? {
        blocks.first { $0.covers(anchor: anchor) }
    }
}

extension ChsCurrentGateInfo {
    /// Offline, "stay connected" is advice you can't act on — say what's true
    /// instead, without implying a wait in progress.
    func provisionalExpectation(online: Bool) -> String {
        online
            ? "Stay connected for \(durationPhrase(refineSeconds)) more and Slackwater refines it to the full \(Int(fitDays))-day model, in place — nothing to tap."
            : "The fast answer is already on this device; next time you're connected, Slackwater refines it to the full \(Int(fitDays))-day model — nothing to tap."
    }
}
