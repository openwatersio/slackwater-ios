// Slackwater — GPL v3. What a scheduled Live Activity carries, fixed when it is requested (docs/alerts.md §5.3).
import ActivityKit
import Foundation

/// Shared by the app, which requests, and the widget extension, which draws. The title and
/// line are the notification's own copy, so the Island and the banner never disagree, and the
/// widget never links the rule types (its target does not link Almanac). Nothing updates the
/// state after the request: the faces are system timers off `event` and `end`.
struct AlertLiveActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {}
    enum Water: String, Codable, Sendable { case tide, current }

    let key: String
    let ruleID: UUID
    let water: Water
    let title: String
    let line: String
    let event: Date
    let end: Date?
    let noWindow: Bool
    let heightM: Double?
    let imperial: Bool
    let url: URL?
}

/// Which of the two faces a context draws: counting down to `event`, then across the window
/// while it is open, or the moment itself where there is no window to cross.
enum AlertLiveActivityFace: Equatable { case countdown, open, moment }

func liveActivityFace(_ a: AlertLiveActivityAttributes, stale: Bool) -> AlertLiveActivityFace {
    guard stale else { return .countdown }
    return a.end != nil && !a.noWindow ? .open : .moment
}
