// Slackwater — GPL v3. The line under the strip: Rest, Pressed, or Set (docs/alerts.md §7.1).
import SwiftUI

/// What the line reads. Set wins whenever a rule already exists for the centerline's offer, so a
/// rule can be found again from the place that made it; Pressed is the strip's own state after a
/// long press; Rest is everything else.
enum AlertLineState: Equatable {
    case rest
    case pressed(Date)
    case set(AlertRule)
}

/// The rule the line would open: one bound to this minute first — it is the one that expires —
/// then, at rest, the soonest one still ahead (a Rest tap binds to the offer's next occurrence,
/// not the centerline's minute), else one repeating this trigger. Enabled or not: a switched-off
/// rule is found and woken in the sheet, never duplicated.
func alertLineRule(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                   at moment: Date, pressed: Bool, now: Date) -> AlertRule? {
    let minute = alertMinute(moment)
    let mine = rules.filter { $0.stationID == stationID && $0.trigger == offer }
    if let exact = mine.first(where: { $0.once == minute }) { return exact }
    if !pressed, let ahead = mine.filter({ ($0.once ?? .distantPast) >= now }).min(by: { $0.once! < $1.once! }) {
        return ahead
    }
    return mine.first { $0.once == nil }
}

func alertLineState(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                    at moment: Date, pressed: Bool, now: Date) -> AlertLineState {
    if let rule = alertLineRule(rules, stationID: stationID, offer: offer, at: moment,
                                pressed: pressed, now: now) { return .set(rule) }
    return pressed ? .pressed(moment) : .rest
}

/// The first occurrence of an offer after a moment, for the line's Rest tap. The sheet binds
/// "Does not repeat" to it rather than to the centerline's own minute, which on an unscrubbed
/// strip is now, floored — already past, and the reschedule a save triggers drops a once rule
/// whose minute has passed (§6). Nil when the station cannot be loaded or nothing comes within
/// the notification horizon.
/// ponytail: on the main actor, one station over 14 days; move it off if a tap ever measures.
func alertNextOccurrence(stationID: String, offer: AlertTrigger, after: Date, threshold: Double) -> Date? {
    guard let record = WidgetStationLoader.loadRecord(id: stationID) else { return nil }
    let rule = AlertRule(stationID: stationID, trigger: offer)
    return alertOccurrences(rule, station: WidgetStationLoader.station(from: record),
                            position: record.alertPosition,
                            from: after, to: after.addingTimeInterval(AlertHorizon.notifications),
                            threshold: threshold)
        .map(\.event).first { $0 > after }
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

/// One quiet line, centred, caption weight, a 44 pt target. Not a Button: Button press tracking
/// goes dead in the iPad split layout's detail column (ReadoutTile, MultiDaySchedule).
struct AlertLine: View {
    let state: AlertLineState
    let offer: AlertTrigger
    let tz: TimeZone
    let action: () -> Void
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = heightUnits()

    var body: some View {
        let on: Bool = { if case .set = state { return true } else { return false } }()
        let label = alertLineLabel(state, offer: offer, tz: tz, imperial: units == "imperial")
        HStack(spacing: 6) {
            Image(systemName: on ? "bell.fill" : "bell")
            Text(label).monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(on ? SN.leaf : SN.foam.opacity(0.62))
        .frame(maxWidth: .infinity, minHeight: 44)
        // Pressed: the strip's reading line continues from the top edge down to the words,
        // so the parked moment and its name read as one thing.
        .overlay(alignment: .top) {
            if case .pressed = state {
                Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 14)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("alert-line")
    }
}
