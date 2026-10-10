// Slackwater — GPL v3. SPIKE, throwaway: answers docs/alerts.md §11 on a phone. Never merge.
import ActivityKit
import Foundation

/// Shared by the app (schedules) and the widget (draws). Everything is fixed at scheduling.
struct LiveActivitySpikeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}
    var label: String
    var event: Date   // the "water event"; `staleDate` is set to this
    var end: Date     // the window's close
}
