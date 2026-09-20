# Download Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Download the stations the list is already showing without asking, then offer one small tier the user can accept, and let that acceptance carry the work into the background.

**Architecture:** The download queue is already one distance-sorted list (`ChsQueue`, ordered by `reorder()`). Tiers are not new queues — they are ceilings on how far `ChsFitService.adopt` walks the candidate list when it adds jobs. A captured cohort of station ids, taken once per place from what `ListGroups` renders, defines the automatic tier and gives the prompt a completion predicate that cannot flap.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftUI, XCTest, XcodeGen (`project.yml` generates `Slackwater.xcodeproj` and `Slackwater/Info.plist`), BackgroundTasks (iOS 26).

**Spec:** `docs/superpowers/specs/2026-09-20-download-tiers-design.md`

## Global Constraints

- Deployment target iOS 26.0. `BGContinuedProcessingTask` is iOS 26+; no `#available` fences are used in this codebase.
- `BGTaskScheduler` is **unavailable in the Simulator** (`BGTaskSchedulerErrorDomain` code 1). No test in `scripts/test.sh` may depend on a task actually running. Tasks 1–5 are fully testable; Task 6's background submission is not.
- Background task identifiers must be prefixed with the app's bundle id. Both the `Info.plist` entry and the Swift constant derive from `$(PRODUCT_BUNDLE_IDENTIFIER)` / `Bundle.main.bundleIdentifier` — never a literal. The bundle id is `io.openwaters.slackwater` and has been renamed once already.
- A `BGContinuedProcessingTask` handler is registered against a **concrete** identifier at tap time and submitted immediately. Continued-processing registrations are exempt from the register-before-launch rule. Never register against the wildcard pattern itself, and never register the same identifier twice in one session — that is a fatal exception, not an error.
- The nearby tier radius is **25 km** (`DownloadTier.nearbyRadiusKm`).
- No user-facing string may promise background completion. Locking the device stops a continued-processing task. Offers state a count, never a duration; durations appear only inside the downloads manager.
- Commit messages end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` and carry no session URL.
- Compile-check with `lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages`. `lockf -t 0` fails immediately if another worktree holds the machine — wait, never force it.

## Sequencing note

**#423 should land before Task 4.** Promotion is what makes "that station is outside your tier, tap it" true, and it currently waits for the whole station in flight — up to 157 s behind a 210-day gate. The tiers are shippable without it, but the narrower the automatic tier, the more the product leans on a responsive tap.

The numbers in the spec assume today's 60-day tide fit window. If that changes, no code here changes; only the counts users see.

## File Structure

- **Create** `Slackwater/DownloadTier.swift` — the tier enum and the cohort value type. Pure, no UIKit, no service access. This is where the arithmetic and the completion rule live so they can be tested without a running app.
- **Create** `Slackwater/DownloadStrip.swift` — the strip view and its three states. View only; it reads `ChsFitService` and calls back.
- **Create** `Slackwater/BackgroundDownloads.swift` — `BGContinuedProcessingTask` registration and submission.
- **Create** `SlackwaterTests/DownloadTierTests.swift` — tests for Tasks 1, 2, 3.
- **Modify** `Slackwater/ChsFitService.swift` — hold the cohort and active tier, gate `adopt` on the tier, expose the prompt state.
- **Modify** `Slackwater/StationListView.swift` — capture the cohort where `ListGroups` is built; host the strip.
- **Modify** `Slackwater/OfflineDownloads.swift` — per-tier rows and the "Everything" switch.
- **Modify** `project.yml` — `UIBackgroundModes` and the permitted task identifiers.

---

### Task 1: The tier, and which candidates it admits

**Files:**
- Create: `Slackwater/DownloadTier.swift`
- Create: `SlackwaterTests/DownloadTierTests.swift`

**Interfaces:**
- Consumes: `ChsJob` (`Slackwater/ChsQueue.swift`), `distanceKm` (`Slackwater/Theme.swift`).
- Produces: `enum DownloadTier { case inView, nearby, everything }`, `DownloadTier.nearbyRadiusKm: Double`, `DownloadTier.admits(_ job: ChsJob, from: (lat: Double, lon: Double), cohort: Set<String>) -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `SlackwaterTests/DownloadTierTests.swift`:

