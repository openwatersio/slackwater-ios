// Slackwater — GPL v3. First-run connected fetch → fit → stored model for the
// Canadian Salish tide ports (milestones spec M3). No region UX — Salish
// auto-fits in the background; each station lands as its fit completes.
//
// The M0 spike's carry-forwards, honoured here:
//   - JSContext.exceptionHandler is set (JS errors are silent without it)
//   - no fetch inside JSCore — IWLS via URLSession, JSON strings + epoch-ms bridge
//   - BASIS + SA/SSA constituent list (in chs-glue.js)
//   - wlp is 1-min native → decimated to 15-min before bridging; 7-day request
//     cap; queries by resolved Mongo id, never station code
import Foundation
import JavaScriptCore

/// Where a CHS station stands. Stored models load synchronously at init, so a
/// previously fitted station is `.fitted` before the first frame — offline.
enum ChsState {
    case pending      // queued: no model yet, waiting its turn
    case fitting
    case failed       // this run tried and could not finish it
    case fitted(TideStationRecord)
}

/// Same four states for a validated current gate — the fitted payload is a
/// CurrentStationRecord, so the gate rides the NOAA current view path.
enum ChsCurrentState {
    case pending
    case fitting
    case failed
    case fitted(CurrentStationRecord)
}

@MainActor
final class ChsFitService: ObservableObject {
    static let shared = ChsFitService()

    /// The download queue — ordering, status and progress for every CHS
    /// station (ChsQueue, the port of the web's offlineSync store). The fitted
    /// records live beside it; the queue owns status, so there is exactly one
    /// place a station's state can disagree with itself: none.
    @Published private(set) var queue = ChsQueue()

    private var tideRecords: [String: TideStationRecord] = [:]
    /// Published: a gate's record is REPLACED in place when the provisional fit
    /// refines to the final one, and any open detail has to follow it.
    @Published private(set) var currentRecords: [String: CurrentStationRecord] = [:]
    /// Gates whose current record is the 60-day fast answer, not the full
    /// model. Published for the same reason.
    @Published private(set) var provisional: Set<String> = []
    /// Bumped whenever an online gate's fetched window is saved
    /// (`fetchOnlineWindow`, below). An online gate has no `currentRecords`
    /// entry to publish — its data lives on disk (`ChsModelStore.loadOnline`)
    /// — so this is the fit-landing signal's stand-in: a card holding a
    /// stale disk read (opened before the fetch, still on screen after)
    /// reloads off this the same way a fitted card re-renders off
    /// `currentRecords` changing.
    @Published private(set) var onlineFetchStamp = 0

    /// True once launched with `-networkKillSwitch` (UI tests' honest
    /// airplane-mode stand-in: every IWLS request throws before the socket).
    let networkDisabled = CommandLine.arguments.contains("-networkKillSwitch")

    /// UI-test hook: `-chsFitOnly <id,id>` scopes the fit run to those station
    /// ids — a REAL live fit, bounded to one gate's fetch time.
    private static let fitOnly: Set<String>? = {
        guard let at = CommandLine.arguments.firstIndex(of: "-chsFitOnly"),
              CommandLine.arguments.indices.contains(at + 1) else { return nil }
        return Set(CommandLine.arguments[at + 1].split(separator: ",").map(String.init))
    }()

    /// UI-test hook: `-chsFailOnly <id,id>` marks jobs `.failed` at launch, no
    /// network attempt — a `.failed` row (and its Retry button) otherwise only
    /// happens after a real fetch fails, which isn't deterministic for a fast
    /// test. `run()`'s claim loop only ever touches `.pending` jobs, so this
    /// status sticks until something explicitly retries it.
    private static let failOnly: Set<String> = {
        guard let at = CommandLine.arguments.firstIndex(of: "-chsFailOnly"),
              CommandLine.arguments.indices.contains(at + 1) else { return [] }
        return Set(CommandLine.arguments[at + 1].split(separator: ",").map(String.init))
    }()

    private var started = false
    private var running = false

