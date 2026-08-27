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
import CoreLocation
import Foundation
import JavaScriptCore

/// True when launched with `-networkKillSwitch` (UI tests' honest airplane-mode
/// stand-in: every IWLS request throws before the socket).
let networkKillSwitch = CommandLine.arguments.contains("-networkKillSwitch")

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

    /// Readable (the map's pin-tone resolve reads it beside `currentRecords`);
    /// written only by the fit run.
    private(set) var tideRecords: [String: TideStationRecord] = [:]
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

    /// The online fetch in flight for each gate, so a gate never has two.
    /// Keyed by gate id rather than one global handle: two gates' fetches are
    /// independent — different station, different file, different returned
    /// window — and a single handle would both serialise them and hand gate B's
    /// caller gate A's window. Read and written only on the main actor, which
    /// is what makes the check-and-set atomic. See `fetchOnlineWindow`.
    private var onlineFetches: [String: Task<ChsOnlineWindow, Error>] = [:]

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
    /// Online gates this launch has already tried to prefetch (`prefetchOnlineGates`).
    private var attempted: Set<String> = []
    private var onlinePending: [ChsCurrentGateInfo] = []
    private var onlinePreferred: [String] = []
    private var onlineOrigin: (lat: Double, lon: Double)?
    private var onlineRunning = false

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
    ///   - 6 tide ports, ~25 s each => ~2.5 min, anywhere in reach.
    ///   - 3 current gates, 52 s (60-day) to 158 s (210-day) => ~4-6 min in
    ///     the Salish, and a 210-day gate publishes its usable fast answer
    ///     partway through rather than at the end.
    /// ~8.5 min of background download in the worst case, 2.5 min away from
    /// the gates. The nearest tide port is still usable at ~30 s — the number
    /// that matters most, and it does not move.
    ///
    /// The radius guards BOTH series, and it is what keeps a first run honest
    /// away from Canadian water (#205). Gating only the gates would look
    /// sufficient from a Canadian fix — a Nova Scotian's nearest gate is
    /// 305 km off, so they fit no Salish passes either way — and is not
    /// sufficient anywhere else: unguarded ports adopt the nearest 6 from any
    /// fix on Earth, which from Massachusetts is three St. Lawrence river
    /// gauges at Montréal plus three Bay of Fundy stations across the Gulf of
    /// Maine, ~400 km off, in a list whose nearest entry is NOAA Boston
    /// Harbor at 1 km. 150 km is about a long day's passage at 6 knots.
    ///
    /// The radius cannot starve a real user: it only ever drops stations
    /// further away than every station that outranks them, so nothing it drops
    /// could have reached Near Me, and #178's "the first screen is covered by
    /// what the first run downloads" still holds. Ports inside the radius,
    /// measured against the shipped bundle: Nanaimo 129, Vancouver 106,
    /// Victoria 94, Charlottetown 74, Saint John 71, Halifax 61, Prince Rupert
    /// 51, Québec 42, St John's 38, Montréal 10, Iqaluit 5 — and Bellingham
    /// 84, Port Angeles 80, Seattle 28, so a Puget Sound sailor keeps Gulf
    /// Islands coverage. Boston, Portland ME, Toronto, Ottawa, Winnipeg,
    /// Calgary and Whitehorse get zero, which is the point.
    ///
    /// Everything else stays visible, searchable and one tap from downloading:
    /// opening a station adds it to this set and jumps it to the front.
    /// ponytail: constants, not settings. Make them settings when somebody
    /// asks — a region picker is the thing nobody has asked for.
    static let autoFitPorts = 6
    static let autoFitGates = 3
    static let autoFitRadiusKm = 150.0

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

    /// The online (fit-reject) gates a fix fetches on its own.
    ///
    /// These are the other half of "what downloads without being asked", and
    /// until #178 there was no such half: `candidates` excludes them at the
    /// source, so they can never be queued, `onlineGateStatus` renders
    /// `.notDownloaded` while no window is on disk, and the ONLY thing that
    /// ever fetched one was opening its detail. Tillicum Bridge is 3.4 km from
    /// downtown Victoria and Second Narrows is in Vancouver harbour — both land
    /// in Near Me on a first run and both said "Tap to download" forever.
    ///
    /// Same budget shape as the fitted gates deliberately: nearest first, at
    /// most `autoFitGates`, and only within `autoFitRadiusKm` so a Halifax
    /// first run fetches no Salish passes. Far cheaper than the fitted set —
    /// one `Timeline.onlineFetchDays` window each, not a 60-to-210-day fit.
    static func autoPrefetchGates(lat: Double, lon: Double) -> [ChsCurrentGateInfo] {
        ChsCurrentGateInfo.all
            .filter { $0.isOnline && distanceKm($0.latitude, $0.longitude, lat, lon) <= autoFitRadiusKm }
            .sorted {
                let a = distanceKm($0.latitude, $0.longitude, lat, lon)
                let b = distanceKm($1.latitude, $1.longitude, lat, lon)
                return a == b ? $0.id < $1.id : a < b
            }
            .prefix(autoFitGates).map { $0 }
    }

    /// The stations a fix downloads on its own: the nearest ports and the
    /// nearest gates, out of those inside `autoFitRadiusKm`.
    static func autoFitSet(lat: Double, lon: Double) -> [ChsJob] {
        func nearest(_ jobs: [ChsJob], _ count: Int) -> [ChsJob] {
            jobs.sorted {
                let a = distanceKm($0.latitude, $0.longitude, lat, lon)
                let b = distanceKm($1.latitude, $1.longitude, lat, lon)
                return a == b ? $0.id < $1.id : a < b
            }.prefix(count).map { $0 }
        }
        let near = candidates.filter {
            distanceKm($0.latitude, $0.longitude, lat, lon) <= autoFitRadiusKm
        }
        let ports = near.filter { !$0.isCurrent }
        let gates = near.filter { $0.isCurrent }
        return nearest(ports, autoFitPorts) + nearest(gates, autoFitGates)
    }

    /// The CHS artifacts behind favorite rows. NOAA rows are bundled; derived
    /// gates ride their reference port; online gates need a fetched window.
    static func favoriteDownloads(_ ids: [String])
        -> (jobIDs: [String], online: [ChsCurrentGateInfo]) {
        var jobIDs: [String] = []
        var online: [ChsCurrentGateInfo] = []
        for id in ids {
            guard let item = StationItem.byId[id] else { continue }
            switch item {
            case .tide, .current: continue
            case .chs(let port):
                if !jobIDs.contains(port.id) { jobIDs.append(port.id) }
            case .chsGate(let gate):
                if !jobIDs.contains(gate.reference) { jobIDs.append(gate.reference) }
            case .chsCurrent(let gate):
                if gate.isOnline {
                    if !online.contains(where: { $0.id == gate.id }) { online.append(gate) }
                } else if !jobIDs.contains(gate.id) {
                    jobIDs.append(gate.id)
                }
            }
        }
        return (jobIDs, online)
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
        //
        // Sorts ONLY (#205). `adopt` would also enqueue Victoria's auto-fit
        // set, and this runs on every device on Earth before any fix is known
        // — 6 Salish ports and 3 Salish gates, the gates being the 60-to-210
        // day fits, downloaded for someone who may be 4,000 km away. Jobs
        // accrete and nothing prunes them, so a real fix landing later cannot
        // take them back. `.task` in the list adopts the ranking anchor a
        // moment later, which is the call that is allowed to add work.
        queue.prioritize(lat: firstRunFix.lat, lon: firstRunFix.lon)
        markFailOnly()
        Self.sweepOrphans(files)
    }

    /// Which files under `ChsModels/` belong to no station the bundle still
    /// ships (issue #91). Pure and passed its sets so it can be tested without
    /// a filesystem — the destructive half is four lines in `sweepOrphans`.
    ///
    /// Keyed off the bundled catalogs rather than `candidates`, which
    /// `-chsFitOnly` shrinks: a UI-test flag must never decide that a real
    /// user's models are garbage.
    /// `nonisolated` so a test can call it off the main actor: it reads nothing
    /// but its arguments, all value types.
    nonisolated static func orphanFiles(in files: Set<String>,
                                        ports: Set<String>, gates: Set<String>) -> [String] {
        files.sorted().filter { file in
            guard file.hasSuffix(".json") else { return false }
            let stem = String(file.dropLast(5))
            // `-current` and `-online` are the only suffixes ChsModelStore
            // writes, and both belong to gates; anything else is a port id.
            if let suffix = ["-current", "-online"].first(where: { stem.hasSuffix($0) }) {
                return !gates.contains(String(stem.dropLast(suffix.count)))
            }
            return !ports.contains(stem)
        }
    }

    /// Delete fitted models for stations that have left the bundle. Nothing
    /// else ever would: the launch scan iterates bundled candidates, never the
    /// directory, so a removed station's downloaded model is neither loaded nor
    /// deleted — dead weight, and most likely present precisely because someone
    /// cared enough to favorite it.
    ///
    /// Runs off the listing `init` already has in hand, so it costs no I/O on
    /// the overwhelmingly common no-orphans launch.
    private static func sweepOrphans(_ files: Set<String>) {
        let ports = Set(ChsStationInfo.all.map(\.id))
        let gates = Set(ChsCurrentGateInfo.all.map(\.id))
        // `bundled()` swallows a decode failure into an empty array, and an
        // empty catalog would read as "every model on this device is an
        // orphan". Nothing is worth deleting on that evidence.
        guard !ports.isEmpty, !gates.isEmpty else { return }
        for file in orphanFiles(in: files, ports: ports, gates: gates) {
            // The chunk cache is keyed by IWLS id, which only the model
            // carries — read it before the file goes. Best effort: an
            // `-online.json` decodes as no model and keeps its chunks, and a
            // chunk cache is re-fetchable by definition.
            if let model: ChsModel = ChsModelStore.load(String(file.dropLast(5)), suffix: "") {
                ChsChunkStore.purge(model.iwlsID)
            }
            try? FileManager.default.removeItem(at: ChsModelStore.dir.appendingPathComponent(file))
        }
    }

    /// Take the nearest stations into the download set and re-sort. Jobs only
    /// ACCRETE: a fix moving from Victoria to Halifax adds Halifax's nearest
    /// ports, and never drops what Victoria already paid for.
    private func adopt(lat: Double, lon: Double) {
        for job in Self.autoFitSet(lat: lat, lon: lon) { queue.add(job) }
        queue.prioritize(lat: lat, lon: lon)
        markFailOnly()
    }

    /// Re-assert the `-chsFailOnly` hook over whatever is now in the queue.
    /// The hook means "these ids are failed for this whole launch", and a job
    /// it names may join the queue at any adopt — `queue.set` is a no-op on an
    /// id that is not there yet, so marking once at init would only cover the
    /// jobs already on disk. `chs-victoria-harbour`, the seeded id in
    /// `testDownloadsRowRetryButtonWinsOverRowTap`, arrives with the list's
    /// first adopt and would otherwise render `.pending` with no Retry button.
    private func markFailOnly() {
        for id in Self.failOnly { queue.set(id, .failed) }
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
    func prioritize(lat: Double, lon: Double, favorites: [String]? = nil,
                    visibleID: String? = nil) {
        adopt(lat: lat, lon: lon)
        onlineOrigin = (lat, lon)
        let favoriteGates = favorites.map { applyFavorites($0, after: visibleID) } ?? []
        pump()
        prefetchOnlineGates(favoriteGates + Self.autoPrefetchGates(lat: lat, lon: lon))
    }

    /// Queue the visible station, then favorites, before the nearby tail.
    /// Called again when iCloud delivers a newer list after launch.
    func prioritizeFavorites(_ ids: [String], after visibleID: String?) {
        let online = applyFavorites(ids, after: visibleID)
        pump()
        prefetchOnlineGates(online)
    }

    private func applyFavorites(_ ids: [String], after visibleID: String?) -> [ChsCurrentGateInfo] {
        let downloads = Self.favoriteDownloads(visibleID.map { [$0] + ids } ?? ids)
        for id in downloads.jobIDs {
            if let job = Self.candidates.first(where: { $0.id == id }) { queue.add(job) }
        }
        queue.prefer(downloads.jobIDs)
        onlinePreferred = downloads.online.map(\.id)
        return downloads.online
    }

    /// Fetch the nearby online gates once per launch (#178).
    ///
    /// Serial, in one task: `IwlsFetcher` paces itself per instance, and each
    /// fetch here builds its own — running three at once would be three
    /// unpaced request streams alongside the fit queue's. `attempted` is what
    /// keeps this to once per gate: `prioritize` fires on every fix update,
    /// and a gate that failed must not re-fetch on every GPS twitch.
    ///
    /// Offline marks nothing, so a launch in airplane mode doesn't spend the
    /// one attempt on a fetch that could never have worked — the next fix
    /// update (or the next launch) tries again. This is also the kill switch:
    /// `Connectivity` reports offline under `-networkKillSwitch` by
    /// construction, so UI tests' airplane mode stays honest here for free.
    /// ponytail: per-launch, per-gate. Opening the gate's detail is still the
    /// manual retry, and the manager's retry-all is still queue-only.
    private func prefetchOnlineGates(_ gates: [ChsCurrentGateInfo]) {
        guard Connectivity.shared.online else { return }
        var due: [ChsCurrentGateInfo] = []
        for gate in gates where !attempted.contains(gate.id) {
            if !due.contains(where: { $0.id == gate.id }) { due.append(gate) }
        }
        for gate in due { onlinePending.removeAll { $0.id == gate.id } }
        onlinePending.append(contentsOf: due)
        let preferred = onlinePreferred.compactMap { id in onlinePending.first { $0.id == id } }
        var tail = onlinePending.filter { !onlinePreferred.contains($0.id) }
        if let onlineOrigin {
            tail.sort {
                let a = distanceKm($0.latitude, $0.longitude, onlineOrigin.lat, onlineOrigin.lon)
                let b = distanceKm($1.latitude, $1.longitude, onlineOrigin.lat, onlineOrigin.lon)
                return a == b ? $0.id < $1.id : a < b
            }
        }
        onlinePending = preferred + tail
        guard !onlinePending.isEmpty else { return }
        guard !onlineRunning else { return }
        onlineRunning = true
        Task {
            while !onlinePending.isEmpty {
                let gate = onlinePending.removeFirst()
                attempted.insert(gate.id)
                // A covering window already on disk is the common case after
                // the first launch — nothing to fetch, and the fetch is the
                // expensive part, so check before spending it.
                if ChsModelStore.loadOnline(gate.id)?.block(covering: todayLocal(gate.tz)) != nil { continue }
                _ = try? await Self.fetchOnlineWindow(for: gate, from: nil)
            }
            onlineRunning = false
        }
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
        guard !running, !networkKillSwitch, queue.nextPending != nil else { return }
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
    private func publishProvisional(_ gate: ChsCurrentGateInfo, _ model: ChsModel) {
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
                    else { throw ChsError.failed("no bundled gate \(job.id)") }
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
                    else { throw ChsError.failed("no bundled port \(job.id)") }
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
                // Printed, not swallowed: the row only ever says "Failed", so
                // without this the reason is gone and diagnosing one station
                // means re-deriving it from the IWLS API by hand.
                print("CHS fit FAILED \(job.id): \(error)")
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
                                 fetcher: IwlsFetcher, fitter: ChsFitter) async throws -> ChsModel {
        let station = try Self.resolve(info, in: list)
        let end = Calendar(identifier: .gregorian).startOfDay(for: .now)
        let plan = Self.chunkPlan(days: Self.tideFitDays, end: end)
        var samples: [ChsSample] = []
        for chunk in plan {
            samples += try await fetcher.wlp(stationID: station.id, chunk: chunk)
            if await MainActor.run(body: { self.queue.shouldYield(running: info.id) }) { throw ChsError.yielded }
        }
        samples.sort { $0.t < $1.t }
        // IWLS advertises wlp on stations it serves no water for, and can retire
        // one after this build's bundle was minted. Say so, rather than handing
        // the fitter nothing and reporting whatever JSCore makes of it.
        guard !samples.isEmpty else {
            throw ChsError.failed("\(info.name): IWLS served no wlp samples over \(Int(Self.tideFitDays)) d")
        }
        let start = plan.last?.start ?? end
        let fit = try await fitter.fit(samples: samples)
        print("CHS fit \(info.id): \(samples.count) samples, \(Int(fit.fitMs)) ms (interpreted, no JIT), rms \(String(format: "%.1f", fit.rms * 100)) cm")
        return ChsModel(
            stationID: info.id, iwlsID: station.id, iwlsName: station.officialName,
            fittedAt: .now, fitStartMs: start.timeIntervalSince1970 * 1000,
            fitEndMs: end.timeIntervalSince1970 * 1000,
            offset: fit.offset, rms: fit.rms, constituents: fit.constituents)
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
                                        fetcher: IwlsFetcher, fitter: ChsFitter) async throws -> ChsModel {
        let station = try Self.resolve(name: gate.name, latitude: gate.latitude, longitude: gate.longitude,
                                       series: "wcsp1", in: list)
        let meta = try await fetcher.metadata(stationID: station.id)
        guard let flood = meta.floodDirection, let ebb = meta.ebbDirection else {
            throw ChsError.failed("\(gate.name): IWLS metadata has no flood axis")
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
                                          fitter: ChsFitter) async throws -> ChsModel {
        let samples = project(speeds: speeds.sorted { $0.t < $1.t }, dirs: dirs, floodDirection: flood)
        guard !samples.isEmpty else {
            throw ChsError.failed("\(gate.name): IWLS served no wcsp1/wcdp1 samples over \(Int(fitDays)) d")
        }
        let fit = try await fitter.fit(samples: samples)
        print("CHS current fit \(gate.id) @ \(Int(fitDays)) d: \(samples.count) samples, \(Int(fit.fitMs)) ms, rms \(String(format: "%.2f", fit.rms)) kn")
        return ChsModel(
            stationID: gate.id, iwlsID: station.id, iwlsName: station.officialName,
            fittedAt: .now, fitStartMs: start.timeIntervalSince1970 * 1000,
            fitEndMs: end.timeIntervalSince1970 * 1000, fitDays: fitDays,
            floodDirection: flood, ebbDirection: ebb,
            offset: fit.offset, rms: fit.rms, constituents: fit.constituents)
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
        }) else { throw ChsError.failed("no IWLS station serves \(series)") }
        let km = distanceKm(latitude, longitude, best.latitude, best.longitude)
        guard km <= resolveToleranceKm else {
            throw ChsError.failed("\(name): nearest \(series) station \(best.officialName) is \(String(format: "%.1f", km)) km away")
        }
        return best
    }
}