```swift
// Slackwater — GPL v3. Tiers are stopping points on one distance-sorted
// queue, and the cohort is what makes the in-view tier a fixed set rather
// than a moving target.
import XCTest
@testable import Slackwater

final class DownloadTierTests: XCTestCase {
    private let victoria = (lat: 48.4284, lon: -123.3656)

    private func job(_ id: String, _ lat: Double, _ lon: Double) -> ChsJob {
        ChsJob(id: id, name: id, region: "test", isCurrent: false,
               latitude: lat, longitude: lon, fitDays: 60)
    }

    func testInViewAdmitsOnlyTheCohort() {
        let inside = job("a", 48.43, -123.37)
        let outside = job("b", 48.44, -123.38)
        let cohort: Set<String> = ["a"]
        XCTAssertTrue(DownloadTier.inView.admits(inside, from: victoria, cohort: cohort))
        XCTAssertFalse(DownloadTier.inView.admits(outside, from: victoria, cohort: cohort),
                       "proximity must not smuggle a station into the automatic tier")
    }

    func testNearbyAdmitsInsideTwentyFiveKilometresAndTheCohort() {
        let close = job("close", 48.50, -123.40)          // ~9 km
        let far = job("far", 49.28, -123.12)              // ~95 km, Vancouver
        XCTAssertTrue(DownloadTier.nearby.admits(close, from: victoria, cohort: []))
        XCTAssertFalse(DownloadTier.nearby.admits(far, from: victoria, cohort: []))
        XCTAssertTrue(DownloadTier.nearby.admits(far, from: victoria, cohort: ["far"]),
                      "a station already on screen stays admitted at every tier")
    }

    func testEverythingAdmitsEverything() {
        let halifax = job("halifax", 44.6488, -63.5752)
        XCTAssertTrue(DownloadTier.everything.admits(halifax, from: victoria, cohort: []))
    }

    func testNearbyRadiusIsTwentyFive() {
        XCTAssertEqual(DownloadTier.nearbyRadiusKm, 25)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
lockf -t 0 /tmp/slackwater-test.lock xcodebuild test \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:SlackwaterTests/DownloadTierTests 2>&1 | tail -20
```
Expected: FAIL — "cannot find 'DownloadTier' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `Slackwater/DownloadTier.swift`:

