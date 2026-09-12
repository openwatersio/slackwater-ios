// Slackwater — GPL v3. Runs the alert pipeline — rules → occurrences → plan → writers — on launch and on every change (notifications spec §6).
import Foundation

/// One planned delivery with everything a writer needs.
struct AlertEntry {
    let occurrence: AlertOccurrence
    let copy: AlertCopy
    let url: URL?
    let place: AlertPlace
    /// A calendar event's alarm, relative to its start. Nil for a free user, and for notifications.
    var alarmOffset: TimeInterval? = nil
}

struct ResolvedAlerts: Sendable {
    var occurrences: [AlertOccurrence] = []
    /// Keyed by `AlertRule.stationID`.
    var places: [String: AlertPlace] = [:]
    /// Enabled rules whose station can't be loaded yet — a CHS station not fitted on this
    /// device, or an id that left the catalog.
    var unresolved: Set<UUID> = []
}

/// Occurrences for every enabled rule from `now` to the calendar horizon. Off the main
/// actor: a season-scale scan per station is real work.
/// ponytail: two rules on one station load it twice; share the record if that ever measures.
func resolveAlerts(_ rules: [AlertRule], now: Date, threshold: Double) -> ResolvedAlerts {
    var resolved = ResolvedAlerts()
    let until = now.addingTimeInterval(AlertHorizon.calendar)
    for rule in rules where rule.enabled {
        guard let record = WidgetStationLoader.loadRecord(id: rule.stationID) else {
            resolved.unresolved.insert(rule.id)
            continue
        }
        resolved.places[rule.stationID] = record.alertPlace
        resolved.occurrences += alertOccurrences(rule, station: WidgetStationLoader.station(from: record),
                                                 position: record.alertPosition,
                                                 from: now, to: until, threshold: threshold)
    }
    return resolved
}

struct AlertStatusSnapshot: Equatable {
    var scheduledThrough: [UUID: Date] = [:]
    var unresolved: Set<UUID> = []
    var notificationsAuthorized = false
    var calendarAuthorized = false
}

@MainActor final class AlertScheduler: ObservableObject {
    static let shared = AlertScheduler()

    @Published private(set) var status = AlertStatusSnapshot()
    private var running = false
    private var again = false

    /// Safe from anywhere. One run at a time; any number of requests during a run buy
    /// exactly one more.
    nonisolated static func requestReschedule() {
        Task { @MainActor in await shared.coalesced() }
    }

    private func coalesced() async {
        if running { again = true; return }
        running = true
        repeat {
            again = false
            await reschedule()
        } while again
        running = false
    }

    func reschedule(now: Date = appNow()) async {
        let rules = AlertRuleStore.shared.rules
        let threshold = slackThresholdKn
        let premium = PremiumStore.shared.isPremium
        let imperial = AppGroup.defaults.string(forKey: unitsKey) != "metric"

        let resolved = await Task.detached(priority: .utility) {
            resolveAlerts(rules, now: now, threshold: threshold)
        }.value
        let plan = deliveryPlan(rules: rules, occurrences: resolved.occurrences, now: now, premium: premium)
        // Deviation from the brief (controller ruling): uniqueKeysWithValues crashes on a
        // duplicated rule id; keep the first the way deliveryPlan already does.
        let byID = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func entries(_ list: [AlertOccurrence], includeLead: Bool, alarm: Bool) -> [AlertEntry] {
            list.compactMap { o in
                guard let rule = byID[o.ruleID], let place = resolved.places[rule.stationID] else { return nil }
                return AlertEntry(
                    occurrence: o,
                    copy: alertCopy(rule, o, place: place, imperial: imperial,
                                    threshold: threshold, includeLead: includeLead),
                    url: shareURL(forStationID: rule.stationID, at: o.event, tz: place.tz)
                        ?? deepLink(forStationID: rule.stationID),
                    place: place,
                    alarmOffset: alarm ? -rule.lead : nil)
            }
        }

        // Premium puts an alarm on every calendar event (spec §5.1).
        AlertCalendar.apply(entries(plan.calendar, includeLead: false, alarm: premium), now: now)

        status = AlertStatusSnapshot(scheduledThrough: scheduledThrough(plan),
                                     unresolved: resolved.unresolved,
                                     notificationsAuthorized: false,
                                     calendarAuthorized: AlertCalendar.authorized)
    }
}
