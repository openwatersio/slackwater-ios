// Slackwater — GPL v3. Scheduled Live Activities for the soonest alerts (docs/alerts.md §5.3).
import ActivityKit
import Foundation

/// One of our activities as the sweep sees it.
struct LiveActivityRecord: Equatable, Sendable {
    let key: String
    let ruleID: UUID
    /// Scheduled and not yet started.
    let pending: Bool
    let event: Date
    let end: Date?
}

/// Which activities a run ends before requesting the plan's: every pending one, since the
/// plan re-requests what it still wants; one whose window has closed or whose moment has
/// passed; and one whose rule is gone. An active one still inside its window stays.
func liveActivitiesToEnd(_ records: [LiveActivityRecord], liveRuleIDs: Set<UUID>, now: Date) -> [String] {
    records.filter { r in
        r.pending || (r.end ?? r.event) < now || !liveRuleIDs.contains(r.ruleID)
    }.map(\.key)
}