```swift
// Slackwater — GPL v3. How far out the download queue walks.
//
// The queue is ONE list, sorted nearest-first (ChsQueue.reorder). A tier is
// not a separate queue or a separate set of stations — it is where that one
// walk stops. That is what lets the manager ask "how far out should I go?"
// instead of explaining three download systems.
import Foundation

enum DownloadTier: String, CaseIterable {
    /// Exactly the stations the list is rendering. Downloads with no prompt.
    case inView
    /// Everything inside `nearbyRadiusKm`. Needs a yes — and that yes is what
    /// iOS requires before any of this can continue in the background.
    case nearby
    /// No ceiling. A preference, not a job: there is no finish line to show.
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
        case .everything: return true
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/DownloadTier.swift SlackwaterTests/DownloadTierTests.swift
git commit -m "Add download tiers as ceilings on the station walk

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: The cohort, captured once per place

**Files:**
- Modify: `Slackwater/DownloadTier.swift`
- Modify: `SlackwaterTests/DownloadTierTests.swift`

**Interfaces:**
- Consumes: `ChsQueue`, `ChsJobStatus` (`Slackwater/ChsQueue.swift`).
- Produces: `struct DownloadCohort` with `ids: Set<String>`, `heroID: String?`, `mutating func capture(ids: [String], heroID: String?) -> Bool`, `func settled(in queue: ChsQueue) -> Bool`.

`capture` returns `true` when it took a new cohort, so the caller knows the prompt should be offered again.

- [ ] **Step 1: Write the failing test**

Append to `SlackwaterTests/DownloadTierTests.swift`, inside the class:

```swift
    func testCohortIsCapturedOnceAndIgnoresLaterReRanking() {
        var cohort = DownloadCohort()
        XCTAssertTrue(cohort.capture(ids: ["a", "b"], heroID: "a"))
        XCTAssertEqual(cohort.ids, ["a", "b"])

        // A fix moves a few metres: same place, list re-ranks, cohort holds.
        XCTAssertFalse(cohort.capture(ids: ["b", "a", "c"], heroID: "a"))
        XCTAssertEqual(cohort.ids, ["a", "b"],
                       "fix jitter must not grow the automatic tier")
    }

    func testCohortIsRecapturedWhenThePlaceChanges() {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["a", "b"], heroID: "a")
        XCTAssertTrue(cohort.capture(ids: ["x", "y"], heroID: "x"),
                      "a new nearest station is a new place and a new question")
        XCTAssertEqual(cohort.ids, ["x", "y"])
    }

    func testCohortIsSettledOnlyWhenEveryMemberIsDone() {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["a", "b"], heroID: "a")

        var queue = ChsQueue([job("a", 48.43, -123.37), job("b", 48.44, -123.38)])
        XCTAssertFalse(cohort.settled(in: queue))

        queue.set("a", .ready)
        XCTAssertFalse(cohort.settled(in: queue))

        // Failed counts as done: another attempt gets the same answer, and the
        // user should not be held at "downloading" by a station that cannot.
        queue.set("b", .failed)
        XCTAssertTrue(cohort.settled(in: queue))
    }

    func testJobsAddedAfterCaptureDoNotUnsettleTheCohort() {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["a"], heroID: "a")
        var queue = ChsQueue([job("a", 48.43, -123.37)])
        queue.set("a", .ready)
        XCTAssertTrue(cohort.settled(in: queue))

        queue.add(job("later", 49.0, -123.0))
        XCTAssertTrue(cohort.settled(in: queue),
                      "accepting a wider tier must not re-open the question")
    }

    func testAnEmptyCohortIsNotSettled() {
        let cohort = DownloadCohort()
        XCTAssertFalse(cohort.settled(in: ChsQueue()),
                       "nothing captured yet is not the same as finished")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the Task 1 Step 2 command. Expected: FAIL — "cannot find 'DownloadCohort' in scope".

- [ ] **Step 3: Write minimal implementation**

Append to `Slackwater/DownloadTier.swift`:

```swift
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
    mutating func capture(ids newIDs: [String], heroID newHero: String?) -> Bool {
        guard !newIDs.isEmpty else { return false }
        guard self.ids.isEmpty || newHero != heroID else { return false }
        self.ids = Set(newIDs)
        self.heroID = newHero
        return true
    }

    /// Every captured station has finished, one way or the other. `.failed`
    /// counts: another attempt gets the same answer, and holding the user at
    /// "downloading" for a station that cannot finish is a lie.
    func settled(in queue: ChsQueue) -> Bool {
        guard !ids.isEmpty else { return false }
        return ids.allSatisfy { id in
            guard let status = queue.status(id) else { return false }
            return status == .ready || status == .failed
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Task 1 Step 2 command. Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/DownloadTier.swift SlackwaterTests/DownloadTierTests.swift
git commit -m "Capture the in-view cohort once per place

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: The prompt state the strip renders

**Files:**
- Modify: `Slackwater/DownloadTier.swift`
- Modify: `SlackwaterTests/DownloadTierTests.swift`

**Interfaces:**
- Produces: `enum DownloadStripState: Equatable { case absent, working(done: Int, total: Int), asking(count: Int) }` and `func downloadStripState(cohort: DownloadCohort, queue: ChsQueue, tier: DownloadTier, declined: Bool, remaining: Int) -> DownloadStripState`.

A free function, not a view-model: it is a pure mapping from state to state, and the view is then trivial to test and trivial to read.

- [ ] **Step 1: Write the failing test**

Append to `SlackwaterTests/DownloadTierTests.swift`, inside the class:

```swift
    private func settledQueue() -> (DownloadCohort, ChsQueue) {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["a"], heroID: "a")
        var queue = ChsQueue([job("a", 48.43, -123.37)])
        queue.set("a", .ready)
        return (cohort, queue)
    }

    func testStripWorksWhileTheCohortIsDownloading() {
        var cohort = DownloadCohort()
        _ = cohort.capture(ids: ["a", "b"], heroID: "a")
        var queue = ChsQueue([job("a", 48.43, -123.37), job("b", 48.44, -123.38)])
        queue.set("a", .ready)
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: false, remaining: 14),
                       .working(done: 1, total: 2))
    }

    func testStripAsksOnceTheCohortIsSettled() {
        let (cohort, queue) = settledQueue()
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: false, remaining: 14),
                       .asking(count: 14))
    }

    func testStripIsAbsentWhenDeclined() {
        let (cohort, queue) = settledQueue()
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: true, remaining: 14),
                       .absent)
    }

    func testStripIsAbsentWithNothingLeftToOffer() {
        let (cohort, queue) = settledQueue()
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .inView,
                                          declined: false, remaining: 0),
                       .absent)
    }

    func testStripDoesNotAskAgainOnceAWiderTierIsAccepted() {
        let (cohort, queue) = settledQueue()
        XCTAssertEqual(downloadStripState(cohort: cohort, queue: queue, tier: .nearby,
                                          declined: false, remaining: 14),
                       .absent,
                       "the question belongs to the in-view tier only")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the Task 1 Step 2 command. Expected: FAIL — "cannot find 'downloadStripState' in scope".

- [ ] **Step 3: Write minimal implementation**

Append to `Slackwater/DownloadTier.swift`:

```swift
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
        let done = cohort.ids.count { id in
            let status = queue.status(id)
            return status == .ready || status == .failed
        }
        return .working(done: done, total: cohort.ids.count)
    }
    // The question belongs to the automatic tier. Once a wider one is running
    // the manager owns the conversation.
    guard tier == .inView, !declined, remaining > 0 else { return .absent }
    return .asking(count: remaining)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Task 1 Step 2 command. Expected: PASS, 14 tests.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/DownloadTier.swift SlackwaterTests/DownloadTierTests.swift
git commit -m "Derive the download strip's state from the queue

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Gate the download set on the active tier

**Files:**
- Modify: `Slackwater/ChsFitService.swift` — `autoFitSet` (around line 168), `adopt` (around line 307), and the stored properties block (around line 119).
- Modify: `SlackwaterTests/DownloadTierTests.swift`

**Interfaces:**
- Consumes: `DownloadTier`, `DownloadCohort` from Tasks 1–2.
- Produces on `ChsFitService`: `@Published private(set) var tier: DownloadTier`, `@Published private(set) var cohort: DownloadCohort`, `@Published private(set) var declinedNearby: Bool`, `func captureCohort(ids: [String], heroID: String?)`, `func accept(_ tier: DownloadTier)`, `func declineNearby()`, `var remainingBeyondCohort: Int`.
- Produces static: `ChsFitService.autoFitSet(lat:lon:constrained:tier:cohort:) -> [ChsJob]` — the existing signature gains two arguments with defaults `tier: .inView`, `cohort: []`, so existing callers and tests keep compiling.

- [ ] **Step 1: Write the failing test**

Append to `SlackwaterTests/DownloadTierTests.swift`, inside the class:

```swift
    @MainActor
    func testAutoFitSetStopsAtTheActiveTier() {
        let cohort: Set<String> = []
        let inView = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon,
                                              tier: .inView, cohort: cohort)
        XCTAssertTrue(inView.isEmpty,
                      "with nothing captured the automatic tier downloads nothing")

        let nearby = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon,
                                              tier: .nearby, cohort: cohort)
        let everything = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon,
                                                  tier: .everything, cohort: cohort)
        XCTAssertGreaterThan(nearby.count, 0)
        XCTAssertGreaterThan(everything.count, nearby.count,
                             "the widest tier has no ceiling")
        XCTAssertTrue(nearby.allSatisfy {
            distanceKm($0.latitude, $0.longitude, victoria.lat, victoria.lon)
                <= DownloadTier.nearbyRadiusKm
        })
    }

    @MainActor
    func testTheCohortIsDownloadedAtTheAutomaticTier() {
        let all = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon,
                                           tier: .everything, cohort: [])
        guard let first = all.first else { return XCTFail("no CHS candidates bundled") }
        let inView = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon,
                                              tier: .inView, cohort: [first.id])
        XCTAssertEqual(inView.map(\.id), [first.id])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the Task 1 Step 2 command. Expected: FAIL — "extra arguments 'tier', 'cohort'".

