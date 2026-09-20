// Slackwater — GPL v3. How far out the download queue walks.
//
// The queue is ONE list, sorted nearest-first (ChsQueue.reorder). A tier is
// not a separate queue or a separate set of stations — it is where that one
// walk stops. That is what lets the manager ask "how far out should I go?"
// instead of explaining three download systems.
import Foundation

enum DownloadTier {
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
    /// means — not the fix moving, which happens constantly.
    private(set) var heroID: String?

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
    case working(done: Int, total: Int)
    /// `count` is the offer. A count and never a duration: locking the device
    /// stops the work, so any promise of a finish would be false in a pocket.
    case asking(count: Int)
}

/// Pure mapping from download state to what the list shows. Free function
/// rather than a view model so it can be tested without a view or a service.
func downloadStripState(cohort: DownloadCohort, queue: ChsQueue, tier: DownloadTier,
                        declined: Bool, remaining: Int) -> DownloadStripState {
    guard !cohort.ids.isEmpty else { return .absent }
    guard cohort.settled(in: queue) else {
        // An id the queue has never heard of counts as done, same as
        // `settled` above (`isDone`): no job means nothing is downloading,
        // so it can't be holding the cohort back. Without this, an unknown
        // id is settled-but-not-done and `done` never reaches `total`.
        let done = cohort.ids.count { cohort.isDone($0, in: queue) }
        return .working(done: done, total: cohort.ids.count)
    }
    // The question belongs to the automatic tier. Once a wider one is running
    // the manager owns the conversation.
    guard tier == .inView, !declined, remaining > 0 else { return .absent }
    return .asking(count: remaining)
}

// TEMPORARY STUB (Task 4) — Task 6 adds the real Slackwater/BackgroundDownloads.swift
// and MUST DELETE this enum when it does. Leaving both in place is a build
// failure: two types named `BackgroundDownloads`.
enum BackgroundDownloads {
    static func submitIfPossible(queue: ChsQueue) {}
}
