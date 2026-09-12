// Slackwater — GPL v3. Occurrences → what gets delivered where, and what it says (notifications spec §5–§6).
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

/// Which occurrences go to the calendar (free) and which become notifications (Premium).
/// The calendar keeps an event until it happens; a notification is gone once its fire time passes.
/// Whether a calendar event carries an alarm is the writer's call, from the same `premium`.
func deliveryPlan(rules: [AlertRule], occurrences: [AlertOccurrence], now: Date, premium: Bool) -> DeliveryPlan {
    let live = Dictionary(rules.filter(\.enabled).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let ordered = occurrences.sorted { $0.fire < $1.fire }

    let calendar = ordered.filter {
        live[$0.ruleID]?.calendar == true
            && $0.event > now && $0.event <= now.addingTimeInterval(AlertHorizon.calendar)
    }
    guard premium else { return DeliveryPlan(calendar: calendar) }
    let notifications = ordered.filter {
        live[$0.ruleID]?.alert == .notification
            && $0.fire > now && $0.fire <= now.addingTimeInterval(AlertHorizon.notifications)
    }
    return DeliveryPlan(calendar: calendar,
                        notifications: Array(notifications.prefix(AlertHorizon.notificationLimit)))
}

/// Each rule's last delivered moment — a calendar event's time or a notification's fire —
/// for the Alerts screen's "Scheduled through".
func scheduledThrough(_ plan: DeliveryPlan) -> [UUID: Date] {
    var through: [UUID: Date] = [:]
    for (id, moment) in plan.calendar.map({ ($0.ruleID, $0.event) }) + plan.notifications.map({ ($0.ruleID, $0.fire) }) {
        through[id] = max(through[id] ?? moment, moment)
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

/// Title and body for one occurrence. The title is the place, then the event in as few words
/// as it takes; the body is the time in the station's zone, with the span, threshold or height
/// where they matter. The calendar passes `includeLead: false`: an event sits at its own time,
/// so "in 30 min" means nothing there.
func alertCopy(_ rule: AlertRule, _ o: AlertOccurrence, place: AlertPlace, imperial: Bool,
               threshold: Double, includeLead: Bool, locale: Locale = .autoupdatingCurrent) -> AlertCopy {
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
    return AlertCopy(title: "\(place.name) - \(event)", body: body)
}

/// What a calendar event is compared by.
struct CalendarEventShape: Equatable {
    let title: String
    let start: Date
    let end: Date
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