// MARK: - Online gates: fetched, never fitted

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
    ///
    /// Returns the stored block this fetch merged into — never narrower than
    /// the disk's copy of this span. Only a failed disk write falls back to
    /// the bare fetched block.
    ///
    /// ONE fetch per gate at a time. The picker's speculative prefetch and the
    /// user's own fetch of the week they landed on are both fetches of the same
    /// file, and run concurrently they interleave a read-modify-write: the
    /// store no longer loses a block to that race (disjoint blocks coexist on
    /// disk since #67 item 4), but two concurrent read-modify-writes of one
    /// file still lose ONE of the two fetches. A second caller joins the fetch
    /// already running instead of starting its own, which also spares the
    /// duplicate 30-day round trip — and is what the coalescing below is
    /// actually still for.
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
        if let existing = onlineFetches[gate.id] { return existing }
        let task = Task { @MainActor in
            defer { ChsFitService.shared.onlineFetches[gate.id] = nil }
            return try await ChsFitService.runOnlineFetch(for: gate, from: anchor)
        }
        onlineFetches[gate.id] = task
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
            await MainActor.run { shared.onlineFetchStamp += 1 }
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

enum ChsError: Error {
    case networkDisabled
    /// Stepped aside at a chunk boundary for a station the user opened. Not a
    /// failure: the job goes back to `.pending` with its chunks on disk.
    case yielded
    /// Anything terminal for this job. No catch site reads the string; it is
    /// for the thrown error's description only.
    case failed(String)
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

