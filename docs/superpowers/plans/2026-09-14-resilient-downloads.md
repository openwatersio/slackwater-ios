# Resilient Downloads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Download and cache every Canadian station within reach, retry transient failures on a clock instead of giving up, and say what is ready rather than asking the user to fix errors.

**Architecture:** The download queue (`ChsQueue`) keeps its head-is-the-priority shape and gains a per-job retry clock: a transient failure returns the job to `.pending` with a `retryAfter` date, and the service schedules one pump at the earliest of them. Errors are classified at the throw site — `ChsError.permanent` versus `ChsError.transient` — so transient is what an unanticipated failure falls back to. The auto-fit set widens from nine stations to everything inside the existing 150 km radius, tiered so the first screen is unaffected. The UI reads the queue and reports readiness.

**Tech Stack:** Swift 6, SwiftUI, XCTest/XCUITest, `Network.framework` (`NWPathMonitor`), MapLibre (`MLNOfflineStorage`), Xcode project driven by `project.yml` (XcodeGen).

**Spec:** `docs/superpowers/specs/2026-09-13-resilient-downloads-design.md`

## Global Constraints

- **No new dependencies.** Nothing enters `project.yml`.
- **Read `CLAUDE.md` before building.** The test machine is shared. Compile-check with `lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages`. Never force the lock. Never switch branches while a suite runs — it compiles from source.
- **Suite:** `./scripts/test.sh` (fast). Read `build/results-fast-iPhone_17.xcresult`, not the exit code. `build/` holds stale bundles from older runs; check the bundle's modification time is from your run.
- **Follow the house skills** for comments (`code-comments`) and PR/commit prose (`pr-writing`). Mark deliberate shortcuts with a `ponytail:` comment naming the ceiling.
- **Calendar days go through `Calendar` with its `timeZone` set.** `addingTimeInterval` is for durations only.
- **The app clock is `appNow()`** (`Slackwater/Palette.swift:215`). Never `Date()` in logic a test needs to control.
- **Radius and budget constants** stay as they are: `autoFitRadiusKm = 150.0`, `autoFitPorts = 6`, `autoFitGates = 3`.
- **Backoff ladder:** 1, 2, 4, 8 minutes, capped at 15 minutes.
- **Copy register:** plain, no exclamation, no blame. "Retrying in 3 min", "Waiting · 4th in line", "Downloading · 12 of 31", "Available offline", "Unavailable · <reason>".
- **Amber (`SN.amber`) is the warning colour and stays scarce.** A deferred retry is not a warning; it renders in `SN.foam`.

---

### Task 1: Classify failures as permanent or transient

The queue cannot defer what it cannot classify, so this comes first. `ChsError.failed` splits in two. No catch site reads its string today (it is only printed), so the rename is safe.

**Files:**
- Modify: `Slackwater/ChsFitService.swift` (the `ChsError` enum at the file's end, and its six throw sites)
- Modify: `Slackwater/IwlsClient.swift` (one throw site in `get`)
- Modify: `Slackwater/OnlineGates.swift` (two throw sites in `runOnlineFetch`)
- Test: `SlackwaterTests/ChsQueueTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ChsError.permanent(String)`, `ChsError.transient(String)`, and `static func ChsError.isPermanent(_ error: Error) -> Bool`.

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/ChsQueueTests.swift`:

```swift
    /// Transient is the DEFAULT: a cause nobody anticipated gets retried rather
    /// than stranding a station for the session.
    func testOnlyNamedCausesArePermanent() {
        XCTAssert(ChsError.isPermanent(ChsError.permanent("no IWLS station serves wlp")))
        XCTAssertFalse(ChsError.isPermanent(ChsError.transient("HTTP 503")))
        XCTAssertFalse(ChsError.isPermanent(URLError(.timedOut)))
        XCTAssertFalse(ChsError.isPermanent(NSError(domain: NSPOSIXErrorDomain, code: 54)))
        XCTAssertFalse(ChsError.isPermanent(DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "IWLS served nonsense"))))
        // Stepping aside is not a failure at all, and must never read as one.
        XCTAssertFalse(ChsError.isPermanent(ChsError.yielded))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -5`
Expected: compile failure, "type 'ChsError' has no member 'permanent'".

- [ ] **Step 3: Write minimal implementation**

Replace the `ChsError` enum at the end of `Slackwater/ChsFitService.swift`:

```swift
enum ChsError: Error {
    case networkDisabled
    /// Stepped aside at a chunk boundary for a station the user opened. Not a
    /// failure: the job goes back to `.pending` with its chunks on disk.
    case yielded
    /// Terminal for this station: another attempt gets the same answer. A
    /// station that does not resolve, a series IWLS does not serve, a gate with
    /// no flood axis, an id that left the bundle, a 4xx.
    case permanent(String)
    /// This attempt did not get there; a later one can. The fetcher has already
    /// spent its own retries by the time one of these reaches the queue, so it
    /// means "try again in minutes", not "try again now".
    case transient(String)

