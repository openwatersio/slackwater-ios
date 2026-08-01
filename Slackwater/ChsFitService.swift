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

    private var started = false
    private var running = false

    private init() {
        ChsModelStore.resetIfRequested()
        // Every Canadian station, always — "which regions" is not a question
        // the app asks. If it ever should (Bryan: "later we might make this an
        // option, for non-Canadians"), it is one more `where` clause on these
        // two loops, exactly where the -chsFitOnly test hook already filters.
        var jobs: [ChsJob] = []
        for info in ChsStationInfo.all where Self.fitOnly?.contains(info.id) ?? true {
            var job = ChsJob(id: info.id, name: info.name, region: info.region, isCurrent: false,
                             latitude: info.latitude, longitude: info.longitude,
                             fitDays: Self.tideFitDays)
            if let model = ChsModelStore.load(info.id) {
                tideRecords[info.id] = info.record(with: model)
                job.status = .ready
            }
            jobs.append(job)
        }
        for gate in ChsCurrentGateInfo.all where Self.fitOnly?.contains(gate.id) ?? true {
            var job = ChsJob(id: gate.id, name: gate.name, region: gate.region, isCurrent: true,
                             latitude: gate.latitude, longitude: gate.longitude,
                             fitDays: gate.fitDays)
            if let model = ChsModelStore.loadCurrent(gate.id) {
                currentRecords[gate.id] = gate.record(with: model)
                // A provisional model is usable but NOT done: the job stays
                // queued so the next connected run refines it, and its cached
                // chunks mean that costs only the chunks it never fetched.
                if gate.isProvisional(model) { provisional.insert(gate.id) } else { job.status = .ready }
            }
            jobs.append(job)
        }
        queue = ChsQueue(jobs)
        // Never an arbitrary order, even before a fix lands: the prototype's
        // Victoria fallback anchors the first sort, and a real fix re-sorts.
        queue.prioritize(lat: fallbackFix.lat, lon: fallbackFix.lon)
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

    /// Start the download run: nearest-first, one station at a time. Partial
    /// failure is fine — whatever fit is stored; the rest are retryable from
    /// the manager and retry on the next connected launch.
    func startIfNeeded() {
        guard !started else { return }
        started = true
        pump()
    }

    /// A fix landed (or moved): re-order what is still queued closest-first.
    func prioritize(lat: Double, lon: Double) {
        queue.prioritize(lat: lat, lon: lon)
    }

    /// The station the user just opened jumps the queue — ahead of proximity
    /// order — and retries if it had failed. Kicks the loop in case it had run
    /// dry (every job done or failed).
    func promote(_ id: String) {
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
    static let tideFitDays = 60.0

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

enum ChsError: Error {
    case networkDisabled
    /// Stepped aside at a chunk boundary for a station the user opened. Not a
    /// failure: the job goes back to `.pending` with its chunks on disk.
    case yielded
    case noStations
    case noStationWithinTolerance(String, String, Double)
    case noFloodAxis(String)
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
