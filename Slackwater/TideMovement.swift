// Slackwater — GPL v3. Shared tide-movement classification for the detail
// scrubber and widget extension.
// Scrubber behavior here is specified in docs/scrubber.md: update the spec in the same change as any visible change.
import Foundation
import SlackwaterKit

let tideMovementRampAnchorsMHr: [Double] = [0.6, 1.0, 1.5, 1.8]

/// Each rising or falling run gets one cue at its fastest point.
func tideFlowArrows(_ rates: [TideRatePoint]) -> [TideRatePoint] {
    flowPeaks(rates, floor: tideMovementRampAnchorsMHr[0])
}