    /// Is this the end of the line for the station?
    ///
    /// Transient is the default, and that is the point: the classification is a
    /// list of causes we KNOW are hopeless, so a cause nobody anticipated —
    /// a decoding error on a garbled response, a POSIX socket teardown — is
    /// retried rather than stranding a station for the session.
    static func isPermanent(_ error: Error) -> Bool {
        guard case .permanent = error as? ChsError else { return false }
        return true
    }
}
```

In `Slackwater/ChsFitService.swift`, change all six `ChsError.failed(` throw sites to `ChsError.permanent(`. They are: the fixture-checkpoint throws in `IwlsFetcher.waitForFixtureRelease` (in `IwlsClient.swift`, see below), `"no bundled gate \(job.id)"`, `"no bundled port \(job.id)"`, `"\(info.name): IWLS served no wlp samples…"`, `"\(gate.name): IWLS metadata has no flood axis"`, `"\(gate.name): IWLS served no wcsp1/wcdp1 samples…"`, and both `resolve` throws (`"no IWLS station serves \(series)"` and `"\(name): nearest \(series) station…"`).

In `Slackwater/IwlsClient.swift`, the two `ChsError.failed` in `waitForFixtureRelease` become `.permanent`, and the status throw in `get` classifies:

```swift
                case .success(let code):
                    // The fetcher has already spent its retries on anything a
                    // retry could fix, so a status arriving here is either the
                    // server refusing this request for good (4xx) or a server
                    // problem that outlasted the ladder.
                    throw (400...499).contains(code) ? ChsError.permanent("HTTP \(code)")
                                                     : ChsError.transient("HTTP \(code)")
```

In `Slackwater/OnlineGates.swift`, both `ChsError.failed` become `.permanent` (no flood axis, empty series).

- [ ] **Step 4: Run the suite**

Run: `./scripts/test.sh`
Expected: `build/results-fast-iPhone_17.xcresult` reports `Passed`, 0 failed, and `testOnlyNamedCausesArePermanent` among the cases.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/ChsFitService.swift Slackwater/IwlsClient.swift Slackwater/OnlineGates.swift SlackwaterTests/ChsQueueTests.swift
git commit -m "Split ChsError into permanent and transient"
```

---

### Task 2: Give the queue a retry clock

**Files:**
- Modify: `Slackwater/ChsQueue.swift`
- Test: `SlackwaterTests/ChsQueueTests.swift`

**Interfaces:**
- Consumes: `ChsError.isPermanent` (Task 1).
- Produces: `ChsJob.attempts: Int`, `ChsJob.retryAfter: Date?`, `ChsJob.lastError: String?`; `ChsQueue.nextPending(at:) -> ChsJob?`, `ChsQueue.deferRetry(_:error:at:)`, `ChsQueue.earliestRetry(after:) -> Date?`, `ChsQueue.deferred(at:) -> Int`, `ChsQueue.backoff(attempts:) -> TimeInterval`, `ChsQueue.retryNow()`.

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/ChsQueueTests.swift`:

```swift
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    /// A transient failure is a wait, not a verdict: the job stays pending and
    /// the queue simply will not hand it out yet.
    func testADeferredJobIsSkippedUntilItsClockRunsOut() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.set("near", .downloading)
        q.deferRetry("near", error: "HTTP 503", at: t0)

        XCTAssertEqual(q.job("near")?.status, .pending, "deferred is pending, never failed")
        XCTAssertEqual(q.job("near")?.attempts, 1)
        XCTAssertEqual(q.job("near")?.lastError, "HTTP 503")
        XCTAssertEqual(q.nextPending(at: t0)?.id, "mid", "the deferred job is passed over")
        XCTAssertEqual(q.nextPending(at: t0.addingTimeInterval(61))?.id, "near",
                       "and picked up again once its minute is up")
        XCTAssertEqual(q.deferred(at: t0), 1)
        XCTAssertEqual(q.deferred(at: t0.addingTimeInterval(61)), 0)
    }

    /// 1, 2, 4, 8 minutes, then flat. A ship passing a headland should not be
    /// waiting an hour for the next try.
    func testBackoffDoublesToAFifteenMinuteCeiling() {
        XCTAssertEqual(ChsQueue.backoff(attempts: 1), 60)
        XCTAssertEqual(ChsQueue.backoff(attempts: 2), 120)
        XCTAssertEqual(ChsQueue.backoff(attempts: 3), 240)
        XCTAssertEqual(ChsQueue.backoff(attempts: 4), 480)
        XCTAssertEqual(ChsQueue.backoff(attempts: 5), 900)
        XCTAssertEqual(ChsQueue.backoff(attempts: 50), 900)
    }

    /// The service needs one date to schedule one pump against.
    func testEarliestRetryIsTheNextJobDue() {
        var q = queue()
        q.set("far", .downloading)
        q.deferRetry("far", error: "dropped", at: t0)                       // due t0+60
        q.set("near", .downloading)
        q.deferRetry("near", error: "dropped", at: t0.addingTimeInterval(30))  // due t0+90
        XCTAssertEqual(q.earliestRetry(after: t0), t0.addingTimeInterval(60))
        XCTAssertNil(q.earliestRetry(after: t0.addingTimeInterval(120)),
                     "nothing is waiting on a clock once every clock has run out")
    }

    /// Opening a station is the clearest "try this one now" there is.
    func testPromoteAndRetryNowBothClearTheClock() {
        var q = queue()
        q.set("far", .downloading)
        q.deferRetry("far", error: "dropped", at: t0)
        q.promote("far")
        XCTAssertNil(q.job("far")?.retryAfter)
        XCTAssertEqual(q.job("far")?.attempts, 0, "a fresh ask starts the ladder over")
        XCTAssertEqual(q.nextPending(at: t0)?.id, "far")

        q.set("mid", .downloading)
        q.deferRetry("mid", error: "dropped", at: t0)
        q.set("near", .failed)

        // A reconnect clears clocks and nothing else.
        q.clearBackoffs()
        XCTAssertNil(q.job("mid")?.retryAfter, "a link coming back clears a deferral")
        XCTAssertEqual(q.job("near")?.status, .failed,
                       "but cannot fix a station that will never resolve")

        // The user asking is worth one more go at the terminal ones too.
        q.retryNow()
        XCTAssertEqual(q.job("near")?.status, .pending, "Retry now re-queues a permanent failure")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the compile check from Global Constraints.
Expected: failure, "value of type 'ChsQueue' has no member 'deferRetry'".

- [ ] **Step 3: Write minimal implementation**

In `Slackwater/ChsQueue.swift`, add to `ChsJob`:

```swift
    /// Transient failures so far. Drives the backoff and nothing else; a
    /// success or a fresh ask from the user resets it.
    var attempts = 0
    /// When this job may be claimed again. Nil means now. A job with a date in
    /// the future is still `.pending` — waiting on a clock is not a failure,
    /// and the UI says so.
    var retryAfter: Date?
    /// Why the last attempt stopped, for the row to show when it is terminal.
    var lastError: String?
```

Replace `nextPending` and add the clock API:

```swift
    /// The next job a worker should claim: the first `.pending` job in queue
    /// order whose retry clock has run out.
    func nextPending(at now: Date = appNow()) -> ChsJob? {
        jobs.first { $0.status == .pending && ($0.retryAfter ?? .distantPast) <= now }
    }

    /// 1, 2, 4, 8 minutes, then flat at 15.
    ///
    /// The ceiling is the point: an unbounded ladder means a boat that regains
    /// signal after an hour of shadow waits another hour to find out.
    /// ponytail: no jitter. These are minutes apart on one device; add jitter
    /// only if IWLS ever reports a thundering herd.
    static func backoff(attempts: Int) -> TimeInterval {
        min(pow(2, Double(max(attempts, 1) - 1)) * 60, 15 * 60)
    }

    /// This attempt did not get there. The job goes back in line with a clock
    /// on it, keeping its place in the queue order.
    mutating func deferRetry(_ id: String, error: String, at now: Date = appNow()) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].attempts += 1
        jobs[i].lastError = error
        jobs[i].retryAfter = now.addingTimeInterval(Self.backoff(attempts: jobs[i].attempts))
        jobs[i].status = .pending
    }

    /// The soonest a deferred job comes due, for the service to schedule one
    /// pump against. Nil when nothing is waiting on a clock.
    func earliestRetry(after now: Date = appNow()) -> Date? {
        jobs.filter { $0.status == .pending }
            .compactMap(\.retryAfter)
            .filter { $0 > now }
            .min()
    }

    /// How many jobs are waiting out a backoff — the manager's "Retry now"
    /// appears only while this is non-zero.
    func deferred(at now: Date = appNow()) -> Int {
        jobs.filter { $0.status == .pending && ($0.retryAfter ?? .distantPast) > now }.count
    }

    /// Stop waiting on every clock. What a reconnect does — and ONLY that: a
    /// permanent failure is not something a link coming back can fix, and
    /// re-attempting one on every flap of a bad connection is how a queue
    /// spends its afternoon on a station that will never resolve.
    mutating func clearBackoffs() {
        for i in jobs.indices where jobs[i].status == .pending {
            jobs[i].retryAfter = nil
            jobs[i].attempts = 0
        }
    }

    /// The manager's one action: the above, plus one more go at the terminal
    /// failures, because the user asking is worth an attempt the app would not
    /// have made on its own. (Replaces `retryFailed`.)
    mutating func retryNow() {
        clearBackoffs()
        for i in jobs.indices where jobs[i].status == .failed {
            jobs[i].status = .pending
            jobs[i].retryAfter = nil
            jobs[i].attempts = 0
        }
    }
```

Delete `retryFailed()`. In `promote`, clear the clock — insert after the `set(id, .pending)` line:

```swift
        if let i = jobs.firstIndex(where: { $0.id == id }) {
            // A fresh ask starts the ladder over: the user watching this
            // station is worth more than the backoff's memory of a bad minute.
            jobs[i].retryAfter = nil
            jobs[i].attempts = 0
        }
```

Also in `promote`, widen the un-fail guard so a deferred job promotes cleanly: change `if current == .failed { set(id, .pending) }` to `if current == .failed || current == .pending { set(id, .pending) }` (a no-op for pending, but it keeps the intent readable).

Update the two call sites of the old computed `nextPending` inside this file: `active` stays as it is (a deferred job IS active), and any `nextPending` reference becomes `nextPending()`.

- [ ] **Step 4: Run the suite**

Run: `./scripts/test.sh`
Expected: `Passed`, 0 failed. Existing `testNextPendingIsTheHeadAndSkipsClaimedOrFinishedJobs` and `testRetryFailedRequeuesOnlyFailures` will need their call sites updated to `nextPending()` and `retryNow()` — update them, keeping their assertions.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/ChsQueue.swift SlackwaterTests/ChsQueueTests.swift
git commit -m "Defer a transient download failure instead of failing it"
```

---

### Task 3: Make the service honour the clock

**Files:**
- Modify: `Slackwater/ChsFitService.swift`
- Test: `SlackwaterTests/ChsQueueTests.swift`

**Interfaces:**
- Consumes: Task 1's `ChsError.isPermanent`, Task 2's queue clock API.
- Produces: `ChsFitService.retryNow()` (replaces `retryFailed()`); `pump()` scheduling behaviour.

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/ChsQueueTests.swift`:

```swift
    /// A station list that does not arrive is the one failure that used to take
    /// every queued job down with it.
    func testAStationListFailureDefersTheQueueRatherThanFailingIt() {
        var q = queue()
        for job in q.jobs { q.deferRetry(job.id, error: "station list unavailable", at: t0) }
        XCTAssertEqual(q.jobs.filter { $0.status == .failed }.count, 0)
        XCTAssertEqual(q.deferred(at: t0), 3)
        XCTAssertEqual(q.earliestRetry(after: t0), t0.addingTimeInterval(60))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the compile check. Expected: PASS to compile but the behaviour it describes is not yet wired into `run()`; this test guards the queue contract the service now depends on. Run it and confirm it passes before changing the service, so a later failure points at the service.

- [ ] **Step 3: Write minimal implementation**

In `Slackwater/ChsFitService.swift`:

Replace `pump()`:

```swift
    /// Schedules the next pump when the loop has nothing to claim right now.
    private var retryTimer: Task<Void, Never>?

    private func pump() {
        guard !running, !networkKillSwitch else { return }
        // Nothing to do without a path. The rising edge in `observeConnectivity`
        // pumps again, so this is a pause, not a stop.
        guard Connectivity.shared.online else { return }
        guard queue.nextPending() != nil else { return scheduleRetryPump() }
        running = true
        Task.detached(priority: .utility) { [self] in await run() }
    }

    /// One timer for the whole queue, at the earliest job due. Cancelled and
    /// replaced whenever the queue changes, so it is never stale.
    private func scheduleRetryPump() {
        retryTimer?.cancel()
        guard let due = queue.earliestRetry() else { return }
        retryTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(due.timeIntervalSinceNow, 1)))
            guard !Task.isCancelled else { return }
            self?.pump()
        }
    }
