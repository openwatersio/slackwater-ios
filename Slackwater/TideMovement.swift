// Slackwater — GPL v3. Shared tide-movement classification for the detail
// scrubber and widget extension.
import Foundation
import TideEngine

let tideMovementRampAnchorsMHr: [Double] = [0.6, 1.0, 1.5, 1.8]

/// Each rising or falling run gets one cue at its fastest point.
func tideFlowArrows(_ rates: [TideRatePoint]) -> [TideRatePoint] {
    var peaks: [TideRatePoint] = []
    var run: [TideRatePoint] = []
    var direction = 0

    func finishRun() {
        if let peak = run.max(by: { abs($0.rate) < abs($1.rate) }),
           abs(peak.rate) >= tideMovementRampAnchorsMHr[0] {
            peaks.append(peak)
        }
        run = []
    }

    for point in rates {
        guard abs(point.rate) >= 0.0001 else { finishRun(); direction = 0; continue }
        let nextDirection = point.rate.sign == .minus ? -1 : point.rate.sign == .plus ? 1 : 0
        if direction != 0, nextDirection != direction { finishRun() }
        direction = nextDirection
        run.append(point)
    }
    finishRun()
    return peaks
}

func tideRateSeverity(_ rate: Double) -> String? {
    let rate = abs(rate)
    guard rate >= tideMovementRampAnchorsMHr[0] else { return nil }
    if rate >= tideMovementRampAnchorsMHr[2] { return "🚨 Extreme" }
    if rate >= tideMovementRampAnchorsMHr[1] { return "‼️ Very fast" }
    return "⚠️ Fast"
}