- [ ] **Step 3: Write minimal implementation**

In `Slackwater/ChsFitService.swift`, replace the body of `autoFitSet` with a tier-aware version. The existing distance ordering and the Low Data Mode budget are unchanged; the tier filters what is admitted before ordering:

```swift
    /// The stations a fix downloads: those the active tier admits, nearest
    /// first. The cohort is always admitted — a station on screen is being
    /// looked at, and a ceiling must never evict it.
    static func autoFitSet(lat: Double, lon: Double, constrained: Bool = false,
                           tier: DownloadTier = .inView,
                           cohort: Set<String> = []) -> [ChsJob] {
        func byDistance(_ jobs: [ChsJob]) -> [ChsJob] {
            jobs.sorted {
                let a = distanceKm($0.latitude, $0.longitude, lat, lon)
                let b = distanceKm($1.latitude, $1.longitude, lat, lon)
                return a == b ? $0.id < $1.id : a < b
            }
        }
        let admitted = candidates.filter {
            tier.admits($0, from: (lat, lon), cohort: cohort)
        }
        let ports = byDistance(admitted.filter { !$0.isCurrent })
        let gates = byDistance(admitted.filter { $0.isCurrent })
        let budgeted = Array(ports.prefix(autoFitPorts)) + Array(gates.prefix(autoFitGates))
        guard !constrained else { return budgeted }
        return budgeted + Array(gates.dropFirst(autoFitGates)) + Array(ports.dropFirst(autoFitPorts))
    }
```

Add to the stored-properties block near `private var started = false`:

