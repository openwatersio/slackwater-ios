// Slackwater — GPL v3. Runs the alert pipeline — rules → occurrences → plan → writers — on launch and on every change (notifications spec §6).
import Foundation

/// One planned delivery with everything a writer needs.
struct AlertEntry {
    /// Which station's calendar this belongs in.
    let stationID: String
    let occurrence: AlertOccurrence
    let copy: AlertCopy
    let url: URL?
    let place: AlertPlace
}

struct ResolvedAlerts: Sendable {
    /// From rules: what becomes a notification.
    var occurrences: [AlertOccurrence] = []
    /// From station subscriptions: what the calendar publishes.
    var calendarOccurrences: [AlertOccurrence] = []
    /// The throwaway rules behind `calendarOccurrences`, so copy has a trigger to read.
    var calendarRules: [UUID: AlertRule] = [:]
    /// Which station each of those belongs to, so the writer knows the calendar.
    var calendarStations: [UUID: String] = [:]
    /// Keyed by station id.
    var places: [String: AlertPlace] = [:]
    /// Enabled rules whose station can't be loaded yet — a CHS station not fitted on this
    /// device, or an id that left the catalog.
    var unresolved: Set<UUID> = []
    /// Subscribed stations that can't be loaded. Their calendars are left exactly as they
    /// are: an empty plan is "nothing known yet", not "delete the next 90 days".
    var unresolvedStations: Set<String> = []
}

/// Occurrences for every enabled rule and every subscribed station, from `now` to the calendar
/// horizon. Off the main actor: a season-scale scan per station is real work.
/// ponytail: two rules on one station load it twice; share the record if that ever measures.
func resolveAlerts(_ rules: [AlertRule], subscriptions: [String],
                   now: Date, threshold: Double) -> ResolvedAlerts {
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

    for stationID in subscriptions {
        guard let record = WidgetStationLoader.loadRecord(id: stationID) else {
            resolved.unresolvedStations.insert(stationID)
            continue
        }
        resolved.places[stationID] = record.alertPlace
        let station = WidgetStationLoader.station(from: record)
        for trigger in calendarTriggers(for: record.calendarKind) {
            // A throwaway rule per trigger. Its id only has to be unique within this run:
            // a calendar event is matched by its content, never by an occurrence key.
            let rule = AlertRule(stationID: stationID, trigger: trigger)
            resolved.calendarRules[rule.id] = rule
            resolved.calendarStations[rule.id] = stationID
            resolved.calendarOccurrences += alertOccurrences(rule, station: station,
                                                             position: record.alertPosition,
                                                             from: now, to: until, threshold: threshold)
        }
    }
    return resolved
}

struct AlertStatusSnapshot: Equatable {
    var scheduledThrough: [UUID: Date] = [:]
    var unresolved: Set<UUID> = []
    var notificationsAuthorized = false
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

    /// One full pass: expire what's due, resolve 90 days off the main actor, then write the
    /// calendars and the notifications.
    ///
    /// Two constraints hold it up, and both are invisible at the call site.
    ///
    /// It must be callable directly and run to completion, not only through `coalesced()`:
    /// `CalendarStationsView.subscribeAndVerify` awaits this exact call and reads whether a
    /// calendar came out of it, which is the only signal that a source refused to make one.
    /// Routing it through the coalescer would return before the work it is inspecting happened.
    ///
    /// And it must stay safe to interleave with a coalesced pass, because that direct call can
    /// land in the middle of one. Both writers are built for that: `AlertCalendar.apply` has no
    /// `await` in it, so its EventKit removes and adds are atomic against the other pass, and it
    /// writes only stations the live store and the caller's snapshot agree on;
    /// `AlertNotifications.apply` keys every request on the occurrence, so two passes over the
    /// same rules converge on the same set instead of doubling it. Anything added here that
    /// suspends mid-write, or writes off a snapshot without re-checking it, breaks that.
    func reschedule(now: Date = appNow()) async {
        for id in expiredRules(AlertRuleStore.shared.rules, now: now) {
            AlertRuleStore.shared.remove(id)
        }
        let rules = AlertRuleStore.shared.rules
        let threshold = slackThresholdKn
        let premium = PremiumStore.shared.isPremium
        let imperial = AppGroup.defaults.string(forKey: unitsKey) != "metric"

        let subscriptions = StationCalendarStore.shared.subscriptions.map(\.stationID)

        let resolved = await Task.detached(priority: .utility) {
            resolveAlerts(rules, subscriptions: subscriptions, now: now, threshold: threshold)
        }.value
        let plan = deliveryPlan(rules: rules, occurrences: resolved.occurrences,
                                calendarOccurrences: resolved.calendarOccurrences,
                                now: now, premium: premium)
        // A duplicated rule id would trap uniqueKeysWithValues; keep the first, as deliveryPlan does.
        let byID = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .merging(resolved.calendarRules) { mine, _ in mine }

        func entries(_ list: [AlertOccurrence], includeLead: Bool, includePlace: Bool) -> [AlertEntry] {
            list.compactMap { o in
                guard let rule = byID[o.ruleID], let place = resolved.places[rule.stationID] else { return nil }
                return AlertEntry(
                    stationID: rule.stationID,
                    occurrence: o,
                    copy: alertCopy(rule, o, place: place, imperial: imperial,
                                    threshold: threshold, includeLead: includeLead,
                                    includePlace: includePlace),
                    url: shareURL(forStationID: rule.stationID, at: o.event, tz: place.tz)
                        ?? deepLink(forStationID: rule.stationID),
                    place: place)
            }
        }

        AlertCalendar.apply(entries(plan.calendar, includeLead: false, includePlace: false),
                            subscribed: subscriptions, skipping: resolved.unresolvedStations, now: now)
        await AlertNotifications.apply(entries(plan.notifications, includeLead: true, includePlace: true))

        status = AlertStatusSnapshot(scheduledThrough: scheduledThrough(plan),
                                     unresolved: resolved.unresolved,
                                     notificationsAuthorized: await AlertNotifications.authorized())
    }
}
