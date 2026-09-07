// Slackwater — GPL v3. The CHS fit orchestrator: what downloads without being
// asked, the download queue that runs it, and the fetch → fit → stored model
// run itself. No region UX — the stations near a fix auto-fit in the
// background; each one lands as its fit completes.
import CoreLocation
import Foundation

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

    /// The accessors the online-gate coalescing rides (`fetchOnlineWindow`,
    /// OnlineGates.swift) — methods rather than direct access, so the stored
    /// state stays private to this file and every touch stays on the main
    /// actor by construction.
    func onlineFetch(for id: String) -> Task<ChsOnlineWindow, Error>? { onlineFetches[id] }
    func setOnlineFetch(_ task: Task<ChsOnlineWindow, Error>?, for id: String) {
        onlineFetches[id] = task
    }
    func bumpOnlineFetchStamp() { onlineFetchStamp += 1 }

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
    /// Not "every Canadian station" — affordable at 21 stations and not at
    /// 1,097: bulk-downloading
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
        // Keep this conservative guard for an unexpectedly empty catalog:
        // nothing is worth deleting on that evidence. Bundled catalog lookup,
        // read, and decode failures terminate through the required loader.
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
    /// "open it and it downloads", not "wait your turn" — a different
    /// sentence, and the only honest one for the other 1,000-odd stations.
    func isQueued(_ id: String) -> Bool { queue.job(id) != nil }

    /// How many Canadian stations exist but are not downloading — the number
    /// the manager needs to say what "all done" actually means.
    var notQueued: Int { Self.candidates.count - queue.total }

    /// Every Canadian current gate the fix's radius leaves out, and what they
    /// cost — the manager's bulk action, and the reason currents need no
    /// region model (#8).
    ///
    /// Gates are the series a bulk download is affordable for. There are 13
    /// fittable ones in the whole country and 9 online windows, against 1,058
    /// tide ports: fitting every gate is about 25 minutes, fitting every port
    /// is about 4.4 hours. So the passes a passage crosses are selectable as
    /// one set, and "the Gulf Islands" never has to become a place you pick.
    /// ponytail: no region picker, no route parsing — all of them, once.
    var gatesToDownload: [ChsJob] {
        Self.candidates.filter { $0.isCurrent && queue.job($0.id) == nil }
    }

    /// Take every Canadian gate into the download set. Nearest still runs
    /// first: these join the queue's proximity order rather than jumping it,
    /// so the passes you are actually near stay ahead of the rest.
    func downloadAllGates() {
        for job in gatesToDownload { queue.add(job) }
        pump()
        prefetchOnlineGates(ChsCurrentGateInfo.all.filter(\.isOnline))
    }

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
    /// order — and retries if it had failed. It also JOINS the queue
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

    /// 60 d @ 15 min ending yesterday — a validated fit window. Deliberately
    /// not per-gate: per-gate windows are a currents-only concern.
    nonisolated static let tideFitDays = 60.0

    private nonisolated func fit(_ info: ChsStationInfo, list: [IwlsStation],
                                 fetcher: IwlsFetcher, fitter: ChsFitter) async throws -> ChsModel {
        let station = try Self.resolve(info, in: list)
        // The STATION's today, on the app clock — not the device's. A phone
        // set to UTC, or a traveller outside Pacific time, would otherwise
        // anchor the window a day off (#230).
        let end = todayLocal(info.tz)
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
        let end = todayLocal(gate.tz)
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


enum ChsError: Error {
    case networkDisabled
    /// Stepped aside at a chunk boundary for a station the user opened. Not a
    /// failure: the job goes back to `.pending` with its chunks on disk.
    case yielded
    /// Anything terminal for this job. No catch site reads the string; it is
    /// for the thrown error's description only.
    case failed(String)
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
}