    /// What downloads WITHOUT being asked for.
    ///
    /// Until M53 the answer was "every Canadian station" — true and affordable
    /// at 21 Salish stations, and neither at 1,097 nationally: bulk-downloading
    /// Canada is about 4.4 hours of politely paced IWLS requests, which is not
    /// a thing to do to somebody's first run or their cellular plan.
    ///
    /// The replacement is NOT "the nearest ten", which is the obvious answer
    /// and is wrong. Canadian tide gauges cluster: the ten nearest a Victoria
    /// fix are ten gauges inside 6 km of each other — Selkirk Water, three
    /// separate Gorge gauges, Portage Inlet — and not one current gate. It
    /// would have downloaded the harbour six times and none of the passes,
    /// which are the reason the app exists.
    ///
    /// So the two series are budgeted separately, and the numbers are measured
    /// against the fetcher's 2.5 s pacing:
    ///   - 6 tide ports, ~25 s each => ~2.5 min, anywhere in the country.
    ///   - 3 current gates, 52 s (60-day) to 158 s (210-day) => ~4-6 min in
    ///     the Salish, and a 210-day gate publishes its usable fast answer
    ///     partway through rather than at the end.
    /// ~8.5 min of background download in the worst case, 2.5 min away from
    /// the gates. The nearest tide port is still usable at ~30 s — the number
    /// that matters most, and it does not move.
    ///
    /// The radius is what keeps a Halifax first run honest: the nearest CHS
    /// current gate is 4,430 km away, and downloading Salish passes for a Nova
    /// Scotian is pure waste. 150 km is about a long day's passage at 6 knots.
    ///
    /// Everything else stays visible, searchable and one tap from downloading:
    /// opening a station adds it to this set and jumps it to the front.
    /// ponytail: constants, not settings. Make them settings when somebody
    /// asks — a region picker is the thing nobody has asked for.
    static let autoFitPorts = 6
    static let autoFitGates = 3
    static let autoFitGateRadiusKm = 150.0

    /// Every CHS station the app could fit, ports and validated gates. The 7
    /// online (fit-reject) gates are excluded here, at the source every job —
    /// auto-fit and opened-by-hand alike — is drawn from (`autoFitSet` below,
    /// and `promote`'s add-if-missing): they never get an on-device model, so
    /// there is no fit for them to wait in line for (online-gates spec §1,
    /// `ChsCurrentGateInfo.isOnline`'s "never queued").
    private static let candidates: [ChsJob] = {
        var jobs = ChsStationInfo.all.map {
            ChsJob(id: $0.id, name: $0.name, region: $0.region, isCurrent: false,
                   latitude: $0.latitude, longitude: $0.longitude, fitDays: tideFitDays)
        }
        jobs += ChsCurrentGateInfo.all.filter { !$0.isOnline }.map {
            ChsJob(id: $0.id, name: $0.name, region: $0.region, isCurrent: true,
                   latitude: $0.latitude, longitude: $0.longitude, fitDays: $0.fitDays)
        }
        return jobs.filter { fitOnly?.contains($0.id) ?? true }
    }()

    /// The stations a fix downloads on its own: the nearest ports, and the
    /// nearest gates that are actually near.
    static func autoFitSet(lat: Double, lon: Double) -> [ChsJob] {
        func nearest(_ jobs: [ChsJob], _ count: Int) -> [ChsJob] {
            jobs.sorted {
                let a = distanceKm($0.latitude, $0.longitude, lat, lon)
                let b = distanceKm($1.latitude, $1.longitude, lat, lon)
                return a == b ? $0.id < $1.id : a < b
            }.prefix(count).map { $0 }
        }
        let ports = candidates.filter { !$0.isCurrent }
        let gates = candidates.filter {
            $0.isCurrent && distanceKm($0.latitude, $0.longitude, lat, lon) <= autoFitGateRadiusKm
        }
        return nearest(ports, autoFitPorts) + nearest(gates, autoFitGates)
    }