```swift
    /// How far out the queue is currently allowed to walk, and the stations
    /// the list was rendering when the question was last framed.
    @Published private(set) var tier: DownloadTier = .inView
    @Published private(set) var cohort = DownloadCohort()
    /// "Not now" holds for the session. The manager is the way back in.
    @Published private(set) var declinedNearby = false
```

Replace `adopt` so it passes the tier and cohort through:

```swift
    private func adopt(lat: Double, lon: Double) {
        for job in Self.autoFitSet(lat: lat, lon: lon,
                                   constrained: Connectivity.shared.constrained,
                                   tier: tier, cohort: cohort.ids) { queue.add(job) }
        queue.prioritize(lat: lat, lon: lon)
        markFailOnly()
    }
```

Add the four public entry points beside `startIfNeeded()`:

```swift
    /// The list hands over what it is rendering. Captured once per place;
    /// a capture that takes re-opens the question.
    func captureCohort(ids: [String], heroID: String?) {
        guard cohort.capture(ids: ids, heroID: heroID) else { return }
        declinedNearby = false
        if let origin = onlineOrigin { adopt(lat: origin.lat, lon: origin.lon) }
        pump()
    }

    /// The user accepted a wider tier. This is the tap that lets the work
    /// continue in the background.
    func accept(_ newTier: DownloadTier) {
        tier = newTier
        if let origin = onlineOrigin { adopt(lat: origin.lat, lon: origin.lon) }
        pump()
        BackgroundDownloads.submitIfPossible(queue: queue)
    }

    func declineNearby() { declinedNearby = true }

    /// How many stations the next tier would add. The offer's number.
    var remainingBeyondCohort: Int {
        guard let origin = onlineOrigin else { return 0 }
        return Self.autoFitSet(lat: origin.lat, lon: origin.lon,
                               tier: .nearby, cohort: cohort.ids)
            .count { !cohort.ids.contains($0.id) }
    }
```

`BackgroundDownloads.submitIfPossible` arrives in Task 6. Until then, add this temporary no-op at the bottom of `DownloadTier.swift` so the file compiles, and delete it in Task 6:

```swift
// Replaced by Slackwater/BackgroundDownloads.swift in Task 6.
enum BackgroundDownloads {
    static func submitIfPossible(queue: ChsQueue) {}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Task 1 Step 2 command. Expected: PASS, 16 tests. Then run the existing suites that touch the queue to confirm nothing regressed:

```bash
lockf -t 0 /tmp/slackwater-test.lock xcodebuild test \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:SlackwaterTests/ChsQueueTests 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/ChsFitService.swift Slackwater/DownloadTier.swift SlackwaterTests/DownloadTierTests.swift
git commit -m "Stop the download walk at the active tier

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: The strip, and the list that feeds it

**Files:**
- Create: `Slackwater/DownloadStrip.swift`
- Modify: `Slackwater/StationListView.swift` — the `locatedSections` builder (around line 654) and the `.onAppear` at line 225.

**Interfaces:**
- Consumes: `DownloadStripState`, `downloadStripState(...)`, `ChsFitService.captureCohort/accept/declineNearby/remainingBeyondCohort`.
- Produces: `struct DownloadStrip: View`.

- [ ] **Step 1: Write the failing test**

There is no view test harness for this; the logic is already covered by Task 3. Verify by compile-check instead, and by the manual check in Step 4.

Create `Slackwater/DownloadStrip.swift`:

```swift
// Slackwater — GPL v3. The download strip: what the list says about work in
// flight, and the one question that lets it continue in the background.
//
// It sits at the TOP of the list while active because it is the only surface
// that can carry the tap, and iOS requires a tap before a continued-processing
// task may be submitted. The Settings row is where downloads live the rest of
// the time.
import SwiftUI

struct DownloadStrip: View {
    let state: DownloadStripState
    let onOpen: () -> Void
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        switch state {
        case .absent:
            EmptyView()
        case let .working(done, total):
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Downloading nearby stations")
                        Spacer()
                        Text("\(done) of \(total)").monospacedDigit()
                    }
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(SN.leaf)
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
        case let .asking(count):
            HStack(spacing: 12) {
                // A count, never a duration: locking the phone stops the work,
                // so a time here would be a promise the app cannot keep.
                Text("Download \(count) more nearby?")
                Spacer(minLength: 8)
                Button("Not now", action: onDecline).buttonStyle(.plain)
                Button("Yes", action: onAccept).buttonStyle(.borderedProminent)
            }
            .foregroundStyle(SN.leaf)
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
        }
    }
}
```

- [ ] **Step 2: Run compile-check to verify it fails**

