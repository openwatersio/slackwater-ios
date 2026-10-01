// Slackwater — GPL v3. Occurrences → what gets delivered where, and what it says (docs/alerts.md §5–§6).
import Foundation

enum AlertHorizon {
    /// The calendar holds the long view; it survives the app never opening again.
    static let calendar: TimeInterval = 90 * 86_400
    /// Notifications hold until 14 days past the last launch.
    static let notifications: TimeInterval = 14 * 86_400
    /// iOS keeps only the soonest 64 pending requests an app holds.
    static let notificationLimit = 64
}

struct DeliveryPlan: Equatable {
    var calendar: [AlertOccurrence] = []
    var notifications: [AlertOccurrence] = []
}

/// Which occurrences the calendar publishes and which become notifications. The two have
/// separate sources: `calendarOccurrences` come from a station's subscription (spec §5.1) and
/// are free at any tier; `occurrences` come from rules, and rules are Premium. The calendar
/// keeps an event until it happens; a notification is gone once its fire time passes.
func deliveryPlan(rules: [AlertRule], occurrences: [AlertOccurrence],
                  calendarOccurrences: [AlertOccurrence],
                  now: Date, premium: Bool) -> DeliveryPlan {
    let calendar = calendarOccurrences
        .filter { $0.event > now && $0.event <= now.addingTimeInterval(AlertHorizon.calendar) }
        .sorted { $0.event < $1.event }
    guard premium else { return DeliveryPlan(calendar: calendar) }
    // A duplicated rule id would trap uniqueKeysWithValues; keep the first.
    let live = Dictionary(rules.filter(\.enabled).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    // Rules are independent, but a banner is not: "Alert me" on one moment and "every <event>"
    // at the same lead are two rules that arrive as two banners with the same title and the same
    // body, and the popup's two rows invite exactly that. One reminder per thing-the-user-sees.
    // The fire time is part of that: the same moment at 30 minutes and at a day is two reminders
    // and stays two.
    struct Perceived: Hashable {
        let stationID: String
        let trigger: AlertTrigger
        let event: Date
        let fire: Date
    }
    var seen = Set<Perceived>()
    let notifications = occurrences
        // Same fire time: the `once` rule keeps it. That rule has exactly one occurrence, so
        // losing it would leave the Alerts screen reading "Nothing coming up" against a rule
        // that is about to be delivered by its repeating twin; the repeating rule has the rest
        // of the season to name a date from.
        .sorted { a, b in
            a.fire == b.fire ? (live[a.ruleID]?.once != nil && live[b.ruleID]?.once == nil)
                             : a.fire < b.fire
        }
        .filter { o in
            guard let rule = live[o.ruleID], o.fire > now,
                  o.fire <= now.addingTimeInterval(AlertHorizon.notifications) else { return false }
            return seen.insert(Perceived(stationID: rule.stationID, trigger: rule.trigger,
                                         event: o.event, fire: o.fire)).inserted
        }
    return DeliveryPlan(calendar: calendar,
                        notifications: Array(notifications.prefix(AlertHorizon.notificationLimit)))
}

/// Each rule's last scheduled notification, for the Alerts screen's "Scheduled through".
func scheduledThrough(_ plan: DeliveryPlan) -> [UUID: Date] {
    var through: [UUID: Date] = [:]
    for o in plan.notifications {
        through[o.ruleID] = max(through[o.ruleID] ?? o.fire, o.fire)
    }
    return through
}

struct AlertCopy: Equatable {
    let title: String
    let body: String
}

let alertLeads: [TimeInterval] = [0, 900, 1_800, 3_600, 10_800, 86_400]

func alertLeadLabel(_ lead: TimeInterval) -> String {
    lead == 0 ? "At the time" : "\(leadAmount(lead)) before"
}

private func leadAmount(_ lead: TimeInterval) -> String {
    switch lead {
    case ..<3_600: "\(Int(lead / 60)) min"
    case ..<86_400: "\(Int(lead / 3_600)) hr"
    default: "\(Int(lead / 86_400)) day" + (lead >= 172_800 ? "s" : "")
    }
}

/// Title and body for one occurrence. A notification's title is the place, then the event in
/// as few words as it takes; a calendar event's carries no place, because its calendar is named
/// for one (spec §5.1) — and a tide's height rides in the title there, where the body is a note
/// nobody opens. The calendar passes `includeLead: false`: an event sits at its own time, so
/// "in 30 min" means nothing there.
func alertCopy(_ rule: AlertRule, _ o: AlertOccurrence, place: AlertPlace, imperial: Bool,
               threshold: Double, includeLead: Bool, includePlace: Bool = true,
               locale: Locale = .autoupdatingCurrent) -> AlertCopy {
    let clock = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: place.tz).locale(locale)
    let time = o.event.formatted(clock)
    let limit = String(format: "%.1f kn", threshold)

    var body: String
    switch rule.trigger {
    case .slackWindowOpens where o.noWindow:
        body = "\(time), no window under \(limit)"
    case .slackWindowOpens:
        body = o.end.map { "\(time)–\($0.formatted(clock)), under \(limit)" } ?? time
    case .tideExtreme:
        body = o.heightM.map { "\(time) · \(formatHeight($0, imperial: imperial)) \(heightUnit(imperial: imperial))" } ?? time
    case .slack, .currentPeak, .tideCrossing, .eclipse:
        body = time
    }
    if includeLead, rule.lead > 0 { body += " · in \(leadAmount(rule.lead))" }

    let event = alertEventName(rule.trigger, noWindow: o.noWindow, imperial: imperial)
    if includePlace { return AlertCopy(title: "\(place.name) - \(event)", body: body) }
    guard case .tideExtreme = rule.trigger, let h = o.heightM else {
        return AlertCopy(title: event, body: body)
    }
    return AlertCopy(title: "\(event) \(formatHeight(h, imperial: imperial)) \(heightUnit(imperial: imperial))",
                     body: body)
}