```

Replace `retryFailed()`:

```swift
    /// The manager's one action: stop waiting on every clock and try now.
    func retryNow() {
        queue.retryNow()
        pump()
    }
```

In `run()`, the station-list branch defers instead of failing:

```swift
        guard let list = try? await fetcher.stationList() else {
            // One failed request used to take every queued job down with it.
            // The list is re-fetchable and cached on disk; this is a wait.
            await MainActor.run {
                for job in self.queue.jobs where job.status == .pending {
                    self.queue.deferRetry(job.id, error: "station list unavailable")
                }
                self.running = false
                self.scheduleRetryPump()
            }
            return
        }
```

And the per-job catch classifies:

```swift
            } catch {
                // Printed, not swallowed: the row shows the reason for a
                // terminal failure, but the full error is the only way to
                // diagnose one station without re-deriving it from IWLS by hand.
                print("CHS fit FAILED \(job.id): \(error)")
                await MainActor.run {
                    if ChsError.isPermanent(error) {
                        self.queue.set(job.id, .failed)
                        self.queue.note(job.id, error: Self.reason(error))
                    } else {
                        self.queue.deferRetry(job.id, error: Self.reason(error))
                    }
                }
            }
```

At the end of `run()`, schedule the next pump:

```swift
        await MainActor.run {
            self.running = false
            self.scheduleRetryPump()
        }
```

Add the reason formatter and the `note` helper. In `ChsQueue.swift`:

```swift
    /// Record why a job stopped without touching its clock — the terminal
    /// counterpart to `deferRetry`.
    mutating func note(_ id: String, error: String) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].lastError = error
    }
```

In `ChsFitService.swift`:

```swift
    /// The short half of a failure, for a row to show. The long half stays in
    /// the log.
    nonisolated static func reason(_ error: Error) -> String {
        switch error {
        case let chs as ChsError:
            switch chs {
            case .permanent(let why), .transient(let why): return why
            case .networkDisabled: return "no connection"
            case .yielded: return "stepped aside"
            }
        case let url as URLError: return url.localizedDescription
        default: return (error as NSError).localizedDescription
        }
    }
```

Add connectivity observation. In `ChsFitService`'s stored properties and `init`:

```swift
    private var connectivity: AnyCancellable?
```

At the end of `init()`:

```swift
        observeConnectivity()
```

And the method:

```swift
    /// A link coming back is the best retry signal there is, and it costs
    /// nothing to act on: clear every clock and pump.
    ///
    /// `dropFirst` because `@Published` replays its current value on subscribe,
    /// and `online` is already true on a connected launch. Without it, every
    /// launch would clear backoffs that had just been restored or seeded — the
    /// UI-test hook in Task 11 is the case that catches this.
    private func observeConnectivity() {
        connectivity = Connectivity.shared.$online
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] online in
                guard online else { return }
                Task { @MainActor in
                    // Backoffs only. A permanent failure is not a connectivity
                    // problem, and `retryNow` is the user's call, not the
                    // network's.
                    self?.queue.clearBackoffs()
                    self?.pump()
                }
            }
    }
```

Add `import Combine` at the top of `ChsFitService.swift`.

Update the three callers of `retryFailed()`: `Slackwater/OfflineDownloads.swift:299` becomes `service.retryNow()`.

- [ ] **Step 4: Run the suite**

Run: `./scripts/test.sh`
Expected: `Passed`, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/ChsFitService.swift Slackwater/ChsQueue.swift Slackwater/OfflineDownloads.swift SlackwaterTests/ChsQueueTests.swift
git commit -m "Pump on a clock and on a reconnect, never on a dead path"
```

---

### Task 4: One pacer for every fetcher

`IwlsFetcher` paces per instance. The fit run holds one and each online-gate fetch builds another, so two in flight run at about 48 requests a minute against IWLS's 30-per-minute cap — the app rate-limits itself, then retries into its own 429s.

**Files:**
- Modify: `Slackwater/IwlsClient.swift`
- Test: `SlackwaterTests/IwlsFixtureTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `actor IwlsPacer` with `func wait() async`, and `IwlsFetcher.pacer` (shared).

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/IwlsFixtureTests.swift`:

```swift
    /// Two fetchers are two callers of ONE pacer, or the fit run and an
    /// online-gate fetch together exceed IWLS's 30-per-minute cap.
    func testThePacerSerialisesAcrossFetchers() async {
        let pacer = IwlsPacer(interval: 0.2)
        let start = Date.now
        await pacer.wait()
        await pacer.wait()
        await pacer.wait()
        let elapsed = Date.now.timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(elapsed, 0.4, "three requests are two intervals apart")
        XCTAssertLessThan(elapsed, 1.5, "and no slower than that")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the compile check. Expected: "cannot find 'IwlsPacer' in scope".

- [ ] **Step 3: Write minimal implementation**

In `Slackwater/IwlsClient.swift`, above `IwlsFetcher`:

```swift
/// The one throttle in front of IWLS.
///
/// An actor, and shared, because the pacing has to hold across every caller:
/// the fit run builds one fetcher and each online-gate fetch builds another, so
/// per-instance pacing put ~48 requests a minute against a documented 30, and
/// the retry ladder then spent its attempts on the 429s the app had caused.
actor IwlsPacer {
    private let interval: TimeInterval
    private var last = Date.distantPast

    init(interval: TimeInterval = 2.5) { self.interval = interval }

    /// Returns when the caller may make its request. Serialised by the actor,
    /// so concurrent callers queue rather than collide.
    func wait() async {
        let due = last.addingTimeInterval(interval)
        let gap = due.timeIntervalSinceNow
        if gap > 0 { try? await Task.sleep(for: .seconds(gap)) }
        last = .now
    }
}
```

In `IwlsFetcher`, replace the `lastRequest` property with:

```swift
    /// Shared: see `IwlsPacer`.
    static let pacer = IwlsPacer()
```

and in `get`, replace the two pacing lines:

```swift
            await Self.pacer.wait()
```

Delete `private var lastRequest = Date.distantPast`.

- [ ] **Step 4: Run the suite**

Run: `./scripts/test.sh`
Expected: `Passed`, 0 failed, `testThePacerSerialisesAcrossFetchers` among them.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/IwlsClient.swift SlackwaterTests/IwlsFixtureTests.swift
git commit -m "Pace every IWLS request through one shared throttle"
```

---

### Task 5: Download everything in reach

**Files:**
- Modify: `Slackwater/ChsFitService.swift` (`autoFitSet`)
- Modify: `Slackwater/OfflineDownloads.swift` (`Connectivity`)
- Test: `SlackwaterTests/ChsQueueTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ChsFitService.autoFitSet(lat:lon:constrained:) -> [ChsJob]`, `Connectivity.constrained: Bool`.

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/ChsQueueTests.swift`:

```swift
    /// Everything inside the radius, but in an order that leaves the first
    /// screen exactly as fast as it was: the budgeted nine, then the passes,
    /// then the rest of the harbours.
    func testAutoFitTakesEverythingInReachWithTheBudgetedNineStillFirst() {
        let victoria = (lat: 48.4235, lon: -123.3705)
        let full = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon, constrained: false)
        let near = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon, constrained: true)

        XCTAssertEqual(near.count, ChsFitService.autoFitPorts + ChsFitService.autoFitGates,
                       "Low Data Mode keeps the budgeted set and nothing else")
        XCTAssertGreaterThan(full.count, near.count, "and off it, everything in reach joins")
        XCTAssertEqual(Array(full.prefix(near.count)).map(\.id), near.map(\.id),
                       "the budgeted nine lead either way — the first screen must not slow down")
        XCTAssert(full.allSatisfy {
            distanceKm($0.latitude, $0.longitude, victoria.lat, victoria.lon)
                <= ChsFitService.autoFitRadiusKm
        }, "the radius still bounds the set")
        XCTAssertEqual(Set(full.map(\.id)).count, full.count, "no station is queued twice")

        // Tier 2 is gates: the passes a passage crosses come before the
        // fortieth harbour gauge.
        let tail = Array(full.dropFirst(near.count))
        let firstPort = tail.firstIndex { !$0.isCurrent } ?? tail.count
        let lastGate = tail.lastIndex { $0.isCurrent } ?? -1
        XCTAssertLessThan(lastGate, firstPort, "every remaining gate precedes every remaining port")

        // Away from Canadian water the radius still means zero.
        XCTAssert(ChsFitService.autoFitSet(lat: 42.3601, lon: -71.0589, constrained: false).isEmpty,
                  "a Boston fix downloads no Canadian predictions")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the compile check. Expected: "extra argument 'constrained' in call".