Run:
```bash
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```
Expected: FAIL until `Slackwater/DownloadStrip.swift` is added to the target by `xcodegen generate` — run that first if the build does not see the file.

- [ ] **Step 3: Wire it into the list**

In `Slackwater/StationListView.swift`, inside `locatedSections`, immediately after `let groups = ListGroups(...)` is built, hand the rendered ids to the service. The cohort deliberately takes the UNFILTERED ranking, so the series chips cannot re-trigger downloads:

```swift
        // The automatic tier is what the list is rendering, and `ListGroups`
        // has just computed exactly that. Unfiltered on purpose: filtering to
        // Currents says what the user wants to LOOK at, not what to fetch.
        let cohortIds = groups.heroIds + groups.nearMe
        DispatchQueue.main.async {
            ChsFitService.shared.captureCohort(ids: cohortIds, heroID: groups.heroIds.first)
        }
```

`ListGroups` does not currently expose `heroIds`. Add it — `Slackwater/Theme.swift`, in the struct and its initialiser:

```swift
struct ListGroups {
    let heroIds: [String]
    let favorites: [String]
    let nearMe: [String]
    let recents: [String]

    init(heroIds: [String], favoriteIds: [String], recentIds: [String],
         rankedIds: [String], nearCount: Int) {
        self.heroIds = heroIds
        favorites = favoriteIds.filter { !heroIds.contains($0) }
        var shown = Set(favorites)
        shown.formUnion(heroIds)
        nearMe = Array(rankedIds.filter { !shown.contains($0) }.prefix(nearCount))
        shown.formUnion(nearMe)
        recents = recentIds.filter { !shown.contains($0) }
    }
}
```

Then render the strip above the My Location slot, as the first thing in `locatedSections`:

```swift
        DownloadStrip(
            state: downloadStripState(cohort: chs.cohort, queue: chs.queue,
                                      tier: chs.tier, declined: chs.declinedNearby,
                                      remaining: chs.remainingBeyondCohort),
            onOpen: { showDownloads = true },
            onAccept: { ChsFitService.shared.accept(.nearby) },
            onDecline: { ChsFitService.shared.declineNearby() })
```

`StationListView` does not observe the fit service today — it holds `loc`, `recents`, `favorites` and `chosen` at lines 76–79. Add a fifth beside them:

```swift
    @ObservedObject private var chs = ChsFitService.shared
```

and add the sheet state beside `showMap`:

```swift
    @State private var showDownloads = false
```

Present the manager from that state wherever the other sheets are presented in `StationListView`:

```swift
        .sheet(isPresented: $showDownloads) {
            NavigationStack {
                OfflineManagerList()
                    .navigationTitle("Downloads")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(SN.canvas, for: .navigationBar)
            }
        }
```

- [ ] **Step 4: Run to verify**

```bash
xcodegen generate
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED.

Then run on a clean simulator with a Canadian fix and confirm by eye that the strip shows progress, then the question, and that scrolling does not change the count:

```bash
xcrun simctl boot "SW Clean iPhone 17"
xcrun simctl privacy "SW Clean iPhone 17" grant location io.openwaters.slackwater
xcrun simctl location "SW Clean iPhone 17" set 48.4284,-123.3656
xcrun simctl launch "SW Clean iPhone 17" io.openwaters.slackwater -seedGate
xcrun simctl io "SW Clean iPhone 17" screenshot /tmp/strip.png
```
Shut the simulator down afterwards with `xcrun simctl shutdown "SW Clean iPhone 17"` — never `shutdown all`, another session may be mid-test.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/DownloadStrip.swift Slackwater/StationListView.swift Slackwater/Theme.swift
git commit -m "Show download progress and the nearby offer above the list

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Carry the accepted tier into the background

**Files:**
- Create: `Slackwater/BackgroundDownloads.swift`
- Modify: `Slackwater/DownloadTier.swift` — delete the temporary `enum BackgroundDownloads` stub from Task 4.
- Modify: `project.yml` — `UIBackgroundModes` and `BGTaskSchedulerPermittedIdentifiers`.

**Interfaces:**
- Consumes: `ChsQueue` (for `total`, `ready`).
- Produces: `BackgroundDownloads.submitIfPossible(queue: ChsQueue)`, `BackgroundDownloads.pattern: String`.

- [ ] **Step 1: Add the Info.plist keys**

In `project.yml`, under the `Slackwater` target's `info.properties`, after `CFBundleURLTypes`:

```yaml
        # A continued-processing task is what the "Yes" tap buys. Both keys are
        # required: the mode alone does not let registration succeed, and the
        # identifier list alone does not grant runtime.
        UIBackgroundModes: [processing]
        # Derived, never written out. A literal that drifts from the bundle id
        # fails registration SILENTLY, and this app has been renamed once.
        # A handler is registered against a CONCRETE id matching this pattern,
        # never against the pattern itself.
        BGTaskSchedulerPermittedIdentifiers:
          - $(PRODUCT_BUNDLE_IDENTIFIER).downloads.*
