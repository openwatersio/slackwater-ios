import Foundation

/// Widens wall-clock budgets outside their Mac Studio calibration environment.
/// Direct Xcode runs use 1×, test.sh defaults to 2×, and CI passes 4× through
/// TEST_RUNNER_SLACKWATER_PERF_SCALE.
let perfScale = Double(ProcessInfo.processInfo.environment["SLACKWATER_PERF_SCALE"] ?? "1") ?? 1

/// Wall clock for one block, in seconds.
func elapsed(_ body: () -> Void) -> TimeInterval {
    let start = Date.now
    body()
    return Date.now.timeIntervalSince(start)
}