- [ ] **Step 3: Write minimal implementation**

In `Slackwater/ChsFitService.swift`, replace `autoFitSet`:

```swift
    /// The stations a fix downloads on its own.
    ///
    /// Three tiers, in this order:
    ///   1. the budgeted nearest `autoFitPorts` ports and `autoFitGates` gates —
    ///      unchanged, so the first screen still lands in the same ~30 s
    ///   2. every other gate inside the radius
    ///   3. every other port inside the radius
    ///
    /// Gates before ports in the tail because gates are the reason the app
    /// exists and there are 13 of them against 1,058 ports; a passage crosses
    /// passes, not harbour gauges.
    ///
    /// `constrained` is iOS Low Data Mode — the one signal where the user has
    /// actually said "spend less here". It stops at tier 1. Cellular as such is
    /// NOT special-cased: a ship's Starlink presents as Wi-Fi, and a phone on
    /// LTE off the coast is the user who needs this data most.
    static func autoFitSet(lat: Double, lon: Double,
                           constrained: Bool = Connectivity.shared.constrained) -> [ChsJob] {
        func byDistance(_ jobs: [ChsJob]) -> [ChsJob] {
            jobs.sorted {
                let a = distanceKm($0.latitude, $0.longitude, lat, lon)
                let b = distanceKm($1.latitude, $1.longitude, lat, lon)
                return a == b ? $0.id < $1.id : a < b
            }
        }
        let near = candidates.filter {
            distanceKm($0.latitude, $0.longitude, lat, lon) <= autoFitRadiusKm
        }
        let ports = byDistance(near.filter { !$0.isCurrent })
        let gates = byDistance(near.filter { $0.isCurrent })
        let budgeted = Array(ports.prefix(autoFitPorts)) + Array(gates.prefix(autoFitGates))
        guard !constrained else { return budgeted }
        return budgeted + Array(gates.dropFirst(autoFitGates)) + Array(ports.dropFirst(autoFitPorts))
    }
```

In `Slackwater/OfflineDownloads.swift`, `Connectivity` gains the flag:

```swift
    /// iOS Low Data Mode on the current path. The user asking for less is the
    /// only thing that narrows the download set.
    @Published private(set) var constrained = false
```

and in the path handler:

```swift
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            let constrained = path.isConstrained
            Task { @MainActor in
                self?.online = up
                self?.constrained = constrained
            }
        }
```

`adopt` needs no change — it already calls `autoFitSet(lat:lon:)` and the new parameter defaults.

- [ ] **Step 4: Run the suite**

Run: `./scripts/test.sh`
Expected: `Passed`, 0 failed. `notQueued` and the manager's row count change with the wider set; if `OfflineCoverageTests` asserts on a station count, update the assertion to the new set rather than pinning the old number.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/ChsFitService.swift Slackwater/OfflineDownloads.swift SlackwaterTests/ChsQueueTests.swift
git commit -m "Download every station inside the radius, budgeted nine first"
```

---

### Task 6: Online gates onto the same ladder

`attempted` is once per launch per gate, and `failedOnline` is `@State` in the manager — lost when the sheet closes. Both move into the service.

**Files:**
- Modify: `Slackwater/ChsFitService.swift`
- Modify: `Slackwater/OfflineDownloads.swift`
- Test: `SlackwaterTests/ChsQueueTests.swift`

**Interfaces:**
- Consumes: Task 2's `ChsQueue.backoff`.
- Produces: `ChsFitService.onlineState(_ id: String) -> OnlineFetchState`, `ChsFitService.fetchOnline(_ gate: ChsCurrentGateInfo)`, `enum OnlineFetchState { case idle, fetching, deferred(Date), failed(String) }`.

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/ChsQueueTests.swift`:

```swift
    /// An online gate's failure outlives the sheet it happened in, and comes
    /// back on a clock like everything else.
    @MainActor func testAnOnlineGateFailureIsRememberedAndDeferred() {
        let service = ChsFitService.shared
        let gate = ChsCurrentGateInfo.all.first { $0.isOnline }!
        service.resetOnlineStateForTesting()
        XCTAssertEqual(service.onlineState(gate.id), .idle)

        service.noteOnlineFailure(gate.id, error: "dropped", permanent: false, at: t0)
        guard case .deferred(let due) = service.onlineState(gate.id, at: t0) else {
            return XCTFail("a dropped fetch should defer, not fail")
        }
        XCTAssertEqual(due, t0.addingTimeInterval(60))
        XCTAssertEqual(service.onlineState(gate.id, at: t0.addingTimeInterval(61)), .idle,
                       "once the clock runs out it is simply fetchable again")

        service.noteOnlineFailure(gate.id, error: "IWLS metadata has no flood axis",
                                  permanent: true, at: t0)
        XCTAssertEqual(service.onlineState(gate.id, at: t0.addingTimeInterval(3600)),
                       .failed("IWLS metadata has no flood axis"),
                       "a permanent cause does not come back on a clock")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the compile check. Expected: "value of type 'ChsFitService' has no member 'onlineState'".

- [ ] **Step 3: Write minimal implementation**

In `Slackwater/ChsFitService.swift`, replace the `attempted` set:

```swift
    /// Where each online gate stands. Replaces `attempted` (once per launch,
    /// so a gate that failed on a bad minute stayed dead until relaunch) and
    /// the manager's `@State failedOnline` (lost when the sheet closed).
    enum OnlineFetchState: Equatable {
        case idle
        case fetching
        case deferred(Date)
        case failed(String)
    }

    @Published private(set) var onlineStates: [String: OnlineFetchState] = [:]

    /// A gate's state, with a deferral that has run out reading as `.idle` —
    /// the clock is the whole difference between the two.
    func onlineState(_ id: String, at now: Date = appNow()) -> OnlineFetchState {
        guard let state = onlineStates[id] else { return .idle }
        if case .deferred(let due) = state, due <= now { return .idle }
        return state
    }

    private var onlineAttempts: [String: Int] = [:]

    /// Record a failed online fetch: a clock for anything a later try could get
    /// past, a reason for anything it could not.
    func noteOnlineFailure(_ id: String, error: String, permanent: Bool,
                           at now: Date = appNow()) {
        guard !permanent else {
            onlineStates[id] = .failed(error)
            return
        }
        let attempts = (onlineAttempts[id] ?? 0) + 1
        onlineAttempts[id] = attempts
        onlineStates[id] = .deferred(now.addingTimeInterval(ChsQueue.backoff(attempts: attempts)))
    }

    /// Fetch one online gate's window, tracking its state. The manager's row
    /// and the prefetch loop both go through this, so there is one place a
    /// gate's state can be set.
    func fetchOnline(_ gate: ChsCurrentGateInfo) {
        guard Connectivity.shared.online, onlineState(gate.id) != .fetching else { return }
        onlineStates[gate.id] = .fetching
        Task { @MainActor in
            do {
                _ = try await ChsFitService.fetchOnlineWindow(for: gate, from: todayLocal(gate.tz))
                onlineStates[gate.id] = .idle
                onlineAttempts[gate.id] = 0
            } catch {
                noteOnlineFailure(gate.id, error: Self.reason(error),
                                  permanent: ChsError.isPermanent(error))
            }
        }
    }

#if DEBUG
    /// Unit tests share the singleton; this is the only way to start clean.
    func resetOnlineStateForTesting() {
        onlineStates = [:]
        onlineAttempts = [:]
    }
