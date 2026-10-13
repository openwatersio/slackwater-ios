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

/// The entries whose start is still ahead of the clock. The plan filtered on the pass's start
/// time; a slow resolve can reach the writer after `fire`, and a past start must not be requested.
func liveActivityEntriesAhead(_ entries: [AlertEntry], of now: Date) -> [AlertEntry] {
    entries.filter { $0.occurrence.fire > now }
}

/// Off the main actor on purpose: `Activity` is not `Sendable`, so ending one from an actor
/// would be a send across its boundary. Nothing here touches app state.
enum AlertLiveActivities {
    /// Ends what the sweep names, requests `entries` in order until the system refuses, and
    /// returns the keys it placed. `entries` carry the §5.2 copy without the lead: the line
    /// outlives the event on the open face.
    nonisolated static func apply(_ entries: [AlertEntry], water: @Sendable (String) -> AlertLiveActivityAttributes.Water,
                      liveRuleIDs: Set<UUID>, imperial: Bool, now: Date) async -> Set<String> {
        let ours = Activity<AlertLiveActivityAttributes>.activities
        let records = ours.map { a in
            LiveActivityRecord(key: a.attributes.key, ruleID: a.attributes.ruleID,
                               pending: a.activityState == .pending,
                               event: a.attributes.event, end: a.attributes.end)
        }
        let ending = Set(liveActivitiesToEnd(records, liveRuleIDs: liveRuleIDs, now: now))
        for a in ours where ending.contains(a.attributes.key) {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return [] }

        var placed = Set<String>()
        for entry in liveActivityEntriesAhead(entries, of: Date()) {
            let o = entry.occurrence
            let attributes = AlertLiveActivityAttributes(
                key: o.key, ruleID: o.ruleID, water: water(entry.stationID),
                title: entry.copy.title, line: entry.copy.body,
                event: o.event, end: o.end, noWindow: o.noWindow, heightM: o.heightM,
                imperial: imperial, tz: entry.place.tz, url: entry.url)
            let content = ActivityContent(state: AlertLiveActivityAttributes.ContentState(), staleDate: o.event)
            let alert = AlertConfiguration(title: LocalizedStringResource(stringLiteral: entry.copy.title),
                                           body: LocalizedStringResource(stringLiteral: entry.copy.body), sound: .default)
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil,
                                         style: .standard, alertConfiguration: alert, start: o.fire)
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