/// What a calendar event is compared by.
struct CalendarEventShape: Equatable {
    let title: String
    let start: Date
    let end: Date
    /// Always nil on a planned event: no Slackwater calendar event carries an alarm — the
    /// calendar is a published record and a reminder is a notification (spec §5.1). Still read
    /// off stored events and still compared, because that is what makes an event that does
    /// carry one — written by a build whose events had alarms, and synced from a device that
    /// hasn't updated — fail to match and be replaced by one that doesn't.
    let alarmOffset: TimeInterval?
}

/// How far apart a stored event's times and a planned event's times can be and still be the same
/// event. The engine's event search lands a second apart from one reschedule to the next, so an
/// instant on a minute boundary can floor to either minute.
let calendarMatchTolerance: TimeInterval = 90

/// Which of the calendar's events to remove and which planned events to add. A stored event is a
/// planned one when their title and alarm agree and both times are within `calendarMatchTolerance`;
/// each stored event answers for one planned event. A planned event identical to an earlier one is
/// written once. An event already under way — a slack window open right now — is never removed.
/// ponytail: a pairwise scan, O(existing × planned) over a few hundred events per run; index by
/// title if calendars grow into the thousands.
func calendarChanges(existing: [CalendarEventShape], wanted: [CalendarEventShape],
                     now: Date) -> (remove: [Int], add: [Int]) {
    var claimed = Set<Int>()
    var add: [Int] = []
    for (w, plan) in wanted.enumerated() {
        if wanted[..<w].contains(plan) { continue }
        let match = existing.indices.first { i in
            !claimed.contains(i)
                && existing[i].title == plan.title
                && existing[i].alarmOffset == plan.alarmOffset
                && abs(existing[i].start.timeIntervalSince(plan.start)) <= calendarMatchTolerance
                && abs(existing[i].end.timeIntervalSince(plan.end)) <= calendarMatchTolerance
        }
        if let match { claimed.insert(match) } else { add.append(w) }
    }
    let remove = existing.indices.filter { !claimed.contains($0) && existing[$0].start >= now }
    return (remove, add)
}