#endif
```

In `prefetchOnlineGates`, replace the `attempted` guard with the state check:

```swift
        for gate in gates where onlineState(gate.id) == .idle {
```

and inside the serial `Task`, replace `attempted.insert(gate.id)` and the bare `try?` with a call through the new seam:

```swift
            while !onlinePending.isEmpty {
                let gate = onlinePending.removeFirst()
                if ChsModelStore.loadOnline(gate.id)?.block(covering: todayLocal(gate.tz)) != nil { continue }
                onlineStates[gate.id] = .fetching
                do {
                    _ = try await Self.fetchOnlineWindow(for: gate, from: nil)
                    onlineStates[gate.id] = .idle
                    onlineAttempts[gate.id] = 0
                } catch {
                    noteOnlineFailure(gate.id, error: Self.reason(error),
                                      permanent: ChsError.isPermanent(error))
                }
            }
```

Delete `private var attempted: Set<String> = []`.

In `Slackwater/OfflineDownloads.swift`, delete `@State private var fetchingOnline` and `@State private var failedOnline`, delete the private `fetch(_:)` method, and route the row's button and the reconnect handler through `service.fetchOnline(gate)`. `managedState`'s online branch reads the service:

```swift
        case .online(let gate):
            switch service.onlineState(gate.id) {
            case .fetching: return (.downloading, nil)
            case .failed: return (.failed, nil)
            case .deferred: return (.queued, nil)
            case .idle: break
            }
            guard onlineWindow(gate) != nil else { return (.notDownloaded, nil) }
            let days = remainingDays(gate) ?? 0
            return (days < 0 ? .expired : .available, days)
```

and `failedCount` becomes:

```swift
    private var failedCount: Int {
        queue.failed + onlineGates.filter {
            if case .failed = service.onlineState($0.id) { return true }
            return false
        }.count
    }
```

- [ ] **Step 4: Run the suite**

Run: `./scripts/test.sh`
Expected: `Passed`, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/ChsFitService.swift Slackwater/OfflineDownloads.swift SlackwaterTests/ChsQueueTests.swift
git commit -m "Give online gates the same retry clock, in the service"
```

---

### Task 7: Progress and a measured estimate

**Files:**
- Modify: `Slackwater/ChsQueue.swift`
- Modify: `Slackwater/ChsFitService.swift`
- Modify: `Slackwater/IwlsClient.swift`
- Test: `SlackwaterTests/ChsQueueTests.swift`

**Interfaces:**
- Consumes: Task 4's pacer.
- Produces: `ChsJob.done: Int`, `ChsJob.total: Int`, `ChsQueue.setProgress(_:done:total:)`, `IwlsFetcher.observedSecondsPerRequest: Double`, `ChsJob.estimatedSeconds(perRequest:)`.

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/ChsQueueTests.swift`:

```swift
    /// A row that says "Downloading" for four minutes with nothing moving is
    /// indistinguishable from a stalled one.
    func testAJobCarriesItsOwnProgress() {
        var q = queue()
        q.set("near", .downloading)
        q.setProgress("near", done: 3, total: 11)
        XCTAssertEqual(q.job("near")?.done, 3)
        XCTAssertEqual(q.job("near")?.total, 11)
        // Progress is per attempt: a deferral resets it so the row cannot claim
        // 9 of 11 while it waits to start over.
        q.deferRetry("near", error: "dropped", at: t0)
        XCTAssertEqual(q.job("near")?.done, 0)
    }

    /// The estimate stops being a pacing constant. On a ship link the real
    /// number is several times the 2.5 s floor, and the constant made the
    /// manager promise minutes where it meant an hour.
    func testTheEstimateScalesWithObservedRequestTime() {
        let port = job("p", 48.4, -123.3)
        let fast = port.estimatedSeconds(perRequest: 2.5)
        let slow = port.estimatedSeconds(perRequest: 10)
        XCTAssertEqual(slow, fast * 4, accuracy: 0.001)
        XCTAssertGreaterThan(job("g", 48.4, -123.3, current: true, days: 210)
                                .estimatedSeconds(perRequest: 2.5), fast)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the compile check. Expected: "value of type 'ChsQueue' has no member 'setProgress'".

- [ ] **Step 3: Write minimal implementation**

In `Slackwater/ChsQueue.swift`, add to `ChsJob`:

```swift
    /// Requests finished and expected for the attempt in flight. Per attempt,
    /// not cumulative: a deferred job starts its count over, or the row claims
    /// progress it will not keep.
    var done = 0
    var total = 0
```

Replace `estimatedSeconds` with a parameterised version, keeping the old one as a default-argument call:

```swift
    /// Requests this job costs: the chunk plan, doubled for a gate's two
    /// series, plus a gate's one metadata call.
    var requestCount: Double {
        let chunks = (fitDays / 7).rounded(.up) + 1
        return chunks * (isCurrent ? 2 : 1) + (isCurrent ? 1 : 0)
    }

    /// Wall-clock cost at a given seconds-per-request. The caller passes what
    /// the fetcher has actually been seeing, so the manager's estimate tracks
    /// the link instead of a constant.
    func estimatedSeconds(perRequest: Double = 2.5) -> Double {
        requestCount * perRequest
    }
```

Add:

```swift
    mutating func setProgress(_ id: String, done: Int, total: Int) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].done = done
        jobs[i].total = total
    }
```

In `deferRetry`, reset progress — add before the status line:

```swift
        jobs[i].done = 0
```

Update `waitSeconds` and any `estimatedSeconds` reference in `ChsQueue` and `OfflineDownloads` to the call form `estimatedSeconds(perRequest: IwlsFetcher.observedSecondsPerRequest)`.

In `Slackwater/IwlsClient.swift`, add the observation to `IwlsPacer` (it already serialises every request, so it is the one place that sees them all):

```swift
    /// A slow exponential average of seconds between completed requests, seeded
    /// at the pacing floor. The manager's estimate reads this, so "about 12 min"
    /// means twelve minutes on THIS link.
    private(set) var observedInterval: TimeInterval = 2.5

    /// Called by the fetcher when a request completes, successfully or not.
    func observe(_ seconds: TimeInterval) {
        // ponytail: fixed 0.2 weight. Tune only if the estimate visibly lags a
        // link that changed.
        observedInterval += 0.2 * (max(seconds, 0) - observedInterval)
    }
```

In `IwlsFetcher`:

```swift
    /// What the link has actually been doing, for the manager's estimate.
    /// Reading an actor's state synchronously is not possible, so the fetcher
    /// mirrors it here after each request.
    private(set) nonisolated(unsafe) static var observedSecondsPerRequest: Double = 2.5
```

and in `get`, around the request:

```swift
            await Self.pacer.wait()
            let began = Date.now
            let outcome: Result<Int, Error>
            var retryAfter: Double?
            do {
                …
            } catch {
                outcome = .failure(error)
            }
            await Self.pacer.observe(Date.now.timeIntervalSince(began))
            Self.observedSecondsPerRequest = await Self.pacer.observedInterval
```

Place the `observe`/mirror lines after the do/catch and before the retry decision, so a returned 200 also records. For the success path, record before `return data` by hoisting the timing into a small helper:

```swift
    /// One request, timed, with its outcome classified. Split out so the
    /// success path records its duration too.
    private func attempt(_ url: URL) async -> (data: Data?, outcome: Result<Int, Error>, retryAfter: Double?) {
        await Self.pacer.wait()
        let began = Date.now
        defer {
            let elapsed = Date.now.timeIntervalSince(began)
            Task { await Self.pacer.observe(elapsed)
                   Self.observedSecondsPerRequest = await Self.pacer.observedInterval }
        }
        do {
            let (data, response) = try await Self.session.data(from: url)
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            if code == 200 { return (data, .success(200), nil) }
            return (nil, .success(code),
                    http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
        } catch {
            return (nil, .failure(error), nil)
        }
    }
```

and `get`'s loop body becomes:

```swift
            let result = await attempt(url)
            if let data = result.data { return data }
            guard let delay = Self.retryDelay(after: result.outcome, attempt: attempt,
                                              retryAfter: result.retryAfter) else {
                switch result.outcome {
                case .success(let code):
                    throw (400...499).contains(code) ? ChsError.permanent("HTTP \(code)")
                                                     : ChsError.transient("HTTP \(code)")
                case .failure(let error): throw error
                }
            }
            try await Task.sleep(for: .seconds(delay))
```

In `Slackwater/ChsFitService.swift`, publish progress from both fit paths. In `fit`, before the loop and inside it:

```swift
        let plan = Self.chunkPlan(days: Self.tideFitDays, end: end)
        await MainActor.run { self.queue.setProgress(info.id, done: 0, total: plan.count) }
        var samples: [ChsSample] = []
        for (index, chunk) in plan.enumerated() {
            samples += try await fetcher.wlp(stationID: station.id, chunk: chunk)
            await MainActor.run { self.queue.setProgress(info.id, done: index + 1, total: plan.count) }
            if await MainActor.run(body: { self.queue.shouldYield(running: info.id) }) { throw ChsError.yielded }
        }
```

In `fitCurrent`, the same shape with `total: plan.count * 2 + 1` (two series and the metadata call), incrementing after each `series` call and once after `metadata`.

- [ ] **Step 4: Run the suite**

Run: `./scripts/test.sh`
Expected: `Passed`, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/ChsQueue.swift Slackwater/ChsFitService.swift Slackwater/IwlsClient.swift SlackwaterTests/ChsQueueTests.swift
git commit -m "Publish per-job progress and estimate from the observed rate"
```

---

### Task 8: The manager reports readiness

**Files:**
- Modify: `Slackwater/OfflineDownloads.swift`
- Test: `SlackwaterTests/ChsQueueTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 6, 7.
- Produces: `ManagedDownloadState.retrying`, `downloadSortRank` handling for it, `rowStatus(_ job: ChsJob, at: Date) -> String`.

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/ChsQueueTests.swift`:

```swift
    /// Every row says what the app is doing, and never asks the user to fix it.
    @MainActor func testRowStatusSaysWhatIsHappening() {
        var q = ChsQueue([job("a", 48.4, -123.3)])
        XCTAssertEqual(rowStatus(q.job("a")!, at: t0), "Waiting")

        q.set("a", .downloading)
        q.setProgress("a", done: 12, total: 31)
        XCTAssertEqual(rowStatus(q.job("a")!, at: t0), "Downloading · 12 of 31")

        q.deferRetry("a", error: "dropped", at: t0)
        XCTAssertEqual(rowStatus(q.job("a")!, at: t0), "Retrying in 1 min")
        XCTAssertEqual(rowStatus(q.job("a")!, at: t0.addingTimeInterval(30)), "Retrying in 1 min",
                       "rounded up, never a ticking countdown")

        q.set("a", .failed)
        q.note("a", error: "IWLS serves no wlp here")
        XCTAssertEqual(rowStatus(q.job("a")!, at: t0), "Unavailable · IWLS serves no wlp here")

        q.set("a", .ready)
        XCTAssertEqual(rowStatus(q.job("a")!, at: t0), "Available offline")
    }

    func testRetryingSortsWithTheQueueNotWithFailures() {
        XCTAssertLessThan(downloadSortRank(.queued, remainingDays: nil),
                          downloadSortRank(.failed, remainingDays: nil))
        XCTAssertEqual(downloadSortRank(.retrying, remainingDays: nil),
                       downloadSortRank(.queued, remainingDays: nil) + 1,
                       "a deferred job sits with the queue, just behind it")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the compile check. Expected: "cannot find 'rowStatus' in scope".

- [ ] **Step 3: Write minimal implementation**

In `Slackwater/OfflineDownloads.swift`:

```swift
enum ManagedDownloadState: Equatable {
    case downloading, queued, retrying, failed, expired, notDownloaded, available, permanent
}

func downloadSortRank(_ state: ManagedDownloadState, remainingDays: Int?) -> Int {
    switch state {
    case .downloading: 0
    case .queued: 100_000
    // A job on a clock is queued work, not a problem: it sits with the queue.
    case .retrying: 100_001
    case .failed, .expired, .notDownloaded: 200_000
    case .available where (remainingDays ?? 0) <= 3: 200_000
    case .available: 300_000 + (remainingDays ?? 0)
    case .permanent: 400_000
    }
}

/// One row's worth of state, as a sentence about what the app is doing.
///
/// Free function and pure so the copy can be tested without building a view —
/// this is the language the whole change is about.
@MainActor func rowStatus(_ job: ChsJob, at now: Date = appNow()) -> String {
    if ChsFitService.shared.isProvisional(job.id) { return "Refining…" }
    switch job.status {
    case .ready: return "Available offline"
    case .failed: return job.lastError.map { "Unavailable · \($0)" } ?? "Unavailable"
    case .downloading:
        return job.total > 0 ? "Downloading · \(job.done) of \(job.total)" : "Downloading…"
    case .pending:
        guard let due = job.retryAfter, due > now else {
            guard Connectivity.shared.online else { return "Waiting for signal" }
            return ChsFitService.shared.queue.position(job.id)
                .map { $0 <= 1 ? "Waiting · next" : "Waiting · \(ordinal($0)) in line" } ?? "Waiting"
        }
        // Rounded up and coarse. A ticking countdown claims a precision the
        // backoff does not have, and invites watching rather than sailing.
        let minutes = max(1, Int((due.timeIntervalSince(now) / 60).rounded(.up)))
        return "Retrying in \(minutes) min"
    }
}
```

Replace the row's `statusText`/`statusTint` with `rowStatus` and a tint that keeps amber scarce:

```swift
    private func statusTint(_ job: ChsJob) -> Color {
        if service.isProvisional(job.id) { return SN.amber }
        switch job.status {
        // Amber is for something being wrong. A clock is the app working.
        case .failed: return SN.amber
        case .downloading, .ready: return SN.leaf
        case .pending: return SN.foam.opacity(0.5)
        }
    }
```

In `managedState`'s fitted branch, add the deferred case:

```swift
        case .fitted(let job):
            if job.status == .downloading || service.isProvisional(job.id) { return (.downloading, nil) }
            if job.status == .failed { return (.failed, nil) }
            if job.status == .pending {
                return ((job.retryAfter ?? .distantPast) > appNow() ? .retrying : .queued, nil)
            }
            return (.permanent, nil)
```

Delete the row's `Retry` button entirely — the row's own tap opens the station, which promotes and retries it. The summary's action becomes:

```swift
            if deferredCount > 0 {
                Button { service.retryNow() } label: {
                    Text("Retry now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SN.leaf)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("downloads-retry-now")
            }
```

with:

```swift
    private var deferredCount: Int { queue.deferred() }
```

`summaryLine`'s downloading branch uses the measured estimate:

```swift
        return "Downloading Canadian tidal and current predictions… Nearest to you first, and whatever you open jumps the queue. About \(durationPhrase(remainingSeconds)) for the rest at the current speed. Expiring downloads can be refreshed below.\(onDemandLine)"
```

and `remainingSeconds`:

```swift
    private var remainingSeconds: Double {
        let rate = IwlsFetcher.observedSecondsPerRequest
        return queue.jobs.filter { $0.status == .pending || $0.status == .downloading }
            .reduce(0) { $0 + $1.estimatedSeconds(perRequest: rate) }
    }
```

`durationPhrase` already says "about N minutes", so drop the leading "About " if the phrase begins with "about" — simplest is to change the sentence to `"\(durationPhrase(remainingSeconds).prefix(1).uppercased())\(durationPhrase(remainingSeconds).dropFirst()) for the rest at the current speed."` Keep it readable instead:

```swift
        return "Downloading Canadian tidal and current predictions… Nearest to you first, and whatever you open jumps the queue. Usually \(durationPhrase(remainingSeconds)) for the rest at the current speed. Expiring downloads can be refreshed below.\(onDemandLine)"
```

The indicator's tint keeps amber for real trouble only:

```swift
    private var tint: Color {
        switch state {
        case .downloading: service.queue.failed > 0 ? SN.amber : SN.leaf
        case .online: service.queue.failed > 0 ? SN.amber : SN.foam.opacity(0.8)
        case .offline: service.queue.complete ? SN.leaf : SN.amber
        }
    }
```

(unchanged — `queue.failed` now counts only permanent failures, which is exactly the rule the spec asks for; add a comment saying so.)

- [ ] **Step 4: Run the suite**

Run: `./scripts/test.sh`
Expected: `Passed`, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/OfflineDownloads.swift SlackwaterTests/ChsQueueTests.swift
git commit -m "Say what the download manager is doing, not what failed"
```

---

### Task 9: Cards and the waiting page follow the queue

**Files:**
- Modify: `Slackwater/CardStatus.swift`
- Modify: `Slackwater/StationCard.swift`
- Modify: `Slackwater/ChsDetailView.swift`
- Test: `SlackwaterTests/ChsQueueTests.swift`

**Interfaces:**
- Consumes: Task 2's clock.
- Produces: `CardStatus.retrying`, `cardStatus(id:) -> CardStatus` reading the job directly.

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/ChsQueueTests.swift`:

```swift
    func testRetryingCardStatusReadsAsWorkNotFailure() {
        let status = CardStatus.retrying
        XCTAssertEqual(status.label, "Retrying")
        XCTAssertEqual(status.tint, SN.foam.opacity(0.85), "a clock is not a warning")
        XCTAssertFalse(status.showsPlaceholder == false, "it is still a card with no reading")
        XCTAssert(status.accessibilityLabel.contains("on its own"),
                  "VoiceOver must say the app retries by itself")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the compile check. Expected: "type 'CardStatus' has no member 'retrying'".

- [ ] **Step 3: Write minimal implementation**

In `Slackwater/CardStatus.swift`, add the case and its four switch arms:

```swift
    /// The last attempt did not get there and the app is waiting to try again
    /// by itself. Distinct from `.failed`, which is the end of the line.
    case retrying
```

```swift
    var showsPlaceholder: Bool {
        switch self {
        case .downloading, .queued, .notDownloaded, .retrying: true
        default: false
        }
    }
```

```swift
        case .retrying: "arrow.clockwise"
```

```swift
        case .retrying: "Retrying"
```

```swift
        case .retrying: return "Retrying — the download didn't finish and Slackwater tries again on its own. \(once)"
```

```swift
        case .queued, .offline, .notDownloaded, .retrying: SN.foam.opacity(0.85)
```

In `Slackwater/StationCard.swift`, collapse the three `pending(fitting:failed:)` helpers onto the job. Replace `cardStatus`:

```swift
/// Where a fittable CHS station stands, in precedence order: what is happening
/// right now beats what is merely true.
///
/// Reads the job rather than taking `fitting`/`failed` flags from the caller —
/// three call sites passing their own booleans was three ways for a card to
/// disagree with the queue it is describing.
@MainActor func cardStatus(id: String) -> CardStatus {
    guard let job = ChsFitService.shared.queue.job(id) else {
        // Not in the download set at all (M53 — most of Canada). Opening it is
        // what downloads it, so this is the honest state connected or not.
        return .notDownloaded
    }
    switch job.status {
    case .downloading: return .downloading
    case .failed: return .failed
    case .ready: return .queued   // unreachable: a ready job renders its reading
    case .pending:
        if (job.retryAfter ?? .distantPast) > appNow() { return .retrying }
        return Connectivity.shared.online ? .queued : .offline
    }
}
```

Change each of the three `pending(...)` helpers to take no flags:

```swift
    private func pending() -> ChsPendingCard {
        ChsPendingCard(name: info.name, region: info.region, id: info.id, km: km,
                       status: cardStatus(id: info.id))
    }
```

(and the gate/derived variants with their own `id` and `cardStatus(id:)` argument), and change all nine call sites from `pending(fitting: true)` / `pending(failed: true)` / `pending()` to `pending()`.

In `Slackwater/ChsDetailView.swift`, `ChsWaitingView.status` reads the clock:

```swift
    private var status: CardStatus {
        if !net.online { return .offline }
        guard let job else { return .queued }
        switch job.status {
        case .failed: return .failed
        case .downloading: return .downloading
        case .pending: return (job.retryAfter ?? .distantPast) > appNow() ? .retrying : .queued
        case .ready: return .queued
        }
    }
```

`title` gains its arm:

```swift
        case .retrying: "Retrying"
```

`headline` gains:

```swift
        if status == .retrying {
            return "\(what) didn't finish downloading. Trying again shortly."
        }
```

`expectation` gains, before the queued branch:

```swift
        if status == .retrying {
            return "Nothing to tap — Slackwater retries on its own, and again whenever your signal comes back. Once it downloads, this station works offline, with no signal, for good."
        }
```

and the downloading branch shows progress:

```swift
        if job?.status == .downloading, let job, job.total > 0 {
            return "Downloading \(job.done) of \(job.total) requests. It downloads once; after that this station works offline, with no signal, for good."
        }
```

The failed card's action stays "Retry" and still calls `service.promote(jobID)`, which now also clears the clock.

- [ ] **Step 4: Run the suite**

Run: `./scripts/test.sh`
Expected: `Passed`, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/CardStatus.swift Slackwater/StationCard.swift Slackwater/ChsDetailView.swift SlackwaterTests/ChsQueueTests.swift
git commit -m "Read card and waiting-page state from the job itself"
```

---

### Task 10: Charts follow what the user chose, and stop asking for a retry

**Files:**
- Modify: `Slackwater/ChartPacks.swift`
- Modify: `Slackwater/OfflineDownloads.swift` (`chartsLine`, the card's button)
- Test: `SlackwaterTests/ChartPackTests.swift`

**Interfaces:**
- Consumes: Task 5's widened download set (the reason this task exists).
- Produces: `desiredChartPacks` unchanged in signature; `ChartPackManager` reconciles on reconnect.

- [ ] **Step 1: Write the failing test**

Add to `SlackwaterTests/ChartPackTests.swift`:

```swift
    /// Every downloaded station used to get its own z9–z12 disc. With the
    /// radius-wide download set that is ~100 discs and several hundred MB of
    /// satellite imagery for ground nobody has looked at.
    func testStationDiscsCoverChosenStationsNotEveryDownload() {
        let fix = (lat: 48.4235, lon: -123.3705)
        let chosen = [(id: "chs-victoria-harbour", lat: 48.4243, lon: -123.3709)]
        let specs = desiredChartPacks(fix: fix, stations: chosen)
        let discs = specs.filter { $0.key.hasPrefix("station/") }
        XCTAssertEqual(discs.count, 1, "one disc per chosen station, and no more")
        XCTAssert(specs.contains { $0.key == "world" })
        XCTAssertEqual(specs.filter { $0.key.hasPrefix("area/") }.count, 9,
                       "the 3×3 neighbourhood still covers where the boat is")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the compile check. Expected: PASS — `desiredChartPacks` is already pure and takes the station list it is given. This test pins the contract; the change is at the call site, so run it, confirm green, and move to Step 3.

- [ ] **Step 3: Write minimal implementation**

In `Slackwater/ChartPacks.swift`, `reconcile()` stops feeding the download set into station discs:

```swift
        // Favorites and stations the user has actually opened — NOT the
        // download set. Since the set widened to the whole radius, following it
        // would mean ~100 z9–z12 discs, several hundred MB of imagery, for
        // ground nobody has looked at. The z5 area cells below still cover the
        // neighbourhood at every zoom the chart needs to be useful there.
        let chosen = Set(FavoritesStore.shared.ids + ChsFitService.shared.openedStationIDs)
            .compactMap { id -> (String, Double, Double)? in
                guard let item = StationItem.byId[id] else { return nil }
                return (id, item.latitude, item.longitude)
            }
        let desired = desiredChartPacks(fix: fix, stations: chosen)
```

and the subscription that drove it changes from the ready-jobs map to the favorites store only — delete the `ChsFitService.shared.$queue` sink and replace with:

```swift
        // A station the user opens gets chart detail; the queue no longer does.
        ChsFitService.shared.$openedStationIDs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setNeedsReconcile() }
            .store(in: &cancellables)
```

Add the reconnect reconcile at the end of `start`:

```swift
        // Packs resume themselves, but a pack that failed while offline is only
        // retried when something asks. A link coming back is that something.
        Connectivity.shared.$online
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setNeedsReconcile() }
            .store(in: &cancellables)
```

In `Slackwater/ChsFitService.swift`, publish what `promote` already tracks — add the stored property and set it in `promote`:

```swift
    /// Stations the user has opened this install. Drives chart detail coverage
    /// (`ChartPacks`), which follows what someone chose rather than what the
    /// queue happened to download.
    /// ponytail: in memory, so it resets on relaunch and the discs rebuild from
    /// favorites. Persist it if a rebuild ever costs a user real bytes.
    @Published private(set) var openedStationIDs: [String] = []
```

in `promote(_:)`, after the existing body:

```swift
        if !openedStationIDs.contains(id) { openedStationIDs.append(id) }
```

In `Slackwater/OfflineDownloads.swift`, `chartsLine`'s failure branch stops asking:

```swift
        if state.failed > 0 {
            return "Some map areas haven't finished.\(held) They pick up again on their own when you're connected."
        }
```

and the card's button appears only when there is something to top up:

```swift
            if net.online, state.total > 0, state.ready == state.total {
                Button { charts.refresh() } label: {
                    Text("Refresh charts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SN.leaf)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("charts-refresh")
            }
```

- [ ] **Step 4: Run the suite**

Run: `./scripts/test.sh`
Expected: `Passed`, 0 failed. If a UI test asserts on `charts-refresh` being present mid-download, update it — the button is now absent until every pack is complete.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/ChartPacks.swift Slackwater/ChsFitService.swift Slackwater/OfflineDownloads.swift SlackwaterTests/ChartPackTests.swift
git commit -m "Give chart detail to chosen stations, and stop asking for chart retries"
```

---

### Task 11: UI tests for the states a user actually sees

**Files:**
- Modify: `Slackwater/ChsFitService.swift` (launch flag)
- Modify: `SlackwaterUITests/OfflineCoverageTests.swift`
- Test: same file

**Interfaces:**
- Consumes: Tasks 2, 8, 9.
- Produces: `-chsDeferOnly <id,id>` launch flag.

- [ ] **Step 1: Write the failing test**

In `SlackwaterUITests/OfflineCoverageTests.swift`, replace `testDownloadsRowRetryButtonWinsOverRowTap` — the Retry pill it asserts on is gone — with:

```swift
    /// The row's own tap is the retry now: it opens the station, and opening a
    /// station promotes it and clears its clock. There is no pill to miss.
    func testTappingADeferredRowOpensTheStationAndClearsItsClock() throws {
        // `-networkKillSwitch` with `-connectivityOnline`: every IWLS request
        // throws before the socket, while `Connectivity` reports a link — so
        // the row says "Retrying in", not "Waiting for signal", and nothing
        // real is fetched.
        let app = launch("-seedGate", "-chsResetModels", "-networkKillSwitch",
                         "-connectivityOnline",
                         "-chsDeferOnly", "chs-victoria-harbour",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")  // Victoria

        openDownloads(app)

        let row = app.descendants(matching: .any)["download-row-chs-victoria-harbour"].firstMatch
        XCTAssert(row.appears(within: 5), "the seeded deferred row is missing")
        XCTAssert(reachInSheet(row, in: app),
                  "download-row-chs-victoria-harbour exists but never became hittable")
        XCTAssert(row.label.contains("Retrying in"),
                  "a deferred row must say the app is retrying, got \"\(row.label)\"")
        XCTAssertFalse(row.buttons["Retry"].exists, "the Retry pill is gone from rows")

        row.tap()
        XCTAssert(app.descendants(matching: .any)["chs-waiting-warning"].appears(within: 5),
                  "tapping the row did not open the station")
    }

    /// The summary's one action, and it appears only while something is waiting.
    func testRetryNowAppearsOnlyWhileSomethingIsDeferred() throws {
        let app = launch("-seedGate", "-chsResetModels", "-networkKillSwitch",
                         "-connectivityOnline",
                         "-chsDeferOnly", "chs-victoria-harbour",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openDownloads(app)

        let retry = app.buttons["downloads-retry-now"].firstMatch
        XCTAssert(retry.appears(within: 5), "a deferred job should offer Retry now")
        XCTAssert(reachInSheet(retry, in: app), "Retry now exists but never became hittable")
    }
```

`launch(_:)` is variadic, and `openDownloads(_:)`, `reachInSheet(_:in:)` and `waitFor(_:_:)` come from `ScreenshotTestCase`, which `OfflineCoverageTests` already subclasses. Follow the file's existing launch-flag set (`-seedGate`, `-fixLat`/`-fixLon`) so the seeded station is actually in the download set.

- [ ] **Step 2: Run test to verify it fails**

Run: `SLACKWATER_ONLY=OfflineCoverageTests ./scripts/test.sh`
Expected: failure — the app does not know `-chsDeferOnly`, so the row says "Waiting".

- [ ] **Step 3: Write minimal implementation**

In `Slackwater/ChsFitService.swift`, beside `failOnly`:

```swift
    /// UI-test hook: `-chsDeferOnly <id,id>` puts those jobs on a retry clock at
    /// launch. A deferred row otherwise needs a real transient failure, which is
    /// not something a fast test can arrange. `-chsFailOnly` keeps meaning
    /// PERMANENT, which is now a different row.
    private static let deferOnly: Set<String> = {
        guard let at = CommandLine.arguments.firstIndex(of: "-chsDeferOnly"),
              CommandLine.arguments.indices.contains(at + 1) else { return [] }
        return Set(CommandLine.arguments[at + 1].split(separator: ",").map(String.init))
    }()
```

and in `markFailOnly`, which runs at init and on every adopt, add:

```swift
        for id in Self.deferOnly where queue.job(id) != nil {
            // A long clock: the test asserts on the row, never waits it out.
            queue.deferRetry(id, error: "seeded by -chsDeferOnly")
            queue.setProgress(id, done: 0, total: 0)
        }
```

Because `deferRetry` increments `attempts` on every adopt, guard it:

```swift
        for id in Self.deferOnly where queue.job(id)?.retryAfter == nil {
```

- [ ] **Step 4: Run the suite**

Run: `./scripts/test.sh`
Expected: `Passed`, 0 failed, both new UI cases among them.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/ChsFitService.swift SlackwaterUITests/OfflineCoverageTests.swift
git commit -m "Cover the deferred row and Retry now in UI tests"
```

---

### Task 12: Verify on a throttled link, and write the PR

Nothing above demonstrates the experience this work exists for. The offline suite proves the logic; a lossy link proves the feel.

**Files:**
- Modify: `docs/superpowers/plans/2026-09-14-resilient-downloads.md` (tick the boxes)

- [ ] **Step 1: Run the full offline suite on both devices**

Run: `./scripts/test.sh --full`
Read `build/results-full-*.xcresult`. Record counts and skips.

- [ ] **Step 2: Run the live smoke**

Run: `./scripts/test.sh --live`
This is the only lane that touches real IWLS. A failure here after the `resolution=FIFTEEN_MINUTES` and retry changes is a compatibility signal worth reading carefully, not a flake to re-run past.

- [ ] **Step 3: Throttled-link pass on a device**

On a device with Network Link Conditioner set to a lossy profile (3% loss, high latency):

1. Delete and reinstall, grant location, and watch a first run through. The nearest port should become readable in well under a minute.
2. Turn the conditioner to 100% loss mid-run. Rows should move to "Retrying in N min", not "Download failed", and the indicator should not go amber.
3. Restore the link. Everything should resume without a tap.
4. Lock the phone mid-chunk for a minute, unlock. The job should carry on rather than fail.
5. Open a station near the back of the queue. It should jump the queue and start within a few seconds.

Record what each step actually did.

- [ ] **Step 4: Open the PR**

Follow the `pr-writing` skill. The body must carry: what the download set now covers and roughly what it costs, the backoff ladder and what counts as permanent, the chart-disc decision and why, the copy changes as a before/after list, and a verification section separating what ran offline from what ran on a device. Say plainly which of the five device steps were done and which were not.

```bash
git push -u origin <branch>
gh pr create --base main --title "<title>" --body "<body>"
```

---

## Self-Review

**Spec coverage.** Widened radius set (Task 5), Low Data Mode (5), chart discs (10), backoff ladder and permanent narrowing (1, 2, 3), clearing on promote/reconnect/Retry now (2, 3), online gates on the ladder with state in the service (6), shared pacer (4), pump gated on connectivity with a rising edge (3), manager rows and copy (8), progress (7), measured estimate (7), indicator amber rule (8), `CardStatus.retrying` and collapsed card sites (9), waiting page (9), chart card copy and reconnect reconcile (10), UI tests including the `-chsFailOnly` change (11), device pass (12). Out-of-scope items are absent, as intended.

**Types.** `deferRetry(_:error:at:)`, `nextPending(at:)`, `earliestRetry(after:)`, `deferred(at:)`, `backoff(attempts:)`, `clearBackoffs()`, `retryNow()`, `note(_:error:)`, `setProgress(_:done:total:)`, `estimatedSeconds(perRequest:)`, `ChsError.permanent`/`.transient`/`.isPermanent`, `OnlineFetchState`, `onlineState(_:at:)`, `noteOnlineFailure(_:error:permanent:at:)`, `fetchOnline(_:)`, `openedStationIDs`, `CardStatus.retrying`, `ManagedDownloadState.retrying`, `rowStatus(_:at:)`, `IwlsPacer.wait()`/`observe(_:)`/`observedInterval`, `IwlsFetcher.observedSecondsPerRequest`, `-chsDeferOnly`. Each is defined in the task that introduces it and used with the same spelling afterwards.

**Known risk.** Task 7's `nonisolated(unsafe) static var observedSecondsPerRequest` is a mutable static read from the main actor and written from the fetcher. It is a display-only number and a torn read is a slightly stale estimate, which is why it is not worth an actor hop on the render path — but if Swift 6 strict concurrency rejects it in this target, make it an `@MainActor` property on `ChsFitService` updated from the same place instead.
