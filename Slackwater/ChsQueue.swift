// Slackwater — GPL v3. The offline-download queue, ported from slackwater-web
// (src/offlineSync.ts + its offlineSync.test.ts, which encode the intended
// behaviour): an ordered job list whose HEAD IS THE PRIORITY. The fit loop
// always takes the first `.pending` job, so re-ordering the list is how
// prioritisation happens — safely, mid-run, because a worker that has already
// claimed a job is unaffected by a re-sort.
//
// Two orderings, in this precedence:
//   1. `promote(id)` — the station the user is LOOKING AT goes to the front.
//      Sticky, unlike the web's plain re-sort: a later prioritize() must not
//      demote it the moment a GPS fix moves.
//   2. `prioritize(lat:lon:)` — everything else closest-first from the fix
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
    /// A current gate fits a 210-day window (≈7× a tide port's requests). The
    /// manager and the detail warning both say which, because it is the whole
    /// explanation for the wait.
    let isCurrent: Bool
    let latitude: Double
    let longitude: Double
    var status: ChsJobStatus = .pending

    /// Rough wall-clock cost of this job, seconds: IwlsFetcher paces one
    /// request every 2.5 s, and the window divides into 7-day chunks — 9 for a
    /// 60-day tide port, 30 × 2 series + 1 metadata for a 210-day current gate.
    /// ponytail: a constant, not a measurement; it only ever feeds "about N
    /// min", so a live moving average would be precision nobody reads.
    var estimatedSeconds: Double { isCurrent ? 61 * 2.5 : 9 * 2.5 }
}

struct ChsQueue {
    private(set) var jobs: [ChsJob]
    /// Ids the user opened, most recent first — pinned to the head of the queue.
    private var promoted: [String] = []
    private var origin: (lat: Double, lon: Double)?

    init(_ jobs: [ChsJob] = []) { self.jobs = jobs }

    var total: Int { jobs.count }
    var ready: Int { jobs.filter { $0.status == .ready }.count }
    var failed: Int { jobs.filter { $0.status == .failed }.count }
    /// A run is still in flight: something is queued or downloading.
    var active: Bool { jobs.contains { $0.status == .pending || $0.status == .downloading } }
    var complete: Bool { total > 0 && ready == total }
    /// The next job a worker should claim — first `.pending` in queue order.
    var nextPending: ChsJob? { jobs.first { $0.status == .pending } }

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
    func waitSeconds(_ id: String) -> Double {
        let waiting = jobs.filter { $0.status == .pending || $0.status == .downloading }
        guard let at = waiting.firstIndex(where: { $0.id == id }) else { return 0 }
        return waiting[...at].reduce(0) { $0 + $1.estimatedSeconds }
    }

    mutating func set(_ id: String, _ status: ChsJobStatus) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].status = status
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
        reorder()
    }

    /// Closest-first from the fix (web offlineSync.prioritize).
    mutating func prioritize(lat: Double, lon: Double) {
        origin = (lat, lon)
        reorder()
    }

    /// The manager's retry: re-queue the failures, leave everything else be.
    /// (Web restartAll — never re-downloads a ready station.)
    mutating func retryFailed() {
        for job in jobs where job.status == .failed { set(job.id, .pending) }
    }

    private mutating func reorder() {
        let head = promoted.compactMap { id in jobs.first { $0.id == id } }
        var tail = jobs.filter { !promoted.contains($0.id) }
        if let origin {
            // Ties break on id so the order is total — two stations at the
            // same distance must not shuffle between re-sorts.
            tail.sort {
                let a = distanceKm($0.latitude, $0.longitude, origin.lat, origin.lon)
                let b = distanceKm($1.latitude, $1.longitude, origin.lat, origin.lon)
                return a == b ? $0.id < $1.id : a < b
            }
        }
        jobs = head + tail
    }
}