    private init() {
        ChsModelStore.resetIfRequested()
        // One directory read, not 1,097 stat calls: which stations already
        // have a model on disk decides both what renders fitted and what stays
        // in the download set after the auto-fit rule stops choosing it.
        let files = Set((try? FileManager.default.contentsOfDirectory(atPath: ChsModelStore.dir.path)) ?? [])
        var jobs: [ChsJob] = []
        for var job in Self.candidates {
            let stored = files.contains(job.isCurrent ? "\(job.id)-current.json" : "\(job.id).json")
            if stored, !job.isCurrent, let model = ChsModelStore.load(job.id),
               let info = ChsStationInfo.all.first(where: { $0.id == job.id }) {
                tideRecords[job.id] = info.record(with: model)
                job.status = .ready
            } else if stored, job.isCurrent, let model = ChsModelStore.loadCurrent(job.id),
                      let gate = ChsCurrentGateInfo.all.first(where: { $0.id == job.id }) {
                currentRecords[job.id] = gate.record(with: model)
                // A provisional model is usable but NOT done: the job stays
                // queued so the next connected run refines it, and its cached
                // chunks mean that costs only the chunks it never fetched.
                if gate.isProvisional(model) { provisional.insert(job.id) } else { job.status = .ready }
            } else if !stored {
                continue  // not downloaded, and the auto-fit set decides below
            }
            jobs.append(job)
        }
        queue = ChsQueue(jobs)
        // Never an arbitrary order, even before a fix lands: the prototype's
        // Victoria fallback anchors the first sort, and a real fix re-sorts.
        adopt(lat: fallbackFix.lat, lon: fallbackFix.lon)
        // After adopt(), so a `-chsFailOnly` id not already in the auto-fit
        // set (added by adopt() above) still gets marked.
        for id in Self.failOnly { queue.set(id, .failed) }
    }

    /// Take the nearest stations into the download set and re-sort. Jobs only
    /// ACCRETE: a fix moving from Victoria to Halifax adds Halifax's nearest
    /// ports, and never drops what Victoria already paid for.
    private func adopt(lat: Double, lon: Double) {
        for job in Self.autoFitSet(lat: lat, lon: lon) { queue.add(job) }
        queue.prioritize(lat: lat, lon: lon)
    }

    func state(_ id: String) -> ChsState {
        if let record = tideRecords[id] { return .fitted(record) }
        switch queue.status(id) ?? .pending {
        case .downloading: return .fitting
        case .failed: return .failed
        case .pending, .ready: return .pending
        }
    }

    func currentState(_ id: String) -> ChsCurrentState {
        if let record = currentRecords[id] { return .fitted(record) }
        switch queue.status(id) ?? .pending {
        case .downloading: return .fitting
        case .failed: return .failed
        case .pending, .ready: return .pending
        }
    }

    /// Is this gate's showing record the 60-day fast answer? Every provisional
    /// treatment in the UI hangs off this one question.
    func isProvisional(_ id: String) -> Bool { provisional.contains(id) }

    /// Is this station in the download set at all? Outside it, "pending" means
    /// "open it and it downloads", not "wait your turn" (M53) — a different
    /// sentence, and the only honest one for the other 1,000-odd stations.
    func isQueued(_ id: String) -> Bool { queue.job(id) != nil }

    /// How many Canadian stations exist but are not downloading — the number
    /// the manager needs to say what "all done" actually means.
    var notQueued: Int { Self.candidates.count - queue.total }

    /// Start the download run: nearest-first, one station at a time. Partial
    /// failure is fine — whatever fit is stored; the rest are retryable from
    /// the manager and retry on the next connected launch.
    func startIfNeeded() {
        guard !started else { return }
        started = true
        pump()
    }

    /// A fix landed (or moved): take the nearest stations there into the
    /// download set, and re-order what is still queued closest-first.
    func prioritize(lat: Double, lon: Double) {
        adopt(lat: lat, lon: lon)
        pump()
    }

    /// The station the user just opened jumps the queue — ahead of proximity
    /// order — and retries if it had failed. Since M53 it also JOINS the queue
    /// if it wasn't in it: outside the auto-fit set, opening a station is how
    /// it gets downloaded, and a tap must never be a dead tap.
    /// Kicks the loop in case it had run dry (every job done or failed).
    func promote(_ id: String) {
        if queue.job(id) == nil, let job = Self.candidates.first(where: { $0.id == id }) {
            queue.add(job)
        }
        queue.promote(id)
        pump()
    }

    /// The manager's retry-all: re-queue the failures and run again.
    func retryFailed() {
        queue.retryFailed()
        pump()
    }

    private func pump() {
        guard !running, !networkDisabled, queue.nextPending != nil else { return }
        running = true
        Task.detached(priority: .utility) { [self] in await run() }
    }

    /// Claim the head of the queue. Sync find-then-mark on the main actor, so
    /// the loop can never hand the same job out twice (web offlineSync.worker).
    private func claimNext() -> ChsJob? {
        guard let job = queue.nextPending else { return nil }
        queue.set(job.id, .downloading)
        return job
    }