```

Run `xcodegen generate`, then confirm the substitution reaches the built plist rather than the source one:

```bash
plutil -p Slackwater/Info.plist | grep -A3 BGTaskScheduler
```
Expected: the literal `$(PRODUCT_BUNDLE_IDENTIFIER).downloads.*` — expansion happens at build time, and is verified in Step 4.

- [ ] **Step 2: Write the implementation**

Create `Slackwater/BackgroundDownloads.swift`:

```swift
// Slackwater — GPL v3. The accepted tier, continued in the background.
//
// What iOS grants, and the three limits that shape everything around this:
//   - The task must be submitted from the FOREGROUND in response to a person's
//     action. The "Yes" on the download strip is that action; no separate
//     consent dialog is needed or wanted.
//   - LOCKING THE DEVICE STOPS EXECUTION. Apple treats this as a framework
//     bug, but it reproduces on shipping builds. Nothing here may promise
//     completion, and the queue must treat a stop as "resume next time".
//   - Swiping the app away cancels the task with NO callback, and a person can
//     cancel from the Live Activity, which invokes the same expiration handler
//     as a system kill with no reason code. State is therefore always derived
//     from queue progress, never from "I submitted a task".
//
// None of this is reachable in the Simulator: BGTaskScheduler answers
// .unavailable there, so it is verified by hand on a device.
import BackgroundTasks
import Foundation

enum BackgroundDownloads {
    /// The wildcard, matching `BGTaskSchedulerPermittedIdentifiers`. Built from
    /// the bundle id so the two cannot drift; a stale literal fails
    /// registration silently.
    static var pattern: String { (Bundle.main.bundleIdentifier ?? "") + ".downloads.*" }

    /// Register a fresh concrete identifier and submit it. Continued-processing
    /// registrations are exempt from the register-before-launch rule, so this
    /// belongs at the tap and not in the App's init. A fresh id per call is
    /// required: registering the same identifier twice in one session is a
    /// fatal exception, not an error.
    @MainActor static func submitIfPossible(queue: ChsQueue) {
        let remaining = queue.total - queue.ready
        guard remaining > 0 else { return }
        let id = pattern.replacingOccurrences(of: "*", with: UUID().uuidString)

        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id,
                                                         using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            run(task)
        }
        guard registered else { return }

        let request = BGContinuedProcessingTaskRequest(
            identifier: id,
            title: "Downloading tide stations",
            subtitle: "\(queue.ready) of \(queue.total)")
        request.strategy = .queue
        // Throws .unavailable in the Simulator and when Background App Refresh
        // is off. Neither is an error the user should be told about: the
        // foreground run continues either way.
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func run(_ task: BGContinuedProcessingTask) {
        // Set FIRST: the system may expire the task before any other setup
        // finishes, and an expiry with no handler set is silent.
        nonisolated(unsafe) var poll: Task<Void, Never>?
        task.expirationHandler = { poll?.cancel() }

        let service = ChsFitService.shared
        poll = Task { @MainActor in
            let total = service.queue.total
            task.progress.totalUnitCount = Int64(total)
            service.resumeForBackground()
            while !Task.isCancelled, service.queue.active {
                task.progress.completedUnitCount = Int64(service.queue.ready)
                task.updateTitle("Downloading tide stations",
                                 subtitle: "\(service.queue.ready) of \(total)")
                try? await Task.sleep(for: .seconds(2))
            }
            task.setTaskCompleted(success: !Task.isCancelled)
        }
    }
}
```

Add the entry point the task needs, beside `retryNow()` in `Slackwater/ChsFitService.swift`:

```swift
    /// A background entry into the existing run loop, without `retryNow()`'s
    /// online-state reset.
    func resumeForBackground() { pump() }
```

Delete the temporary stub at the bottom of `Slackwater/DownloadTier.swift`.

- [ ] **Step 3: Run compile-check**

```bash
xcodegen generate
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Verify the identifier actually expands**

A literal that drifts from the bundle id fails registration silently, so check the BUILT plist, not the source:

