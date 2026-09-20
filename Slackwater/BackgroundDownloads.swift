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
import os

enum BackgroundDownloads {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.openwaters.slackwater",
                                        category: "BackgroundDownloads")

    /// The wildcard, matching `BGTaskSchedulerPermittedIdentifiers`. Built from
    /// the bundle id so the two cannot drift; a stale literal fails
    /// registration silently. Nothing outside this file reads it.
    private static var pattern: String { (Bundle.main.bundleIdentifier ?? "") + ".downloads.*" }

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
        guard registered else {
            // The one failure the derived-identifier design exists to
            // prevent: an id outside BGTaskSchedulerPermittedIdentifiers (a
            // stale bundle-id literal, most likely), a duplicate
            // registration this session, or the wildcard pattern itself
            // (never permitted). `register` reports it as a plain `false`
            // with no throw and no callback — on a device that is
            // indistinguishable from "the feature does nothing" unless it
            // is logged here.
            logger.error("BGTaskScheduler registration failed for \(id, privacy: .public)")
            return
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: id,
            title: "Downloading tide stations",
            subtitle: "\(queue.ready) of \(queue.total)")
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Same failure class as a failed registration can land here too
            // (an id outside the permitted list), alongside the routine
            // .unavailable in the Simulator or with Background App Refresh
            // off. None of this should surface to the user — the foreground
            // run continues regardless — but a permitted-identifiers
            // mismatch must leave a trace somewhere, and this is it.
            logger.error("BGTaskScheduler submit failed for \(id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Bridges `task.expirationHandler` (called by the system, on its own
    /// queue, at any time — including before the poll `Task` in `run(_:)`
    /// below has even been created) with that poll task's own completion.
    ///
    /// The hazard this closes: `task.expirationHandler` is assigned first,
    /// but "first" only orders it against the *rest of this function*, not
    /// against the system itself. A bare `var poll: Task<Void, Never>?`
    /// captured by the handler has a real window where expiry runs before
    /// `poll` is assigned, finds it `nil`, and cancels nothing — and then
    /// nothing ever calls `setTaskCompleted` for that run, because the poll
    /// task never gets a turn to notice `Task.isCancelled`. Marking that
    /// `var` `nonisolated(unsafe)` silences the compiler's data-race
    /// warning; it does not order the write against the read, which is
    /// exactly what the lock below provides instead.
    ///
    /// Do not simplify this back to a bare `var poll` — that reintroduces
    /// both the lost-cancellation bug and the unsynchronized access at once.
    private final class ExpiryGate: @unchecked Sendable {
        private let lock = NSLock()
        private var poll: Task<Void, Never>?
        private var expired = false

        /// Called from `task.expirationHandler`, on whatever queue the
        /// system chooses. Cancels the poll task if it is already running;
        /// otherwise just records that expiry won the race, which `attach`
        /// below checks before ever creating the poll task.
        func expire() {
            lock.lock()
            expired = true
            let toCancel = poll
            lock.unlock()
            toCancel?.cancel()
        }

        /// Creates the poll task via `makePoll` and stores it — unless
        /// expiry already fired, in which case `makePoll` is never called
        /// and this returns `false`. The caller must complete the
        /// `BGContinuedProcessingTask` itself in that case: with no poll
        /// task created, nothing else ever will.
        func attach(_ makePoll: () -> Task<Void, Never>) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !expired else { return false }
            poll = makePoll()
            return true
        }
    }

    private static func run(_ task: BGContinuedProcessingTask) {
        // Set FIRST: the system may expire the task before any other setup
        // finishes, and an expiry with no handler set is silent. "First" on
        // its own still races the poll task below into existence — see
        // ExpiryGate above for how that race is closed, and why
        // `setTaskCompleted` below is safe to call from exactly one place
        // either way.
        let gate = ExpiryGate()
        task.expirationHandler = { gate.expire() }

        let started = gate.attach {
            Task { @MainActor in
                // Read inside the @MainActor closure, not above it: `run(_:)`
                // itself runs on whatever queue BGTaskScheduler's handler
                // uses, and `ChsFitService.shared` is @MainActor-isolated.
                let service = ChsFitService.shared
                service.resumeForBackground()
                // Per REQUEST, not per station: a 210-day current gate is ~150
                // requests behind one station-level tick, which freezes the bar
                // for ~2.5 minutes on an API that kills tasks showing no
                // progress first. `ChsJob.total`/`done` already track chunks
                // within a job (set by `fit`/`fitCurrent`); `requestCount` is
                // the same figure for a job that hasn't started one yet, so it
                // stands in as that job's planned share before `total` is set.
                while !Task.isCancelled, service.queue.active {
                    let jobs = service.queue.jobs
                    let planned = jobs.reduce(0.0) { $0 + $1.requestCount }
                    let done = jobs.reduce(0.0) { sum, job in
                        sum + (job.status == .ready ? job.requestCount : Double(job.done))
                    }
                    task.progress.totalUnitCount = Int64(planned.rounded())
                    task.progress.completedUnitCount = Int64(done.rounded())
                    // A rate-limit backoff waits at least 60 s (`ChsQueue.backoff`),
                    // which would otherwise read as a second stall with no
                    // explanation.
                    let waiting = jobs.contains {
                        $0.status == .pending && ($0.retryAfter ?? .distantPast) > appNow()
                    }
                    task.updateTitle("Downloading tide stations",
                                     subtitle: waiting
                                        ? "Waiting for a rate limit to clear…"
                                        : "\(Int(done.rounded())) of \(Int(planned.rounded())) requests")
                    try? await Task.sleep(for: .seconds(2))
                }
                task.setTaskCompleted(success: !Task.isCancelled)
            }
        }
        guard started else {
            // Expired before the poll task could ever be created: `attach`
            // guarantees its `setTaskCompleted` call above never runs in
            // this branch, so this is the only call for this run — never
            // zero, never two.
            task.setTaskCompleted(success: false)
            return
        }
    }
}