    /// The fast answer landed: publish it, keep the job queued (it is not done).
    private func publishProvisional(_ gate: ChsCurrentGateInfo, _ model: ChsCurrentModel) {
        try? ChsModelStore.saveCurrent(model)
        currentRecords[gate.id] = gate.record(with: model)
        provisional.insert(gate.id)
    }

    private nonisolated func run() async {
        let fetcher = IwlsFetcher()
        let fitter = ChsFitter()
        guard let list = try? await fetcher.stationList() else {
            // No station list, no fit is possible this run. Fail the queued
            // jobs rather than leaving them on "Waiting" forever — the manager
            // can then say so, and offer the retry.
            await MainActor.run {
                for job in self.queue.jobs where job.status == .pending {
                    self.queue.set(job.id, .failed)
                }
                self.running = false
            }
            return
        }
        while let job = await MainActor.run(body: { self.claimNext() }) {
            do {
                if job.isCurrent {
                    guard let gate = ChsCurrentGateInfo.all.first(where: { $0.id == job.id })
                    else { throw ChsError.noStations }
                    let model = try await fitCurrent(gate, list: list, fetcher: fetcher, fitter: fitter)
                    try ChsModelStore.saveCurrent(model)
                    await MainActor.run {
                        self.currentRecords[gate.id] = gate.record(with: model)
                        self.provisional.remove(gate.id)
                        self.queue.set(job.id, .ready)
                    }
                    ChsChunkStore.purge(model.iwlsID)
                } else {
                    guard let info = ChsStationInfo.all.first(where: { $0.id == job.id })
                    else { throw ChsError.noStations }
                    let model = try await fit(info, list: list, fetcher: fetcher, fitter: fitter)
                    try ChsModelStore.save(model)
                    await MainActor.run {
                        self.tideRecords[info.id] = info.record(with: model)
                        self.queue.set(job.id, .ready)
                    }
                    ChsChunkStore.purge(model.iwlsID)
                }
            } catch ChsError.yielded {
                // Stepped aside for a station the user opened. Everything
                // fetched is on disk, so resuming costs only what is missing.
                await MainActor.run { self.queue.set(job.id, .pending) }
            } catch {
                // ponytail: no retry ladder — the manager's retry and the next
                // connected launch are the retries.
                await MainActor.run { self.queue.set(job.id, .failed) }
            }
        }
        await MainActor.run { self.running = false }
    }

    /// 60 d @ 15 min ending yesterday — the window the M0 spike validated, and
    /// unchanged by M51: the per-gate window work is currents-only.
    nonisolated static let tideFitDays = 60.0

    private nonisolated func fit(_ info: ChsStationInfo, list: [IwlsStation],
                                 fetcher: IwlsFetcher, fitter: ChsFitter) async throws -> ChsFittedModel {
        let station = try Self.resolve(info, in: list)
        let end = Calendar(identifier: .gregorian).startOfDay(for: .now)
        let plan = Self.chunkPlan(days: Self.tideFitDays, end: end)
        var samples: [ChsSample] = []
        for chunk in plan {
            samples += try await fetcher.wlp(stationID: station.id, chunk: chunk)
            if await MainActor.run(body: { self.queue.shouldYield(running: info.id) }) { throw ChsError.yielded }
        }
        samples.sort { $0.t < $1.t }
        let start = plan.last?.start ?? end
        let fit = try await fitter.fit(samples: samples)
        print("CHS fit \(info.id): \(samples.count) samples, \(Int(fit.fitMs)) ms (interpreted, no JIT), rms \(String(format: "%.1f", fit.rms * 100)) cm")
        return ChsFittedModel(
            stationID: info.id, iwlsID: station.id, iwlsName: station.officialName,
            fittedAt: .now, fitStartMs: start.timeIntervalSince1970 * 1000,
            fitEndMs: end.timeIntervalSince1970 * 1000,
            offset: fit.offset, rms: fit.rms,
            constituents: fit.constituents.map { .init(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) })
    }

