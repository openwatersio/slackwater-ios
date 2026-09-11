import Foundation

/// Widens wall-clock budgets outside their Mac Studio calibration environment.
/// CI passes TEST_RUNNER_SLACKWATER_PERF_SCALE through xcodebuild; local runs
/// stay at 1×.
let perfScale = Double(ProcessInfo.processInfo.environment["SLACKWATER_PERF_SCALE"] ?? "1") ?? 1

/// Wall clock for one block, in seconds.
func elapsed(_ body: () -> Void) -> TimeInterval {
    let start = Date.now
    body()
    return Date.now.timeIntervalSince(start)
}
