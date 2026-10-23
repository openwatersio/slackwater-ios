// Slackwater — GPL v3. How far out the download queue walks.
//
// The queue is ONE list, sorted nearest-first (ChsQueue.reorder). A tier is
// not a separate queue or a separate set of stations — it is where that one
// walk stops. That is what lets the manager ask "how far out should I go?"
// instead of explaining three download systems.
import Foundation

/// `String`-backed so the accepted tier can be persisted verbatim
/// (`AppGroup.downloadTierKey`) — the widest tier is a preference, and a
/// preference that forgets itself on a cold launch is not one.
enum DownloadTier: String {
    /// Exactly the stations the list is rendering. Downloads with no prompt.
    case inView
    /// Everything inside `nearbyRadiusKm`. Needs a yes — and that yes is what
    /// iOS requires before any of this can continue in the background.
    case nearby
    /// Everything inside `ChsFitService.autoFitRadiusKm` — the same ceiling
    /// today's unconstrained auto-fit already uses. It is the widest tier,
    /// not an unlimited one: lifting the radius itself is a separate change.
    case everything

    /// Sized to be ACCEPTED rather than to maximise coverage. That tap is the
    /// only thing that unlocks background execution, so its acceptance rate is
    /// the whole mechanism; a tier that reads as 45 minutes gets declined.
    static let nearbyRadiusKm = 25.0

    var next: Self? {
        switch self {
        case .inView: .nearby
        case .nearby: .everything
        case .everything: nil
        }
    }

    /// Does this tier take that station into the download set?
    ///
    /// The cohort is admitted at every tier, never only at `.inView`: a station
    /// on screen is already being looked at, and a tier ceiling must never
    /// evict something the user can see.
    func admits(_ job: ChsJob, from origin: (lat: Double, lon: Double),
                cohort: Set<String>) -> Bool {
        if cohort.contains(job.id) { return true }
        switch self {
        case .inView: return false
        case .nearby:
            return distanceKm(job.latitude, job.longitude, origin.lat, origin.lon)
                <= Self.nearbyRadiusKm
        case .everything:
            return distanceKm(job.latitude, job.longitude, origin.lat, origin.lon)
                <= ChsFitService.autoFitRadiusKm
        }
    }
}

/// The stations the list was rendering when the question was framed.
///
/// Captured ONCE per place, because three separate things re-order the list
/// underneath it: `prioritize()` runs on every location update, so fix jitter
/// re-ranks constantly; iCloud delivers favorites after launch; and the series
/// filter chips change what Near Me renders. A set that cannot change cannot
/// flap, so the prompt needs no debounce, timer or suppression window.
struct DownloadCohort {
    private(set) var ids: Set<String> = []
    /// The nearest station's id. Its identity changing is what "a new place"
    /// means — not the fix moving, which happens constantly. Nothing outside
    /// this file reads it; `capture` is the only way in or out.
    private var heroID: String?

    /// Take a cohort if this is a new place. Returns true when it did, which
    /// is the caller's signal that the question may be asked again.
    ///
    /// With a hero, only the hero's identity marks a new place — that is the
    /// anti-flap rule and it does not change when a hero is present. Without
    /// one (location denied, no fix yet), there is no identity to key off,
    /// so a genuine change to the id set is what counts instead; the same
    /// set in a different order is not a change.
    mutating func capture(ids newIDs: [String], heroID newHero: String?) -> Bool {
        guard !newIDs.isEmpty else { return false }
        let isNewPlace = ids.isEmpty
            || newHero != heroID
            || (newHero == nil && Set(newIDs) != ids)
        guard isNewPlace else { return false }
        self.ids = Set(newIDs)
        self.heroID = newHero
        return true
    }

    /// A station the queue has no job for cannot be downloading, so it counts
    /// as done: cohorts are list ids (NOAA + CHS), the queue is CHS-only.
    func isDone(_ id: String, in queue: ChsQueue) -> Bool {
        guard let status = queue.status(id) else { return true }
        return status == .ready || status == .failed
    }

    /// Every captured station has finished, one way or the other — or the
    /// download queue never had a job for it. A cohort is built from the
    /// station list's ids, which include NOAA stations; `ChsQueue` only ever
    /// holds CHS jobs, so an id the queue doesn't know needs no download and
    /// cannot be "still downloading" — treating it as unsettled would leave
    /// any cohort with a NOAA station stuck forever. `.failed` counts too:
    /// another attempt gets the same answer, and holding the user at
    /// "downloading" for a station that cannot finish is a lie.
    func settled(in queue: ChsQueue) -> Bool {
        guard !ids.isEmpty else { return false }
        return ids.allSatisfy { isDone($0, in: queue) }
    }
}

