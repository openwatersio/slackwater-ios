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

/// A calendar event's identity is its content, alarm included. A moved window, or an event
/// that gains or loses its Premium alarm, is a different event: the old one is removed and
/// the new one added.
func calendarEventKey(title: String, start: Date, end: Date, alarmOffset: TimeInterval?) -> String {
    let alarm = alarmOffset.map { String(Int($0)) } ?? "none"
    return "\(title)|\(Int(start.timeIntervalSince1970))|\(Int(end.timeIntervalSince1970))|\(alarm)"
}