    /// wcsp1+wcdp1 over the gate's OWN validated window, projected onto the CHS
    /// flood axis, fitted with the same JSCore path as the tides. Most gates
    /// need 210 d — Rayleigh separation of K1/P1, which drive PNW diurnal
    /// inequality, needs ≥183 d — but four meet the full bar at 60 d and are
    /// final on their first fit (spikes/chs-currents-fit/README.md).
    ///
    /// Chunks are fetched NEWEST FIRST, so the trailing 60 days land first and
    /// a 210-day gate can publish its fast answer at ~45 s and keep going. The
    /// 60-day chunks are the same chunks the 210-day fetch needs: no request is
    /// made twice, and nothing is thrown away.
    private nonisolated func fitCurrent(_ gate: ChsCurrentGateInfo, list: [IwlsStation],
                                        fetcher: IwlsFetcher, fitter: ChsFitter) async throws -> ChsCurrentModel {
        let station = try Self.resolve(name: gate.name, latitude: gate.latitude, longitude: gate.longitude,
                                       series: "wcsp1", in: list)
        let meta = try await fetcher.metadata(stationID: station.id)
        guard let flood = meta.floodDirection, let ebb = meta.ebbDirection else {
            throw ChsError.noFloodAxis(gate.name)
        }
        let end = Calendar(identifier: .gregorian).startOfDay(for: .now)
        let plan = Self.chunkPlan(days: gate.fitDays, end: end)
        let provisionalCut = end.addingTimeInterval(-ChsCurrentGateInfo.provisionalDays * 86_400)
        var speeds: [ChsSample] = [], dirs: [ChsSample] = []
        var fastAnswerDone = !gate.offersProvisional

        for chunk in plan {
            speeds += try await fetcher.series("wcsp1", stationID: station.id, chunk: chunk)
            if await MainActor.run(body: { self.queue.shouldYield(running: gate.id) }) { throw ChsError.yielded }
            dirs += try await fetcher.series("wcdp1", stationID: station.id, chunk: chunk)
            if await MainActor.run(body: { self.queue.shouldYield(running: gate.id) }) { throw ChsError.yielded }
            // The trailing 60 days are in: publish the fast answer and carry on.
            guard !fastAnswerDone, chunk.start <= provisionalCut else { continue }
            fastAnswerDone = true
            let model = try await Self.model(gate: gate, station: station, flood: flood, ebb: ebb,
                                             start: chunk.start, end: end,
                                             fitDays: ChsCurrentGateInfo.provisionalDays,
                                             speeds: speeds, dirs: dirs, fitter: fitter)
            await MainActor.run { self.publishProvisional(gate, model) }
        }
        return try await Self.model(gate: gate, station: station, flood: flood, ebb: ebb,
                                    start: plan.last?.start ?? end, end: end, fitDays: gate.fitDays,
                                    speeds: speeds, dirs: dirs, fitter: fitter)
    }

    /// Project + fit + wrap. Refitting the widened sample set is 19–106 ms —
    /// cheap enough that the provisional stage costs nothing but the fit.
    private nonisolated static func model(gate: ChsCurrentGateInfo, station: IwlsStation,
                                          flood: Double, ebb: Double, start: Date, end: Date,
                                          fitDays: Double, speeds: [ChsSample], dirs: [ChsSample],
                                          fitter: ChsFitter) async throws -> ChsCurrentModel {
        let samples = project(speeds: speeds.sorted { $0.t < $1.t }, dirs: dirs, floodDirection: flood)
        let fit = try await fitter.fit(samples: samples)
        print("CHS current fit \(gate.id) @ \(Int(fitDays)) d: \(samples.count) samples, \(Int(fit.fitMs)) ms, rms \(String(format: "%.2f", fit.rms)) kn")
        return ChsCurrentModel(
            stationID: gate.id, iwlsID: station.id, iwlsName: station.officialName,
            fittedAt: .now, fitStartMs: start.timeIntervalSince1970 * 1000,
            fitEndMs: end.timeIntervalSince1970 * 1000, fitDays: fitDays,
            floodDirection: flood, ebbDirection: ebb,
            offset: fit.offset, rms: fit.rms,
            constituents: fit.constituents.map { .init(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) })
    }

