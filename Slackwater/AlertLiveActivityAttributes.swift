// Slackwater — GPL v3. What a scheduled Live Activity carries, fixed when it is requested (docs/alerts.md §5.3).
import ActivityKit
import Foundation

/// A fixed slice of the station's series for the face to draw: nothing updates after the
/// request, so six hours around the event is the whole story the activity can tell.
struct AlertLiveActivityCurve: Codable, Hashable, Sendable {
    let start: Date
    let step: TimeInterval
    let values: [Double]
}

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
    /// The station's zone: the face formats `event` itself, and the phone may be elsewhere.
    let tz: TimeZone
    /// Six hours around the event in the engine's units; nil on a derived gate, which has no series.
    let curve: AlertLiveActivityCurve?
    let url: URL?
}

/// The stale face of a moment with no window: its time in the station's zone and, for a tide,
/// its height — the same reading the notification line gave.
func liveActivityMoment(_ a: AlertLiveActivityAttributes, locale: Locale = .autoupdatingCurrent) -> String {
    let time = a.event.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: a.tz).locale(locale))
    guard let h = a.heightM else { return time }
    return "\(time) · \(formatHeight(h, imperial: a.imperial)) \(heightUnit(imperial: a.imperial))"
}

/// Which of the two faces a context draws: counting down to `event`, then across the window
/// while it is open, or the moment itself where there is no window to cross.
enum AlertLiveActivityFace: Equatable { case countdown, open, moment }

func liveActivityFace(_ a: AlertLiveActivityAttributes, stale: Bool) -> AlertLiveActivityFace {
    guard stale else { return .countdown }
    return a.end != nil && !a.noWindow ? .open : .moment
}

/// The countdown timer's range. A render that lands after `event` before `isStale` has
/// flipped would trap a `ClosedRange`, so the lower bound never passes the event.
func liveActivityCountdown(now: Date, event: Date) -> ClosedRange<Date> {
    min(now, event)...event
}