/// What the strip at the top of the station list is saying, if anything.
enum DownloadStripState: Equatable {
    case absent
    case working(done: Int, total: Int, progress: Double)
    /// The same count while nothing downloads and something sits out a retry
    /// backoff, which can last 15 minutes. A bare bar would read as a hang.
    case waiting(done: Int, total: Int, progress: Double)
    /// `count` is the offer. A count and never a duration: locking the device
    /// stops the work, so any promise of a finish would be false in a pocket.
    case asking(count: Int)
}

/// Online current gates download predictions, not a fit, so they have no
/// queue job and the queue's counts never include them.
struct OnlineDownloads: Equatable {
    var ready = 0
    var total = 0
    var requestsCompleted = 0.0
    var requestsRemaining = 0.0
    /// Keeps the background task alive. Offline, a gate with nothing covering
    /// today counts: the task waits for signal rather than ending.
    var active = false
    /// A fetch is running, queued, or waiting out a retry, the same states that
    /// keep a fitted job `.pending`. The strip shows this, not `active`, so a
    /// gate merely waiting for signal doesn't hide the offer.
    var inFlight = false
    /// A gate is fetching, queued to fetch next, or held by a caller about to
    /// fetch it (`ChsFitService.onlineHolds`), whatever its last fetch did.
    var moving = false
    /// A gate with nothing covering today is sitting out a retry backoff, and
    /// no caller holds it to fetch now.
    var deferred = false
}

/// The one station count every iOS download surface shows. The list strip
/// once counted the queue alone while the Live Activity added online gates,
/// so the two disagreed on both numbers at once. The watch never fetches
/// online gates, so its queue-only count is already this one.
struct DownloadCount: Equatable {
    let ready: Int
    let total: Int
    /// Request units, the same scale `BGContinuedProcessingTask.progress` uses.
    let completed: Double
    let requests: Double
    let active: Bool
    /// Something is sitting out a retry backoff and nothing else is
    /// downloading or due, so the count is stalled. While anything else can
    /// run it is not, and the count is the better thing to show. "Due"
    /// matters as much as "downloading": a run fetches the station list
    /// before it claims a job, and the gap between jobs is not a stall. The strip and the Live Activity
    /// both say "Waiting to retry…" on this, and only on this.
    ///
    /// The copy names no cause, because this cannot tell which. A deferral
    /// follows every transient failure (offline, 5xx, station list
    /// unavailable), and the IWLS 429 wait (`IwlsFetch.retryDelay`) happens
    /// with the job still downloading, so it never lands here.
    let waitingToRetry: Bool
    var complete: Bool { total > 0 && ready == total }

    init(queue: ChsQueue, online: OnlineDownloads) {
        let progress = queue.requestProgress
        ready = queue.ready + online.ready
        total = queue.total + online.total
        completed = progress.completed + online.requestsCompleted
        requests = progress.total + online.requestsCompleted + online.requestsRemaining
        active = queue.active || online.active
        let now = appNow()
        let moving = online.moving || queue.jobs.contains {
            $0.status == .downloading || $0.status == .pending && ($0.retryAfter ?? .distantPast) <= now
        }
        waitingToRetry = !moving && (online.deferred || queue.deferred(at: now) > 0)
    }
}

/// Pure mapping from download state to what the list shows. Free function
/// rather than a view model so it can be tested without a view or a service.
func downloadStripState(cohort: DownloadCohort, queue: ChsQueue, online: OnlineDownloads = OnlineDownloads(),
                        tier: DownloadTier, declined: Bool, remaining: Int) -> DownloadStripState {
    let count = DownloadCount(queue: queue, online: online)
    if queue.active || online.inFlight {
        let progress = count.requests > 0 ? count.completed / count.requests * 10 : 0
        return count.waitingToRetry
            ? .waiting(done: count.ready, total: count.total, progress: progress)
            : .working(done: count.ready, total: count.total, progress: progress)
    }
    guard !cohort.ids.isEmpty else { return .absent }
    guard tier.next != nil, !declined, remaining > 0 else { return .absent }
    return .asking(count: remaining)
}

// Estimates reflect request pacing, so their copy deliberately avoids a countdown.
func durationPhrase(_ seconds: Double) -> String {
    if seconds < 90 { return String(localized: "under a minute", comment: "Approximate download duration under ninety seconds.") }
    let minutes = Int((seconds / 60).rounded())
    if minutes < 60 { return String(localized: "about \(minutes) minutes", comment: "Approximate duration. The integer is a number of minutes; vary by plural.") }
    let hours = Int((Double(minutes) / 60).rounded())
    return hours <= 1
        ? String(localized: "about an hour", comment: "Approximate duration of one hour.")
        : String(localized: "about \(hours) hours", comment: "Approximate duration. The integer is a number of hours; vary by plural.")
}
