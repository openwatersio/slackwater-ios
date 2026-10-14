// Slackwater — GPL v3. The accepted tier, continued in the background.
//
// What iOS grants, and the three limits that shape everything around this:
//   - The task must be submitted from the FOREGROUND in response to a person's
//     action. Accepting downloads or reopening an unfinished accepted run
//     supplies that action.
//   - LOCKING THE DEVICE STOPS EXECUTION. Apple treats this as a framework
//     bug, but it reproduces on shipping builds. Nothing here may promise
//     completion, and the queue must treat a stop as "resume next time".
//   - Swiping the app away cancels the task with NO callback, and a person can
//     cancel from the Live Activity, which invokes the same expiration handler
//     as a system kill with no reason code. Unfinished work comes from queue
//     progress; the submission identifier only prevents duplicate tasks.
//
// None of this is reachable in the Simulator: BGTaskScheduler answers
// .unavailable there, so it is verified by hand on a device.
@preconcurrency import BackgroundTasks
import Foundation
import os
import UIKit

struct BackgroundDownloadSubmission {
    private(set) var identifier: String?

    mutating func begin(tier: DownloadTier, allCurrentsSelected: Bool = false,
                        queue: ChsQueue, onlineActive: Bool = false, isForeground: Bool) -> String? {
        let fittedActive = tier != .inView ? queue.active : allCurrentsSelected && queue.jobs.contains {
            $0.isCurrent && ($0.status == .pending || $0.status == .downloading)
        }
        let selectedOnlineActive = (tier != .inView || allCurrentsSelected) && onlineActive
        guard isForeground, fittedActive || selectedOnlineActive, identifier == nil else { return nil }
        let id = UUID().uuidString
        identifier = id
        return id
    }

    mutating func finish(_ identifier: String) {
        // Expiry and poll completion can arrive on either side of a new submission.
        if self.identifier == identifier { self.identifier = nil }
    }
}

enum BackgroundDownloads {
    @MainActor private static var submission = BackgroundDownloadSubmission()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.openwaters.slackwater",
                                        category: "BackgroundDownloads")

    /// The wildcard, matching `BGTaskSchedulerPermittedIdentifiers`. Built from
    /// the bundle id so the two cannot drift; a stale literal fails
    /// registration silently. Nothing outside this file reads it.
    private static var pattern: String { (Bundle.main.bundleIdentifier ?? "") + ".downloads.*" }

    /// Register a fresh concrete identifier and submit it. Continued-processing
    /// registrations are exempt from the register-before-launch rule, so this
    /// belongs at foreground acceptance or resume, not in the App's init. A fresh id per call is
    /// required: registering the same identifier twice in one session is a
    /// fatal exception, not an error.
    @MainActor static func submitIfPossible() {
        guard submission.identifier == nil else { return }
        let service = ChsFitService.shared
        let queue = service.queue
        let online = service.onlineDownloads
        guard let identifier = submission.begin(tier: service.tier,
            allCurrentsSelected: service.allCurrentsSelected,
            queue: queue, onlineActive: online.active,
            isForeground: UIApplication.shared.applicationState == .active) else { return }
        let id = pattern.replacingOccurrences(of: "*", with: identifier)

        // The scheduler's default queue is background; this callback must not inherit MainActor.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id,
                                                         using: nil) { @Sendable task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                Task { @MainActor in submission.finish(identifier) }
                return
            }
            run(task, identifier: identifier)
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
            submission.finish(identifier)
            return
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: id,
            title: String(localized: "Downloading", comment: "Compact download status."),
            subtitle: String(localized: "\(queue.ready + online.ready) of \(queue.total + online.total)", comment: "Completed and total station downloads."))
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
            submission.finish(identifier)
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

    private static func run(_ task: BGContinuedProcessingTask, identifier: String) {
        // Set FIRST: the system may expire the task before any other setup
        // finishes, and an expiry with no handler set is silent. "First" on
        // its own still races the poll task below into existence — see
        // ExpiryGate above for how that race is closed, and why
        // `setTaskCompleted` below is safe to call from exactly one place
        // either way.
        let gate = ExpiryGate()
        task.expirationHandler = {
            gate.expire()
            Task { @MainActor in submission.finish(identifier) }
        }

        let started = gate.attach {
            Task { @MainActor in
                // Read inside the @MainActor closure, not above it: `run(_:)`
                // itself runs on whatever queue BGTaskScheduler's handler
                // uses, and `ChsFitService.shared` is @MainActor-isolated.
                let service = ChsFitService.shared
                service.resumeForBackground()
                while !Task.isCancelled {
                    let online = service.onlineDownloads
                    guard service.queue.active || online.active else { break }
                    let progress = service.queue.requestProgress
                    task.progress.totalUnitCount = Int64((progress.total + online.requestsCompleted + online.requestsRemaining).rounded())
                    task.progress.completedUnitCount = Int64((progress.completed + online.requestsCompleted).rounded())
                    // A deferred job is sitting out `ChsQueue.backoff`, which
                    // reads as a stall with no explanation — up to 15 minutes,
                    // on an API that kills tasks showing no progress first.
                    //
                    // The copy names no cause, because this cannot tell which.
                    // `deferRetry` fires for every transient failure — offline,
                    // 5xx, station list unavailable — and the rate limit it was
                    // written for is the one case it does NOT catch: IWLS's 429
                    // wait happens inside `IwlsClient.get`, with the job still
                    // `.downloading`. "Waiting to retry" is true of all of them.
                    let waitingToRetry = service.queue.deferred() > 0 || service.onlineStates.values.contains {
                        if case .deferred = $0 { return true }
                        return false
                    }
                    task.updateTitle(String(localized: "Downloading", comment: "Compact download status."),
                                     subtitle: waitingToRetry
                                        ? String(localized: "Waiting to retry…", comment: "Background download activity while waiting to retry.")
                                        : String(localized: "Stations ready: \(service.queue.ready + online.ready) of \(service.queue.total + online.total)", comment: "Background download activity. Values are ready and total station counts."))
                    try? await Task.sleep(for: .seconds(2))
                }
                task.setTaskCompleted(success: !Task.isCancelled)
                submission.finish(identifier)
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