```bash
for d in ~/Library/Developer/Xcode/DerivedData/Slackwater-*/; do
  wp=$(plutil -extract WorkspacePath raw "$d/info.plist" 2>/dev/null)
  case "$wp" in *download-tiers*)
    plutil -p "$d/Build/Products/Debug-iphonesimulator/Slackwater.app/Info.plist" \
      | grep -A3 BGTaskScheduler ;;
  esac
done
```
Expected: `io.openwaters.slackwater.downloads.*`. If it prints `$(PRODUCT_BUNDLE_IDENTIFIER)`, the substitution did not run and registration will fail on device.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/BackgroundDownloads.swift Slackwater/DownloadTier.swift Slackwater/ChsFitService.swift project.yml Slackwater/Info.plist
git commit -m "Continue an accepted tier in the background

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: The manager explains the tiers

**Files:**
- Modify: `Slackwater/OfflineDownloads.swift` — the summary copy (around line 425) and the list body.

**Interfaces:**
- Consumes: `DownloadTier`, `ChsFitService.tier/accept/remainingBeyondCohort`.

- [ ] **Step 1: Replace the duration-led summary**

The current summary tells the user a duration to wait out. Replace it with readiness plus the tier controls. In `Slackwater/OfflineDownloads.swift`, replace the string at the "Downloading Canadian tidal and current predictions…" site:

```swift
        return "The stations you have opened are ready and stay ready offline. Everything else fills in as you use the app, and nothing downloads twice.\(onDemandLine)"
```

- [ ] **Step 2: Add the tier section**

Add above the per-station rows:

```swift
    /// The tiers, and the only place a duration is allowed to appear: someone
    /// who opened the manager came looking for the number, whereas the same
    /// number on the list's strip is an invitation to sit and wait.
    @ViewBuilder private var tierSection: some View {
        let service = ChsFitService.shared
        VStack(alignment: .leading, spacing: 12) {
            Text("In view").font(.headline)
            Text("The stations on your list download on their own.")

            if service.tier == .inView {
                Button("Download \(service.remainingBeyondCohort) more within 25 km") {
                    service.accept(.nearby)
                }
                .buttonStyle(.borderedProminent)
                .disabled(service.remainingBeyondCohort == 0)
            } else {
                Text("Nearby (25 km) — downloading").foregroundStyle(SN.leaf)
            }

            Toggle(isOn: Binding(
                get: { service.tier == .everything },
                set: { on in service.accept(on ? .everything : .nearby) })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keep downloading Canadian stations")
                        // No estimate and no percentage: 1,073 stations is
                        // hours of requests and has no finish line to show.
                        Text("Whenever Slackwater is open. \(service.queue.ready) so far.")
                            .font(.footnote)
                    }
                }
        }
        .padding(.horizontal, 26)
    }
```

Render `tierSection` at the top of the manager's list body.

- [ ] **Step 3: Run compile-check**

```bash
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the full suite**

```bash
./scripts/test.sh
```
Expected: PASS. No unit test asserts the summary string itself, but `SlackwaterUITests/OfflineCoverageTests.swift` drives the manager and `SlackwaterTests/ChsQueueTests.swift` covers the row statuses beside it. If a string assertion fails, change the test to the new copy only after confirming the new string is the one the spec asks for — not the other way round.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/OfflineDownloads.swift SlackwaterTests
git commit -m "Explain the download tiers in the manager

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage.** Three stop points on one queue → Tasks 1, 4. What "in view" means, including the filter exclusion → Tasks 2, 5. Asking once, latch and re-capture → Tasks 2, 4. The strip's three states → Tasks 3, 5. The yes and the iOS limits → Task 6. The manager → Task 7. Copy that stays true → Tasks 5, 7. Numbers → no code. Dependencies → sequencing note. Testing → each task's Step 4.

**Gap, deliberately left:** the spec's "Testing" section asks that a cancelled background task read as "working" again on next foreground rather than as an error. No task adds error state for it to read as, because `DownloadStripState` has no failure case — cancellation already falls through to `.working`. This is covered by construction rather than by a test, and is worth confirming in review.

**Type consistency.** `DownloadTier`, `DownloadCohort`, `DownloadStripState` and `downloadStripState(cohort:queue:tier:declined:remaining:)` are defined in Tasks 1–3 and used with the same names and argument labels in Tasks 4, 5 and 7. `ChsFitService.autoFitSet` gains `tier:` and `cohort:` with defaults, so existing callers in `downloadAllGates`, `prioritize` and `ChsQueueTests` keep compiling. `BackgroundDownloads.submitIfPossible(queue:)` is stubbed in Task 4 and replaced in Task 6 with the same signature.

**Placeholder scan.** No TBD, no "add error handling", no "similar to Task N". Every code step carries its code.