    init(killSwitch: Bool = networkKillSwitch) {
        self.killSwitch = killSwitch
    }

    private func get(_ path: String) async throws -> Data {
        guard !killSwitch else { throw ChsError.networkDisabled }
        let wait = 2.5 - Date.now.timeIntervalSince(lastRequest)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        lastRequest = .now
        let (data, response) = try await URLSession.shared.data(from: URL(string: Self.base + path)!)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ChsError.failed("HTTP \(code)") }
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
    let fitMs: Double
    let offset: Double
    let rms: Double
    let constituents: [Con]
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
                throw ChsError.failed("\(name).js missing from bundle")
            }
            ctx.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            if let e = jsError { throw ChsError.failed("\(name).js: \(e)") }
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
            throw ChsError.failed(jsError ?? "fitTides returned nothing")
        }
        return try JSONDecoder().decode(ChsFitResult.self, from: Data(str.utf8))
    }
}

extension CurrentStationRecord {
    /// The paired reference tide port: a bundled NOAA record, or — for a CHS
    /// gate — the reference port's on-device fitted record (pending ports pair
    /// once their fit lands; until then the gate renders current-only).
    @MainActor var pairedTide: TideStationRecord? {
        tideReference.flatMap { rid in
            if let bundled = TideStationRecord.all.first(where: { $0.id == rid }) { return bundled }
            if case .fitted(let record) = ChsFitService.shared.state(rid) { return record }
            return nil
        }
    }
}

extension ChsModelStore {
    /// UI-test hook: `-chsResetModels` wipes the store for a clean first run —
    /// including the fetched chunks, or "first run" would silently be a resume.
    static func resetIfRequested() {
        guard CommandLine.arguments.contains("-chsResetModels") else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: ChsChunkStore.dir)
    }

    /// The prune cut is bounded backward retention (#67 item 6): blocks age out
    /// at the first save after they fall behind today − onlineRetentionDays. The
    /// min(_, window.start) guard is unchanged from the single-window days — the
    /// cut never discards data the incoming fetch itself covers, or a picked old
    /// week would be deleted by its own save and refetch forever.
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
