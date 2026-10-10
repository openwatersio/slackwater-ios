// Slackwater — GPL v3. The line under the strip: Rest, Pressed, or Set (docs/alerts.md §7.1).
import Foundation

/// What the line reads. Set wins whenever a rule already exists for the centerline's offer, so a
/// rule can be found again from the place that made it; Pressed is the strip's own state after a
/// long press; Rest is everything else.
enum AlertLineState: Equatable {
    case rest
    case pressed(Date)
    case set(AlertRule)
}

/// The rule the line would open: one bound to this minute first — it is the one that expires —
/// else one repeating this trigger. Enabled or not: a switched-off rule is found and woken in the
/// sheet, never duplicated.
func alertLineRule(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                   at moment: Date) -> AlertRule? {
    let minute = alertMinute(moment)
    let mine = rules.filter { $0.stationID == stationID && $0.trigger == offer }
    return mine.first { $0.once == minute } ?? mine.first { $0.once == nil }
}

func alertLineState(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                    at moment: Date, pressed: Bool) -> AlertLineState {
    if let rule = alertLineRule(rules, stationID: stationID, offer: offer, at: moment) { return .set(rule) }
    return pressed ? .pressed(moment) : .rest
}

/// "Set an alert" · "Set alert for low tide · Sat 14:32" · "Alert set · low tide · Sat 14:32" ·
/// "Alert set · every low tide". The event in a small letter mid-sentence, the moment in the
/// station's zone.
func alertLineLabel(_ state: AlertLineState, offer: AlertTrigger, tz: TimeZone, imperial: Bool,
                    locale: Locale = .autoupdatingCurrent) -> String {
    // Weekday and time, no date: the line names a moment on the strip, whose horizon is the week.
    func when(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: tz).weekday(.abbreviated).hour().minute().locale(locale))
    }
    func lowered(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }
    let event = lowered(alertEventName(offer, imperial: imperial))
    switch state {
    case .rest:
        return String(localized: "Set an alert", comment: "The line under the timeline, at rest.")
    case .pressed(let moment):
        return String(localized: "Set alert for \(event) · \(when(moment))",
                      comment: "The line under the timeline after a press and hold. First argument is an event such as 'low tide', second a weekday and time.")
    case .set(let rule):
        if let once = rule.once {
            return String(localized: "Alert set · \(event) · \(when(once))",
                          comment: "The line under the timeline when a one-time alert already exists. First argument is an event such as 'low tide', second a weekday and time.")
        }
        return String(localized: "Alert set · \(lowered(alertEveryLabel(offer, imperial: imperial)))",
                      comment: "The line under the timeline when a repeating alert already exists. The argument reads like 'every low tide'.")
    }
}