    /// 7-day chunks covering at least `days` back from `end`, NEWEST FIRST.
    ///
    /// Boundaries sit on an absolute 7-day epoch grid, not on `end` — so a
    /// chunk's identity (and its cache file) is the same tomorrow as today, and
    /// the 60-day plan is exactly the newest chunks of the 210-day plan. The
    /// price is up to 7 days more data than asked for, which a harmonic fit can
    /// only like. Only the newest chunk is short (grid boundary → `end`), and
    /// it is the one chunk that is never cached.
    nonisolated static func chunkPlan(days: Double, end: Date) -> [ChsChunk] {
        let week = 7 * 86_400.0
        let endS = end.timeIntervalSince1970
        var out: [ChsChunk] = []
        var t = (((endS - days * 86_400) / week).rounded(.down)) * week
        while t < endS {
            out.append(ChsChunk(start: Date(timeIntervalSince1970: t),
                                end: Date(timeIntervalSince1970: min(t + week, endS))))
            t += week
        }
        return out.reversed()
    }

    /// Signed along-channel velocity: speed · cos(direction − floodDirection).
    /// The chs-constituents pipeline's own projection — linear, so equivalent
    /// to a full 2D fit projected onto the same axis. Samples without a
    /// matching direction stamp are dropped.
    nonisolated static func project(speeds: [ChsSample], dirs: [ChsSample],
                                    floodDirection: Double) -> [ChsSample] {
        let dirAt = Dictionary(dirs.map { ($0.t, $0.v) }, uniquingKeysWith: { a, _ in a })
        let d2r = Double.pi / 180
        return speeds.compactMap { s in
            guard let dir = dirAt[s.t] else { return nil }
            return ChsSample(t: s.t, v: s.v * cos((dir - floodDirection) * d2r))
        }
    }

    /// Position is the match key, never name (web chs/resolve.ts): nearest
    /// station serving the series within tolerance, else throw — a silent
    /// mis-bind would put the wrong water under a trusted name.
    nonisolated static let resolveToleranceKm = 3.0

    nonisolated static func resolve(_ info: ChsStationInfo, in list: [IwlsStation]) throws -> IwlsStation {
        try resolve(name: info.name, latitude: info.latitude, longitude: info.longitude,
                    series: "wlp", in: list)
    }

    nonisolated static func resolve(name: String, latitude: Double, longitude: Double,
                                    series: String, in list: [IwlsStation]) throws -> IwlsStation {
        let candidates = list.filter { st in st.timeSeries.contains { $0.code == series } }
        guard let best = candidates.min(by: {
            distanceKm(latitude, longitude, $0.latitude, $0.longitude) <
            distanceKm(latitude, longitude, $1.latitude, $1.longitude)
        }) else { throw ChsError.noStations }
        let km = distanceKm(latitude, longitude, best.latitude, best.longitude)
        guard km <= resolveToleranceKm else { throw ChsError.noStationWithinTolerance(name, best.officialName, km) }
        return best
    }
}

// MARK: - Online gates: fetched, never fitted

extension ChsFitService {
    /// The span one fetch covers: `Timeline.window`'s start for the anchor —
    /// back-padded only when the anchor IS today, never re-derived here — and
    /// `Timeline.onlineFetchDays` forward of it, four strips' worth, so ordinary
    /// paging lands in cache instead of on the network.
    ///
    /// Split out of `fetchOnlineWindow` only so it can be tested: everything
    /// around it in that function needs IWLS, which would leave the anchored
    /// branch — the one a date picker will use — shipping unexercised.
    nonisolated static func onlineFetchSpan(anchor: Date?, today: Date) -> (start: Date, end: Date) {
        let from = anchor ?? today
        return (Timeline.window(anchor: from, today: today).start,
                from.addingTimeInterval(Timeline.onlineFetchDays * 86_400))
    }

