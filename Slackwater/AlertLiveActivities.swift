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
    var scheduledStart: Date? = nil
}

/// Replace future pending activities. Once their scheduled start arrives, leave the request
/// intact so ActivityKit can deliver its start alert even if it still reports pending.
func liveActivitiesToEnd(_ records: [LiveActivityRecord], liveRuleIDs: Set<UUID>, now: Date) -> [String] {
    records.filter { r in
        (r.pending && (r.scheduledStart.map { $0 > now } ?? true)) || (r.end ?? r.event) < now || !liveRuleIDs.contains(r.ruleID)
    }.map(\.key)
}

func liveActivityRuleIDs(_ records: [LiveActivityRecord], now: Date) -> Set<UUID> {
    Set(records.filter { !$0.pending && ($0.end ?? $0.event) > now }.map(\.ruleID))
}

func liveWindowRuleIDs(_ records: [LiveActivityRecord], now: Date) -> Set<UUID> {
    Set(records.filter { !$0.pending && $0.end.map { $0 > now } == true }.map(\.ruleID))
}

/// The entries whose event is still ahead of the clock. The plan filtered on the pass's start
/// time; a slow resolve can reach the writer later, and an event already behind must not be
/// requested. One whose reminder time is behind but whose event is not starts at once.
func liveActivityEntriesAhead(_ entries: [AlertEntry], of now: Date, running: Set<String> = []) -> [AlertEntry] {
    entries.filter { $0.occurrence.event > now && !running.contains($0.occurrence.key) }
}

/// Three hours either side of the event at ten minutes: 37 samples in the engine's units. A
/// derived gate knows slacks and no series, so it has none.
func liveActivityCurve(_ station: WidgetStation, around event: Date) -> AlertLiveActivityCurve? {
    let start = event.addingTimeInterval(-3 * 3_600), end = event.addingTimeInterval(3 * 3_600)
    let values: [Double]
    switch station {
    // The engine hands back one sample past `end`; the slice is the six hours and no more.
    case .tide(let s, _, _): values = s.heights(from: start, to: end, step: 600).filter { $0.time <= end }.map(\.height)
    case .current(let s, _, _): values = s.speeds(from: start, to: end, step: 600).filter { $0.time <= end }.map(\.speed)
    case .derived: return nil
    }
    // One sample draws nothing; the face then takes the plain layout rather than a blank frame.
    return values.count < 2 ? nil : AlertLiveActivityCurve(start: start, step: 600, values: values)
}

/// Off the main actor on purpose: `Activity` is not `Sendable`, so ending one from an actor
/// would be a send across its boundary. Nothing here touches app state.
enum AlertLiveActivities {
    nonisolated static func activeRecords() -> [LiveActivityRecord] {
        Activity<AlertLiveActivityAttributes>.activities.compactMap { activity -> LiveActivityRecord? in
            guard activity.activityState == .active || activity.activityState == .stale else { return nil }
            return LiveActivityRecord(key: activity.attributes.key, ruleID: activity.attributes.ruleID,
                                      pending: false, event: activity.attributes.event, end: activity.attributes.end)
        }
    }

    /// Ends what the sweep names, requests `entries` in order until the system refuses, and
    /// returns the keys it placed. `entries` carry the §5.2 copy without the lead: the line
    /// outlives the event on the open face.
    nonisolated static func apply(_ entries: [AlertEntry], water: @Sendable (String) -> AlertLiveActivityAttributes.Water,
                      curve: @Sendable (AlertEntry) -> AlertLiveActivityCurve?,
                      liveRuleIDs: Set<UUID>, imperial: Bool) async -> Set<String> {
        // The real clock, not `appNow()`, for the whole writer: the event, end, start and stale
        // dates ActivityKit holds are absolute and read on the real clock, so a pinned Debug
        // clock would keep activities that have ended and request ones that start at once.
        // Read at each step, not the pass start: the resolve before this can run long, and so
        // can the ends awaited below.
        let ours = Activity<AlertLiveActivityAttributes>.activities
        let records = ours.map { a in
            LiveActivityRecord(key: a.attributes.key, ruleID: a.attributes.ruleID,
                               pending: a.activityState == .pending,
                               event: a.attributes.event, end: a.attributes.end, scheduledStart: a.attributes.scheduledStart)
        }
        let ending = Set(liveActivitiesToEnd(records, liveRuleIDs: liveRuleIDs, now: Date()))
        for a in ours where ending.contains(a.attributes.key) {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return [] }

        // An activity the sweep kept is running for its occurrence already; that one is placed.
        let running = Set(ours.map(\.attributes.key)).subtracting(ending)
        var placed = running
        let clock = Date()
        for entry in liveActivityEntriesAhead(entries, of: clock, running: running) {
            let o = entry.occurrence
            let attributes = AlertLiveActivityAttributes(
                key: o.key, ruleID: o.ruleID, water: water(entry.stationID),
                title: entry.copy.title, line: entry.copy.body,
                event: o.event, end: o.end, noWindow: o.noWindow, heightM: o.heightM,
                imperial: imperial, tz: entry.place.tz, curve: curve(entry), url: entry.url,
                scheduledStart: o.fire > clock ? o.fire : nil)
            let content = ActivityContent(state: AlertLiveActivityAttributes.ContentState(), staleDate: o.event)
            let alert = AlertConfiguration(title: LocalizedStringResource(stringLiteral: entry.copy.title),
                                           body: LocalizedStringResource(stringLiteral: entry.copy.body), sound: .default)
            do {
                if o.fire > clock {
                    _ = try Activity.request(attributes: attributes, content: content, pushType: nil,
                                             style: .standard, alertConfiguration: alert, start: o.fire)
                } else {
                    // Inside its lead already: the person just set it and is looking at the
                    // app, so it starts now and nothing buzzes.
                    _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                }
                placed.insert(o.key)
            } catch is ActivityAuthorizationError {
                // `targetMaximumExceeded` at the fifth, or activities off for the app: everything
                // from here stays a notification (spec §5.3).
                break
            } catch {
                continue
            }
        }
        return placed
    }
}
