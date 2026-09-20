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
