// Slackwater — GPL v3. The offline-download queue, ported from slackwater-web
// (src/offlineSync.ts + its offlineSync.test.ts, which encode the intended
// behaviour): an ordered job list whose HEAD IS THE PRIORITY. The fit loop
// always takes the first `.pending` job, so re-ordering the list is how
// prioritisation happens — safely, mid-run, because a worker that has already
// claimed a job is unaffected by a re-sort.
//
// Three orderings, in this precedence:
//   1. `promote(id)` — the station the user is LOOKING AT goes to the front.
//      Sticky, unlike the web's plain re-sort: a later prioritize() must not
//      demote it the moment a GPS fix moves.
//   2. `prefer(ids)` — favorites, in their saved order.
//   3. `prioritize(lat:lon:)` — everything else closest-first from the fix
//      (web offlineSync.prioritize), so the water you can see out the window
//      downloads before the far end of the coast.
//
// Deviations from the web, and why: no `paused` (the web pauses to protect a
// scarce IWLS *daily* request budget it re-spends every week; here a station
// is fitted once and is then offline forever, so there is nothing to ration),
// and no `resetAll`/cache horizon (the web re-downloads a rolling 7-day cache;
// a fitted harmonic model does not expire).
import Foundation

enum ChsJobStatus { case pending, downloading, ready, failed }

/// One downloadable station. Identity only — the fitted model lives in
/// ChsModelStore, and the record in ChsFitService.
struct ChsJob: Identifiable, Hashable {
    let id: String
    let name: String
    let region: String
    /// A current gate reads two series (speed + direction) and a metadata call;
    /// a tide port reads one. The manager and the detail warning both say
    /// which, because it is the whole explanation for the wait.
    let isCurrent: Bool
    let latitude: Double
    let longitude: Double
    /// This station's OWN fit window — 60 d for every tide port and for the
    /// four gates validated at 60 d, 210 d for the rest (M51).
    let fitDays: Double
    var status: ChsJobStatus = .pending
    var attempts = 0
    var retryAfter: Date?
    var lastError: String?
    var done = 0
    var total = 0

    /// Number of IWLS requests needed for the fit window.
    var requestCount: Double {
        let chunks = (fitDays / 7).rounded(.up) + 1
        return chunks * (isCurrent ? 2 : 1) + (isCurrent ? 1 : 0)
    }

    func estimatedSeconds(perRequest: Double = 2.5) -> Double {
        requestCount * perRequest
    }
}

struct ChsQueue {
    private(set) var jobs: [ChsJob]
    /// Ids the user opened, most recent first — pinned to the head of the queue.
    private var promoted: [String] = []
    /// Cloud favorites, in saved order, after anything the user is viewing.
    private var preferred: [String] = []
    private var origin: (lat: Double, lon: Double)?

    init(_ jobs: [ChsJob] = []) { self.jobs = jobs }

    var total: Int { jobs.count }
    var ready: Int { jobs.filter { $0.status == .ready }.count }
    var failed: Int { jobs.filter { $0.status == .failed }.count }
    /// A run is still in flight: something is queued or downloading.
    var active: Bool { jobs.contains { $0.status == .pending || $0.status == .downloading } }
    var complete: Bool { total > 0 && ready == total }
    func nextPending(at now: Date = appNow()) -> ChsJob? {
        jobs.first { $0.status == .pending && ($0.retryAfter ?? .distantPast) <= now }
    }

    func status(_ id: String) -> ChsJobStatus? { jobs.first { $0.id == id }?.status }
    func job(_ id: String) -> ChsJob? { jobs.first { $0.id == id } }
    /// Did the user jump this one up the queue? Drives the manager's badge.
    func isPromoted(_ id: String) -> Bool { promoted.contains(id) }