    /// The 7 fit-reject gates (online-gates spec §1) get no on-device fit —
    /// only official wcsp1/wcdp1 predictions, `Timeline.onlineFetchDays` forward
    /// of `anchor` (today unless a caller says otherwise) and back-padded like
    /// the strip, resolved/projected exactly like `fitCurrent` (:345-363) but served as
    /// fetched samples rather than harmonic constituents. No queue, no yield
    /// point: these gates never join the fit queue, so there is nothing to
    /// step aside for — a throw here is the whole story, and Task 5's caller
    /// shows the honesty card on it.
    ///
    /// Persists the window itself (never just returns it for the caller to
    /// save) and bumps `onlineFetchStamp` on a successful save — one seam,
    /// so every caller, today's and any future one, gets the same
    /// "the fetch landed" signal without re-deriving it.
    nonisolated static func fetchOnlineWindow(for gate: ChsCurrentGateInfo,
                                             from anchor: Date? = nil) async throws -> ChsOnlineWindow {
        let fetcher = IwlsFetcher()
        let list = try await fetcher.stationList()
        let station = try Self.resolve(name: gate.name, latitude: gate.latitude, longitude: gate.longitude,
                                       series: "wcsp1", in: list)
        let meta = try await fetcher.metadata(stationID: station.id)
        guard let flood = meta.floodDirection, let ebb = meta.ebbDirection else {
            throw ChsError.noFloodAxis(gate.name)
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
        guard !projected.isEmpty else { throw ChsError.emptySeries(gate.name) }
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
            try ChsModelStore.saveOnline(window)
            await MainActor.run { shared.onlineFetchStamp += 1 }
        } catch {
            // ponytail: a local disk-write failure on an already-fetched
            // window isn't worth failing the whole fetch over — the caller
            // still gets `window` to render; only the reload-elsewhere signal
            // (the stamp) and next launch's offline copy are what's lost.
        }
        return window
    }
}

enum ChsError: Error {
    case networkDisabled
    /// Stepped aside at a chunk boundary for a station the user opened. Not a
    /// failure: the job goes back to `.pending` with its chunks on disk.
    case yielded
    case noStations
    case noStationWithinTolerance(String, String, Double)
    case noFloodAxis(String)
    /// IWLS 200'd with zero samples for the requested window.
    case emptySeries(String)
    case badResponse(Int)
    case jsError(String)
}

// MARK: - IWLS client (Swift/URLSession — never JSCore)

struct IwlsStation: Decodable {
    struct Series: Decodable { let code: String }
    let id: String
    let officialName: String
    let latitude: Double
    let longitude: Double
    let timeSeries: [Series]
}

struct IwlsSample: Decodable { let eventDate: String; let value: Double }

/// A decimated sample as bridged to JS: epoch-ms + metres.
struct ChsSample: Codable, Equatable { let t: Double; let v: Double }

/// One request's worth of series: a 7-day slot on the absolute epoch grid.
struct ChsChunk: Equatable { let start: Date; let end: Date }

/// Fetched chunks, on disk, keyed by what identifies them and nothing else —
/// so a job that stepped aside mid-download resumes where it stopped instead of
/// paying for the same bytes twice. Purged per station once its final fit lands
/// (the harmonic model is the artifact; the samples were only scaffolding).
enum ChsChunkStore {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ChsChunks", isDirectory: true)
    }()

    static func url(_ stationID: String, _ code: String, _ chunk: ChsChunk) -> URL {
        dir.appendingPathComponent("\(stationID)-\(code)-\(Int(chunk.start.timeIntervalSince1970)).json")
    }

    static func load(_ stationID: String, _ code: String, _ chunk: ChsChunk) -> [ChsSample]? {
        guard let data = try? Data(contentsOf: url(stationID, code, chunk)) else { return nil }
        return try? JSONDecoder().decode([ChsSample].self, from: data)
    }

    static func save(_ samples: [ChsSample], _ stationID: String, _ code: String, _ chunk: ChsChunk) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(samples).write(to: url(stationID, code, chunk), options: .atomic)
    }

    static func purge(_ stationID: String) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where f.hasPrefix(stationID + "-") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }
}

/// Polite serial IWLS client: one request at a time, 2.5 s apart (~24/min,
/// safely under the documented 3/s and 30/min caps), 7-day chunks.
final class IwlsFetcher {
    static let base = "https://api-iwls.dfo-mpo.gc.ca/api/v1"
    private let killSwitch: Bool
    private var lastRequest = Date.distantPast

    init(killSwitch: Bool = CommandLine.arguments.contains("-networkKillSwitch")) {
        self.killSwitch = killSwitch
    }

    private func get(_ path: String) async throws -> Data {
        guard !killSwitch else { throw ChsError.networkDisabled }
        let wait = 2.5 - Date.now.timeIntervalSince(lastRequest)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        lastRequest = .now
        let (data, response) = try await URLSession.shared.data(from: URL(string: Self.base + path)!)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ChsError.badResponse(code) }
        return data
    }

    func stationList() async throws -> [IwlsStation] {
        try JSONDecoder().decode([IwlsStation].self, from: try await get("/stations"))
    }

    struct Metadata: Decodable { let floodDirection: Double?; let ebbDirection: Double? }

    /// Per-station metadata — the only place IWLS serves the flood/ebb axis
    /// (the /stations list entries carry none).
    func metadata(stationID: String) async throws -> Metadata {
        try JSONDecoder().decode(Metadata.self, from: try await get("/stations/\(stationID)/metadata"))
    }

    /// A natively 15-minute series (wcsp1/wcdp1) for one chunk. Cached on disk,
    /// so this costs a request exactly once — including across a job that
    /// stepped aside and came back, and across days (the grid is absolute).
    func series(_ code: String, stationID: String, chunk: ChsChunk) async throws -> [ChsSample] {
        try await cached(code, stationID: stationID, chunk: chunk) { $0 }
    }

    /// wlp for one chunk, decimated from its 1-min native rate to the 15-min
    /// grid the fit wants (M0 spike carry-forward).
    func wlp(stationID: String, chunk: ChsChunk) async throws -> [ChsSample] {
        try await cached("wlp", stationID: stationID, chunk: chunk) {
            $0.filter { $0.t.truncatingRemainder(dividingBy: 900_000) == 0 }
        }
    }

    private func cached(_ code: String, stationID: String, chunk: ChsChunk,
                        _ transform: ([ChsSample]) -> [ChsSample]) async throws -> [ChsSample] {
        if let hit = ChsChunkStore.load(stationID, code, chunk) { return hit }
        let iso = ISO8601DateFormatter()
        let path = "/stations/\(stationID)/data?time-series-code=\(code)" +
            "&from=\(iso.string(from: chunk.start))&to=\(iso.string(from: chunk.end))"
        let raw = try JSONDecoder().decode([IwlsSample].self, from: try await get(path))
        var out: [ChsSample] = []
        for s in raw {
            guard let date = iso.date(from: s.eventDate) else { continue }
            let ms = date.timeIntervalSince1970 * 1000
            if out.last?.t != ms { out.append(ChsSample(t: ms, v: s.value)) }
        }
        let samples = transform(out)
        // Only whole grid chunks are cached: the newest one runs to "now" and
        // would be a different chunk tomorrow.
        if chunk.end.timeIntervalSince(chunk.start) >= 7 * 86_400 {
            ChsChunkStore.save(samples, stationID, code, chunk)
        }
        return samples
    }
}

// MARK: - JSCore fitter

struct ChsFitResult: Decodable {
    struct Con: Decodable { let name: String; let amplitude: Double; let phase: Double }
    let fitMs: Double
    let offset: Double
    let rms: Double
    let constituents: [Con]
    let unseparable: [String]
}

/// Runs chs-bundle.js + chs-glue.js in JavaScriptCore, off the main thread.
/// One context, reused across stations within a fit run.
final class ChsFitter {
    private var context: JSContext?
    private var jsError: String?

    private func makeContext() throws -> JSContext {
        if let context { return context }
        let ctx = JSContext()!
        ctx.exceptionHandler = { [weak self] _, exc in self?.jsError = exc?.toString() }
        // JSCore has no console; shim it so a stray log can't crash the fit.
        ctx.evaluateScript("var console = {log:function(){},warn:function(){},error:function(){},info:function(){},debug:function(){}};")
        for name in ["chs-bundle", "chs-glue"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js") else {
                throw ChsError.jsError("\(name).js missing from bundle")
            }
            ctx.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            if let e = jsError { throw ChsError.jsError("\(name).js: \(e)") }
        }
        context = ctx
        return ctx
    }

    func fit(samples: [ChsSample]) async throws -> ChsFitResult {
        let json = String(data: try JSONEncoder().encode(samples), encoding: .utf8)!
        let ctx = try makeContext()
        jsError = nil
        guard let out = ctx.objectForKeyedSubscript("fitTides")?.call(withArguments: [json]),
              jsError == nil, let str = out.toString() else {
            throw ChsError.jsError(jsError ?? "fitTides returned nothing")
        }
        return try JSONDecoder().decode(ChsFitResult.self, from: Data(str.utf8))
    }
}

// MARK: - Geo

func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let r = 6371.0, d = Double.pi / 180
    let dLat = (lat2 - lat1) * d, dLon = (lon2 - lon1) * d
    let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * d) * cos(lat2 * d) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * atan2(sqrt(a), sqrt(1 - a))
}