    /// 1-based position among the stations still to come; nil once it is ready.
    func position(_ id: String) -> Int? {
        let waiting = jobs.filter { $0.status == .pending || $0.status == .downloading }
        return waiting.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    /// Seconds until `id` is usable: everything ahead of it, plus itself.
    func waitSeconds(_ id: String, perRequest: Double = 2.5) -> Double {
        let waiting = jobs.filter { $0.status == .pending || $0.status == .downloading }
        guard let at = waiting.firstIndex(where: { $0.id == id }) else { return 0 }
        return waiting[...at].reduce(0) { $0 + $1.estimatedSeconds(perRequest: perRequest) }
    }

    /// Put a station into the download set. It contains the stations in the
    /// active radius plus anything opened or already on disk. Adding an id
    /// already here is a no-op —
    /// re-adding must never reset a job that is downloading or done.
    mutating func add(_ job: ChsJob) {
        guard !jobs.contains(where: { $0.id == job.id }) else { return }
        jobs.append(job)
        reorder()
    }

    mutating func set(_ id: String, _ status: ChsJobStatus) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].status = status
    }

    mutating func note(_ id: String, error: String) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].lastError = error
    }

    mutating func setProgress(_ id: String, done: Int, total: Int) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].done = done
        jobs[i].total = total
    }

    /// The station being viewed jumps the queue. Also un-fails it: opening a
    /// station that failed is the clearest possible "try this one again".
    /// A ready station is left alone — nothing to download, and pinning it
    /// would shuffle the manager's list for no reason.
    mutating func promote(_ id: String) {
        guard let current = status(id), current != .ready else { return }
        promoted.removeAll { $0 == id }
        promoted.insert(id, at: 0)
        if current == .failed { set(id, .pending) }
        if let i = jobs.firstIndex(where: { $0.id == id }) {
            jobs[i].retryAfter = nil
            jobs[i].attempts = 0
        }
        reorder()
    }

    /// Put favorites ahead of proximity. Missing ids are ignored; the service adds their jobs.
    mutating func prefer(_ ids: [String]) {
        preferred = ids
        reorder()
    }

    /// Closest-first from the fix (web offlineSync.prioritize).
    mutating func prioritize(lat: Double, lon: Double) {
        origin = (lat, lon)
        reorder()
    }

    static func backoff(attempts: Int) -> TimeInterval {
        min(pow(2, Double(max(attempts, 1) - 1)) * 60, 15 * 60)
    }

    mutating func deferRetry(_ id: String, error: String, at now: Date = appNow()) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].attempts += 1
        jobs[i].lastError = error
        jobs[i].retryAfter = now.addingTimeInterval(Self.backoff(attempts: jobs[i].attempts))
        jobs[i].done = 0
        jobs[i].status = .pending
    }

    func earliestRetry(after now: Date = appNow()) -> Date? {
        jobs.compactMap { job in
            guard job.status == .pending, let due = job.retryAfter, due > now else { return nil }
            return due
        }.min()
    }

    func deferred(at now: Date = appNow()) -> Int {
        jobs.count { $0.status == .pending && ($0.retryAfter ?? .distantPast) > now }
    }

    mutating func clearBackoffs() {
        for i in jobs.indices where jobs[i].status == .pending {
            jobs[i].retryAfter = nil
            jobs[i].attempts = 0
        }
    }

    mutating func retryNow() {
        clearBackoffs()
        for i in jobs.indices where jobs[i].status == .failed {
            jobs[i].status = .pending
            jobs[i].attempts = 0
        }
    }

    private mutating func reorder() {
        let head = promoted.compactMap { id in jobs.first { $0.id == id } }
        let favorites: [ChsJob] = preferred.compactMap { id in
            guard !promoted.contains(id) else { return nil }
            return jobs.first { $0.id == id }
        }
        var tail = jobs.filter { !promoted.contains($0.id) && !preferred.contains($0.id) }
        if let origin {
            // Ties break on id so the order is total — two stations at the
            // same distance must not shuffle between re-sorts.
            tail.sort {
                let a = distanceKm($0.latitude, $0.longitude, origin.lat, origin.lon)
                let b = distanceKm($1.latitude, $1.longitude, origin.lat, origin.lon)
                return a == b ? $0.id < $1.id : a < b
            }
        }
        jobs = head + favorites + tail
    }
}
